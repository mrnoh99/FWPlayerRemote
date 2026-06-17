import Foundation
import Network
import Combine

/// One FWPlayer instance discovered on the local network.
struct DiscoveredPlayer: Identifiable, Hashable {
    let name: String
    let endpoint: NWEndpoint

    /// Stable identity across browse refreshes (the Bonjour service name).
    var id: String { name }

    static func == (lhs: DiscoveredPlayer, rhs: DiscoveredPlayer) -> Bool {
        lhs.endpoint == rhs.endpoint
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(endpoint)
    }
}

/// Browses for FWPlayer (`_fwplayer._tcp`) Bonjour services and publishes the
/// current set of discovered players.
@MainActor
final class RemoteBrowser: ObservableObject {
    @Published private(set) var players: [DiscoveredPlayer] = []
    @Published private(set) var isBrowsing = false

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.fwplayer.remote.browser")

    func start() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: fwRemoteServiceType, domain: nil), using: params)

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready: self?.isBrowsing = true
                case .failed, .cancelled: self?.isBrowsing = false
                default: break
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let discovered = results.compactMap { result -> DiscoveredPlayer? in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                return DiscoveredPlayer(name: name, endpoint: result.endpoint)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            Task { @MainActor in self?.players = discovered }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
        players = []
    }
}
