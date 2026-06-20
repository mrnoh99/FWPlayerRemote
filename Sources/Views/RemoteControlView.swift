import SwiftUI

/// The remote control surface for a single FWPlayer: now-playing info, transport
/// buttons, and the live queue. Sends commands over the network and reflects the
/// state pushed back by the player.
struct RemoteControlView: View {
    @StateObject private var session: RemoteSession
    @State private var selectedTab = 0
    /// The Library tab's navigation stack, owned here so "Locate File" can drive
    /// it from the queue or a playlist.
    @State private var libraryPath: [LibraryRoute] = []
    /// The file a "Locate File" action is revealing (highlighted in its folder).
    @State private var locateFilePath: String?

    init(session: RemoteSession) {
        _session = StateObject(wrappedValue: session)
    }

    /// Bottom space reserved for the floating panel (content + home indicator).
    private static let floatingPanelInset: CGFloat = 76

    var body: some View {
        remoteMainContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, Self.floatingPanelInset)
            .overlay(alignment: .bottom) {
                floatingPanelBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(selectedTab == 1 && !libraryPath.isEmpty)
            .toolbar {
                if selectedTab == 1, !libraryPath.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: popLibrary) {
                            Image(systemName: "chevron.left")
                        }
                    }
                }
            }
            .onAppear { session.connectIfNeeded() }
            .onChange(of: session.status) { _, new in
                if new == .connected { pin = "" }
            }
            .onChange(of: libraryPath) { _, _ in
                clearLocateFocusIfNeeded()
            }
    }

    private var screenTitle: String {
        guard selectedTab == 1 else { return session.playerName }
        guard let route = libraryPath.last else { return "Library" }
        return route.screenTitle
    }

    private var floatingPanelBar: some View {
        FloatingRemotePanel(selectedTab: $selectedTab)
            .frame(maxWidth: .infinity)
            // Keep the panel fixed — don't slide with library navigation pushes.
            .transaction { transaction in
                transaction.animation = nil
            }
    }

    private var remoteMainContent: some View {
        ZStack {
            nowPlayingScreen
                .opacity(selectedTab == 0 ? 1 : 0)
                .allowsHitTesting(selectedTab == 0)
                .accessibilityHidden(selectedTab != 0)

            libraryScreen
                .opacity(selectedTab == 1 ? 1 : 0)
                .allowsHitTesting(selectedTab == 1)
                .accessibilityHidden(selectedTab != 1)
        }
        .clipped()
    }

    @ViewBuilder
    private var nowPlayingScreen: some View {
        switch session.status {
        case .connecting, .authenticating:
            ProgressView(session.hasSavedPIN ? "Reconnecting…" : "Connecting…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .awaitingPIN where session.needsPINEntry:
            pinEntry
        case .awaitingPIN:
            ProgressView("Connecting…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            failure(message)
        case .connected:
            nowPlayingTab
        case .disconnected:
            ProgressView(session.hasSavedPIN ? "Reconnecting…" : "Disconnected")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { session.connectIfNeeded() }
        }
    }

    @ViewBuilder
    private var libraryScreen: some View {
        ZStack {
            libraryNavigationStack

            if session.status != .connected {
                ContentUnavailableView {
                    Label("Not Connected", systemImage: "wifi")
                } description: {
                    Text("Connect to \(session.playerName) to browse its library.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
            }
        }
    }

    /// Library browser driven by `libraryPath` (no NavigationStack push — keeps the
    /// floating panel fixed while browsing folders and playlists).
    private var libraryNavigationStack: some View {
        Group {
            if let route = libraryPath.last {
                libraryDestination(for: route)
            } else {
                LibraryView(session: session, onOpen: openLibraryRoute)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(nil, value: libraryPath.count)
    }

    private func openLibraryRoute(_ route: LibraryRoute) {
        libraryPath.append(route)
    }

    private func popLibrary() {
        guard !libraryPath.isEmpty else { return }
        libraryPath.removeLast()
    }

    @ViewBuilder
    private func libraryDestination(for route: LibraryRoute) -> some View {
        switch route {
        case .folder(let folder):
            FolderBrowseView(
                session: session,
                sourceID: folder.sourceID,
                path: folder.path,
                title: folder.title,
                onOpenFolder: { openLibraryRoute(.folder($0)) },
                onGoBack: popLibrary,
                focusFilePath: locateFilePath
            )
        case .playlist(let playlist):
            PlaylistBrowseView(
                session: session,
                playlist: playlist,
                onLocate: { locate($0) }
            )
        }
    }

    // MARK: - Locate File

    /// Switches to the Library tab and opens the folder containing `track`,
    /// scrolling to (and highlighting) the file.
    private func locate(sourceID: String, path: String) {
        libraryPath = folderRoutes(sourceID: sourceID, path: path)
        locateFilePath = path
        selectedTab = 1
    }

    private func locate(_ track: RemoteTrack) {
        guard let sourceID = track.sourceID, let path = track.path else { return }
        locate(sourceID: sourceID, path: path)
    }

    private func locate(_ track: RemoteQueueTrack) {
        locate(sourceID: track.sourceID, path: track.path)
    }

    /// Drops the "Locate File" highlight once the user leaves the target folder.
    private func clearLocateFocusIfNeeded() {
        guard let focusedPath = locateFilePath else { return }
        let targetFolder = (focusedPath as NSString).deletingLastPathComponent
        let visibleFolderPaths = libraryPath.compactMap { route -> String? in
            guard case .folder(let folder) = route else { return nil }
            return folder.path
        }
        if !visibleFolderPaths.contains(targetFolder) {
            locateFilePath = nil
        }
    }

    /// Rebuilds a queueable track from a queue entry, if it carries its origin.
    private func queueTrack(from track: RemoteTrack) -> RemoteQueueTrack? {
        guard let sourceID = track.sourceID, let path = track.path else { return nil }
        return RemoteQueueTrack(sourceID: sourceID, path: path, title: track.title)
    }

    /// Builds the navigation chain down to the folder that holds `path`, starting
    /// at the source root so the back button walks back up naturally.
    private func folderRoutes(sourceID: String, path: String) -> [LibraryRoute] {
        let sourceName = session.library?.sources.first { $0.id == sourceID }?.displayName ?? "Source"
        var routes: [LibraryRoute] = [.folder(RemoteFolderRoute(sourceID: sourceID, path: "", title: sourceName))]
        let folder = (path as NSString).deletingLastPathComponent
        guard !folder.isEmpty else { return routes }
        var accumulated = ""
        for component in folder.split(separator: "/").map(String.init) {
            accumulated = accumulated.isEmpty ? component : accumulated + "/" + component
            routes.append(.folder(RemoteFolderRoute(sourceID: sourceID, path: accumulated, title: component)))
        }
        return routes
    }

    private var nowPlayingTab: some View {
        VStack(spacing: 8) {
            nowPlaying
            queue
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            progressBar
            transportControls
        }
        .padding()
    }

    // MARK: - PIN pairing

    @State private var pin = ""
    @FocusState private var pinFocused: Bool

    private var pinEntry: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Enter PIN")
                .font(.title2.weight(.semibold))
            Text("Enter the 6-digit PIN shown on \(session.playerName).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("000000", text: $pin)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .font(.title.monospacedDigit())
                .focused($pinFocused)
                .onChange(of: pin) { _, new in
                    let digits = new.filter(\.isNumber)
                    pin = String(digits.prefix(6))
                }

            if let authError = session.authError {
                Text(authError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                session.authenticate(with: pin)
            } label: {
                if session.status == .authenticating {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Connect")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(pin.count != 6 || session.status == .authenticating)
        }
        .padding(.horizontal, 32)
        .onAppear { pinFocused = true }
    }

    // MARK: - Connected content

    private var nowPlaying: some View {
        VStack(spacing: 10) {
            Group {
                if let cover = session.currentArtwork {
                    Image(uiImage: cover).resizable().scaledToFill()
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 52))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.secondary.opacity(0.12))
                }
            }
            .frame(width: 200, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 5)

            Text(session.currentTrack?.title ?? "Nothing Playing")
                .font(.title3.weight(.semibold))
                .lineLimit(1)

            if let format = session.state?.audioFormat {
                Label(format, systemImage: "waveform")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.tint)
            }

            Text(session.currentTrack?.artist ?? session.currentTrack?.album ?? " ")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    private var progressBar: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !session.isPlaying)) { timeline in
            let duration = max(session.effectiveDuration, 0.1)
            let current = session.interpolatedTime(at: timeline.date)
            let progress = min(max(0, current / duration), 1)

            VStack(spacing: 4) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)

                HStack {
                    Text(Self.timeString(current))
                    Spacer()
                    Text(Self.timeString(session.effectiveDuration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    private var transportControls: some View {
        HStack(spacing: 28) {
            Button { session.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundStyle(session.isShuffled ? Color.accentColor : Color.secondary)
            }
            Button { session.previous() } label: {
                Image(systemName: "backward.fill").font(.title)
            }
            Button { session.togglePlayPause() } label: {
                Image(systemName: session.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
            }
            Button { session.next() } label: {
                Image(systemName: "forward.fill").font(.title)
            }
            Button { session.cycleRepeat() } label: {
                Image(systemName: session.repeatMode == 2 ? "repeat.1" : "repeat")
                    .font(.title3)
                    .foregroundStyle(session.repeatMode == 0 ? Color.secondary : Color.accentColor)
            }
        }
        .tint(.primary)
    }

    private var queue: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Queue").font(.headline)
            if let state = session.state, !state.queue.isEmpty {
                List {
                    ForEach(Array(state.queue.enumerated()), id: \.element.id) { index, track in
                        HStack(spacing: 6) {
                            Button {
                                session.play(index: index)
                            } label: {
                                HStack(spacing: 6) {
                                    Group {
                                        if index == state.currentIndex {
                                            Image(systemName: session.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                                                .foregroundStyle(.tint)
                                        } else {
                                            Text("\(index + 1)")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .font(.caption)
                                    .frame(width: 20, alignment: .center)

                                    Text(track.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .contentShape(Rectangle())
                            }
                            .tint(.primary)

                            Menu {
                                if track.sourceID != nil {
                                    Button {
                                        locate(track)
                                    } label: {
                                        Label("Locate File", systemImage: "folder")
                                    }
                                }
                                if let queueTrack = queueTrack(from: track) {
                                    AddToFavoritesButton(session: session, track: queueTrack)
                                    AddToPlaylistMenu(session: session, track: queueTrack)
                                }
                                Button(role: .destructive) {
                                    session.removeFromQueue(at: index)
                                } label: {
                                    Label("Remove from Queue", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                session.removeFromQueue(at: index)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            } else {
                Text("The queue is empty. Open the Library tab to browse playlists, folders, or SMB shares on the player.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func failure(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Can't Connect", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                session.connect()
            }
                .buttonStyle(.borderedProminent)
        }
    }

    static func timeString(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let total = Int(time)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
