import Combine
import Foundation

/// Keeps one `RemoteSession` per discovered player so reconnecting reuses auth state.
@MainActor
final class RemoteSessionStore: ObservableObject {
    private var sessions: [String: RemoteSession] = [:]

    func session(for player: DiscoveredPlayer) -> RemoteSession {
        if let existing = sessions[player.id] {
            return existing
        }
        let session = RemoteSession(player: player)
        sessions[player.id] = session
        return session
    }
}
