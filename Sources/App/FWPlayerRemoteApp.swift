import SwiftUI

@main
struct FWPlayerRemoteApp: App {
    @StateObject private var browser = RemoteBrowser()

    var body: some Scene {
        WindowGroup {
            DeviceListView()
                .environmentObject(browser)
                .onAppear { browser.start() }
        }
    }
}
