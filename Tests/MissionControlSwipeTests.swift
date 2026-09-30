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
        // Every let-go from two captures, all of which committed.
        let opens = [(-0.6679, -1.048), (-0.1672, -5.888), (-0.0922, -1.666), (-0.1259, -2.785),
                     (-0.4106, -1.206), (-0.2773, -3.361), (-0.2478, -3.592), (-0.1292, -3.802)]
        let closes = [(0.1753, 6.027), (0.1228, 1.647), (0.1478, 2.906), (0.1870, 3.635)]
        for (p, v) in opens { XCTAssertTrue(MissionControlSwipe.opening.commits(at: p, velocity: v), "\(p) \(v)") }
        for (p, v) in closes { XCTAssertTrue(MissionControlSwipe.closing.commits(at: p, velocity: v), "\(p) \(v)") }
        // A small nudge released at rest springs back.
        XCTAssertFalse(MissionControlSwipe.opening.commits(at: -0.2, velocity: 0))
        // Pushed up, then dragged back down and let go moving down.
        XCTAssertFalse(MissionControlSwipe.opening.commits(at: -0.4, velocity: 2))
        // A system cancel.
        XCTAssertFalse(MissionControlSwipe.closing.commits(at: 0, velocity: 0))
    }
}
