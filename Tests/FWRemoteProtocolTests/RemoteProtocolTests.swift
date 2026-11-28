import XCTest
@testable import FWRemoteProtocol

/// The wire protocol shared with FWPlayer: every message survives encoding, and
/// decoding tolerates what older and newer players send.
final class RemoteProtocolTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()
    private let decoder = JSONDecoder()

    private let track = RemoteQueueTrack(sourceID: "local:1", path: "Jazz/So What.flac", title: "So What")

    private var allCommands: [RemoteCommand] {
        [
            .authenticate(pin: "1234"), .requestState, .togglePlayPause, .play, .pause, .next, .previous,
            .seek(time: 12.5), .playIndex(index: 3), .stop, .cancelLoading, .showNowPlaying,
            .search(query: "miles"), .toggleShuffle, .cycleRepeat, .setVolume(volume: 0.4),
            .requestLibrary, .browse(sourceID: "local:1", path: "Jazz"),
            .setQueue(tracks: [track], startAt: 0, playlistID: nil),
            .setQueue(tracks: [track], startAt: 0, playlistID: fwFavoritesPlaylistID),
            .enqueue(tracks: [track]), .playNext(tracks: [track]), .removeFromQueue(at: [1, 2]),
            .clearQueue, .moveQueue(from: [0], to: 2),
            .playFolder(sourceID: "local:1", path: "Jazz", recursive: true),
            .createPlaylist(name: "Late", tracks: [track]), .renamePlaylist(playlistID: "p", name: "Later"),
            .deletePlaylist(playlistID: "p"), .clearPlaylist(playlistID: "p"),
            .addToPlaylist(playlistID: "p", tracks: [track]), .movePlaylistEntry(playlistID: "p", from: [0], to: 1),
            .removePlaylistEntry(playlistID: "p", at: [0]), .toggleFavorite(track: track),
        ]
    }

    private func state() -> PlaybackState {
        let remoteTrack = RemoteTrack(id: "local:1|Jazz/So What.flac", title: "So What", artist: "Miles Davis",
                                      album: "Kind of Blue", year: "1959", genre: "Jazz", duration: 562,
                                      sourceID: "local:1", path: "Jazz/So What.flac")
        return PlaybackState(deviceName: "Mac Studio", isPlaying: true, isLoading: false, currentTime: 30,
                             duration: 562, currentIndex: 0, queue: [remoteTrack], history: [remoteTrack],
                             errorMessage: nil, audioFormat: "96 kHz", isShuffled: true, repeatMode: 1,
                             volume: 0.8)
    }

    func testEveryCommandRoundTrips() throws {
        for command in allCommands {
            let data = try encoder.encode(RemoteMessage.command(command))
            guard case .command(let decoded) = try decoder.decode(RemoteMessage.self, from: data) else {
                return XCTFail("\(command) decoded as another message")
            }
            XCTAssertEqual(decoded, command)
        }
    }

    func testPlayerMessagesRoundTrip() throws {
        let messages: [RemoteMessage] = [
            .pairingRequired(PairingRequired(deviceName: "Mac Studio")),
            .authResult(AuthResult(success: false, message: "Incorrect PIN.")),
            .state(state()),
            .catalogInfo(RemoteCatalogInfo(trackID: "t", albumTitle: "Kind of Blue", lyrics: "words",
                                           source: "file tags")),
        ]
        for message in messages {
            let data = try encoder.encode(message)
            let again = try encoder.encode(try decoder.decode(RemoteMessage.self, from: data))
            XCTAssertEqual(again, data, String(decoding: data, as: UTF8.self))
        }
    }

    func testStateSurvivesExactly() throws {
        let original = state()
        let data = try encoder.encode(RemoteMessage.state(original))
        guard case .state(let decoded) = try decoder.decode(RemoteMessage.self, from: data) else {
            return XCTFail("not a state message")
        }
        XCTAssertEqual(decoded, original)
    }

    /// A newer player may send fields this remote doesn't know yet.
    func testUnknownFieldsAreIgnored() throws {
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoder.encode(state())) as? [String: Any])
        json["fieldFromTheFuture"] = ["anything": 1]
        let data = try JSONSerialization.data(withJSONObject: json)
        XCTAssertEqual(try decoder.decode(PlaybackState.self, from: data), state())
    }

    /// An older player leaves out the optional track fields added later.
    func testOptionalTrackFieldsMayBeMissing() throws {
        let data = Data(#"{"id":"a","title":"Blue in Green"}"#.utf8)
        let decoded = try decoder.decode(RemoteTrack.self, from: data)
        XCTAssertEqual(decoded.title, "Blue in Green")
        XCTAssertNil(decoded.sourceID)
        XCTAssertNil(decoded.composer)
    }

    func testArtistLineJoinsComposerWorkAndArtist() {
        var track = RemoteTrack(id: "a", title: "Symphony No. 5: I. Allegro con brio", artist: "Kleiber")
        XCTAssertEqual(track.artistLine, "Kleiber")
        track.composer = "Beethoven"
        track.work = "Symphony No. 5"
        XCTAssertEqual(track.artistLine, "Beethoven · Kleiber", "the work is left out when the title says it")
        track.title = "I. Allegro con brio"
        XCTAssertEqual(track.artistLine, "Beethoven · Symphony No. 5 · Kleiber")
        XCTAssertNil(RemoteTrack(id: "b", title: "x").artistLine)
    }
}
