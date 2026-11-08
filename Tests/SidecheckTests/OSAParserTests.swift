import XCTest
@testable import Sidecheck

/// Pins the osascript output parser: field order, the playing-row-wins rule,
/// position lookup, and the unit-separator format (a tab inside metadata must
/// not break a row).
final class OSAParserTests: XCTestCase {
    private func row(player: String, playing: Bool, title: String, artist: String,
                     album: String, duration: String, position: String, artwork: String) -> String {
        [player, playing ? "true" : "false", title, artist, album, duration, position, artwork]
            .joined(separator: OSAParser.fieldSeparator)
    }

    func testPlayingRowParses() {
        let out = row(player: "Spotify", playing: true, title: "Song A", artist: "Artist X",
                      album: "Album Q", duration: "210.5", position: "42.25", artwork: "https://img/a.jpg")
        let parsed = OSAParser.parse(out)
        let track = try! XCTUnwrap(parsed.track)
        XCTAssertEqual(track.title, "Song A")
        XCTAssertEqual(track.artist, "Artist X")
        XCTAssertEqual(track.album, "Album Q")
        XCTAssertEqual(track.duration, 210.5, accuracy: 0.001)
        XCTAssertEqual(track.artworkURL, "https://img/a.jpg")
        XCTAssertEqual(track.player, "Spotify")
        XCTAssertTrue(parsed.isPlaying)
        XCTAssertEqual(parsed.position, 42.25, accuracy: 0.001)
    }

    func testPausedRowReportsNotPlaying() {
        let out = row(player: "Music", playing: false, title: "Song B", artist: "Artist Y",
                      album: "", duration: "180", position: "60", artwork: "")
        let parsed = OSAParser.parse(out)
        XCTAssertNotNil(parsed.track)
        XCTAssertFalse(parsed.isPlaying)
        XCTAssertEqual(parsed.position, 60, accuracy: 0.001)
    }

    func testPlayingRowWinsWhenBothPlayersHaveRows() {
        let spotify = row(player: "Spotify", playing: true, title: "A", artist: "X",
                          album: "Q", duration: "200", position: "10", artwork: "")
        let music = row(player: "Music", playing: false, title: "B", artist: "Y",
                        album: "R", duration: "180", position: "60", artwork: "")
        let parsed = OSAParser.parse(spotify + "\n" + music)
        XCTAssertEqual(parsed.track?.player, "Spotify")
        XCTAssertTrue(parsed.isPlaying)
        XCTAssertEqual(parsed.position, 10, accuracy: 0.001) // current row's position
    }

    func testEmptyAndGarbageOutputGiveNothing() {
        XCTAssertTrue(OSAParser.parse("").track == nil)
        XCTAssertTrue(OSAParser.parse("some error text\n").track == nil)
        XCTAssertFalse(OSAParser.parse("").isPlaying)
        XCTAssertEqual(OSAParser.parse("").position, 0)
    }

    func testTitleContainingTabStillParses() {
        // The old tab-separated format shifted every field for this input.
        let out = row(player: "Spotify", playing: true, title: "Song\tWith\tTabs", artist: "X",
                      album: "Q", duration: "200", position: "5", artwork: "")
        let parsed = OSAParser.parse(out)
        XCTAssertEqual(parsed.track?.title, "Song\tWith\tTabs")
        XCTAssertEqual(parsed.track?.artist, "X")
        XCTAssertEqual(parsed.position, 5, accuracy: 0.001)
    }

    func testRowsWithoutUsableDurationAreSkipped() {
        let out = row(player: "Spotify", playing: true, title: "A", artist: "X",
                      album: "Q", duration: "", position: "10", artwork: "")
        XCTAssertTrue(OSAParser.parse(out).track == nil)
    }

    func testBlankTitleIsSkipped() {
        let out = row(player: "Spotify", playing: true, title: "   ", artist: "X",
                      album: "Q", duration: "200", position: "10", artwork: "")
        XCTAssertTrue(OSAParser.parse(out).track == nil)
    }

    func testMalformedRowIsSkipped() {
        let parsed = OSAParser.parse("Spotify\(OSAParser.fieldSeparator)true\(OSAParser.fieldSeparator)broken row")
        XCTAssertTrue(parsed.track == nil)
        XCTAssertEqual(parsed.position, 0)
    }

    func testEmptyArtworkGivesNil() {
        let out = row(player: "Music", playing: true, title: "B", artist: "Y",
                      album: "R", duration: "180", position: "1", artwork: "")
        XCTAssertNil(OSAParser.parse(out).track?.artworkURL)
    }
}
