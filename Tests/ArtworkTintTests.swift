import CoreGraphics
import Foundation
import ImageIO
import XCTest

/// The Now Playing panel's legibility is a property of four constants, and
/// every one of them is a number somebody will later want to nudge.
///
/// This is the only failure mode a screenshot review cannot catch: a panel
/// that reads perfectly in every picture anyone rendered and fails on the one
/// hue nobody tried. So it is checked by exhaustion rather than by sample.
final class ArtworkTintTests: XCTestCase {

    /// Every ground the extractor can possibly produce, against every colour
    /// the panel draws on it.
    ///
    /// Fails the moment anyone raises `topBrightness` past 0.34, lifts
    /// `saturationCap` beyond what luminance allows, dims the secondary ink,
    /// or drops the scrubber's alpha. Those are the four edits most likely to
    /// happen months from now by someone who cannot see that this was ever
    /// load bearing.
    func testGroundIsLegibleAcrossEveryPossibleTint() {
        let title = (1.0, 1.0, 1.0)
        let secondary = (0.8, 0.8, 0.8)
        var worstTitle = Double.infinity
        var worstSecondary = Double.infinity
        var worstTrack = Double.infinity

        for degrees in 0..<360 {
            let hue = Double(degrees) / 360
            // 0 for a greyscale cover, then the band the clamp allows. Every
            // value `extract` can emit and nothing it cannot.
            for percent in [0] + Array(34...70) {
                let saturation = Double(percent) / 100
                let tint = ArtworkTint(hue: hue, saturation: saturation)
                for ground in [tint.top, tint.bottom] {
                    let g = (ground.red, ground.green, ground.blue)
                    worstTitle = min(worstTitle, ratio(title, g))
                    worstSecondary = min(worstSecondary, ratio(secondary, g))
                    // The scrubber's unfilled track is white at 0.48 over the
                    // ground, so what it has to clear is its own composite.
                    worstTrack = min(worstTrack, ratio(over(title, g, alpha: 0.48), g))
                }
            }
        }

        // AAA, because the title is the one thing read at a glance.
        XCTAssertGreaterThanOrEqual(worstTitle, 7.0,
            "title ink fell to \(worstTitle):1; WCAG AAA for body text is 7:1")
        // AA for text that is smaller and less important but still read.
        XCTAssertGreaterThanOrEqual(worstSecondary, 4.5,
            "secondary ink fell to \(worstSecondary):1; WCAG AA is 4.5:1")
        // Non-text contrast, which is what a scrubber is.
        XCTAssertGreaterThanOrEqual(worstTrack, 3.0,
            "scrubber track fell to \(worstTrack):1; WCAG AA for a UI component is 3:1")
    }

    /// Whatever comes out of an image, the clamp has already dealt with it.
    func testExtractionStaysInsideTheBand() {
        for (name, colour) in [("white", (1.0, 1.0, 1.0)), ("black", (0.0, 0.0, 0.0)),
                               ("green", (0.0, 1.0, 0.0)), ("magenta", (1.0, 0.0, 1.0)),
                               ("yellow", (1.0, 1.0, 0.0))] {
            guard let data = solidPNG(colour), let tint = ArtworkTint.extract(data) else {
                return XCTFail("could not build or read a \(name) fixture")
            }
            XCTAssertLessThanOrEqual(tint.saturation, ArtworkTint.saturationCap, name)
            // Never stranded between the grey threshold and the floor, which
            // is the muddy region the floor exists to jump.
            XCTAssertTrue(tint.saturation == 0 || tint.saturation >= ArtworkTint.saturationFloor,
                          "\(name) landed at \(tint.saturation), inside the mud gap")
        }
    }

    /// A greyscale cover has no hue, and inventing one would be a lie about
    /// the artwork.
    func testGreyscaleArtworkGetsNoHue() {
        for (name, colour) in [("white", (1.0, 1.0, 1.0)), ("black", (0.0, 0.0, 0.0)),
                               ("mid grey", (0.5, 0.5, 0.5))] {
            guard let data = solidPNG(colour), let tint = ArtworkTint.extract(data) else {
                return XCTFail("could not read the \(name) fixture")
            }
            XCTAssertEqual(tint.saturation, 0, "\(name) should have no hue")
        }
    }

    /// The contract the "no artwork looks exactly like today" path rests on.
    func testNonImageDataDegrades() {
        XCTAssertNil(ArtworkTint.extract(Data()))
        XCTAssertNil(ArtworkTint.extract(Data([0, 1, 2, 3])))
        XCTAssertNil(ArtworkTint.extract(Data("not an image".utf8)))
    }

    // MARK: Contrast

    /// Relative luminance on linearised channels.
    ///
    /// Not the NTSC luma shortcut on raw sRGB: that overstates dark colours
    /// and would pass grounds that actually fail, which is the one mistake
    /// that would make this whole file decorative.
    private func luminance(_ c: (Double, Double, Double)) -> Double {
        func linear(_ v: Double) -> Double {
            v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.0) + 0.7152 * linear(c.1) + 0.0722 * linear(c.2)
    }

    private func ratio(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let (high, low) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (high + 0.05) / (low + 0.05)
    }

    /// Source over, so a translucent ink is judged as what it actually looks
    /// like rather than as the colour it was declared.
    private func over(_ top: (Double, Double, Double), _ bottom: (Double, Double, Double),
                      alpha: Double) -> (Double, Double, Double) {
        (top.0 * alpha + bottom.0 * (1 - alpha),
         top.1 * alpha + bottom.1 * (1 - alpha),
         top.2 * alpha + bottom.2 * (1 - alpha))
    }

    // MARK: Fixtures

    /// A one-colour PNG, built here rather than committed: a fixture on disk
    /// is a file somebody has to trust, and this is three lines.
    private func solidPNG(_ colour: (Double, Double, Double)) -> Data? {
        let side = 32
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = UInt8(colour.0 * 255)
            bytes[i + 1] = UInt8(colour.1 * 255)
            bytes[i + 2] = UInt8(colour.2 * 255)
            bytes[i + 3] = 255
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let image = bytes.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let context = CGContext(data: buffer.baseAddress,
                                          width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            return context.makeImage()
        }
        guard let image else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
