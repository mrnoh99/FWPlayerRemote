import Foundation
import Network
import Combine

/// A live connection to one FWPlayer instance. Holds the latest `PlaybackState`
/// pushed by the player and sends transport commands back. Drives the
/// `RemoteControlView`.
@MainActor
final class RemoteSession: ObservableObject {
    enum Status: Equatable {
        case connecting
        case awaitingPIN
        case authenticating
        case connected
        case disconnected
        case failed(String)
    }

    @Published private(set) var status: Status = .disconnected
    @Published private(set) var needsPINEntry = false
    @Published private(set) var state: PlaybackState?
    @Published private(set) var authError: String?
    /// The player's browsable library (sources + playlists), once requested.
    @Published private(set) var library: RemoteLibrary?
    /// Folder listings received so far, keyed by source+path. Lets each browse
    /// screen show its own folder while we navigate a stack.
    @Published private(set) var listings: [String: RemoteListing] = [:]
    /// The player we are connected to (its advertised name).
    @Published private(set) var playerName: String
    /// Stable Bonjour identity used to cache the verified PIN.
    let playerID: String

    private let endpoint: NWEndpoint
    private var link: RemoteLink?
    /// While the user is dragging the scrubber we ignore inbound time updates so
    /// the thumb doesn't fight the user.
    @Published var isScrubbing = false
    /// Wall-clock anchor for the last `currentTime` received from the player.
    private var playbackAnchorDate: Date?

    init(player: DiscoveredPlayer) {
        self.playerID = player.id
        self.playerName = player.name
        self.endpoint = player.endpoint
    }

    var hasSavedPIN: Bool { PairedPINStore.isPaired(playerID) }

    // MARK: - Lifecycle

    /// Opens a connection only when not already connected or pairing.
    func connectIfNeeded() {
        switch status {
        case .connected, .connecting, .authenticating, .awaitingPIN:
            return
        case .disconnected, .failed:
            connect()
        }
    }

    func connect() {
        teardown()
        resetCachedData()
        status = .connecting
        authError = nil
        needsPINEntry = false
        let connection = NWConnection(to: endpoint, using: .tcp)
        let link = RemoteLink(connection: connection)
        link.onStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .waiting(let error):
                self.status = .failed(error.localizedDescription)
            case .failed(let error):
                self.status = .failed(error.localizedDescription)
                self.teardown()
            case .cancelled:
                self.status = .disconnected
                self.reconnectIfPaired()
            default:
                break
            }
        }
        link.onMessage = { [weak self] message in
            self?.handle(message)
        }
        self.link = link
        link.start()
    }

    func authenticate(with pin: String) {
        guard link != nil else { return }
        authError = nil
        pendingPIN = pin
        status = .authenticating
        send(.authenticate(pin: pin))
    }

    /// Drops the TCP link but keeps the saved PIN for this player.
    func suspend() {
        teardown()
        resetCachedData()
        status = .disconnected
        needsPINEntry = false
    }

    func disconnect() {
        suspend()
    }

    func forgetPIN() {
        PairedPINStore.remove(for: playerID)
    }

    private func resetCachedData() {
        state = nil
        library = nil
        listings = [:]
        isScrubbing = false
        playbackAnchorDate = nil
    }

    private func teardown() {
        link?.cancel()
        link = nil
    }

    private func handle(_ message: RemoteMessage) {
        switch message {
        case .pairingRequired(let pairing):
            playerName = pairing.deviceName
            authError = nil
            if let savedPIN = PairedPINStore.pin(for: playerID) {
                needsPINEntry = false
                authenticate(with: savedPIN)
            } else {
                needsPINEntry = true
                status = .awaitingPIN
            }
        case .authResult(let result):
            if result.success {
                if let pendingPIN {
                    PairedPINStore.save(pendingPIN, for: playerID)
                    self.pendingPIN = nil
                }
                authError = nil
                needsPINEntry = false
                status = .connected
                requestLibrary()
            } else {
                pendingPIN = nil
                PairedPINStore.remove(for: playerID)
                authError = result.message ?? "Incorrect PIN."
                needsPINEntry = true
                status = .awaitingPIN
            }
        case .state(let state):
            guard status == .connected || status == .authenticating else { return }
            if self.isScrubbing {
                var merged = state
                merged.currentTime = self.state?.currentTime ?? state.currentTime
                self.state = merged
            } else {
                self.state = state
                playbackAnchorDate = Date()
            }
        case .library(let library):
            guard status == .connected else { return }
            self.library = library
        case .listing(let listing):
            guard status == .connected else { return }
            listings[Self.key(listing.sourceID, listing.path)] = listing
        case .command:
            break
        }
    }

    // MARK: - Commands

    func send(_ command: RemoteCommand) {
        guard let link else { return }
        switch command {
        case .authenticate:
            guard status == .awaitingPIN || status == .authenticating else { return }
        default:
            guard status == .connected else { return }
        }
        link.send(.command(command))
    }

    private var pendingPIN: String?

    func togglePlayPause() { send(.togglePlayPause) }
    func next() { send(.next) }
    func previous() { send(.previous) }
    func seek(to time: TimeInterval) {
        let clamped = min(max(0, time), effectiveDuration)
        if var state = state {
            state.currentTime = clamped
            self.state = state
            playbackAnchorDate = Date()
        }
        send(.seek(time: clamped))
    }
    func play(index: Int) { send(.playIndex(index: index)) }
    func toggleShuffle() { send(.toggleShuffle) }
    func cycleRepeat() { send(.cycleRepeat) }

    /// Whether the player has shuffle on.
    var isShuffled: Bool { state?.isShuffled ?? false }
    /// Repeat mode: 0 = off, 1 = all, 2 = one.
    var repeatMode: Int { state?.repeatMode ?? 0 }

    // MARK: - Library & queue construction

    func requestLibrary() { send(.requestLibrary) }
    func browse(sourceID: String, path: String) {
        listings.removeValue(forKey: Self.key(sourceID, path))
        send(.browse(sourceID: sourceID, path: path))
    }
    func setQueue(_ tracks: [RemoteQueueTrack], startAt: Int, playlistID: String? = nil) {
        send(.setQueue(tracks: tracks, startAt: startAt, playlistID: playlistID))
    }
    func enqueue(_ tracks: [RemoteQueueTrack]) { send(.enqueue(tracks: tracks)) }
    func playNext(_ tracks: [RemoteQueueTrack]) { send(.playNext(tracks: tracks)) }
    func addToPlaylist(_ playlistID: String, tracks: [RemoteQueueTrack]) {
        send(.addToPlaylist(playlistID: playlistID, tracks: tracks))
    }
    func removeFromQueue(at index: Int) { send(.removeFromQueue(at: [index])) }
    func removeFromQueue(at offsets: IndexSet) {
        send(.removeFromQueue(at: offsets.sorted()))
    }
    func playFolder(sourceID: String, path: String, recursive: Bool = true) {
        send(.playFolder(sourceID: sourceID, path: path, recursive: recursive))
    }

    func listing(sourceID: String, path: String) -> RemoteListing? {
        listings[Self.key(sourceID, path)]
    }

    static func key(_ sourceID: String, _ path: String) -> String {
        sourceID + "\n" + path
    }

    private func reconnectIfPaired() {
        guard PairedPINStore.isPaired(playerID), link == nil else { return }
        connect()
    }

    // MARK: - Derived view helpers

    var currentTrack: RemoteTrack? {
        guard let state, let index = state.currentIndex, state.queue.indices.contains(index) else { return nil }
        return state.queue[index]
    }

    var isPlaying: Bool { state?.isPlaying ?? false }

    /// Best-known track length — prefers the live player value, then track metadata.
    var effectiveDuration: TimeInterval {
        guard let state else { return 0 }
        return max(state.duration, currentTrack?.duration ?? 0)
    }

    /// Playback position, extrapolated between server pushes while playing.
    func interpolatedTime(at date: Date = .now) -> TimeInterval {
        guard let state else { return 0 }
        let base = state.currentTime
        guard state.isPlaying, !isScrubbing, let anchor = playbackAnchorDate else {
            return min(max(0, base), effectiveDuration)
        }
        return min(max(0, base + date.timeIntervalSince(anchor)), effectiveDuration)
    }
}
