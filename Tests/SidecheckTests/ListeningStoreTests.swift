import XCTest
@testable import Sidecheck

/// Pins the listening-credit logic: the per-listen cap, replay detection,
/// chunk clamps and play counting — the math that turns polls into stats.
/// Each test drives its own UserDefaults suite, so nothing touches the real
/// persisted history. Assertions read `totalTrackedSeconds` /
/// `localTopTracks` (both aggregate the live `heard` store — the published
/// `history` array only refreshes on track changes). Gap slices since the
/// previous poll always land on the track that was playing when a session
/// ends, never on the one that just started.
@MainActor
final class ListeningStoreTests: XCTestCase {
    /// duration 180 → per-listen cap max(180 × 1.25, 30) = 225 s.
    private let a = TrackInfo(title: "A", artist: "X", album: "", duration: 180, artworkURL: nil, player: "Spotify")
    private let b = TrackInfo(title: "B", artist: "X", album: "", duration: 200, artworkURL: nil, player: "Spotify")

    private func freshStore() -> (store: ListeningStore, cleanup: () -> Void) {
        let suite = "sidecheck-listening-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (ListeningStore(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
    }

    private func playCount(_ store: ListeningStore, _ title: String) -> Int? {
        store.localTopTracks(range: .lifetime).first { $0.title == title }?.playCount
    }

    // MARK: Repeat listens

    func testRepeatListenAcrossOtherTracksCountsBothPlays() {
        let (store, cleanup) = freshStore(); defer { cleanup() }
        let start = Date()
        // First listen: 6 polls × 30 s apart → 150 s credited (t=0 primes).
        for i in 0..<6 {
            store.note(track: a, isPlaying: true, position: Double(i * 30 + 3), at: start.addingTimeInterval(Double(i * 30)))
        }
        store.note(track: b, isPlaying: true, position: 5, at: start.addingTimeInterval(180)) // finalize A → play 1
        // Second listen: 4 polls → 90 s more, then a finalizing B note.
        for i in 0..<4 {
            store.note(track: a, isPlaying: true, position: Double(i * 30 + 3), at: start.addingTimeInterval(Double(210 + i * 30)))
        }
        store.note(track: b, isPlaying: true, position: 5, at: start.addingTimeInterval(330)) // finalize A → play 2
        XCTAssertEqual(playCount(store, "A"), 2)
        // A: 150 + 30 (gap at the switch) + 90 + 30 (gap at the switch back)
        // = 300. B: its own 30 s gap credit at the second switch. The gap
        // slices land on the track that was playing, not the new one.
        XCTAssertEqual(store.totalTrackedSeconds, 330, accuracy: 0.001)
    }

    func testContinuousLoopKeepsCountingPastTheCap() {
        let (store, cleanup) = freshStore(); defer { cleanup() }
        let start = Date()
        // First pass: 150 s credited.
        for i in 0..<6 {
            store.note(track: a, isPlaying: true, position: Double(i * 30 + 3), at: start.addingTimeInterval(Double(i * 30)))
        }
        // The track loops: same key, position jumps back to 5 → fresh session.
        store.note(track: a, isPlaying: true, position: 5, at: start.addingTimeInterval(180))
        // Second pass: 4 more polls → 120 s more.
        for i in 0..<4 {
            store.note(track: a, isPlaying: true, position: Double(i * 30 + 8), at: start.addingTimeInterval(Double(210 + i * 30)))
        }
        store.note(track: b, isPlaying: true, position: 5, at: start.addingTimeInterval(360)) // finalize A → play 2
        XCTAssertEqual(playCount(store, "A"), 2)
        // A: 150 + 30 (rewind gap) + 120 + 30 (switch gap) = 330 — the old
        // lifetime cap would have stopped at 225.
        XCTAssertEqual(store.totalTrackedSeconds, 330, accuracy: 0.001)
    }

    // MARK: Stalled player

    func testStuckPlayerStopsAtTheSessionCap() {
        let (store, cleanup) = freshStore(); defer { cleanup() }
        let start = Date()
        // Position frozen while "playing": 9 crediting polls × 30 s would be
        // 270 s uncapped — the per-listen cap stops it at 225.
        for i in 0..<10 {
            store.note(track: a, isPlaying: true, position: 60, at: start.addingTimeInterval(Double(i * 30)))
        }
        XCTAssertEqual(store.totalTrackedSeconds, 225, accuracy: 0.001)
        XCTAssertEqual(playCount(store, "A"), 0)
    }

    // MARK: Play counting

    func testShortSessionDoesNotCountAPlay() {
        let (store, cleanup) = freshStore(); defer { cleanup() }
        let start = Date()
        store.note(track: a, isPlaying: true, position: 3, at: start) // prime
        store.note(track: a, isPlaying: true, position: 13, at: start.addingTimeInterval(10)) // 10 s
        store.note(track: b, isPlaying: true, position: 5, at: start.addingTimeInterval(12)) // finalize
        XCTAssertEqual(playCount(store, "A"), 0) // 12 s < the 20 s minimum
        // A 10 s + the 2 s gap at the switch — both land on A.
        XCTAssertEqual(store.totalTrackedSeconds, 12, accuracy: 0.001)
    }

    // MARK: Gap clamp

    func testLongGapCreditsAtMostThirtySeconds() {
        let (store, cleanup) = freshStore(); defer { cleanup() }
        let start = Date()
        store.note(track: a, isPlaying: true, position: 3, at: start) // prime
        // 150 s pass (player quit and came back, say) — credit at most 30 s.
        store.note(track: a, isPlaying: true, position: 10, at: start.addingTimeInterval(150))
        XCTAssertEqual(store.totalTrackedSeconds, 30, accuracy: 0.001)
    }
}
