import Foundation
import XCTest

/// What happens to a state file the app cannot read.
///
/// These exist because of a live defect: quarantine used a fixed
/// `state.json.corrupt`, `moveItem` refuses an existing destination, and so the
/// second unreadable file was not set aside at all. The save that followed
/// replaced the user's only copy with a first-run default. A machine that had
/// ever hit it once was one failure away from losing everything, silently.
final class PersistenceTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "docket-persistence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func store() -> Store { Store(directory: dir) }

    private func write(_ text: String) throws {
        try text.data(using: .utf8)!.write(to: dir.appending(path: "state.json"))
    }

    private func quarantinedFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path())
            .filter { $0.contains("quarantined") }
    }

    // MARK: Quarantine

    func testAnUnreadableFileIsSetAside() throws {
        try write("{ this is not json")
        _ = store().load()
        XCTAssertEqual(try quarantinedFiles().count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appending(path: "state.json").path()))
    }

    /// The defect itself: a second failure must not throw the first copy away.
    func testASecondUnreadableFileIsAlsoKept() throws {
        try write("{ broken one")
        _ = store().load()
        try write("{ broken two")
        _ = store().load()
        XCTAssertEqual(try quarantinedFiles().count, 2,
                       "each unreadable file has to survive; a fixed name kept only the first")
    }

    /// A file from a newer version is refused, and refusing still means the
    /// next save overwrites it, so it has to be set aside too.
    func testAFileFromTheFutureIsKept() throws {
        try write(#"{"version": 9999}"#)
        _ = store().load()
        XCTAssertEqual(try quarantinedFiles().count, 1)
    }

    // MARK: Lenient decoding

    /// Synthesized Codable makes every non-optional property required, so one
    /// added setting rejected the whole file and cost the user every profile.
    func testAStateFileMissingNewerKeysStillLoads() throws {
        try write(#"{"version": 1, "customDock": {"position": "left"}}"#)
        let state = store().load()
        XCTAssertEqual(state.customDock.position, .left, "the key that was there is honoured")
        XCTAssertTrue(state.customDock.followSystemDock, "and the ones that were not take their default")
        XCTAssertTrue(try quarantinedFiles().isEmpty, "this is not a corrupt file")
    }

    // MARK: Values it does not recognise

    /// A misspelled or newer choice used to reject the whole file, so one bad
    /// word cost every profile, widget and pinned app.
    func testAnUnknownChoiceFallsBackInsteadOfRejectingTheFile() throws {
        try write(#"{"version": 1, "customDock": {"position": "diagonal", "glass": "frobnicated"}}"#)
        let state = store().load()
        XCTAssertEqual(state.customDock.position, .bottom)
        XCTAssertEqual(state.customDock.glass, .regular)
        XCTAssertTrue(try quarantinedFiles().isEmpty,
                      "a value we do not know is not a corrupt file")
    }

    /// An unreadable item is dropped on its own. Falling back would be worse
    /// here: an unknown widget kind becoming a clock looks like configuration
    /// rather than like a loss.
    func testAnUnreadableItemIsDroppedAndTheProfileSurvives() throws {
        let id = UUID()
        try write("""
        {"version": 1, "profiles": [{"id": "\(id.uuidString)", "name": "Everyday",
          "kind": "customDock", "color": "blue", "scale": 0.5,
          "items": [{"totally": "unrecognisable"}, {"alsoNot": 3}]}]}
        """)
        let state = store().load()
        XCTAssertEqual(state.profiles.count, 1, "the profile survives its bad items")
        XCTAssertEqual(state.profiles.first?.name, "Everyday")
        XCTAssertTrue(state.profiles.first?.items.isEmpty == true)
        XCTAssertTrue(try quarantinedFiles().isEmpty)
    }

    /// The good items either side of a bad one have to survive it, which is
    /// what separates skipping an element from giving up on the array.
    func testGoodItemsAroundABadOneAreKept() throws {
        let id = UUID(), spacer = UUID()
        try write("""
        {"version": 1, "profiles": [{"id": "\(id.uuidString)", "name": "Everyday",
          "kind": "customDock", "color": "blue", "scale": 0.5,
          "items": [{"nonsense": true},
                    {"spacer": {"_0": "\(spacer.uuidString)", "_1": "regular"}},
                    {"more": "nonsense"}]}]}
        """)
        let state = store().load()
        XCTAssertEqual(state.profiles.count, 1)
        XCTAssertTrue(try quarantinedFiles().isEmpty)
    }

    /// A key from a build that has since dropped it must not throw either.
    func testAnUnknownKeyIsIgnored() throws {
        try write(#"{"version": 1, "customDock": {"somethingRemovedLater": true}}"#)
        _ = store().load()
        XCTAssertTrue(try quarantinedFiles().isEmpty)
    }

    /// Note the limit this documents: leniency covers keys that are absent,
    /// not values that are wrong. An unrecognised enum anywhere in the file
    /// still rejects all of it, which is its own open issue.
    /// Removing a setting must not cost anyone their file. Every state file
    /// written before now still carries `showAppBadges`, and the decoder has
    /// to ignore it rather than throw.
    func testAStateFileCarryingARemovedKeyStillLoads() throws {
        try write(#"{"version": 1, "customDock": {"showAppBadges": true, "position": "right"}}"#)
        let state = store().load()
        XCTAssertEqual(state.customDock.position, .right)
        XCTAssertTrue(try quarantinedFiles().isEmpty, "a key we dropped is not a corrupt file")
    }

    func testProfilesSurviveAMissingSettingsBlock() throws {
        let id = UUID()
        try write("""
        {"version": 1, "profiles": [{"id": "\(id.uuidString)", "name": "Everyday",
         "kind": "customDock", "color": "blue", "items": [], "scale": 0.5}]}
        """)
        let state = store().load()
        XCTAssertEqual(state.profiles.count, 1)
        XCTAssertEqual(state.profiles.first?.name, "Everyday")
    }

    // MARK: Round trip

    func testASavedStateReadsBackTheSame() throws {
        var state = PersistedState()
        state.customDock.position = .right
        state.customDock.scale = 0.61
        state.customDock.autoHide = true
        try store().save(state)

        let read = store().load()
        XCTAssertEqual(read.customDock.position, .right)
        XCTAssertEqual(read.customDock.scale, 0.61, accuracy: 0.0001)
        XCTAssertTrue(read.customDock.autoHide)
        XCTAssertTrue(try quarantinedFiles().isEmpty)
    }
}
