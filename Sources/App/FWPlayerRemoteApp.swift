import SwiftUI

@main
struct FWPlayerRemoteApp: App {
    @StateObject private var browser = RemoteBrowser()
    @StateObject private var sessionStore = RemoteSessionStore()

    var body: some Scene {
        WindowGroup {
            DeviceListView()
                .environmentObject(browser)
                .environmentObject(sessionStore)
                .onAppear { browser.start() }
        }
    }
}
