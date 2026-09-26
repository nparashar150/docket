import Foundation
import XCTest

/// Backing profiles up and restoring them.
///
/// The buttons for this shipped as empty closures under a footer describing
/// what they did, so the feature existed only as a promise. These cover the
/// promise: what goes in the file, what comes back, and what a restore does to
/// what is already there.
final class BackupTests: XCTestCase {

    private func profile(_ name: String, id: UUID = UUID()) -> DockProfile {
        DockProfile(id: id, kind: .customDock, name: name)
    }

    private func state(_ profiles: [DockProfile]) -> PersistedState {
        var s = PersistedState()
        s.profiles = profiles
        s.customDock.profileID = profiles.first?.id
        return s
    }

    // MARK: Round trip

    func testProfilesSurviveTheRoundTrip() throws {
        let original = state([profile("Everyday"), profile("Focus")])
        let payload = try Backup.decode(try Backup.encode(original))

        XCTAssertEqual(payload.profiles.map(\.name), ["Everyday", "Focus"])
        XCTAssertEqual(payload.customProfileID, original.customDock.profileID)
    }

    /// A widget's configuration is the part worth backing up, and the part
    /// most likely to be lost by a shallow copy.
    func testAWidgetsConfigurationSurvives() throws {
        var config = WidgetConfig()
        config.set("city", .string("Delhi"))
        config.set("fahrenheit", .bool(false))
        var p = profile("Everyday")
        p.items = [.widget(WidgetInstance(kind: .weather, config: config))]

        let payload = try Backup.decode(try Backup.encode(state([p])))
        guard case .widget(let restored)? = payload.profiles.first?.items.first else {
            return XCTFail("expected the widget back")
        }
        XCTAssertEqual(restored.kind, .weather)
        XCTAssertEqual(restored.config.string("city"), "Delhi")
    }

    // MARK: What a backup deliberately leaves out

    /// A backup is for moving a setup to another Mac, and the rest of the
    /// state file is about this one. Restoring a display pin or a borrowed
    /// Dock onto different hardware would be restoring somebody else's
    /// machine.
    func testMachineSpecificSettingsAreNotInTheBackup() throws {
        var s = state([profile("Everyday")])
        s.customDock.displayID = 12345
        s.borrowedDockPrefs = DockPrefs(autoHide: true, tileSize: 38, orientation: "left")
        s.checkForUpdates = true

        let json = String(data: try Backup.encode(s), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("displayID"))
        XCTAssertFalse(json.contains("borrowedDockPrefs"))
        XCTAssertFalse(json.contains("checkForUpdates"))
    }

    // MARK: Merging

    /// Restoring adds rather than replaces. Wiping what is there would make
    /// importing one setup from another Mac destructive, with nothing to undo
    /// it.
    func testRestoringKeepsProfilesTheBackupDoesNotHave() throws {
        let mine = profile("Mine")
        var current = state([mine])
        let payload = try Backup.decode(try Backup.encode(state([profile("Theirs")])))

        Backup.merge(payload, into: &current)
        XCTAssertEqual(Set(current.profiles.map(\.name)), ["Mine", "Theirs"])
    }

    /// A profile both sides have is taken from the backup, which is what
    /// restoring it means.
    func testAProfileInBothIsTakenFromTheBackup() throws {
        let shared = UUID()
        var current = state([profile("Old name", id: shared)])
        let payload = try Backup.decode(try Backup.encode(state([profile("New name", id: shared)])))

        Backup.merge(payload, into: &current)
        XCTAssertEqual(current.profiles.count, 1, "matched by identifier, not duplicated")
        XCTAssertEqual(current.profiles.first?.name, "New name")
    }

    /// The backup's active profile only wins if it actually arrived, or a
    /// restore could point the shelf at a profile that does not exist and
    /// leave it empty.
    func testTheActiveProfileIsOnlyAdoptedIfItIsPresent() throws {
        var current = state([profile("Mine")])
        let mineID = current.customDock.profileID
        var payload = try Backup.decode(try Backup.encode(state([profile("Theirs")])))
        payload.customProfileID = UUID()   // names something not in the file

        Backup.merge(payload, into: &current)
        XCTAssertEqual(current.customDock.profileID, mineID,
                       "a dangling identifier must not become the active profile")
    }

    // MARK: Refusing what it cannot read

    func testABackupFromTheFutureIsRefused() throws {
        var payload = Backup.Payload(profiles: [], customProfileID: nil, macOSProfileID: nil)
        payload.version = Backup.Payload.currentVersion + 1
        let data = try JSONEncoder().encode(payload)
        XCTAssertThrowsError(try Backup.decode(data))
    }

    func testTheSuggestedNameCarriesTheExtension() {
        XCTAssertTrue(Backup.suggestedName().hasSuffix(".\(Backup.fileExtension)"))
    }
}
