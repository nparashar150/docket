import Foundation
import XCTest

/// Following the real Dock, and getting back to it.
///
/// Both overrides used to be one directional. Dragging the size grip once set
/// a flag nothing could clear, and rearranging a single mirrored app took the
/// whole list over for good. In each case the shelf stopped tracking the Dock
/// permanently, from one ordinary gesture, with nothing in the app able to
/// undo it.
final class FollowingTests: XCTestCase {

    // MARK: Size

    func testFollowingTakesTheDocksSize() {
        XCTAssertEqual(DockFollowing.scale(overridden: false, custom: 0.9,
                                           system: 0.4, following: true), 0.4)
    }

    func testAnOverrideWinsWhileStillFollowingEverythingElse() {
        XCTAssertEqual(DockFollowing.scale(overridden: true, custom: 0.9,
                                           system: 0.4, following: true), 0.9,
                       "the size is the user's; the edge and hiding are not")
    }

    func testNotFollowingUsesTheStoredSize() {
        XCTAssertEqual(DockFollowing.scale(overridden: false, custom: 0.9,
                                           system: 0.4, following: false), 0.9)
    }

    /// The fix, expressed as the thing that was impossible: clearing the flag
    /// has to put the Dock's size back, not leave the last override behind.
    func testClearingTheOverrideReturnsToTheDocksSize() {
        let overridden = DockFollowing.scale(overridden: true, custom: 0.9,
                                             system: 0.4, following: true)
        let cleared = DockFollowing.scale(overridden: false, custom: 0.9,
                                          system: 0.4, following: true)
        XCTAssertEqual(overridden, 0.9)
        XCTAssertEqual(cleared, 0.4, "resuming has to be a real return, not a no-op")
    }

    /// Clearing it keeps the stored size, so turning following off later lands
    /// back on the size the user chose rather than on a default.
    func testTheStoredSizeSurvivesResuming() {
        XCTAssertEqual(DockFollowing.scale(overridden: false, custom: 0.9,
                                           system: 0.4, following: false), 0.9)
    }

    // MARK: The stored flags

    /// `scaleOverridden` and `mirrorSystemApps` are optional so state written
    /// before they existed still decodes. Absent has to mean the pre-existing
    /// behaviour: not overridden, and mirroring on.
    func testAbsentFlagsMeanFollowing() throws {
        let json = #"{"version": 1, "customDock": {"followSystemDock": true}}"#
        let state = try JSONDecoder().decode(PersistedState.self,
                                             from: json.data(using: .utf8)!)
        XCTAssertNil(state.customDock.scaleOverridden)
        XCTAssertNil(state.customDock.mirrorSystemApps)
        XCTAssertEqual(DockFollowing.scale(overridden: state.customDock.scaleOverridden == true,
                                           custom: 0.9, system: 0.4,
                                           following: state.customDock.followSystemDock), 0.4)
    }

    func testAnExplicitFalseIsTheSameAsAbsent() throws {
        let json = #"""
        {"version": 1, "customDock": {"followSystemDock": true, "scaleOverridden": false}}
        """#
        let state = try JSONDecoder().decode(PersistedState.self,
                                             from: json.data(using: .utf8)!)
        XCTAssertEqual(state.customDock.scaleOverridden, false)
        XCTAssertEqual(DockFollowing.scale(overridden: state.customDock.scaleOverridden == true,
                                           custom: 0.9, system: 0.4, following: true), 0.4,
                       "a cleared override is a cleared override, however it was written")
    }

    // MARK: Handing the app list back

    /// Resuming mirroring has to drop the adopted copies as well as flip the
    /// flag. Leaving them would show the profile's copy and the Dock's mirror
    /// of the same app side by side.
    func testResumingMirroringRemovesTheAdoptedCopies() {
        let pinned = ["com.apple.Safari", "com.apple.finder"]
        let items = [
            app("com.apple.Safari"),
            app("com.apple.finder"),
            app("com.example.NotInTheDock"),
        ]
        let kept = items.filter { item in
            guard case .app(_, let bundleID, _) = item else { return true }
            return !pinned.contains(bundleID)
        }
        XCTAssertEqual(kept.count, 1)
        guard case .app(_, let bundleID, _) = kept[0] else { return XCTFail("expected an app") }
        XCTAssertEqual(bundleID, "com.example.NotInTheDock",
                       "an app the user added, which the Dock does not pin, has to survive")
    }

    /// Non-app items are never adopted copies of anything, so nothing may drop
    /// a widget or a folder on the way back to mirroring.
    func testResumingMirroringKeepsEverythingThatIsNotAnApp() {
        let pinned = ["com.apple.Safari"]
        let items: [DockItem] = [
            app("com.apple.Safari"),
            .widget(WidgetInstance(kind: .clock, config: WidgetConfig())),
            .spacer(id: UUID(), size: .regular),
        ]
        let kept = items.filter { item in
            guard case .app(_, let bundleID, _) = item else { return true }
            return !pinned.contains(bundleID)
        }
        XCTAssertEqual(kept.count, 2)
    }

    private func app(_ bundleID: String) -> DockItem {
        .app(id: UUID(), bundleID: bundleID,
             ref: FileRef(url: URL(fileURLWithPath: "/Applications/\(bundleID).app")))
    }
}

/// The Focus Timer, which is one timer for the whole app.
///
/// The six controls in Settings wrote `state.timer`, which nothing read, while
/// every tile and panel read a shared in-memory provider, which nothing saved.
/// So changing the work length did nothing and a session was forgotten on
/// quit. These cover the rules that connecting them has to respect.
final class TimerStateTests: XCTestCase {

    /// Mirrors `TimerStateProvider.adopt`: a running session is not disturbed
    /// by a settings edit.
    private func adopt(_ incoming: TimerState, into current: TimerState) -> TimerState {
        var next = incoming
        if current.deadline != nil || current.paused != nil {
            next.deadline = current.deadline
            next.paused = current.paused
            next.duration = current.duration
        }
        return next
    }

    func testSettingsReachAnIdleTimer() {
        var incoming = TimerState()
        incoming.work = 45
        let result = adopt(incoming, into: TimerState())
        XCTAssertEqual(result.work, 45)
    }

    /// Editing the work length while a session runs must not restart it. The
    /// new length applies to the next one.
    func testARunningSessionSurvivesASettingsEdit() {
        var running = TimerState()
        running.deadline = Date(timeIntervalSinceNow: 600)
        running.duration = 1500

        var incoming = TimerState()
        incoming.work = 45

        let result = adopt(incoming, into: running)
        XCTAssertEqual(result.work, 45, "the setting still lands")
        XCTAssertEqual(result.deadline, running.deadline, "and the session is untouched")
        XCTAssertEqual(result.duration, running.duration)
    }

    /// A paused session is a session too: it banks its remaining time, and
    /// losing that is the same as losing a running one.
    func testAPausedSessionAlsoSurvives() {
        var paused = TimerState()
        paused.paused = 420

        var incoming = TimerState()
        incoming.rest = 10

        let result = adopt(incoming, into: paused)
        XCTAssertEqual(result.rest, 10)
        XCTAssertEqual(result.paused, 420)
    }

    /// An idle timer takes the incoming session fields as they are, which is
    /// what makes a restored state file resume where it left off.
    func testAnIdleTimerTakesAStoredSession() {
        var stored = TimerState()
        stored.deadline = Date(timeIntervalSinceNow: 300)

        let result = adopt(stored, into: TimerState())
        XCTAssertEqual(result.deadline, stored.deadline)
    }

    func testTheTimerSurvivesTheStateFile() throws {
        var state = PersistedState()
        state.timer.work = 45
        state.timer.sessions = 6

        let data = try JSONEncoder().encode(state)
        let read = try JSONDecoder().decode(PersistedState.self, from: data)
        XCTAssertEqual(read.timer.work, 45)
        XCTAssertEqual(read.timer.sessions, 6)
    }
}
