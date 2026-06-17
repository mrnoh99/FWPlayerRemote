import SwiftUI

/// Root of the "add music" sheet: lists the player's sources to browse and its
/// playlists to queue directly. Picking music here rebuilds the player's queue
/// over the network.
struct LibraryView: View {
    @ObservedObject var session: RemoteSession
    /// Closes the whole browsing sheet (used after a selection rebuilds the queue).
    let dismissSheet: () -> Void

    var body: some View {
        Group {
            if let library = session.library {
                List {
                    Section("Sources") {
                        if library.sources.isEmpty {
                            Text("No sources on the player.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(library.sources) { source in
                            NavigationLink {
                                FolderBrowseView(
                                    session: session,
                                    sourceID: source.id,
                                    path: "",
                                    title: source.displayName,
                                    dismissSheet: dismissSheet
                                )
                            } label: {
                                Label(source.displayName, systemImage: source.symbolName)
                            }
                        }
                    }

                    if !library.playlists.isEmpty {
                        Section("Playlists") {
                            ForEach(library.playlists) { playlist in
                                Button {
                                    session.setQueue(playlist.tracks, startAt: 0)
                                    dismissSheet()
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
                }
            } else {
                ProgressView("Loading library…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Add Music")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismissSheet() }
            }
        }
        .onAppear { session.requestLibrary() }
        .refreshable { session.requestLibrary() }
    }
}

/// Browses one folder within a source. Tapping a sub-folder pushes another
/// browser; tapping a track replaces the player's queue with this folder's audio
/// (starting at that track); swiping a track appends it to the queue.
struct FolderBrowseView: View {
    @ObservedObject var session: RemoteSession
    let sourceID: String
    let path: String
    let title: String
    let dismissSheet: () -> Void

    private var listing: RemoteListing? { session.listing(sourceID: sourceID, path: path) }
    private var audioItems: [RemoteFileItem] { listing?.items.filter { $0.kind == .audio } ?? [] }

    var body: some View {
        Group {
            if let listing {
                if let error = listing.error {
                    ContentUnavailableView("Couldn't Load Folder", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if listing.items.isEmpty {
                    ContentUnavailableView("Empty Folder", systemImage: "folder", description: Text("No folders or FLAC/WAV files here."))
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
            if !audioItems.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        session.setQueue(queueTracks(from: audioItems), startAt: 0)
                        dismissSheet()
                    } label: {
                        Label("Play All", systemImage: "play.fill")
                    }
                }
            }
        }
        .onAppear { session.browse(sourceID: sourceID, path: path) }
        .refreshable { session.browse(sourceID: sourceID, path: path) }
    }

    private func folderList(_ listing: RemoteListing) -> some View {
        List {
            ForEach(listing.items) { item in
                switch item.kind {
                case .directory:
                    NavigationLink {
                        FolderBrowseView(
                            session: session,
                            sourceID: sourceID,
                            path: item.path,
                            title: item.name,
                            dismissSheet: dismissSheet
                        )
                    } label: {
                        Label(item.name, systemImage: "folder")
                    }
                case .audio:
                    Button {
                        playFolder(startingAt: item)
                    } label: {
                        Label(trackTitle(item), systemImage: "music.note")
                            .tint(.primary)
                    }
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
        dismissSheet()
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
