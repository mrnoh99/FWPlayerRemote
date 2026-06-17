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
        case connected
        case disconnected
        case failed(String)
    }

    @Published private(set) var status: Status = .disconnected
    @Published private(set) var state: PlaybackState?
    /// The player's browsable library (sources + playlists), once requested.
    @Published private(set) var library: RemoteLibrary?
    /// Folder listings received so far, keyed by source+path. Lets each browse
    /// screen show its own folder while we navigate a stack.
    @Published private(set) var listings: [String: RemoteListing] = [:]
    /// The player we are connected to (its advertised name).
    let playerName: String

    private let endpoint: NWEndpoint
    private var link: RemoteLink?
    /// While the user is dragging the scrubber we ignore inbound time updates so
    /// the thumb doesn't fight the user.
    var isScrubbing = false

    init(player: DiscoveredPlayer) {
        self.playerName = player.name
        self.endpoint = player.endpoint
    }

    // MARK: - Lifecycle

    func connect() {
        guard link == nil else { return }
        status = .connecting
        let connection = NWConnection(to: endpoint, using: .tcp)
        let link = RemoteLink(connection: connection)
        link.onStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.status = .connected
                self.send(.requestState)
            case .waiting(let error):
                self.status = .failed(error.localizedDescription)
            case .failed(let error):
                self.status = .failed(error.localizedDescription)
                self.teardown()
            case .cancelled:
                self.status = .disconnected
            default:
                break
            }
        }
        link.onMessage = { [weak self] message in
            guard let self else { return }
            switch message {
            case .state(let state):
                if self.isScrubbing {
                    // Keep everything but the live playhead while scrubbing.
                    var merged = state
                    merged.currentTime = self.state?.currentTime ?? state.currentTime
                    self.state = merged
                } else {
                    self.state = state
                }
            case .library(let library):
                self.library = library
            case .listing(let listing):
                self.listings[Self.key(listing.sourceID, listing.path)] = listing
            case .command:
                break
            }
        }
        self.link = link
        link.start()
    }

    func disconnect() {
        teardown()
        status = .disconnected
    }

    private func teardown() {
        link?.cancel()
        link = nil
    }

    // MARK: - Commands

    func send(_ command: RemoteCommand) {
        link?.send(.command(command))
    }

    func togglePlayPause() { send(.togglePlayPause) }
    func next() { send(.next) }
    func previous() { send(.previous) }
    func seek(to time: TimeInterval) { send(.seek(time: time)) }
    func play(index: Int) { send(.playIndex(index: index)) }

    // MARK: - Library & queue construction

    func requestLibrary() { send(.requestLibrary) }
    func browse(sourceID: String, path: String) { send(.browse(sourceID: sourceID, path: path)) }
    func setQueue(_ tracks: [RemoteQueueTrack], startAt: Int) { send(.setQueue(tracks: tracks, startAt: startAt)) }
    func enqueue(_ tracks: [RemoteQueueTrack]) { send(.enqueue(tracks: tracks)) }

    func listing(sourceID: String, path: String) -> RemoteListing? {
        listings[Self.key(sourceID, path)]
    }

    static func key(_ sourceID: String, _ path: String) -> String {
        sourceID + "\n" + path
    }

    // MARK: - Derived view helpers

    var currentTrack: RemoteTrack? {
        guard let state, let index = state.currentIndex, state.queue.indices.contains(index) else { return nil }
        return state.queue[index]
    }

    var isPlaying: Bool { state?.isPlaying ?? false }
    var duration: TimeInterval { state?.duration ?? 0 }
    var currentTime: TimeInterval { state?.currentTime ?? 0 }
}
