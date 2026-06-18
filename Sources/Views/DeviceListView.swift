import SwiftUI

/// Landing screen: lists the FWPlayer instances discovered on the local network
/// (a Mac, an iPad, or an iPhone running FWPlayer) and lets the user pick one to
/// control.
struct DeviceListView: View {
    @EnvironmentObject private var browser: RemoteBrowser
    @EnvironmentObject private var sessionStore: RemoteSessionStore

    var body: some View {
        NavigationStack {
            Group {
                if browser.players.isEmpty {
                    emptyState
                } else {
                    deviceList
                }
            }
            .navigationTitle("FWPlayer Remote")
        }
    }

    private var deviceList: some View {
        List(browser.players) { player in
            NavigationLink {
                RemoteControlView(session: sessionStore.session(for: player))
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.name).font(.body.weight(.medium))
                        Text(PairedPINStore.isPaired(player.id) ? "Tap to control" : "Tap to connect with PIN")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "hifispeaker.fill")
                        .foregroundStyle(.tint)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Looking for FWPlayer…", systemImage: "wifi")
        } description: {
            Text("Make sure FWPlayer is open on your Mac, iPad, or iPhone and connected to the same Wi‑Fi network.")
        } actions: {
            if browser.isBrowsing {
                ProgressView()
            }
        }
    }
}
