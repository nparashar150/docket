import CoreGraphics
import Foundation

/// Whether Mission Control is on screen.
///
/// Mission Control is not a process. It is drawn by Dock.app, which puts a
/// full-screen window at CG layer 18 up for exactly its duration: absent at
/// rest, present within one sample of opening, gone within one of closing,
/// measured across independent cycles on macOS 26.
///
/// That layer number is an undocumented layout detail of Dock.app rather than
/// private API. Nothing here is a private call and nothing needs permission:
/// owner, layer and on-screen state are public window metadata, and only
/// `kCGWindowName` would require Screen Recording. The cost of it being wrong
/// one day is bounded by design. If a future macOS stops producing that
/// window this reports false forever, which is precisely the behaviour the
/// shelf had before any of this existed. It is one boolean behind one name so
/// that replacing it is a single edit.
///
/// Deliberately not `CGWindowListCopyWindowInfo(.optionAll, …)`, which is the
/// obvious spelling and costs 3ms a call: on a poller that runs thirty times
/// a second in an app that starts at login and never quits, that is nine per
/// cent of a core spent forever on a question whose answer almost never
/// changes.
@MainActor
struct MissionControlProbe {
    /// Twenty times a second.
    ///
    /// Six was enough to notice Mission Control but not to move *with* it:
    /// a sixth of a second of latency against an animation that takes about
    /// a third means the shelf starts sliding when Mission Control is half
    /// done, which is exactly what reads as out of sync. Fifty milliseconds
    /// is three frames.
    ///
    /// The cost lands only where the fix is needed. This is read from the
    /// auto-hide poller, which does not run at all unless the shelf
    /// auto-hides, and a shelf that does not auto-hide is already on screen
    /// during Mission Control because it never left. So the 0.5% of a core
    /// this spends is spent only by people who are already running a 30Hz
    /// poller for the same feature.
    private static let interval: TimeInterval = 1.0 / 20

    /// Dock.app's Mission Control backdrop. The Dock's own window sits at 20,
    /// which is `kCGDockWindowLevel` and is also on screen during Mission
    /// Control, so 20 cannot tell the two apart. 18 appears for nothing else.
    private static let backdropLayer = 18

    private var checkedAt = Date.distantPast
    private var showing = false

    mutating func isShowing(_ now: Date = Date()) -> Bool {
        guard now.timeIntervalSince(checkedAt) >= Self.interval else { return showing }
        checkedAt = now
        showing = Self.probe()
        return showing
    }

    /// On-screen windows only, and no desktop elements. Measured at 252us
    /// against 3000us for the unfiltered list, because the wallpaper windows
    /// alone are most of what the full list carries.
    private static func probe() -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] ?? []
        return list.contains { window in
            (window[kCGWindowOwnerName as String] as? String) == "Dock"
                && (window[kCGWindowLayer as String] as? Int) == backdropLayer
        }
    }
}
