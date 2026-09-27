import Foundation
import XCTest

/// The parser is the half of the Shortcuts widget that can be tested without
/// a machine that has shortcuts on it. The half that runs the tool cannot:
/// the test target compiles the core rather than hosting the app, and the
/// output depends on whatever the person running the tests happens to own.
final class ShortcutListTests: XCTestCase {
    func testOneNamePerLine() {
        XCTAssertEqual(ShortcutList.parse("Morning Routine\nPay Rent\nStart Recording"),
                       ["Morning Routine", "Pay Rent", "Start Recording"])
    }

    /// The state a Mac is in before anybody opens Shortcuts. Measured: the
    /// tool prints nothing and exits 0, which is a legitimate answer and not
    /// an error, so it has to come back as an empty list rather than as a
    /// single empty name.
    func testNoShortcutsIsEmptyRatherThanOneBlankName() {
        XCTAssertEqual(ShortcutList.parse(""), [])
        XCTAssertEqual(ShortcutList.parse("\n"), [])
        XCTAssertEqual(ShortcutList.parse("   \n\t\n"), [])
    }

    func testTrailingNewlineDoesNotBecomeAName() {
        XCTAssertEqual(ShortcutList.parse("Only One\n"), ["Only One"])
    }

    /// Shortcuts.app allows two shortcuts to share a name and running one by
    /// name cannot tell them apart, so offering the name twice would be
    /// offering a choice that does not exist.
    func testDuplicateNamesCollapseToTheFirst() {
        XCTAssertEqual(ShortcutList.parse("Focus\nPay Rent\nFocus"), ["Focus", "Pay Rent"])
    }

    /// Order is the tool's, not ours. It lists alphabetically today, but the
    /// widget has no reason to care and re-sorting would only make the panel
    /// disagree with Shortcuts.app.
    func testOrderIsPreserved() {
        XCTAssertEqual(ShortcutList.parse("Zeta\nAlpha\nMiddle"), ["Zeta", "Alpha", "Middle"])
    }

    /// A name is user data on its way to a command line. It reaches the tool
    /// as argv rather than through a shell, so the parser's job is to leave
    /// it exactly as it found it.
    func testPunctuationInNamesSurvivesIntact() {
        let awkward = "Rent; rm -rf ~ \"quoted\" 'single' $HOME `tick`"
        XCTAssertEqual(ShortcutList.parse(awkward), [awkward])
    }

    func testCarriageReturnsAreTrimmed() {
        XCTAssertEqual(ShortcutList.parse("First\r\nSecond\r\n"), ["First", "Second"])
    }
}
