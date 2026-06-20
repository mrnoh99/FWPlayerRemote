import SwiftUI

/// A folder location pushed onto the library's navigation stack. Hashable so the
/// stack can be driven (and restored) programmatically — e.g. by "Locate File".
struct RemoteFolderRoute: Hashable {
    let sourceID: String
    let path: String
    let title: String
}

/// A destination within the Library tab's value-based navigation stack.
enum LibraryRoute: Hashable {
    case folder(RemoteFolderRoute)
    case playlist(RemotePlaylist)

    var screenTitle: String {
        switch self {
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

    var body: some View {
        Group {
            if let library = session.library {
                List {
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
                        if library.playlists.isEmpty {
                            Text("No playlists on the player.")
                                .foregroundStyle(.secondary)
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
                            .disabled(playlist.tracks.isEmpty)
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

/// Shows one playlist's tracks; tap a track or use Play All to queue on the player.
struct PlaylistBrowseView: View {
    @ObservedObject var session: RemoteSession
    let playlist: RemotePlaylist
    /// Reveals the track's file in the Library (jumps to its containing folder).
    var onLocate: ((RemoteQueueTrack) -> Void)?

    var body: some View {
        List {
            ForEach(Array(playlist.tracks.enumerated()), id: \.offset) { index, track in
                HStack(spacing: 8) {
                    Button {
                        session.playNext([track])
                    } label: {
                        HStack {
                            Text("\(index + 1)")
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                            Text(track.title)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                    .tint(.primary)

                    Menu {
                        trackActions(track, at: index)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    session.setQueue(playlist.tracks, startAt: 0, playlistID: playlist.id)
                } label: {
                    Label("Play All", systemImage: "play.fill")
                }
                .disabled(playlist.tracks.isEmpty)
            }
        }
    }

    /// Per-track actions inside a playlist: mirrors the player's playlist menu
    /// (Play Now / Play from Here / Play Next / Add to Queue / Add to Playlist).
    @ViewBuilder
    private func trackActions(_ track: RemoteQueueTrack, at index: Int) -> some View {
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
        AddToFavoritesButton(session: session, track: track)
        AddToPlaylistMenu(session: session, track: track)
        if let onLocate {
            Button {
                onLocate(track)
            } label: {
                Label("Locate File", systemImage: "folder")
            }
        }
    }
}

/// "Add to Favorites" — adds the track to the player's built-in Favorites
/// playlist. Shown only once the library (and its Favorites playlist) is known.
struct AddToFavoritesButton: View {
    @ObservedObject var session: RemoteSession
    let track: RemoteQueueTrack

    var body: some View {
        if let favorites = session.library?.playlists.first(where: { $0.id == fwFavoritesPlaylistID }) {
            Button {
                session.addToPlaylist(favorites.id, tracks: [track])
            } label: {
                Label("Add to Favorites", systemImage: "star.fill")
            }
        }
    }
}

/// "Add to Playlist ▸" submenu listing every playlist on the player.
struct AddToPlaylistMenu: View {
    @ObservedObject var session: RemoteSession
    let track: RemoteQueueTrack

    var body: some View {
        if let playlists = session.library?.playlists, !playlists.isEmpty {
            Menu {
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
        .toolbar {
            if !audioItems.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        session.setQueue(queueTracks(from: audioItems), startAt: 0)
                    } label: {
                        Label("Play Folder", systemImage: "play.fill")
                    }
                }
            } else if path.isEmpty || listing?.items.contains(where: { $0.kind == .directory }) == true {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        session.playFolder(sourceID: sourceID, path: path, recursive: true)
                    } label: {
                        Label("Play All", systemImage: "play.fill")
                    }
                }
            }
        }
        .onAppear { session.browse(sourceID: sourceID, path: path) }
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
                            onOpenFolder(RemoteFolderRoute(sourceID: sourceID, path: item.path, title: item.name))
                        } label: {
                            Label(item.name, systemImage: "folder")
                        }
                        .tint(.primary)
                        .contextMenu {
                            Button {
                                session.playFolder(sourceID: sourceID, path: item.path, recursive: true)
                            } label: {
                                Label("Play Folder", systemImage: "play.fill")
                            }
                        }
                        .id(item.path)
                    case .audio:
                        audioRow(item)
                            .id(item.path)
                    }
                }
            }
            .onAppear { scrollToFocus(using: proxy) }
            .onChange(of: listing.items.count) { scrollToFocus(using: proxy) }
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
        HStack(spacing: 8) {
            Button {
                session.playNext([queueTrack(from: item)])
            } label: {
                Label(trackTitle(item), systemImage: "music.note")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tint(.primary)

            Menu {
                trackActions(item)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
        .listRowBackground(item.path == focusFilePath ? Color.accentColor.opacity(0.15) : nil)
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
