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

    var body: some View {
        Group {
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
                connectedTabs
            case .disconnected:
                ProgressView(session.hasSavedPIN ? "Reconnecting…" : "Disconnected")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { session.connectIfNeeded() }
            }
        }
        .navigationTitle(session.playerName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { session.connectIfNeeded() }
        .onChange(of: session.status) { _, new in
            if new == .connected { pin = "" }
        }
    }

    private var connectedTabs: some View {
        TabView(selection: $selectedTab) {
            nowPlayingTab
                .tabItem { Label("Now Playing", systemImage: "play.circle") }
                .tag(0)

            NavigationStack(path: $libraryPath) {
                LibraryView(session: session)
                    .navigationDestination(for: LibraryRoute.self) { route in
                        switch route {
                        case .folder(let folder):
                            FolderBrowseView(
                                session: session,
                                sourceID: folder.sourceID,
                                path: folder.path,
                                title: folder.title,
                                onDidStartPlayback: { selectedTab = 0 },
                                focusFilePath: locateFilePath
                            )
                        case .playlist(let playlist):
                            PlaylistBrowseView(
                                session: session,
                                playlist: playlist,
                                onDidStartPlayback: { selectedTab = 0 },
                                onLocate: { locate($0) }
                            )
                        }
                    }
            }
            .tabItem { Label("Library", systemImage: "music.note.list") }
            .tag(1)
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
        VStack(spacing: 4) {
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
        HStack(spacing: 48) {
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
