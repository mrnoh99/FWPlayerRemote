import Foundation
import Network
import Combine
#if canImport(UIKit)
import UIKit
#endif

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
    /// Album covers pushed by the player, keyed by track id.
    @Published private(set) var artworkByTrack: [String: UIImage] = [:]
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

    /// Auto-reconnect bookkeeping. iOS aborts the socket (NWError 53) when the
    /// app is backgrounded, so we retry with backoff and reconnect on foreground.
    private var reconnectTask: Task<Void, Never>?
    private var reconnectDelay: TimeInterval = 1
    private var isBackgrounded = false

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
            case .ready:
                // TCP is up; pairing/auth follows. Clear any pending retry.
                self.reconnectTask?.cancel()
                self.reconnectTask = nil
                self.reconnectDelay = 1
            case .waiting:
                // The path isn't ready yet (common right after returning from the
                // background). Keep showing "Connecting…" and retry rather than
                // dead-ending at "Can't Connect".
                if self.hasSavedPIN {
                    self.status = .connecting
                    self.scheduleReconnect()
                } else {
                    self.status = .failed("Couldn't reach the player.")
                }
            case .failed(let error):
                self.teardown()
                // A paired session recovers on its own (the abort on backgrounding
                // lands here); only surface a hard error when there's no saved PIN.
                if self.hasSavedPIN {
                    self.status = .connecting
                    self.scheduleReconnect()
                } else {
                    self.status = .failed(error.localizedDescription)
                }
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

    /// Force a fresh connection now (used by "Try Again" and on foreground).
    func reconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectDelay = 1
        connect()
    }

    /// Schedules a single backoff reconnect for a paired player.
    private func scheduleReconnect() {
        guard hasSavedPIN, !isBackgrounded, reconnectTask == nil else { return }
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 8)
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.reconnectTask = nil
            guard !self.isBackgrounded, self.status != .connected else { return }
            self.connect()
        }
    }

    /// Call when the app returns to the foreground. The socket is usually torn
    /// down in the background, so re-establish a fresh connection.
    func appDidBecomeActive() {
        isBackgrounded = false
        if hasSavedPIN {
            reconnect()
        } else {
            connectIfNeeded()
        }
    }

    /// Call when the app enters the background: drop the link cleanly so we don't
    /// keep a half-dead socket (which would let commands through but stop state
    /// updates). The last state stays on screen until we reconnect.
    func appDidEnterBackground() {
        isBackgrounded = true
        reconnectTask?.cancel()
        reconnectTask = nil
        teardown()
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
        artworkByTrack = [:]
        isScrubbing = false
        playbackAnchorDate = nil
    }

    /// The cover for the current track, if the player has pushed it.
    var currentArtwork: UIImage? {
        guard let id = currentTrack?.id else { return nil }
        return artworkByTrack[id]
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
        case .artwork(let art):
            guard status == .connected,
                  let data = Data(base64Encoded: art.jpegBase64),
                  let image = UIImage(data: data) else { return }
            if artworkByTrack.count > 16 { artworkByTrack.removeAll() }
            artworkByTrack[art.trackID] = image
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
    /// Recently played tracks, most recent first.
    var history: [RemoteTrack] { state?.history ?? [] }

    // MARK: - Favorites

    func toggleFavorite(_ track: RemoteQueueTrack) { send(.toggleFavorite(track: track)) }

    /// Whether the track is in the player's Favorites playlist (from the library).
    func isFavorite(_ track: RemoteQueueTrack) -> Bool {
        guard let favorites = library?.playlists.first(where: { $0.id == fwFavoritesPlaylistID }) else { return false }
        return favorites.tracks.contains { $0.sourceID == track.sourceID && $0.path == track.path }
    }

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
    func clearQueue() { send(.clearQueue) }
    func moveQueue(from offsets: IndexSet, to destination: Int) {
        send(.moveQueue(from: offsets.sorted(), to: destination))
    }
    func movePlaylistEntry(playlistID: String, from offsets: IndexSet, to destination: Int) {
        send(.movePlaylistEntry(playlistID: playlistID, from: offsets.sorted(), to: destination))
    }
    func removePlaylistEntry(playlistID: String, at offsets: IndexSet) {
        send(.removePlaylistEntry(playlistID: playlistID, at: offsets.sorted()))
    }

    /// True when the track at `sourceID`/`path` is the one currently loaded in the
    /// player, so lists can shade it and show a speaker icon wherever it appears.
    func isNowPlaying(sourceID: String?, path: String?) -> Bool {
        guard let sourceID, let path, let state,
              let index = state.currentIndex, state.queue.indices.contains(index) else { return false }
        let current = state.queue[index]
        return current.sourceID == sourceID && current.path == path
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
        guard PairedPINStore.isPaired(playerID), !isBackgrounded, link == nil else { return }
        scheduleReconnect()
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
