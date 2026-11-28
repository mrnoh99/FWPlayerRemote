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
            .catalogInfo(RemoteCatalogInfo(trackID: "t", lyrics: "One\nTwo", source: "LRCLIB",
                                           syncedLyrics: [RemoteLyricLine(time: 1, text: "One"),
                                                          RemoteLyricLine(time: 2.5, text: "Two")])),
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

    /// An older player leaves out the state fields added later; they take their defaults.
    func testStateFromAnOlderPlayerUsesDefaults() throws {
        let data = Data(#"""
        {"deviceName":"Old iPad","isPlaying":false,"isLoading":false,"currentTime":0,"duration":0,"queue":[]}
        """#.utf8)
        let decoded = try decoder.decode(PlaybackState.self, from: data)
        XCTAssertEqual(decoded.deviceName, "Old iPad")
        XCTAssertEqual(decoded.history, [])
        XCTAssertFalse(decoded.isShuffled)
        XCTAssertEqual(decoded.repeatMode, 0)
        XCTAssertEqual(decoded.volume, 1.0)
        XCTAssertEqual(decoded.protocolVersion, 0)
        XCTAssertNil(decoded.currentIndex)
    }

    func testStateStillRequiresTheCoreFields() {
        let data = Data(#"{"isPlaying":false}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(PlaybackState.self, from: data))
    }

    /// Catalog info from a player without synced lyrics.
    func testSyncedLyricsAreOptional() throws {
        let data = Data(#"{"trackID":"t","lyrics":"words"}"#.utf8)
        XCTAssertNil(try decoder.decode(RemoteCatalogInfo.self, from: data).syncedLyrics)
    }

    func testLineIndexFollowsTime() {
        let lines = [RemoteLyricLine(time: 5, text: "a"), RemoteLyricLine(time: 10, text: "b"),
                     RemoteLyricLine(time: 20, text: "c")]
        XCTAssertNil(lines.lineIndex(at: 4.9))
        XCTAssertEqual(lines.lineIndex(at: 5), 0)
        XCTAssertEqual(lines.lineIndex(at: 19.9), 1)
        XCTAssertEqual(lines.lineIndex(at: 300), 2)
        XCTAssertNil([RemoteLyricLine]().lineIndex(at: 1))
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

    // MARK: Framing

    private func frame(length: Int, body: Int? = nil) -> Data {
        var data = Data([UInt8(length >> 24 & 0xFF), UInt8(length >> 16 & 0xFF),
                         UInt8(length >> 8 & 0xFF), UInt8(length & 0xFF)])
        data.append(Data(repeating: 0x20, count: body ?? length))
        return data
    }

    func testFrameStatusWaitsForAWholeFrame() {
        XCTAssertEqual(RemoteLink.frameStatus(of: Data([0, 0]), maxLength: 100), .incomplete)
        XCTAssertEqual(RemoteLink.frameStatus(of: frame(length: 10, body: 9), maxLength: 100), .incomplete)
        XCTAssertEqual(RemoteLink.frameStatus(of: frame(length: 10), maxLength: 100), .frame(length: 10))
        XCTAssertEqual(RemoteLink.frameStatus(of: frame(length: 0), maxLength: 100), .frame(length: 0))
    }

    func testFrameStatusRefusesOversizedFramesBeforeTheyArrive() {
        // A peer claiming a 4 GB frame is refused from the header alone, not buffered.
        XCTAssertEqual(RemoteLink.frameStatus(of: Data([0xFF, 0xFF, 0xFF, 0xFF]), maxLength: 64 << 20), .tooLarge)
        XCTAssertEqual(RemoteLink.frameStatus(of: frame(length: 101, body: 0), maxLength: 100), .tooLarge)
        XCTAssertEqual(RemoteLink.frameStatus(of: frame(length: 100), maxLength: 100), .frame(length: 100))
    }

    func testFrameStatusReadsABufferThatDoesNotStartAtZero() {
        let buffer = (Data([9, 9]) + frame(length: 3)).dropFirst(2)
        XCTAssertEqual(RemoteLink.frameStatus(of: buffer, maxLength: 100), .frame(length: 3))
    }
}
