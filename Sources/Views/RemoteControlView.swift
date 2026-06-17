import SwiftUI

/// The remote control surface for a single FWPlayer: now-playing info, a seek
/// bar, transport buttons, and the live queue. Sends commands over the network
/// and reflects the state pushed back by the player.
struct RemoteControlView: View {
    @StateObject private var session: RemoteSession
    /// Local mirror of the scrubber position while the user is dragging.
    @State private var scrubTime: TimeInterval = 0

    init(session: RemoteSession) {
        _session = StateObject(wrappedValue: session)
    }

    var body: some View {
        VStack(spacing: 0) {
            switch session.status {
            case .connecting:
                Spacer(); ProgressView("Connecting…"); Spacer()
            case .failed(let message):
                Spacer(); failure(message); Spacer()
            default:
                content
            }
        }
        .navigationTitle(session.playerName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { session.connect() }
        .onDisappear { session.disconnect() }
    }

    // MARK: - Connected content

    private var content: some View {
        VStack(spacing: 24) {
            nowPlaying
            seekBar
            transportControls
            Divider()
            queue
        }
        .padding()
    }

    private var nowPlaying: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .frame(maxWidth: .infinity, minHeight: 140)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16))

            Text(session.currentTrack?.title ?? "Nothing Playing")
                .font(.title3.weight(.semibold))
                .lineLimit(1)
            Text(session.currentTrack?.artist ?? session.currentTrack?.album ?? " ")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var seekBar: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { session.isScrubbing ? scrubTime : session.currentTime },
                    set: { scrubTime = $0 }
                ),
                in: 0...max(session.duration, 0.1),
                onEditingChanged: { editing in
                    if editing {
                        scrubTime = session.currentTime
                        session.isScrubbing = true
                    } else {
                        session.isScrubbing = false
                        session.seek(to: scrubTime)
                    }
                }
            )
            .disabled(session.duration <= 0)

            HStack {
                Text(Self.timeString(session.isScrubbing ? scrubTime : session.currentTime))
                Spacer()
                Text(Self.timeString(session.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
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
                        Button {
                            session.play(index: index)
                        } label: {
                            HStack {
                                if index == state.currentIndex {
                                    Image(systemName: session.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                                        .foregroundStyle(.tint)
                                        .frame(width: 20)
                                } else {
                                    Text("\(index + 1)")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title).lineLimit(1)
                                    if let artist = track.artist {
                                        Text(artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .tint(.primary)
                    }
                }
                .listStyle(.plain)
            } else {
                Text("The player's queue is empty. Start something from FWPlayer.")
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
            Button("Try Again") { session.connect() }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Helpers

    static func timeString(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let total = Int(time)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
