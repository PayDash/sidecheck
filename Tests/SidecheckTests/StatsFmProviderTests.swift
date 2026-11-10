import XCTest
@testable import Sidecheck

/// The stats.fm URL builder must never crash on a username — it used to
/// force-unwrap `URLComponents(string:)`, which returns nil for any character
/// that's illegal raw in a URL (spaces, non-ASCII, …), and a persisted bad
/// username re-crashed the Music page on every open.
final class StatsFmProviderTests: XCTestCase {
    func testUsernameWithSpaceIsPercentEncoded() throws {
        let url = try XCTUnwrap(StatsFmProvider.makeURL(path: "/users/John Doe", query: [:]))
        XCTAssertEqual(url.absoluteString, "https://api.stats.fm/api/v1/users/John%20Doe")
    }

    func testNonASCIIUsernameIsPercentEncoded() throws {
        let url = try XCTUnwrap(StatsFmProvider.makeURL(path: "/users/José", query: [:]))
        XCTAssertEqual(url.absoluteString, "https://api.stats.fm/api/v1/users/Jos%C3%A9")
    }

    func testQueryItemsSurvive() throws {
        let url = try XCTUnwrap(StatsFmProvider.makeURL(path: "/users/x/streams/recent", query: ["limit": "40"]))
        XCTAssertEqual(url.host, "api.stats.fm")
        XCTAssertTrue(url.absoluteString.contains("limit=40"))
    }
}
