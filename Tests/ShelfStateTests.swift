import Foundation
import XCTest

/// Shelf items used by the group tests. Identities are derived from the name so
/// a failure message names the icon that moved.
private enum Sample {

    static func app(_ name: String) -> DockItem {
        .app(id: .stable(from: name), bundleID: name,
             ref: FileRef(url: URL(fileURLWithPath: "/Applications/\(name).app")))
    }

    static func spacer(_ name: String) -> DockItem {
        .spacer(id: .stable(from: name), size: .small)
    }

    static func link(_ name: String) -> DockItem {
        .link(id: .stable(from: name),
              url: URL(fileURLWithPath: "/Users/Shared/\(name).webloc"), title: name)
    }

    static func group(_ name: String, _ items: [DockItem]) -> DockItem {
        .group(DockGroup(id: .stable(from: name), name: name, tint: .teal, items: items))
    }
}

final class ShelfStateMediaTests: XCTestCase {

    private func meaningful(_ title: String, _ duration: TimeInterval,
                            _ elapsed: TimeInterval) -> Bool {
        MediaReading.isMeaningful(title: title, duration: duration, elapsed: elapsed)
    }

    /// The tile this guard exists for: a name with no clock behind it.
    ///
    /// A page reported a title while both the duration and the position were
    /// zero, and the shelf rendered a track stuck at 0:00 - the numbers on
    /// screen were a paused flag and an elapsed count that had landed in the
    /// title and artist slots of a tile with nothing playing behind it.
    func testATitleWithNothingPlayingBehindItIsNotMeaningful() {
        XCTAssertFalse(meaningful("Some Page Heading", 0, 0))
    }

    /// No amount of clock makes a nameless reading into a track: a bridge that
    /// loses the title is reporting a player it failed to read, not a song.
    func testAnEmptyTitleIsNeverMeaningfulHoweverGoodTheNumbersAre() {
        XCTAssertFalse(meaningful("", 240, 97))
        XCTAssertFalse(meaningful("", .infinity, 97))
    }

    /// Scraped titles arrive padded, and a heading that is only padding is the
    /// same "no name" case - including the non-breaking space an HTML page
    /// leaves behind, which is not the space character a naive check looks for.
    func testAWhitespaceOnlyTitleIsNotMeaningful() {
        for blank in [" ", "   ", "\t", "\n", "\r\n", " \t \n ", "\u{00A0}"] {
            XCTAssertFalse(meaningful(blank, 240, 97),
                           "\(blank.debugDescription) counted as a name")
        }
    }

    /// Trimming decides whether a title is blank; it must not decide what the
    /// title is, so a real name surrounded by padding still counts.
    func testATitlePaddedWithWhitespaceStillCounts() {
        XCTAssertTrue(meaningful("  Bohemian Rhapsody \n", 355, 0))
    }

    /// A track cued and not yet started has a duration and no position, which
    /// is a real reading of a real player - the 0:00 that must still render.
    func testADurationWithNoPositionIsMeaningful() {
        XCTAssertTrue(meaningful("Bohemian Rhapsody", 355, 0))
    }

    /// A live stream has no end, so it reports no duration. Requiring one hid
    /// every radio station and live video behind the "nothing playing" tile.
    func testAPositionWithNoDurationIsMeaningful() {
        XCTAssertTrue(meaningful("BBC Radio 6 Music", 0, 1_284))
    }

    /// Browsers report a live stream's duration as infinity rather than zero,
    /// which is a duration like any other as far as this gate is concerned.
    func testAnInfiniteDurationIsMeaningful() {
        XCTAssertTrue(meaningful("Live Coverage", .infinity, 0))
    }

    /// Players signal "length unknown" with a negative duration as well as
    /// with zero, and a stream that has been running for twenty minutes is
    /// unambiguously playing whatever it says about its length.
    func testANegativeDurationDoesNotDisqualifyAStreamThatIsPlaying() {
        XCTAssertTrue(meaningful("BBC Radio 6 Music", -1, 1_284))
    }

    /// The mirror case: a nonsense position must not veto a known duration.
    func testANegativePositionDoesNotDisqualifyATrackWithAKnownLength() {
        XCTAssertTrue(meaningful("Bohemian Rhapsody", 355, -1))
    }

    /// Two "unknown" sentinels are still nothing playing. A check for
    /// `!= 0` rather than `> 0` would have promoted this pair to a track.
    func testNegativeNumbersAloneAreNotMeaningful() {
        XCTAssertFalse(meaningful("Some Page Heading", -1, -1))
        XCTAssertFalse(meaningful("Some Page Heading", -1, 0))
        XCTAssertFalse(meaningful("Some Page Heading", 0, -1))
    }

    /// The boundary is strict: zero is nothing playing, and the smallest
    /// representable position above it is something playing.
    func testZeroIsTheBoundaryAndTheSmallestPositiveValueClearsIt() {
        XCTAssertFalse(meaningful("Track", 0, 0))
        XCTAssertTrue(meaningful("Track", .leastNonzeroMagnitude, 0))
        XCTAssertTrue(meaningful("Track", 0, .leastNonzeroMagnitude))
    }

    /// A bridge that parses a missing number gives NaN, and every comparison
    /// against NaN is false - so it must read as "unknown", not as a position,
    /// while a real number beside it still carries the reading.
    func testNotANumberIsNotMistakenForAPosition() {
        XCTAssertFalse(meaningful("Track", .nan, .nan))
        XCTAssertFalse(meaningful("Track", .nan, 0))
        XCTAssertTrue(meaningful("Track", .nan, 97))
        XCTAssertTrue(meaningful("Track", 355, .nan))
    }

    /// Both halves of the gate are load-bearing: a name without a clock and a
    /// clock without a name are each half a reading, and neither renders.
    func testAReadingNeedsBothANameAndAClock() {
        let clocks: [(TimeInterval, TimeInterval)] = [(0, 0), (355, 0), (0, 97), (355, 97)]
        for (duration, elapsed) in clocks {
            let playing = duration > 0 || elapsed > 0
            XCTAssertEqual(meaningful("Track", duration, elapsed), playing,
                           "named reading at \(duration)/\(elapsed)")
            XCTAssertFalse(meaningful("", duration, elapsed),
                           "nameless reading at \(duration)/\(elapsed)")
        }
    }
}

final class ShelfStateFollowingTests: XCTestCase {

    /// The regression this resolver exists for.
    ///
    /// Dragging the resize grip used to switch `followSystemDock` off wholesale,
    /// which silently took the Dock's edge, magnification and auto-hide with it
    /// - the shelf simply stopped hiding after a resize, with nothing to connect
    /// the two. An explicit size must win while everything else keeps following.
    func testAnOverriddenSizeWinsWhileTheShelfStillFollowsTheDock() {
        XCTAssertEqual(DockFollowing.scale(overridden: true, custom: 0.9,
                                           system: 0.4, following: true), 0.9)
    }

    func testAnOverriddenSizeAlsoWinsWhenNothingIsBeingFollowed() {
        XCTAssertEqual(DockFollowing.scale(overridden: true, custom: 0.9,
                                           system: 0.4, following: false), 0.9)
    }

    /// The default: the user has already told macOS how big they like their
    /// Dock, and an unresized shelf sits beside it at that size.
    func testTheDocksSizeIsUsedWhileFollowingAndUnresized() {
        XCTAssertEqual(DockFollowing.scale(overridden: false, custom: 0.9,
                                           system: 0.4, following: true), 0.4)
    }

    /// A user who switched following off before ever touching the grip keeps
    /// the stored size rather than snapping to the Dock's.
    func testTheStoredSizeIsUsedWhenTheDockIsNotFollowed() {
        XCTAssertEqual(DockFollowing.scale(overridden: false, custom: 0.9,
                                           system: 0.4, following: false), 0.9)
    }

    /// Once the size is overridden, `following` has no say in it at all - which
    /// is exactly what lets the flag stay on and keep governing the edge,
    /// magnification and hiding after a resize.
    func testFollowingCannotChangeAnOverriddenSize() {
        for custom in [0.25, 0.5, 1.0, 1.5] {
            for system in [0.25, 0.4, 1.0, 1.5] {
                let followed = DockFollowing.scale(overridden: true, custom: custom,
                                                   system: system, following: true)
                let unfollowed = DockFollowing.scale(overridden: true, custom: custom,
                                                     system: system, following: false)
                XCTAssertEqual(followed, unfollowed, "custom \(custom), system \(system)")
                XCTAssertEqual(followed, custom)
            }
        }
    }

    /// The Dock's size is consulted on exactly one of the four combinations,
    /// and pinning the whole table here is what stops a later edit from
    /// reintroducing "resized means no longer following".
    func testTheFullTruthTableResolvesAsDocumented() {
        let custom = 0.9, system = 0.4
        for overridden in [true, false] {
            for following in [true, false] {
                let expected = (!overridden && following) ? system : custom
                XCTAssertEqual(DockFollowing.scale(overridden: overridden, custom: custom,
                                                   system: system, following: following),
                               expected, "overridden \(overridden), following \(following)")
            }
        }
    }

    /// The resolver chooses between two sizes; it never clamps, blends or
    /// substitutes a third, so whatever is stored is what the shelf renders.
    func testResolvingASizeNeverInventsAThirdValue() {
        for custom in [-1.0, 0.0, 0.25, 1.5, 12.0] {
            for system in [-1.0, 0.0, 0.25, 1.5, 12.0] {
                for overridden in [true, false] {
                    for following in [true, false] {
                        let result = DockFollowing.scale(overridden: overridden, custom: custom,
                                                         system: system, following: following)
                        XCTAssertTrue(result == custom || result == system,
                                      "\(result) is neither \(custom) nor \(system)")
                    }
                }
            }
        }
    }

    /// A Dock size that cannot be read must not reach a shelf the user has
    /// already sized by hand.
    func testAnUnreadableDockSizeCannotCorruptAnOverriddenSize() {
        for system in [Double.nan, -0.0, 0, -7, .infinity] {
            XCTAssertEqual(DockFollowing.scale(overridden: true, custom: 0.9,
                                               system: system, following: true), 0.9,
                           "system \(system) leaked through the override")
        }
    }

    /// The point of the override: the drag has to actually change the size, or
    /// the grip does nothing while following is on.
    func testAResizeChangesTheSizeTheShelfReports() {
        let before = DockFollowing.scale(overridden: false, custom: 0.9,
                                         system: 0.4, following: true)
        let after = DockFollowing.scale(overridden: true, custom: 0.9,
                                        system: 0.4, following: true)
        XCTAssertEqual(before, 0.4)
        XCTAssertNotEqual(after, before)
        XCTAssertEqual(after, 0.9)
    }

    /// The other half of the same regression, at the settings level: taking
    /// ownership of the size must leave every other mirrored setting alone.
    /// The shelf that stopped hiding after a resize did so because these moved
    /// together.
    func testOverridingTheSizeLeavesEveryOtherDockSettingFollowing() {
        var settings = CustomDockSettings()
        let untouched = settings

        settings.scaleOverridden = true
        settings.scale = 1.2

        XCTAssertTrue(settings.followSystemDock)
        XCTAssertEqual(settings.position, untouched.position)
        XCTAssertEqual(settings.autoHide, untouched.autoHide)
        XCTAssertEqual(settings.magnification, untouched.magnification)
        XCTAssertEqual(settings.hideWhenMacOSDockAppears, untouched.hideWhenMacOSDockAppears)
        XCTAssertEqual(DockFollowing.scale(overridden: settings.scaleOverridden ?? false,
                                           custom: settings.scale, system: 0.4,
                                           following: settings.followSystemDock), 1.2)
    }

    /// State written before the override flag existed decodes with it absent,
    /// and those profiles were following the Dock's size - so absent must mean
    /// "not overridden" rather than failing to decode or defaulting to true.
    func testSettingsWrittenBeforeTheSizeOverrideExistedStillFollowTheDock() throws {
        var settings = CustomDockSettings()
        settings.scaleOverridden = true
        settings.scale = 1.2

        let encoded = try JSONEncoder().encode(settings)
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNotNil(fields.removeValue(forKey: "scaleOverridden"),
                        "precondition: the flag is encoded when set")

        let legacy = try JSONSerialization.data(withJSONObject: fields)
        let back = try JSONDecoder().decode(CustomDockSettings.self, from: legacy)

        XCTAssertNil(back.scaleOverridden)
        XCTAssertTrue(back.followSystemDock)
        XCTAssertEqual(DockFollowing.scale(overridden: back.scaleOverridden ?? false,
                                           custom: back.scale, system: 0.4,
                                           following: back.followSystemDock), 0.4)
    }
}

final class ShelfStateGroupTests: XCTestCase {

    /// Two is the whole threshold: a pair is a group and must come back
    /// byte-identical, id, name, tint and contents included.
    func testAGroupOfExactlyTwoIsLeftAlone() {
        let pair = Sample.group("Work", [Sample.app("a"), Sample.app("b")])
        XCTAssertEqual(ShelfItems.dissolvingSmallGroups(in: [pair]), [pair])
    }

    /// Every undersized group gives way in the same pass. Dissolving only the
    /// first would leave the rest rendering as tiles with one shrunken icon in
    /// a quarter of them until something else happened to touch the shelf.
    func testEveryUndersizedGroupOnTheShelfDissolvesInOnePass() {
        let solo = Sample.app("solo")
        let stray = Sample.app("stray")
        let pair = Sample.group("Work", [Sample.app("b"), Sample.app("c")])
        let shelf = [Sample.group("One", [solo]),
                     pair,
                     Sample.group("Empty", []),
                     Sample.group("Two", [stray])]

        XCTAssertEqual(ShelfItems.dissolvingSmallGroups(in: shelf), [solo, pair, stray])
    }

    /// A dissolving group hands its slot to the icon it held, so the shelf does
    /// not reshuffle around it - the neighbours must not shift by one.
    func testADissolvingGroupSurrendersItsSlotInPlace() {
        let before = Sample.app("before")
        let after = Sample.app("after")
        let inner = Sample.app("inner")
        let shelf = [before, Sample.group("One", [inner]), after]

        XCTAssertEqual(ShelfItems.dissolvingSmallGroups(in: shelf), [before, inner, after])
    }

    /// An empty group has nothing to hand over, so its slot closes - and the
    /// two icons it sat between keep their order.
    func testAnEmptyGroupBetweenTwoAppsClosesWithoutDisturbingThem() {
        let before = Sample.app("before")
        let after = Sample.app("after")
        let shelf = [before, Sample.group("Empty", []), after]

        XCTAssertEqual(ShelfItems.dissolvingSmallGroups(in: shelf), [before, after])
    }

    /// Nesting is never created by dropping one tile on another - that joins
    /// the target group instead - so a group holding only a group came from an
    /// older build or a restored backup. The shelf runs this pass on every
    /// render, and each pass peels one layer, so the debris converges on the
    /// icon underneath rather than surviving as a tile of tiles.
    func testNestedGroupsOfOneConvergeOnTheIconTheyHold() {
        let inner = Sample.app("inner")
        let shelf = [Sample.group("Outer", [Sample.group("Inner", [inner])])]

        var result = shelf
        for _ in 0..<4 { result = ShelfItems.dissolvingSmallGroups(in: result) }
        XCTAssertEqual(result, [inner])
    }

    /// The same for empty debris: nested empties reduce to nothing at all,
    /// and never to a tile with nothing in it.
    func testNestedEmptyGroupsReduceToNothing() {
        let nested = Sample.group("Outer", [Sample.group("Inner", [])])

        var result = [nested]
        for _ in 0..<4 { result = ShelfItems.dissolvingSmallGroups(in: result) }
        XCTAssertTrue(result.isEmpty)
        XCTAssertNil(result.first { $0.group != nil })
    }

    /// Promotion is not flattening: a real group that happened to be nested
    /// inside stray debris comes back out whole, with its own name and tint,
    /// rather than being emptied onto the shelf.
    func testARealGroupNestedInsideDebrisComesOutIntact() {
        let pair = Sample.group("Work", [Sample.app("b"), Sample.app("c")])
        let result = ShelfItems.dissolvingSmallGroups(in: [Sample.group("Outer", [pair])])

        XCTAssertEqual(result, [pair])
        XCTAssertEqual(result.first?.group?.name, "Work")
        XCTAssertEqual(result.first?.group?.tint, .teal)
        XCTAssertEqual(result.first?.group?.items.count, 2)
    }

    /// A surviving group is not rewritten: what is inside it is the group
    /// sheet's business, and a shelf-level pass that reached in would rearrange
    /// a group the user was looking at.
    func testAGroupThatSurvivesIsNotRewrittenInside() {
        let odd = Sample.group("Work", [Sample.app("a"), Sample.group("Nested", [])])
        XCTAssertEqual(ShelfItems.dissolvingSmallGroups(in: [odd]), [odd])
    }

    /// Groups hold more than apps, and a promoted item keeps its own identity
    /// rather than being rebuilt as something the shelf can draw generically.
    func testDissolvingPromotesWhateverTheGroupWasHolding() {
        let link = Sample.link("Docs")
        let spacer = Sample.spacer("gap")
        let result = ShelfItems.dissolvingSmallGroups(in: [Sample.group("One", [link]),
                                                           Sample.group("Two", [spacer])])
        XCTAssertEqual(result, [link, spacer])
    }

    /// The pass must not be able to lose a pinned item or clone one: every id
    /// that was reachable is present exactly once afterwards.
    func testDissolvingNeitherDropsNorClonesTheItemsItPromotes() {
        let loose = (0..<3).map { Sample.app("loose\($0)") }
        let held = (0..<2).map { Sample.app("held\($0)") }
        let pair = Sample.group("Work", [Sample.app("b"), Sample.app("c")])
        let shelf = [loose[0], Sample.group("One", [held[0]]), pair,
                     loose[1], Sample.group("Two", [held[1]]), loose[2]]

        let ids = ShelfItems.dissolvingSmallGroups(in: shelf).map(\.id)
        XCTAssertEqual(ids, [loose[0].id, held[0].id, pair.id,
                             loose[1].id, held[1].id, loose[2].id])
        XCTAssertEqual(Set(ids).count, ids.count, "an item was cloned")
    }

    func testAnEmptyShelfDissolvesToNothing() {
        XCTAssertTrue(ShelfItems.dissolvingSmallGroups(in: []).isEmpty)
    }

    /// A shelf with no groups at all is returned untouched and in order - the
    /// pass runs on every render, so it must be a no-op on the common case.
    func testAShelfWithoutGroupsIsReturnedUnchanged() {
        let shelf = [Sample.app("a"), Sample.spacer("gap"), Sample.link("Docs"),
                     Sample.app("b")]
        XCTAssertEqual(ShelfItems.dissolvingSmallGroups(in: shelf), shelf)
    }

    /// Running it again must change nothing: the shelf calls it on every
    /// render, so a pass that kept rewriting a settled shelf would animate.
    func testASettledShelfIsAFixedPoint() {
        let shelf = [Sample.app("a"),
                     Sample.group("Work", [Sample.app("b"), Sample.app("c")]),
                     Sample.app("d")]
        let once = ShelfItems.dissolvingSmallGroups(in: shelf)
        XCTAssertEqual(ShelfItems.dissolvingSmallGroups(in: once), once)
        XCTAssertEqual(once, shelf)
    }
}

/// Putting an item next to another one.
///
/// Spacers were drawn, sized, labelled and converted both ways to Apple's own
/// spacer tiles, with no way for anyone to make one. Adding that meant
/// inserting rather than appending, because a spacer is entirely about where
/// it sits: appended to the end it is invisible, and the feature would have
/// looked broken rather than absent.
final class ShelfInsertTests: XCTestCase {

    private func app(_ name: String) -> DockItem {
        .app(id: UUID(), bundleID: "com.example.\(name)",
             ref: FileRef(url: URL(fileURLWithPath: "/Applications/\(name).app")))
    }

    /// Mirrors what `AppState.insertItem(_:after:)` does to the array.
    private func insert(_ item: DockItem, after anchor: UUID,
                        into items: [DockItem]) -> [DockItem] {
        var result = items
        if let slot = result.firstIndex(where: { $0.id == anchor }) {
            result.insert(item, at: slot + 1)
        } else {
            result.append(item)
        }
        return result
    }

    func testAnItemLandsDirectlyAfterItsAnchor() {
        let a = app("A"), b = app("B"), c = app("C")
        let spacer = DockItem.spacer(id: UUID(), size: .regular)

        let result = insert(spacer, after: b.id, into: [a, b, c])
        XCTAssertEqual(result.map(\.id), [a.id, b.id, spacer.id, c.id])
    }

    func testInsertingAfterTheLastItemPutsItAtTheEnd() {
        let a = app("A"), b = app("B")
        let spacer = DockItem.spacer(id: UUID(), size: .small)

        let result = insert(spacer, after: b.id, into: [a, b])
        XCTAssertEqual(result.map(\.id), [a.id, b.id, spacer.id])
    }

    /// The anchor can be a running app that was never pinned, so it is not in
    /// the profile at all. Appending is the honest fallback; dropping the
    /// item would look like the menu did nothing.
    func testAnUnknownAnchorAppendsRatherThanDropping() {
        let a = app("A")
        let spacer = DockItem.spacer(id: UUID(), size: .regular)

        let result = insert(spacer, after: UUID(), into: [a])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.last?.id, spacer.id)
    }

    func testInsertingIntoAnEmptyProfileStillWorks() {
        let spacer = DockItem.spacer(id: UUID(), size: .regular)
        XCTAssertEqual(insert(spacer, after: UUID(), into: []).count, 1)
    }

    /// Two spacers in a row are a legitimate arrangement, so nothing may
    /// coalesce or deduplicate them.
    func testSpacersDoNotCollapseIntoEachOther() {
        let a = app("A")
        let first = DockItem.spacer(id: UUID(), size: .regular)
        let second = DockItem.spacer(id: UUID(), size: .small)

        var items = insert(first, after: a.id, into: [a])
        items = insert(second, after: first.id, into: items)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.map(\.id), [a.id, first.id, second.id])
    }
}
