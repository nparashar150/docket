import XCTest

/// Values from a real capture on macOS 26: up runs negative, down positive.
final class MissionControlSwipeTests: XCTestCase {

    func testOpeningTracksTheFingersBothWays() {
        let swipe = MissionControlSwipe.opening
        XCTAssertEqual(swipe.revealed(at: 0), 0)
        XCTAssertEqual(swipe.revealed(at: -0.1), 0.1, accuracy: 1e-9)
        XCTAssertEqual(swipe.revealed(at: -0.3), 0.3, accuracy: 1e-9)
        // Dragged back past where it started, and on past the end.
        XCTAssertEqual(swipe.revealed(at: 0.2), 0)
        XCTAssertEqual(swipe.revealed(at: -1.4), 1)
    }

    func testClosingRetractsFromFullyOut() {
        let swipe = MissionControlSwipe.closing
        XCTAssertEqual(swipe.revealed(at: 0), 1)
        XCTAssertEqual(swipe.revealed(at: 0.3), 0.7, accuracy: 1e-9)
        XCTAssertEqual(swipe.revealed(at: -0.2), 1)
    }

    func testLettingGo() {
        // Slow full swipes and flicks from the capture all committed.
        XCTAssertTrue(MissionControlSwipe.opening.commits(at: -0.6679, velocity: -1.048))
        XCTAssertTrue(MissionControlSwipe.opening.commits(at: -0.1672, velocity: -5.888))
        XCTAssertTrue(MissionControlSwipe.closing.commits(at: 0.1753, velocity: 6.027))
        // A small nudge released at rest springs back.
        XCTAssertFalse(MissionControlSwipe.opening.commits(at: -0.2, velocity: 0))
        // Pushed up, then dragged back down and let go moving down.
        XCTAssertFalse(MissionControlSwipe.opening.commits(at: -0.4, velocity: 2))
        // A system cancel.
        XCTAssertFalse(MissionControlSwipe.closing.commits(at: 0, velocity: 0))
    }
}
