import SwiftUI
import UniformTypeIdentifiers

/// The SF Symbol shown at the leading edge of a track row: a speaker (or pause)
/// when the row is the track the player currently has loaded, otherwise a
/// neutral music note. Keeps the "now playing" indicator consistent across the
/// Library, History, and Playlist lists.
func nowPlayingSymbol(isCurrent: Bool, isPlaying: Bool) -> String {
    guard isCurrent else { return "music.note" }
    return isPlaying ? "speaker.wave.2.fill" : "pause.fill"
}

/// A folder location pushed onto the library's navigation stack. Hashable so the
/// stack can be driven (and restored) programmatically — e.g. by "Locate File".
struct RemoteFolderRoute: Hashable {
    let sourceID: String
    let path: String
    let title: String
}

/// A destination within the Library tab's value-based navigation stack.
enum LibraryRoute: Hashable {
    case queue
    case history
    case folder(RemoteFolderRoute)
    case playlist(RemotePlaylist)

    var screenTitle: String {
        switch self {
        case .queue: "Queue"
        case .history: "History"
        case .folder(let folder): folder.title
        case .playlist(let playlist): playlist.name
        }
    }
}

/// Root of the library browser: lists the player's sources (local folders, SMB
/// shares) and playlists. Picking music rebuilds the player's queue over the network.
struct LibraryView: View {
    @ObservedObject var session: RemoteSession
    var onOpen: (LibraryRoute) -> Void

    @State private var query = ""
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Group {
            if trimmedQuery.isEmpty {
                libraryList
            } else {
                SearchResultsView(session: session, query: trimmedQuery, onOpen: onOpen)
            }
        }
        .searchable(text: $query, prompt: "Search folders and files")
        .onChange(of: query) { _, new in session.search(new) }
    }

    private var libraryList: some View {
        Group {
            if let library = session.library {
                List {
                    Section("Playback") {
                        Button {
                            onOpen(.queue)
                        } label: {
                            HStack {
                                Label("Queue", systemImage: "list.bullet")
                                Spacer()
                                if let count = session.state?.queue.count, count > 0 {
                                    Text("\(count)").foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tint(.primary)

                        Button {
                            onOpen(.history)
                        } label: {
                            HStack {
                                Label("History", systemImage: "clock.arrow.circlepath")
                                Spacer()
                                if !session.history.isEmpty {
                                    Text("\(session.history.count)").foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tint(.primary)
                    }

                    if !library.sources.isEmpty {
                        Section("Sources") {
                            ForEach(library.sources) { source in
                                Button {
                                    onOpen(.folder(
                                        RemoteFolderRoute(sourceID: source.id, path: "", title: source.displayName)
                                    ))
                                } label: {
                                    Label(source.displayName, systemImage: source.symbolName)
                                }
                                .tint(.primary)
                            }
                        }
                    }

                    Section("Playlists") {
                        Button {
                            session.playlistPrompt = .create(tracks: [])
                        } label: {
                            Label("New Playlist…", systemImage: "plus")
                        }
                        ForEach(library.playlists) { playlist in
                            Button {
                                onOpen(.playlist(playlist))
                            } label: {
                                HStack {
                                    Label(playlist.name, systemImage: "music.note.list")
                                    Spacer()
                                    Text("\(playlist.tracks.count)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tint(.primary)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if playlist.id != fwFavoritesPlaylistID && playlist.id != fwPlayedPlaylistID {
                                    Button(role: .destructive) {
                                        session.deletePlaylist(playlist.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button {
                                        session.playlistPrompt = .rename(id: playlist.id, current: playlist.name)
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }
                                    .tint(.orange)
                                }
                            }
                        }
                    }
                }
            } else {
                ProgressView("Loading library…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { session.requestLibrary() }
        .refreshable { session.requestLibrary() }
    }
}

/// The player's current queue, reachable from the Library tab. Tap to jump to a
/// track; the ••• menu offers Play Now / Add to Favorites / Add to Playlist /
/// Locate File / Remove.
struct QueueBrowseView: View {
    @ObservedObject var session: RemoteSession
    var onLocate: ((RemoteTrack) -> Void)?

    @State private var editMode: EditMode = .inactive
    @State private var draggingRow: Int?

    var body: some View {
        Group {
            if let state = session.state, !state.queue.isEmpty {
                List {
                    ForEach(Array(state.queue.enumerated()), id: \.element.id) { index, track in
                        HStack(spacing: 8) {
                            if let qt = queueTrack(track) {
                                FavoriteStarButton(session: session, track: qt)
                            }
                            Button {
                                session.play(index: index)
                            } label: {
                                HStack(spacing: 8) {
                                    Group {
                                        if index == state.currentIndex {
                                            Image(systemName: session.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                                                .foregroundStyle(.tint)
                                        } else {
                                            Text("\(index + 1)").foregroundStyle(.secondary)
                                        }
                                    }
                                    .font(.caption)
                                    .frame(width: 24, alignment: .center)
                                    Text(track.title).lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .contentShape(Rectangle())
                            }
                            .tint(.primary)

                            if !editMode.isEditing {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 30, height: 44)
                                    .contentShape(Rectangle())
                                    .reorderGrip(index: index, dragging: $draggingRow, title: track.title)
                            }

                            VStack(spacing: 0) {
                                Button { session.moveQueue(from: IndexSet(integer: index), to: index - 1) } label: {
                                    Image(systemName: "chevron.up").frame(width: 32, height: 22).contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                                .disabled(index == 0)
                                Button { session.moveQueue(from: IndexSet(integer: index), to: index + 2) } label: {
                                    Image(systemName: "chevron.down").frame(width: 32, height: 22).contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                                .disabled(index >= state.queue.count - 1)
                            }

                            Menu {
                                Button { session.play(index: index) } label: {
                                    Label("Play Now", systemImage: "play.fill")
                                }
                                Section {
                                    Button { session.moveQueue(from: IndexSet(integer: index), to: index - 1) } label: {
                                        Label("Move Up", systemImage: "arrow.up")
                                    }
                                    .disabled(index == 0)
                                    Button { session.moveQueue(from: IndexSet(integer: index), to: index + 2) } label: {
                                        Label("Move Down", systemImage: "arrow.down")
                                    }
                                    .disabled(index >= state.queue.count - 1)
                                }
                                if let qt = queueTrack(track) {
                                    AddToFavoritesButton(session: session, track: qt)
                                    AddToPlaylistMenu(session: session, track: qt)
                                }
                                if track.sourceID != nil, let onLocate {
                                    Button { onLocate(track) } label: {
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
                                    .frame(width: 36, height: 40)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                        }
                        .listRowBackground(index == state.currentIndex
                                           ? Color.accentColor.opacity(0.15) : nil)
                        // Touch and hold, then drag to reorder (no Edit mode needed).
                        .reorderDropTarget(index: index, dragging: $draggingRow) { from, to in
                            session.moveQueue(from: IndexSet(integer: from), to: to)
                        }
                    }
                    .onMove { offsets, destination in
                        session.moveQueue(from: offsets, to: destination)
                    }
                    .onDelete { offsets in
                        session.removeFromQueue(at: offsets)
                    }
                }
                .environment(\.editMode, $editMode)
            } else {
                ContentUnavailableView("Queue is Empty", systemImage: "list.bullet",
                                       description: Text("Add music from the Library to build the queue."))
            }
        }
        .navigationTitle("Queue")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let count = session.state?.queue.count, count > 0 {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) {
                        session.clearQueue()
                        editMode = .inactive
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode.isEditing ? "Done" : "Edit") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                }
            }
        }
    }

    private func queueTrack(_ track: RemoteTrack) -> RemoteQueueTrack? {
        guard let sourceID = track.sourceID, let path = track.path else { return nil }
        return RemoteQueueTrack(sourceID: sourceID, path: path, title: track.title)
    }
}

/// Recently played tracks, reachable from the Library tab. Tap to play next; the
/// ••• menu offers Play Now / Add to Favorites / Add to Playlist / Locate File.
struct HistoryBrowseView: View {
    @ObservedObject var session: RemoteSession
    var onLocate: ((RemoteTrack) -> Void)?

    var body: some View {
        Group {
            if !session.history.isEmpty {
                List {
                    ForEach(Array(session.history.enumerated()), id: \.offset) { _, track in
                        let isCurrent = session.isNowPlaying(sourceID: track.sourceID, path: track.path)
                        HStack(spacing: 8) {
                            if let qt = queueTrack(track) {
                                FavoriteStarButton(session: session, track: qt)
                            }
                            Button {
                                if let qt = queueTrack(track) { session.playNext([qt]) }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: nowPlayingSymbol(isCurrent: isCurrent, isPlaying: session.isPlaying))
                                        .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                    Text(track.title)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .tint(.primary)

                            if let qt = queueTrack(track) {
                                Menu {
                                    Button { session.setQueue([qt], startAt: 0) } label: {
                                        Label("Play Now", systemImage: "play.fill")
                                    }
                                    Button { session.playNext([qt]) } label: {
                                        Label("Play Next", systemImage: "text.insert")
                                    }
                                    Button { session.enqueue([qt]) } label: {
                                        Label("Add to Queue", systemImage: "text.badge.plus")
                                    }
                                    AddToFavoritesButton(session: session, track: qt)
                                    AddToPlaylistMenu(session: session, track: qt)
                                    if let onLocate {
                                        Button { onLocate(track) } label: {
                                            Label("Locate File", systemImage: "folder")
                                        }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 36, height: 40)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .listRowBackground(isCurrent ? Color.accentColor.opacity(0.15) : nil)
                    }
                }
            } else {
                ContentUnavailableView("No History", systemImage: "clock.arrow.circlepath",
                                       description: Text("Tracks you play will appear here."))
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func queueTrack(_ track: RemoteTrack) -> RemoteQueueTrack? {
        guard let sourceID = track.sourceID, let path = track.path else { return nil }
        return RemoteQueueTrack(sourceID: sourceID, path: path, title: track.title)
    }
}

/// Shows one playlist's tracks; tap a track or use Play All to queue on the player.
struct PlaylistBrowseView: View {
    @ObservedObject var session: RemoteSession
    let playlist: RemotePlaylist
    /// Reveals the track's file in the Library (jumps to its containing folder).
    var onLocate: ((RemoteQueueTrack) -> Void)?

    @State private var editMode: EditMode = .inactive
    @State private var draggingPlaylistRow: Int?
    @State private var showingClearAsk = false
    @State private var showingClearFinal = false

    /// The navigation route carries a snapshot of the playlist; resolve the live
    /// copy from the session so reorders (and other edits) reflect immediately
    /// once the player re-broadcasts the library.
    private var livePlaylist: RemotePlaylist {
        session.library?.playlists.first(where: { $0.id == playlist.id }) ?? playlist
    }

    var body: some View {
        let playlist = livePlaylist
        List {
            ForEach(Array(playlist.tracks.enumerated()), id: \.offset) { index, track in
                let isCurrent = session.isNowPlaying(sourceID: track.sourceID, path: track.path)
                HStack(spacing: 8) {
                    FavoriteStarButton(session: session, track: track)

                    Button {
                        session.playNext([track])
                    } label: {
                        HStack {
                            Group {
                                if isCurrent {
                                    Image(systemName: session.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                                        .foregroundStyle(.tint)
                                } else {
                                    Text("\(index + 1)").foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 24, alignment: .trailing)
                            Text(track.title)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                    .tint(.primary)

                    Menu {
                        trackActions(track, at: index, in: playlist)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
                .listRowBackground(isCurrent ? Color.accentColor.opacity(0.15) : nil)
                // Touch and hold, then drag to reorder (no Edit mode needed).
                .reorderable(index: index, isEnabled: !editMode.isEditing, dragging: $draggingPlaylistRow) { from, to in
                    session.movePlaylistEntry(playlistID: playlist.id, from: IndexSet(integer: from), to: to)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        session.removePlaylistEntry(playlistID: playlist.id, at: IndexSet(integer: index))
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
            .onMove { offsets, destination in
                session.movePlaylistEntry(playlistID: playlist.id, from: offsets, to: destination)
            }
            .onDelete { offsets in
                session.removePlaylistEntry(playlistID: playlist.id, at: offsets)
            }
        }
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    session.setQueue(playlist.tracks, startAt: 0, playlistID: playlist.id)
                } label: {
                    Label("Play All", systemImage: "play.fill")
                }
                .disabled(playlist.tracks.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(editMode.isEditing ? "Done" : "Edit") {
                    withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                }
                .disabled(playlist.tracks.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showingClearAsk = true
                    } label: {
                        Label("Delete All Tracks…", systemImage: "trash.slash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(playlist.tracks.isEmpty)
            }
        }
        .modifier(ClearAllConfirmation(
            name: playlist.name, count: playlist.tracks.count,
            isAsking: $showingClearAsk, isFinal: $showingClearFinal,
            onConfirm: { session.clearPlaylist(playlist.id) }))
    }

    /// Per-track actions inside a playlist: mirrors the player's playlist menu
    /// (Play Now / Play from Here / Play Next / Add to Queue / Add to Playlist).
    @ViewBuilder
    private func trackActions(_ track: RemoteQueueTrack, at index: Int, in playlist: RemotePlaylist) -> some View {
        Button {
            session.setQueue([track], startAt: 0)
        } label: {
            Label("Play Now", systemImage: "play.fill")
        }
        Button {
            session.setQueue(playlist.tracks, startAt: index, playlistID: playlist.id)
        } label: {
            Label("Play from Here", systemImage: "play.circle")
        }
        Button {
            session.playNext([track])
        } label: {
            Label("Play Next", systemImage: "text.insert")
        }
        Button {
            session.enqueue([track])
        } label: {
            Label("Add to Queue", systemImage: "text.badge.plus")
        }
        Section {
            Button {
                session.movePlaylistEntry(playlistID: playlist.id, from: IndexSet(integer: index), to: index - 1)
            } label: {
                Label("Move Up", systemImage: "arrow.up")
            }
            .disabled(index == 0)
            Button {
                session.movePlaylistEntry(playlistID: playlist.id, from: IndexSet(integer: index), to: index + 2)
            } label: {
                Label("Move Down", systemImage: "arrow.down")
            }
            .disabled(index >= playlist.tracks.count - 1)
        }
        AddToFavoritesButton(session: session, track: track)
        AddToPlaylistMenu(session: session, track: track)
        if let onLocate {
            Button {
                onLocate(track)
            } label: {
                Label("Locate File", systemImage: "folder")
            }
        }
        Divider()
        Button(role: .destructive) {
            session.removePlaylistEntry(playlistID: playlist.id, at: IndexSet(integer: index))
        } label: {
            Label("Remove from Playlist", systemImage: "trash")
        }
    }
}

/// "Add to Favorites" — adds the track to the player's built-in Favorites
/// playlist. Shown only once the library (and its Favorites playlist) is known.
struct AddToFavoritesButton: View {
    @ObservedObject var session: RemoteSession
    let track: RemoteQueueTrack

    var body: some View {
        Button(role: session.isFavorite(track) ? .destructive : nil) {
            session.toggleFavorite(track)
        } label: {
            Label(session.isFavorite(track) ? "Remove from Favorites" : "Add to Favorites",
                  systemImage: session.isFavorite(track) ? "star.slash" : "star")
        }
    }
}

/// A leading yellow star that toggles a track's Favorites membership.
struct FavoriteStarButton: View {
    @ObservedObject var session: RemoteSession
    let track: RemoteQueueTrack

    var body: some View {
        Button {
            session.toggleFavorite(track)
        } label: {
            Image(systemName: session.isFavorite(track) ? "star.fill" : "star")
                .foregroundStyle(session.isFavorite(track) ? Color.yellow : Color.secondary)
                .font(.footnote)
                .frame(width: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(session.isFavorite(track) ? "Remove from Favorites" : "Add to Favorites")
    }
}

/// "Add to Playlist ▸" submenu listing every playlist on the player.
struct AddToPlaylistMenu: View {
    @ObservedObject var session: RemoteSession
    let track: RemoteQueueTrack

    var body: some View {
        if let playlists = session.library?.playlists {
            Menu {
                Button {
                    session.playlistPrompt = .create(tracks: [track])
                } label: {
                    Label("New Playlist…", systemImage: "plus")
                }
                if !playlists.isEmpty { Divider() }
                ForEach(playlists) { playlist in
                    Button {
                        session.addToPlaylist(playlist.id, tracks: [track])
                    } label: {
                        Text(playlist.name)
                    }
                }
            } label: {
                Label("Add to Playlist", systemImage: "music.note.list")
            }
        }
    }
}

/// Browses one folder within a source. Sub-folders can be opened or played
/// recursively; audio files start playback from the current folder queue.
struct FolderBrowseView: View {
    @ObservedObject var session: RemoteSession
    let sourceID: String
    let path: String
    let title: String
    var onOpenFolder: (RemoteFolderRoute) -> Void
    var onGoBack: () -> Void
    /// When this folder contains it, the file at this path is highlighted and
    /// scrolled into view (set by "Locate File").
    var focusFilePath: String?

    /// Key under which this folder's last-opened child is remembered on the
    /// session (which survives this view being recreated on navigation).
    private var childKey: String { RemoteSession.key(sourceID, path) }

    private var listing: RemoteListing? { session.listing(sourceID: sourceID, path: path) }
    private var audioItems: [RemoteFileItem] { listing?.items.filter { $0.kind == .audio } ?? [] }
    private var canGoToParent: Bool { !path.isEmpty }
    private var parentPath: String { (path as NSString).deletingLastPathComponent }
    private var parentFolderLabel: String {
        if parentPath.isEmpty {
            return session.library?.sources.first(where: { $0.id == sourceID })?.displayName ?? "Source"
        }
        return (parentPath as NSString).lastPathComponent
    }

    var body: some View {
        Group {
            if let listing {
                if let error = listing.error {
                    ContentUnavailableView("Couldn't Load Folder", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if listing.items.isEmpty {
                    if canGoToParent {
                        parentOnlyList
                    } else {
                        ContentUnavailableView("Empty Folder", systemImage: "folder", description: Text("No folders or playable audio files here."))
                    }
                } else {
                    folderList(listing)
                }
            } else {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: path) {
            // Retry a few times: if a browse request or its reply is dropped the
            // folder would otherwise stay stuck on "Loading…".
            for attempt in 0..<4 {
                if session.listing(sourceID: sourceID, path: path) != nil { return }
                session.browse(sourceID: sourceID, path: path)
                try? await Task.sleep(nanoseconds: UInt64((2 + attempt)) * 1_000_000_000)
            }
        }
        .refreshable { session.browse(sourceID: sourceID, path: path) }
    }

    private var parentOnlyList: some View {
        List {
            parentRow
        }
    }

    private var parentRow: some View {
        Button(action: onGoBack) {
            Label(parentFolderLabel, systemImage: "arrow.turn.up.left")
        }
        .tint(.primary)
    }

    private func folderList(_ listing: RemoteListing) -> some View {
        ScrollViewReader { proxy in
            List {
                if canGoToParent {
                    parentRow
                }
                ForEach(listing.items) { item in
                    switch item.kind {
                    case .directory:
                        Button {
                            Haptics.selection()
                            session.lastOpenedChild[childKey] = item.path
                            onOpenFolder(RemoteFolderRoute(sourceID: sourceID, path: item.path, title: item.name))
                        } label: {
                            Label(item.name, systemImage: "folder")
                        }
                        .tint(.primary)
                        .id(item.path)
                    case .audio:
                        audioRow(item)
                            .id(item.path)
                    }
                }
            }
            .onAppear {
                scrollToFocus(using: proxy)
                restoreLastOpenedChild(using: proxy)
            }
            .onChange(of: listing.items.count) {
                scrollToFocus(using: proxy)
                restoreLastOpenedChild(using: proxy)
            }
        }
    }

    /// On returning from a sub-folder, scrolls back to the folder that was opened.
    /// Retries a few times since the rows may not be laid out on the first frame.
    private func restoreLastOpenedChild(using proxy: ScrollViewProxy) {
        guard let child = session.lastOpenedChild[childKey],
              listing?.items.contains(where: { $0.path == child }) == true else { return }
        Task { @MainActor in
            for delayMs in [80, 220, 400] {
                try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
                proxy.scrollTo(child, anchor: .center)
            }
        }
    }

    /// Scrolls to (and the row highlights) the "Locate File" target, if it lives
    /// in this folder.
    private func scrollToFocus(using proxy: ScrollViewProxy) {
        guard let focusFilePath,
              (focusFilePath as NSString).deletingLastPathComponent == path,
              listing?.items.contains(where: { $0.path == focusFilePath }) == true else { return }
        withAnimation { proxy.scrollTo(focusFilePath, anchor: .center) }
    }

    /// A single audio file: tapping plays it next; the ••• menu mirrors the
    /// player's per-file operations (Play Now / Play Next / Add to Queue /
    /// Add to Playlist).
    private func audioRow(_ item: RemoteFileItem) -> some View {
        let isCurrent = session.isNowPlaying(sourceID: sourceID, path: item.path)
        return HStack(spacing: 8) {
            FavoriteStarButton(session: session, track: queueTrack(from: item))

            // Tapping the track row opens its action menu (Play Now / Play Next /
            // Add to Queue / Favorite / Add to Playlist).
            Menu {
                trackActions(item)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: nowPlayingSymbol(isCurrent: isCurrent, isPlaying: session.isPlaying))
                        .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    Text(trackTitle(item))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "ellipsis")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .tint(.primary)
        }
        .listRowBackground((isCurrent || item.path == focusFilePath) ? Color.accentColor.opacity(0.15) : nil)
        .swipeActions(edge: .trailing) {
            Button {
                session.enqueue([queueTrack(from: item)])
            } label: {
                Label("Add to Queue", systemImage: "text.badge.plus")
            }
            .tint(.accentColor)
        }
    }

    /// The shared per-file action menu used by the ••• button.
    @ViewBuilder
    private func trackActions(_ item: RemoteFileItem) -> some View {
        let track = queueTrack(from: item)
        Button {
            session.setQueue([track], startAt: 0)
        } label: {
            Label("Play Now", systemImage: "play.fill")
        }
        if let index = audioItems.firstIndex(where: { $0.path == item.path }) {
            Button {
                session.setQueue(queueTracks(from: audioItems), startAt: index)
            } label: {
                Label("Play from Here", systemImage: "play.circle")
            }
        }
        Button {
            session.playNext([track])
        } label: {
            Label("Play Next", systemImage: "text.insert")
        }
        Button {
            session.enqueue([track])
        } label: {
            Label("Add to Queue", systemImage: "text.badge.plus")
        }
        AddToFavoritesButton(session: session, track: track)
        AddToPlaylistMenu(session: session, track: track)
    }

    // MARK: - Helpers

    private func queueTracks(from items: [RemoteFileItem]) -> [RemoteQueueTrack] {
        items.map(queueTrack(from:))
    }

    private func queueTrack(from item: RemoteFileItem) -> RemoteQueueTrack {
        RemoteQueueTrack(sourceID: sourceID, path: item.path, title: trackTitle(item))
    }

    private func trackTitle(_ item: RemoteFileItem) -> String {
        (item.name as NSString).deletingPathExtension
    }
}

/// The two-step "delete all tracks" confirmation, in its own modifier so the view's modifier
/// chain stays short enough for the compiler to type-check.
private struct ClearAllConfirmation: ViewModifier {
    let name: String
    let count: Int
    @Binding var isAsking: Bool
    @Binding var isFinal: Bool
    let onConfirm: () -> Void

    private var message: String {
        "All \(count) tracks will be removed from “\(name)”. The audio files themselves are not deleted."
    }

    func body(content: Content) -> some View {
        content
            .alert("Delete all tracks?", isPresented: $isAsking) {
                Button("Cancel", role: .cancel) {}
                Button("Continue", role: .destructive) {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 400_000_000)     // let this alert close first
                        isFinal = true
                    }
                }
            } message: {
                Text(message)
            }
            .alert("Are you sure?", isPresented: $isFinal) {
                Button("Cancel", role: .cancel) {}
                Button("Delete All", role: .destructive, action: onConfirm)
            } message: {
                Text("This can't be undone.")
            }
    }
}

/// Results of a library search on the player: folders and files whose names match, grouped by
/// source. Tap a folder to open it, a file to play it; the ••• menu has the other actions.
struct SearchResultsView: View {
    @ObservedObject var session: RemoteSession
    let query: String
    var onOpen: (LibraryRoute) -> Void

    /// Only the answer to the query being shown (a late answer to an earlier one is ignored).
    private var results: RemoteSearchResults? {
        guard let results = session.searchResults, results.query == query else { return nil }
        return results
    }

    var body: some View {
        Group {
            if let results {
                if results.groups.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    resultsList(results)
                }
            } else {
                ProgressView("Searching…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func resultsList(_ results: RemoteSearchResults) -> some View {
        List {
            ForEach(results.groups) { group in
                Section(group.sourceName) {
                    ForEach(group.items) { item in
                        row(item, sourceID: group.sourceID)
                    }
                }
            }
        }
    }

    private func row(_ item: RemoteFileItem, sourceID: String) -> some View {
        let isFolder = item.kind == .directory
        let title = isFolder ? item.name : (item.name as NSString).deletingPathExtension
        let parent = (item.path as NSString).deletingLastPathComponent
        return Button {
            if isFolder {
                onOpen(.folder(RemoteFolderRoute(sourceID: sourceID, path: item.path, title: item.name)))
            } else {
                session.setQueue([queueTrack(item, sourceID: sourceID)], startAt: 0)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isFolder ? "folder.fill" : "music.note")
                    .foregroundStyle(isFolder ? Color.accentColor : Color.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).lineLimit(1)
                    if !parent.isEmpty {
                        Text(parent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .tint(.primary)
        .contextMenu {
            if isFolder {
                Button {
                    session.playFolder(sourceID: sourceID, path: item.path)
                } label: {
                    Label("Play Folder", systemImage: "play.fill")
                }
            } else {
                let track = queueTrack(item, sourceID: sourceID)
                Button { session.setQueue([track], startAt: 0) } label: {
                    Label("Play Now", systemImage: "play.fill")
                }
                Button { session.playNext([track]) } label: {
                    Label("Play Next", systemImage: "text.insert")
                }
                Button { session.enqueue([track]) } label: {
                    Label("Add to Queue", systemImage: "text.badge.plus")
                }
            }
        }
    }

    private func queueTrack(_ item: RemoteFileItem, sourceID: String) -> RemoteQueueTrack {
        RemoteQueueTrack(sourceID: sourceID, path: item.path,
                         title: (item.name as NSString).deletingPathExtension)
    }
}

// MARK: - Long-press reordering

/// Touch and hold a list row, then drag it to reorder, without switching the list into Edit mode.
/// `index` is the row's position in the underlying array and `move(from, toOffset)` moves one
/// element with the meaning of `Array.move(fromOffsets:toOffset:)`. Stays out of the way while
/// the list is in Edit mode (`isEnabled` false), where the handles do the job.
private struct RowReorder: ViewModifier {
    let index: Int
    let isEnabled: Bool
    @Binding var dragging: Int?
    let move: (_ from: Int, _ toOffset: Int) -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .onDrag {
                    dragging = index
                    return NSItemProvider(object: "fwplayer-row-reorder" as NSString)
                }
                .onDrop(of: [UTType.text], delegate: ReorderDropDelegate(index: index, dragging: $dragging, move: move))
        } else {
            content
        }
    }
}

private struct ReorderDropDelegate: DropDelegate {
    let index: Int
    @Binding var dragging: Int?
    let move: (_ from: Int, _ toOffset: Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let from = dragging, from != index else { return }
        move(from, from < index ? index + 1 : index)     // down: after this row; up: before it
        dragging = index
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

extension View {
    func reorderable(index: Int, isEnabled: Bool = true, dragging: Binding<Int?>,
                     move: @escaping (_ from: Int, _ toOffset: Int) -> Void) -> some View {
        modifier(RowReorder(index: index, isEnabled: isEnabled, dragging: dragging, move: move))
    }
}

private struct ReorderGrip: ViewModifier {
    let index: Int
    @Binding var dragging: Int?
    let title: String

    func body(content: Content) -> some View {
        content.onDrag {
            dragging = index
            return NSItemProvider(object: "fwplayer-row-reorder" as NSString)
        } preview: {
            Text(title).padding(8).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct ReorderDropTarget: ViewModifier {
    let index: Int
    @Binding var dragging: Int?
    let move: (_ from: Int, _ toOffset: Int) -> Void

    func body(content: Content) -> some View {
        content.onDrop(of: [UTType.text],
                       delegate: ReorderDropDelegate(index: index, dragging: $dragging, move: move))
    }
}

extension View {
    func reorderGrip(index: Int, dragging: Binding<Int?>, title: String) -> some View {
        modifier(ReorderGrip(index: index, dragging: dragging, title: title))
    }

    func reorderDropTarget(index: Int, dragging: Binding<Int?>,
                           move: @escaping (_ from: Int, _ toOffset: Int) -> Void) -> some View {
        modifier(ReorderDropTarget(index: index, dragging: dragging, move: move))
    }
}
