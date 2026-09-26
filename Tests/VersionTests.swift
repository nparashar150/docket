import Foundation
import XCTest

/// Version ordering, which decides whether an update is offered at all.
///
/// Getting this wrong is quiet in both directions: too eager and it nags about
/// a release the user already has, too shy and the update that matters is
/// never mentioned.
final class VersionTests: XCTestCase {

    // MARK: Parsing

    func testATagParsesWithOrWithoutItsV() {
        XCTAssertEqual(Version("v1.2.3"), Version("1.2.3"))
        XCTAssertEqual(Version("1.2.3")?.description, "1.2.3")
    }

    func testMissingComponentsReadAsZero() {
        XCTAssertEqual(Version("v2")?.description, "2.0.0")
        XCTAssertEqual(Version("v2.5")?.description, "2.5.0")
    }

    func testAPrereleaseIsKept() {
        XCTAssertEqual(Version("v1.2.0-beta.1")?.prerelease, "beta.1")
        XCTAssertEqual(Version("v1.2.0")?.prerelease, "")
    }

    /// A tag that is not a version must not read as 0.0.0, or every build
    /// would look newer than it and the app would nag forever.
    func testSomethingThatIsNotAVersionIsRejected() {
        XCTAssertNil(Version("nightly"))
        XCTAssertNil(Version(""))
        XCTAssertNil(Version("v"))
    }

    // MARK: Ordering

    /// The reason this type exists. String comparison puts "0.1.10" before
    /// "0.1.9", so the first double-digit patch stops being offered.
    func testDoubleDigitsOrderNumericallyAndNotAsText() {
        XCTAssertTrue(Version("v0.1.9")! < Version("v0.1.10")!)
        XCTAssertTrue(Version("v0.9.0")! < Version("v0.10.0")!)
        XCTAssertTrue(Version("v9.0.0")! < Version("v10.0.0")!)
        XCTAssertTrue("0.1.10" < "0.1.9", "which is exactly what text comparison would have said")
    }

    func testMajorBeatsMinorBeatsPatch() {
        XCTAssertTrue(Version("1.0.0")! > Version("0.99.99")!)
        XCTAssertTrue(Version("1.2.0")! > Version("1.1.99")!)
    }

    /// A prerelease leads to its release rather than following it.
    func testAPrereleaseIsOlderThanItsRelease() {
        XCTAssertTrue(Version("1.2.0-beta.1")! < Version("1.2.0")!)
        XCTAssertTrue(Version("1.2.0-beta.1")! < Version("1.2.0-beta.2")!)
    }

    func testEqualVersionsAreNeitherNewerNorOlder() {
        XCTAssertFalse(Version("v0.1.2")! < Version("0.1.2")!)
        XCTAssertFalse(Version("v0.1.2")! > Version("0.1.2")!)
    }

    // MARK: What the service asks

    /// An update is offered only when the release is strictly newer. Equal
    /// must not offer, or every user is told to install what they are running.
    func testAnUpdateIsOfferedOnlyWhenStrictlyNewer() {
        let running = Version("0.1.2")!
        XCTAssertTrue(Version("v0.1.3")! > running)
        XCTAssertFalse(Version("v0.1.2")! > running)
        XCTAssertFalse(Version("v0.1.1")! > running)
    }

    /// Building from source produces a version ahead of the newest release.
    /// Telling that person to downgrade would be absurd.
    func testABuildAheadOfTheReleaseIsNotToldToDowngrade() {
        let running = Version("0.2.0")!
        XCTAssertFalse(Version("v0.1.2")! > running)
    }

    func testTheRealSequenceThisProjectHasShippedOrders() {
        let shipped = ["v0.1.0", "v0.1.1", "v0.1.2"].compactMap(Version.init)
        XCTAssertEqual(shipped.count, 3)
        XCTAssertEqual(shipped, shipped.sorted())
    }
}
