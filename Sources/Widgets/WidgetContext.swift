import SwiftUI

/// Everything a widget view needs that isn't its own config.
///
/// Widgets are authored at their **natural** size (the points in the catalog)
/// and the shelf applies `scaleEffect` to the finished tile. That is why there
/// is no scale in here: a widget that did its own font maths would drift out
/// of step with its neighbours the moment the size slider moved.
public struct WidgetContext: Equatable, Sendable {
    public var position: DockPosition
    /// Ticks once a second; widgets that show time read this rather than
    /// starting timers of their own.
    public var now: Date
    /// True while the widget is shown in the library, where live data sources
    /// should be replaced with representative sample values.
    public var isPreview: Bool

    public init(position: DockPosition = .bottom, now: Date = .now, isPreview: Bool = false) {
        self.position = position
        self.now = now
        self.isPreview = isPreview
    }
}

/// Shared look for every widget tile.
public enum WidgetStyle {
    /// About 0.3 of a card's height, which is what the reference shelf runs
    /// and what macOS 26's own grouped surfaces look like. 14 read as square
    /// beside them.
    public static let corner: CGFloat = 18
    public static let inset: CGFloat = 10

    /// The large figure - times, percentages, amounts.
    public static func value(_ size: CGFloat = 26) -> Font {
        .system(size: size, weight: .bold)
    }

    /// The small caption under or beside a value.
    public static func caption(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .regular)
    }

    public static func label(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .semibold)
    }

    /// Digits that change every second must not make the layout shimmer.
    public static var monospacedDigits: Font.Design { .default }

    public static let primary = Color.primary
    public static let secondary = Color.secondary.opacity(0.85)

    public static func tint(_ color: PaletteColor) -> Color { Color(hex: color.hex) }
    public static func paper(_ color: PaperColor) -> Color { Color(hex: color.hex) }
}

public extension Color {
    /// `#RRGGBB` / `#RRGGBBAA`. Falls back to clear rather than trapping - a
    /// bad swatch should not take the shelf down.
    init(hex: String) {
        let raw = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard let value = UInt64(raw, radix: 16), raw.count == 6 || raw.count == 8 else {
            self = .clear
            return
        }
        let hasAlpha = raw.count == 8
        let r = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? Double(value & 0xFF) / 255 : 1
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

/// The surface every widget draws on.
public struct WidgetSurface<Content: View>: View {
    public var fill: Color?
    @ViewBuilder public var content: Content

    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetHovered) private var hovered

    /// A card is a *recess* in the plate, not something raised on top of it.
    ///
    /// `Color.primary` is white in the dark, so tinting with it lightened the
    /// card toward the shelf until the two matched exactly - measured at 40
    /// against a plate of 40, which is why the cards did not read as cards.
    /// Dockset holds a card at roughly 0.85x the plate's luminance; a black
    /// tint reproduces that ratio against any backdrop the glass samples.
    private var cardFill: Color {
        scheme == .dark ? .black.opacity(0.16) : .white.opacity(0.40)
    }

    /// Just enough to catch the edge; the fill does the work.
    private var cardEdge: Color {
        scheme == .dark ? .white.opacity(0.07) : .black.opacity(0.06)
    }

    public init(fill: Color? = nil, @ViewBuilder content: () -> Content) {
        self.fill = fill
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, WidgetStyle.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: WidgetStyle.corner, style: .continuous)
                    .fill(fill ?? cardFill)
                    // Lifted a little out of the recess under the pointer.
                    .overlay {
                        RoundedRectangle(cornerRadius: WidgetStyle.corner, style: .continuous)
                            .fill(.white.opacity(hovered ? (scheme == .dark ? 0.07 : 0.22) : 0))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: WidgetStyle.corner, style: .continuous)
                    .strokeBorder(hovered ? hoverEdge : cardEdge, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: WidgetStyle.corner, style: .continuous))
            // A transform rather than a layout change, and small.
            //
            // Widgets deliberately do not magnify: a 264pt card swelling the
            // 30% an icon does would displace a quarter of the shelf, so
            // brushing past one would shove every icon aside. But answering
            // nothing at all is what made them feel dead beside the icons.
            // scaleEffect draws bigger without asking for more room, and 2%
            // stays inside the gap between cards.
            .scaleEffect(hovered ? 1.02 : 1)
            .animation(.smooth(duration: 0.16), value: hovered)
    }

    /// The edge catches the light too, or the card reads as merely paler.
    private var hoverEdge: Color {
        scheme == .dark ? .white.opacity(0.16) : .black.opacity(0.12)
    }
}

/// Whether the pointer is over this widget.
///
/// Through the environment rather than `WidgetContext` so that every widget
/// gains the highlight without being edited, and because `WidgetSurface` is
/// the one place that draws a card: putting it there means one definition of
/// what hover looks like instead of twenty.
///
/// Not `.onHover`, which never fires in a non-activating accessory panel.
/// The shelf already tracks the pointer for magnification and already
/// hit-tests it to place a tooltip; this rides on the same answer.
public struct WidgetHoveredKey: EnvironmentKey {
    public static let defaultValue = false
}

public extension EnvironmentValues {
    var widgetHovered: Bool {
        get { self[WidgetHoveredKey.self] }
        set { self[WidgetHoveredKey.self] = newValue }
    }
}

public extension View {
    /// Rolls a changing number instead of hard-cutting it.
    ///
    /// Every widget on the shelf redraws its value on a tick - clock digits,
    /// battery percentage, CPU and memory, prices - and each one swapped its
    /// text instantly, which is what made the widgets look inert next to the
    /// rest of the shelf. `numericText` is Apple's own transition for exactly
    /// this, and it is the difference between a readout and a live one.
    func rollingValue(_ value: some Equatable) -> some View {
        contentTransition(.numericText())
            .animation(.snappy(duration: 0.28), value: value)
    }
}

/// How a widget writes its own state back.
///
/// `WidgetContext` is `Equatable` and `Sendable` so tiles can be diffed
/// cheaply, which rules out carrying a closure. This is the channel instead:
/// the app wires it once at launch, widgets call it, and the change lands in
/// the profile and is persisted like any other edit.
///
/// Without it a widget can only ever be a readout - which is what every tile
/// but Now Playing was. A stopwatch you cannot start is a picture of one.
@MainActor
public enum WidgetWriter {
    public static var update: (WidgetInstance) -> Void = { _ in }

    /// Applies a change to one widget's config.
    public static func write(_ instance: WidgetInstance,
                             _ change: (inout WidgetConfig) -> Void) {
        var updated = instance
        change(&updated.config)
        update(updated)
    }
}
