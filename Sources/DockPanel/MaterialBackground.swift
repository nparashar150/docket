import SwiftUI
import AppKit

/// The shelf's backing surface.
///
/// Two materials. **Liquid Glass** uses macOS 26's real `glassEffect` - an
/// earlier version of this file approximated it with a blur plus stacked white
/// overlays, which produced a flat milky slab with none of the refraction or
/// specular edge that makes the genuine material read as glass. **Frosted** is
/// an `NSVisualEffectView`, which is what Apple's own Dock uses.
///
/// Reduce Transparency wins over both: the accessibility setting is not a
/// style preference.
struct MaterialBackground: View {
    var material: DockMaterial
    var glass: GlassStyle
    var radius: CGFloat

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    var body: some View {
        surface
            .overlay {
                // A hairline top rim is what stops the shelf reading as a flat
                // cut-out against a busy wallpaper. Glass supplies its own, so
                // this is only for the frosted material.
                if material == .frosted && !reduceTransparency {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(scheme == .dark ? 0.22 : 0.65),
                                     .white.opacity(scheme == .dark ? 0.04 : 0.15)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                }
            }
            .compositingGroup()
            // Glass casts its own, and stacking ours on top of it is why the
            // shelf sat heavier on the desktop than Apple's Dock does. The
            // frosted plate is an NSVisualEffectView and genuinely has none.
            .shadow(color: .black.opacity(material == .liquidGlass
                                          ? 0
                                          : (scheme == .dark ? 0.34 : 0.18)),
                    radius: 9, x: 0, y: 4)
    }

    @ViewBuilder
    private var surface: some View {
        if reduceTransparency {
            shape.fill(scheme == .dark ? Color(hex: "#1C1C1C") : Color(hex: "#F2F2F2"))
        } else {
            switch material {
            case .frosted: frosted
            case .liquidGlass: liquid
            }
        }
    }

    /// What Apple's Dock is: a blurred, vibrant plate sampling the desktop.
    ///
    /// The tint is deliberately light. A 90%-opaque fill (which the web
    /// reference uses, because a browser has no vibrancy to work with) would
    /// throw away the blur entirely and leave a plain grey rectangle.
    private var frosted: some View {
        VisualEffectPlate(material: .hudWindow, blending: .behindWindow)
            .overlay {
                shape.fill(scheme == .dark
                           ? Color.black.opacity(0.16)
                           : Color.white.opacity(0.14))
            }
            .clipShape(shape)
    }

    /// The real macOS 26 material, shape-matched to the shelf, and nothing on
    /// top of it.
    ///
    /// There used to be a flat scrim here, 22% black in the dark and 26%
    /// white in the light, added because glass samples what is behind the
    /// window: over a white page the plate turns white and chrome that
    /// follows the system appearance disappears into it.
    ///
    /// The reasoning was sound and the remedy was aimed at the wrong thing. A
    /// uniform fill over glass suppresses exactly the refraction and the
    /// specular edge that make the material read as glass, so the shelf stops
    /// looking like the Dock and starts looking like tinted plastic, which is
    /// obvious the moment Mission Control puts the two side by side. Dimming
    /// the surface to protect what is drawn on it is backwards: the surface
    /// is the thing that has to match, and the chrome is the thing that can
    /// be pinned.
    ///
    /// Known limit, stated rather than papered over: the separator, the grip
    /// and the add button in `DockShelfView` still take `Color.primary`, so
    /// on a light wallpaper under a dark appearance they can lose contrast
    /// against a plate that has sampled it. `.regular` glass carries real
    /// density of its own, so this has not been reproduced here; the fix
    /// when it is would be to pin those three, not to dim the plate again.
    ///
    /// It also applied in `.clear`, so choosing clear glass got 22% black
    /// over it and was not clear at all.
    private var liquid: some View {
        Color.clear
            .glassEffect(glass == .clear ? .clear : .regular, in: shape)
    }
}

/// `NSVisualEffectView` bridge - SwiftUI's `.ultraThinMaterial` samples only
/// within the window, and a floating shelf needs what is *behind* it.
struct VisualEffectPlate: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.material = material
        view.blendingMode = blending
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}
