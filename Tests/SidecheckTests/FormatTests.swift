import XCTest
@testable import Sidecheck

/// Formatting helpers — the unit boundaries users actually see.
final class FormatTests: XCTestCase {
    func testDuration() {
        XCTAssertEqual(Format.duration(0), "0m")
        // Sub-minute totals floor to "0m" (seconds round, minutes floor).
        XCTAssertEqual(Format.duration(59.2), "0m")
        XCTAssertEqual(Format.duration(60), "1m")
        XCTAssertEqual(Format.duration(3662), "1h 01m")
        XCTAssertEqual(Format.duration(7200), "2h 00m")
    }

    func testUptime() {
        XCTAssertEqual(Format.uptime(59), "0m")
        XCTAssertEqual(Format.uptime(3600), "1h 0m")
        XCTAssertEqual(Format.uptime(7322), "2h 2m")
        XCTAssertEqual(Format.uptime(90061), "1d 1h")
    }

    func testRate() {
        XCTAssertEqual(Format.rate(0), "0 B/s")
        XCTAssertEqual(Format.rate(999), "999 B/s")
        XCTAssertEqual(Format.rate(1024), "1.0 KB/s")
        XCTAssertEqual(Format.rate(52_428.8), "51.2 KB/s")
        XCTAssertEqual(Format.rate(1_500_000), "1.43 MB/s")
    }

    func testBytes() {
        // ByteCountFormatter output is locale-aware; assert the scale, not
        // the exact rendering.
        XCTAssertTrue(Format.bytes(1024).contains("KB"))
        XCTAssertTrue(Format.bytes(1_048_576).contains("MB"))
        XCTAssertTrue(Format.bytes(5_368_709_120).contains("GB"))
    }

    func testClock() {
        XCTAssertEqual(Format.clock(0), "0:00")
        XCTAssertEqual(Format.clock(59.7), "1:00") // rounds to the nearest second
        XCTAssertEqual(Format.clock(222), "3:42")
        XCTAssertEqual(Format.clock(3723), "1:02:03")
    }
}
