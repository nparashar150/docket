import CoreGraphics
import Foundation

/// The three finger swipe into and out of Mission Control, as it happens.
///
/// Apple's Dock does not arrive with Mission Control, it arrives *under the
/// fingers*: a tenth of the way up the trackpad it is a tenth of the way out,
/// and dragging back puts it back. Nothing in the window list can follow that.
/// Measured, Dock.app's backdrop appears at full alpha and full size and stays
/// that way until it is gone, so `MissionControlProbe` can only ever say
/// whether, never how far.
///
/// The swipe itself says how far. Dock.app is driven by gesture events of CG
/// type 30 that carry a signed progress, and a listen-only tap sees them. The
/// field numbers are undocumented, so every one is named here and nowhere
/// else. Measured on macOS 26: up (towards Mission Control) runs negative,
/// down runs positive, a slow full swipe lets go at about 0.67, and a flick
/// lets go early with a velocity of 3 to 9.
///
/// Listen-only, so nothing the user does is delayed or consumed. If the tap
/// cannot be made, `start` says so and the shelf keeps the timed slide it had
/// before this existed.
@MainActor
final class MissionControlGesture {
    enum Event: Equatable {
        /// Signed progress of a vertical swipe still under the fingers.
        case moved(Double)
        /// Where the fingers let go, and how fast they were going.
        case ended(Double, velocity: Double)
    }

    private enum Field {
        /// `kCGSEventDockControl`, the event type Dock.app's swipes arrive as.
        static let dockControl: UInt32 = 30
        static let hidType = CGEventField(rawValue: 110)!
        static let motion = CGEventField(rawValue: 123)!
        static let progress = CGEventField(rawValue: 124)!
        static let velocityY = CGEventField(rawValue: 130)!
        static let phase = CGEventField(rawValue: 132)!

        /// `kIOHIDEventTypeDockSwipe`.
        static let dockSwipe: Int64 = 23
        /// Up and down. Horizontal is 1, which is switching Spaces.
        static let vertical: Int64 = 2
    }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var handler: ((Event) -> Void)?

    /// Starts reporting to `handler`. False if the tap could not be made.
    @discardableResult
    func start(_ handler: @escaping (Event) -> Void) -> Bool {
        self.handler = handler
        guard tap == nil else { return true }

        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(1) << Field.dockControl,
            callback: { _, type, event, info in
                // Added to the main run loop, so this is already on main.
                if let info {
                    let gesture = Unmanaged<MissionControlGesture>.fromOpaque(info)
                        .takeUnretainedValue()
                    MainActor.assumeIsolated { gesture.handle(type, event) }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: me)
        else { return false }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        handler = nil
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        // The system switches off a tap it thinks is stalling. A listen-only
        // one should never be, but a tap that quietly stops is this feature
        // quietly stopping.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type.rawValue == Field.dockControl,
              event.getIntegerValueField(Field.hidType) == Field.dockSwipe,
              event.getIntegerValueField(Field.motion) == Field.vertical else { return }

        let progress = event.getDoubleValueField(Field.progress)
        switch event.getIntegerValueField(Field.phase) {
        case 1, 2: handler?(.moved(progress))
        case 4: handler?(.ended(progress, velocity: event.getDoubleValueField(Field.velocityY)))
        // Cancelled by the system rather than let go, so it goes nowhere.
        case 8: handler?(.ended(0, velocity: 0))
        default: break
        }
    }
}

/// Which way a swipe carries the shelf, and how far. Pure, so it is tested.
enum MissionControlSwipe: Equatable {
    /// Mission Control is closed and the shelf is parked: up brings it out.
    case opening
    /// Mission Control is open and the shelf with it: down takes it away.
    case closing

    /// How much of the swipe is the whole reveal. The Dock tracks Mission
    /// Control, which is fully open at 1 - so a slow swipe lets go with the
    /// shelf about two thirds out, exactly as far as the thumbnails are.
    static let travel = 1.0

    /// Where a let-go is projected to land, per unit of velocity. Measured
    /// flicks let go at 0.17 to 0.3 with velocity 3.5 to 6 and still commit.
    static let throwWeight = 0.1

    /// How far out the shelf is, 0 parked to 1 in place, for signed progress.
    func revealed(at progress: Double) -> Double {
        let toward = self == .opening ? -progress : progress
        let moved = min(max(toward / Self.travel, 0), 1)
        return self == .opening ? moved : 1 - moved
    }

    /// Whether letting go here carries Mission Control through, rather than
    /// springing back. A guess at Dock.app's own rule; if it is wrong the
    /// probe corrects it a moment later with the ordinary slide.
    func commits(at progress: Double, velocity: Double) -> Bool {
        let toward = self == .opening ? -1.0 : 1.0
        return toward * (progress + velocity * Self.throwWeight) >= 0.5
    }
}
