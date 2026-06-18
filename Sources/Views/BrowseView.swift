import SwiftUI

/// Root of the library browser: lists the player's sources (local folders, SMB
/// shares) and playlists. Picking music rebuilds the player's queue over the network.
struct LibraryView: View {
    @ObservedObject var session: RemoteSession
    var onDidStartPlayback: (() -> Void)?

    var body: some View {
        Group {
            if let library = session.library {
                List {
                    if !library.sources.isEmpty {
                        Section("Sources") {
                            ForEach(library.sources) { source in
                                NavigationLink {
                                    FolderBrowseView(
                                        session: session,
                                        sourceID: source.id,
                                        path: "",
                                        title: source.displayName,
                                        onDidStartPlayback: onDidStartPlayback
                                    )
                                } label: {
                                    Label(source.displayName, systemImage: source.symbolName)
                                }
                            }
                        }
                    }

                    Section("Playlists") {
                        if library.playlists.isEmpty {
                            Text("No playlists on the player.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(library.playlists) { playlist in
                            NavigationLink {
                                PlaylistBrowseView(
                                    session: session,
                                    playlist: playlist,
                                    onDidStartPlayback: onDidStartPlayback
                                )
                            } label: {
                                HStack {
                                    Label(playlist.name, systemImage: "music.note.list")
                                    Spacer()
                                    Text("\(playlist.tracks.count)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .disabled(playlist.tracks.isEmpty)
                        }
                    }
                }
            } else {
                ProgressView("Loading library…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { session.requestLibrary() }
        .refreshable { session.requestLibrary() }
    }
}

/// Shows one playlist's tracks; tap a track or use Play All to queue on the player.
struct PlaylistBrowseView: View {
    @ObservedObject var session: RemoteSession
    let playlist: RemotePlaylist
    var onDidStartPlayback: (() -> Void)?

    var body: some View {
        List {
            ForEach(Array(playlist.tracks.enumerated()), id: \.offset) { index, track in
                Button {
                    session.setQueue(playlist.tracks, startAt: index, playlistID: playlist.id)
                    onDidStartPlayback?()
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
            }
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    session.setQueue(playlist.tracks, startAt: 0, playlistID: playlist.id)
                    onDidStartPlayback?()
                } label: {
                    Label("Play All", systemImage: "play.fill")
                }
                .disabled(playlist.tracks.isEmpty)
            }
        }
    }
}

/// Browses one folder within a source. Sub-folders can be opened or played
/// recursively; audio files start playback from the current folder queue.
struct FolderBrowseView: View {
    @ObservedObject var session: RemoteSession
    @Environment(\.dismiss) private var dismiss
    let sourceID: String
    let path: String
    let title: String
    var onDidStartPlayback: (() -> Void)?

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
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canGoToParent {
                ToolbarItem(placement: .navigation) {
                    Button { dismiss() } label: {
                        Label("Parent Folder", systemImage: "chevron.left")
                    }
                }
            }
            if !audioItems.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        session.setQueue(queueTracks(from: audioItems), startAt: 0)
                        onDidStartPlayback?()
                    } label: {
                        Label("Play Folder", systemImage: "play.fill")
                    }
                }
            } else if path.isEmpty || listing?.items.contains(where: { $0.kind == .directory }) == true {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        session.playFolder(sourceID: sourceID, path: path, recursive: true)
                        onDidStartPlayback?()
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
        Button { dismiss() } label: {
            Label(parentFolderLabel, systemImage: "arrow.turn.up.left")
        }
        .tint(.primary)
    }

    private func folderList(_ listing: RemoteListing) -> some View {
        List {
            if canGoToParent {
                parentRow
            }
            ForEach(listing.items) { item in
                switch item.kind {
                case .directory:
                    NavigationLink {
                        FolderBrowseView(
                            session: session,
                            sourceID: sourceID,
                            path: item.path,
                            title: item.name,
                            onDidStartPlayback: onDidStartPlayback
                        )
                    } label: {
                        Label(item.name, systemImage: "folder")
                    }
                    .contextMenu {
                        Button {
                            session.playFolder(sourceID: sourceID, path: item.path, recursive: true)
                            onDidStartPlayback?()
                        } label: {
                            Label("Play Folder", systemImage: "play.fill")
                        }
                    }
                case .audio:
                    Button {
                        playFolder(startingAt: item)
                    } label: {
                        Label(trackTitle(item), systemImage: "music.note")
                    }
                    .tint(.primary)
                    .swipeActions(edge: .trailing) {
                        Button {
                            session.enqueue([queueTrack(from: item)])
                        } label: {
                            Label("Add to Queue", systemImage: "text.badge.plus")
                        }
                        .tint(.accentColor)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func playFolder(startingAt item: RemoteFileItem) {
        guard let index = audioItems.firstIndex(of: item) else { return }
        session.setQueue(queueTracks(from: audioItems), startAt: index)
        onDidStartPlayback?()
    }

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
