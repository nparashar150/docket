import AppKit
import SwiftUI

/// Where a shortcut is chosen, and where the reason it did not run is said
/// out loud.
///
/// The tile can only ever show a name and a glyph, which is fine until the
/// shortcut is renamed in Shortcuts.app and the name stored here stops
/// matching anything. The tool reports that plainly, on stderr, and this is
/// the surface that can repeat it and offer the list again. Without that the
/// widget would simply stop working one day with nothing to say.
///
/// Having no shortcuts at all is an ordinary state and gets its own words
/// rather than an empty menu: a Mac nobody has opened Shortcuts on has none,
/// and a picker with nothing in it reads as broken. Same judgement as
/// CalendarDetail, which hides its picker rather than show an empty one.
///
/// The list is read when the panel opens. It can only change in Shortcuts.app,
/// and going there means leaving this panel, which dismisses it, so polling
/// would be a timer spent on a value that cannot move while it is on screen.
struct ShortcutDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var service: ShortcutsService { ShortcutsService.shared }

    private var chosen: String {
        instance.config.string("name").trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            outcome
            chooser
            HStack(spacing: 8) {
                button("Open Shortcuts", fill: Self.accent, label: .white, action: openShortcuts)
                if !chosen.isEmpty {
                    button("Clear", fill: nil, label: WidgetStyle.primary) {
                        WidgetWriter.write(instance) { $0.set("name", .string("")) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await service.load() }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Self.accent.opacity(chosen.isEmpty ? 0.18 : 1))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: running ? "stop.fill" : "play.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(chosen.isEmpty ? WidgetStyle.secondary : .white)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(chosen.isEmpty ? "No shortcut chosen" : chosen)
                    .font(WidgetStyle.label(15))
                    .foregroundStyle(WidgetStyle.primary)
                    .lineLimit(1)
                Text(running ? "Running" : chosen.isEmpty ? "Pick one below" : "Ready")
                    .font(WidgetStyle.caption(11))
                    .foregroundStyle(WidgetStyle.secondary)
            }
            Spacer(minLength: 0)
            if !chosen.isEmpty {
                TileGlyph(symbol: running ? "stop.fill" : "play.fill", size: 12) {
                    if running { service.stop() } else { service.run(chosen) }
                }
            }
        }
    }

    /// Only ever the last run, and only in words the tool actually produced.
    @ViewBuilder private var outcome: some View {
        switch service.lastRun {
        case .failed(let name, let why) where name == chosen:
            note(why, tint: Self.red)
        case .cancelled(let name) where name == chosen:
            note("Stopped.", tint: nil)
        case .ok(let name) where name == chosen:
            note("Finished.", tint: nil)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var chooser: some View {
        if let error = service.loadError {
            note(error, tint: Self.red)
        } else if service.loadedAt == nil {
            note("Reading your shortcuts.", tint: nil)
        } else if service.names.isEmpty {
            note("You have no shortcuts yet. Make one in Shortcuts and it will appear here.", tint: nil)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(service.names.prefix(Self.visibleRows), id: \.self) { name in
                    row(name)
                }
                if service.names.count > Self.visibleRows {
                    Text("and \(service.names.count - Self.visibleRows) more, in Shortcuts")
                        .font(WidgetStyle.caption(10))
                        .foregroundStyle(WidgetStyle.secondary)
                }
            }
        }
    }

    private func row(_ name: String) -> some View {
        Button {
            WidgetWriter.write(instance) { $0.set("name", .string(name)) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: name == chosen ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                    .foregroundStyle(name == chosen ? Self.accent : WidgetStyle.secondary)
                Text(name)
                    .font(WidgetStyle.label(12))
                    .foregroundStyle(WidgetStyle.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func note(_ text: String, tint: Color?) -> some View {
        Text(text)
            .font(WidgetStyle.caption(11))
            .foregroundStyle(tint ?? WidgetStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func button(_ title: String, fill: Color?, label: Color,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(WidgetStyle.label(12))
                .foregroundStyle(label)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(fill ?? WidgetStyle.primary.opacity(0.12))
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: State

    private var running: Bool { !chosen.isEmpty && service.running == chosen }

    /// The panel sizes itself to its content, so an unbounded list would grow
    /// off the screen. Same cut-off reasoning as RemindersDetail.
    private static let visibleRows = 6

    private static let accent = Color(hex: "#A855F7")
    private static let red = Color(hex: "#FF6B6B")

    private func openShortcuts() {
        guard let url = URL(string: "shortcuts://") else { return }
        NSWorkspace.shared.open(url)
    }
}
