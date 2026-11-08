import XCTest
@testable import Sidecheck

/// Pins the hand-rolled decode fallbacks that protect persisted data: stale
/// kinds and missing fields must never fail a whole persisted payload.
final class DecodeFallbackTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: BackgroundSpec (stale kinds removed in v0.9)

    func testRemovedKindBlobsFallsBackToBubbles() throws {
        XCTAssertEqual(try decode(BackgroundSpec.self, #"{"kind":"blobs"}"#).kind, .bubbles)
    }

    func testRemovedKindThemeFallsBackToBubbles() throws {
        XCTAssertEqual(try decode(BackgroundSpec.self, #"{"kind":"theme"}"#).kind, .bubbles)
    }

    func testEmptySpecGivesDefaults() throws {
        let spec = try decode(BackgroundSpec.self, "{}")
        XCTAssertEqual(spec.kind, .bubbles)
        XCTAssertEqual(spec.gradientAngle, 0)
        XCTAssertTrue(spec.isMuted)
        XCTAssertEqual(spec.crop, CropSpec.default)
    }

    func testGradientSpecRoundTrips() throws {
        let spec = try decode(BackgroundSpec.self,
                              #"{"kind":"gradient","gradientID":"ocean","gradientAngle":45}"#)
        XCTAssertEqual(spec.kind, .gradient)
        XCTAssertEqual(spec.gradientID, "ocean")
        XCTAssertEqual(spec.gradientAngle, 45)
    }

    // MARK: AppUsage / UsageDay (Screen Time persistence)

    func testAppUsageMissingFieldsGetDefaults() throws {
        let usage = try decode(AppUsage.self, #"{"name":"Xcode"}"#)
        XCTAssertEqual(usage.name, "Xcode")
        XCTAssertEqual(usage.seconds, 0)
        XCTAssertEqual(usage.hourly, Array(repeating: 0, count: 24))
    }

    func testAppUsageMissingNameFallsBack() throws {
        XCTAssertEqual(try decode(AppUsage.self, "{}").name, "Unknown")
    }

    func testUsageDayMissingAppsIsEmpty() throws {
        let day = try decode(UsageDay.self, #"{"date":"2026-11-09"}"#)
        XCTAssertEqual(day.date, "2026-11-09")
        XCTAssertTrue(day.apps.isEmpty)
    }

    // MARK: HeardTrack (listening history persistence)

    func testHeardTrackMissingFieldsGetDefaults() throws {
        let track = try decode(HeardTrack.self, #"{"key":"Spotify|T|A"}"#)
        XCTAssertEqual(track.key, "Spotify|T|A")
        XCTAssertEqual(track.title, "Unknown")
        XCTAssertEqual(track.seconds, 0)
        XCTAssertEqual(track.playCount, 0)
    }

    // MARK: CropSpec (wallpaper pan/zoom persistence)

    func testCropSpecMissingFieldsGetDefaults() throws {
        let crop = try decode(CropSpec.self, "{}")
        XCTAssertEqual(crop.scale, 1)
        XCTAssertEqual(crop.offsetX, 0)
        XCTAssertEqual(crop.offsetY, 0)
    }
}
