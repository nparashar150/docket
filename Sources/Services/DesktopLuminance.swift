import AppKit
import CoreGraphics
import ImageIO
import Observation

/// How bright the desktop is behind the shelf.
///
/// Liquid Glass samples whatever is behind the window, so the plate's
/// brightness is the wallpaper's, while everything drawn on it follows the
/// system appearance instead. On a dark wallpaper those agree and the shelf
/// looks right. On a white one they do not: the plate goes pale, the cards
/// are a light tint of pale, and white text in a dark appearance has nothing
/// to sit against.
///
/// Measured rather than argued: white label ink on a card over a white plate
/// comes to 1.37:1. The flat scrim this app used to carry got that to 2.14:1,
/// which is why removing it made things worse and also why putting it back
/// would not have fixed anything. Neither passes.
///
/// The way out is to know what is back there. `desktopImageURL` hands over
/// the wallpaper file, which is readable with no permission at all, unlike
/// the screen itself. A 32pt thumbnail of it is enough to answer the only
/// question being asked.
@MainActor @Observable
public final class DesktopLuminance {
    public static let shared = DesktopLuminance()

    /// 0 for black, 1 for white. Starts dark, which is the common case and
    /// the one that needs no correction, so a slow first read never flashes
    /// a heavy card.
    public private(set) var underShelf: Double = 0.15

    @ObservationIgnored private var readURL: URL?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {}

    public func start() {
        guard observers.isEmpty else { return }
        refresh()
        // A space can carry its own wallpaper, and changing the picture
        // without changing space still lands here on the next screen change.
        for name in [NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didWakeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh(force: true) }
            })
        }
    }

    /// Re-reads the wallpaper, skipping the decode when it has not changed.
    public func refresh(force: Bool = false) {
        guard let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen)
        else { return }
        guard force || url != readURL else { return }
        readURL = url
        guard let value = Self.luminance(of: url) else { return }
        underShelf = value
    }

    /// The bottom fifth of the picture, which is the strip the shelf covers.
    ///
    /// Not the whole image: a photograph with a bright sky and a dark
    /// foreground averages to something the shelf never actually sits on.
    private static func luminance(of url: URL) -> Double? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 32,
              ] as CFDictionary),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }

        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h,
                                          bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        var total = 0.0
        var count = 0
        for y in 0..<max(1, h / 5) {
            for x in 0..<w {
                let i = (y * w + x) * 4
                total += 0.2126 * linear(Double(bytes[i]) / 255)
                    + 0.7152 * linear(Double(bytes[i + 1]) / 255)
                    + 0.0722 * linear(Double(bytes[i + 2]) / 255)
                count += 1
            }
        }
        return count > 0 ? total / Double(count) : nil
    }

    /// How much black a card needs so that white ink on it stays legible over
    /// whatever the glass is sampling.
    ///
    /// Derived. A card is black at alpha `a` over a plate showing roughly the
    /// wallpaper's own value `c`, so the card lands at `c * (1 - a)`, and
    /// white label ink at its 0.847 alpha needs that at or below 0.4106 to
    /// clear 4.5:1. Rearranged, `a >= 1 - 0.40 / c`, taking 0.40 rather than
    /// the exact figure so that rounding cannot land under the line: 0.41
    /// measures 4.50:1 with nothing to spare, 0.40 measures 4.67:1.
    ///
    /// Floored at the card's own 0.16 so a dark wallpaper looks exactly as it
    /// does today, which is most of the time and the case that was never
    /// broken. Capped at 0.64 so the brightest wallpaper gets a readable card
    /// rather than a black hole.
    public var cardAlpha: Double {
        // sRGB value whose relative luminance is `underShelf`.
        let c = underShelf <= 0.0031308
            ? underShelf * 12.92
            : 1.055 * pow(underShelf, 1 / 2.4) - 0.055
        guard c > 0.40 else { return 0.16 }
        return min(0.64, max(0.16, 1 - 0.40 / c))
    }
}
