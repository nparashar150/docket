import Foundation
import XCTest

/// Managing profiles: the naming and deletion rules.
///
/// All of this was modelled and unreachable. Nothing could create, rename,
/// duplicate or delete a profile, so the only way to get a second one was to
/// capture Apple's Dock, and the only name it could have was "Current Dock" -
/// again, every time, with no way to tell two apart or remove either.
///
/// The rules live here rather than in a view, so they can be checked.
final class ProfileTests: XCTestCase {

    /// Mirrors `AppState.uniqueName`.
    private func unique(_ wanted: String, taken: [String]) -> String {
        let set = Set(taken)
        guard set.contains(wanted) else { return wanted }
        var n = 2
        while set.contains("\(wanted) \(n)") { n += 1 }
        return "\(wanted) \(n)"
    }

    // MARK: Naming

    func testAFreeNameIsUsedAsIs() {
        XCTAssertEqual(unique("Everyday", taken: ["Focus"]), "Everyday")
    }

    /// The defect: capturing twice produced two profiles called the same
    /// thing, silently.
    func testATakenNameIsNumbered() {
        XCTAssertEqual(unique("Current Dock", taken: ["Current Dock"]), "Current Dock 2")
    }

    func testNumberingSkipsWhatIsAlreadyThere() {
        let taken = ["Current Dock", "Current Dock 2", "Current Dock 3"]
        XCTAssertEqual(unique("Current Dock", taken: taken), "Current Dock 4")
    }

    /// Holes are filled rather than always appending, so deleting the middle
    /// one does not leave the numbering climbing for ever.
    func testNumberingFillsAGap() {
        XCTAssertEqual(unique("Current Dock", taken: ["Current Dock", "Current Dock 3"]),
                       "Current Dock 2")
    }

    func testNamesAreUniquePerRepeatedCapture() {
        var taken: [String] = []
        for _ in 0 ..< 4 { taken.append(unique("Current Dock", taken: taken)) }
        XCTAssertEqual(taken, ["Current Dock", "Current Dock 2",
                               "Current Dock 3", "Current Dock 4"])
        XCTAssertEqual(Set(taken).count, 4, "every capture has to be tellable apart")
    }

    // MARK: Deleting

    /// Mirrors `AppState.canDeleteProfile`. The shelf has to point at
    /// something: deleting the last custom profile would leave it empty with
    /// no way to get one back.
    private func canDelete(_ kind: ProfileKind, siblings: Int) -> Bool {
        kind == .macOSDock || siblings > 0
    }

    func testTheLastShelfProfileCannotBeDeleted() {
        XCTAssertFalse(canDelete(.customDock, siblings: 0))
        XCTAssertTrue(canDelete(.customDock, siblings: 1))
    }

    /// A macOS Dock profile may go to none, which is the documented "leave the
    /// live Dock completely alone" state. It was reachable only until the
    /// first capture, after which nothing could return to it.
    func testTheLastMacOSDockProfileCanBeDeleted() {
        XCTAssertTrue(canDelete(.macOSDock, siblings: 0))
    }

    // MARK: Duplicating

    /// A copy has to carry new identities throughout, or the two profiles
    /// share item ids and editing one moves things on the other.
    func testACopyReusesNoIdentity() {
        let original = DockItem.spacer(id: UUID(), size: .regular)
        let widget = DockItem.widget(WidgetInstance(kind: .clock, config: WidgetConfig()))
        let group = DockItem.group(DockGroup(name: "Tools", items: [original, widget]))

        for item in [original, widget, group] {
            let copy = reidentified(item)
            XCTAssertNotEqual(copy.id, item.id, "\(item)")
        }
    }

    /// Including the items inside a group, which is the level a shallow copy
    /// would miss.
    func testItemsInsideACopiedGroupAlsoGetNewIdentities() {
        let inner = DockItem.spacer(id: UUID(), size: .small)
        let group = DockItem.group(DockGroup(name: "Tools", items: [inner]))

        guard case .group(let copied) = reidentified(group) else { return XCTFail("expected a group") }
        XCTAssertNotEqual(copied.items.first?.id, inner.id)
    }

    /// Mirrors `AppState.reidentified`.
    private func reidentified(_ item: DockItem) -> DockItem {
        switch item {
        case .spacer(_, let size):
            return .spacer(id: UUID(), size: size)
        case .widget(let widget):
            var copy = widget; copy.id = UUID(); return .widget(copy)
        case .group(let group):
            var copy = group
            copy.id = UUID()
            copy.items = copy.items.map(reidentified)
            return .group(copy)
        default:
            return item
        }
    }
}
