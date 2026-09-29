import AppKit
import SwiftUI

/// Now Playing at length: the artwork at a size worth looking at, the track,
/// a scrubber you can actually drag, and the transport in full.
///
/// The tile is width-starved - 264pt carrying artwork, two lines of text, a
/// scrubber and buttons - so it hides controls and shrinks the art. None of
/// those compromises apply here, and the panel undoes them rather than
/// restating the tile larger.
///
/// It does not start the services: the panel only ever opens from a tile that
/// is already on screen, and that tile owns the poll and the source list.
struct MusicDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    /// Where a drag is holding the playhead, 0…1, or nil when the bar is
    /// following playback. Readings keep arriving mid-drag, so the bar has to
    /// answer to the pointer until it is let go or it fights the poll.
    @State private var scrubbing: Double?

    private var config: WidgetConfig { instance.config }

    /// Same preference order the tile reads, so the panel cannot end up
    /// showing a different player than the tile it grew out of.
    private var sources: [MusicSource] {
        var list: [MusicSource] = []
        if config.bool("spotify", default: true) { list.append(.spotify) }
        if config.bool("apple", default: true) { list.append(.appleMusic) }
        return list
    }

    private var browsersEnabled: Bool { config.bool("browsers", default: true) }

    private var playing: Playing? {
        guard !context.isPreview else { return nil }
        let native = MusicService.shared.nowPlaying.map(Playing.init(native:))
        let browser = browsersEnabled
            ? BrowserMedia.shared.track.map { Playing(browser: $0, artwork: BrowserMedia.shared.artwork) }
            : nil
        if native?.isPlaying == true { return native }
        if browser?.isPlaying == true { return browser }
        return native ?? browser
    }

    private var needsPermission: Bool {
        guard !context.isPreview else { return false }
        return MusicService.shared.needsAutomationPermission
            || (browsersEnabled && BrowserMedia.shared.needsPermission)
    }

    var body: some View {
        VStack(spacing: 14) {
            artwork(playing?.artwork)
            if let track = playing {
                titles(track)
                // A video with no readable duration would draw two 0:00 clocks
                // around a bar that can never move, so it gets none.
                if track.duration > 0 || !track.isBrowser { scrubber(track) }
                transport(track)
            } else if needsPermission {
                connect
            } else {
                idle
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Artwork

    /// Clipped twice on purpose: the fill is rounded before the image is laid
    /// over it, and `.fill` aspect ratio overflows the frame after it.
    private func artwork(_ image: NSImage?) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(WidgetStyle.primary.opacity(0.08))
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 52, weight: .medium))
                        .foregroundStyle(WidgetStyle.primary.opacity(0.3))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .frame(width: 170, height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityLabel("Artwork")
    }

    // MARK: Track

    private func titles(_ track: Playing) -> some View {
        VStack(spacing: 2) {
            Text(track.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WidgetStyle.primary)
            Text(track.artist)
                .font(WidgetStyle.caption(13))
                .foregroundStyle(WidgetStyle.secondary)
        }
        // Truncated, never wrapped: the panel is sized once when it opens, so
        // a title that took a second line would be clipped by the window
        // rather than given room.
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity)
    }

    // MARK: Scrubber

    private func scrubber(_ track: Playing) -> some View {
        let ratio = scrubbing ?? track.progress
        return HStack(spacing: 9) {
            time(MusicTime.clock(scrubbing.map { $0 * track.duration } ?? track.elapsed),
                 alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(WidgetStyle.secondary.opacity(0.3))
                    Capsule()
                        .fill(WidgetStyle.primary)
                        .frame(width: max(0, geo.size.width * ratio))
                        // Playback advances at a constant rate, so gliding to
                        // each reading at that rate is the truth; a drag is
                        // not, and must land exactly where the pointer is.
                        .animation(track.isPlaying && scrubbing == nil
                                   ? .linear(duration: MusicTile.pollInterval) : nil,
                                   value: ratio)
                }
                .contentShape(Rectangle())
                .gesture(seek(track, width: geo.size.width))
            }
            .frame(height: 5)
            time(MusicTime.clock(track.duration), alignment: .trailing)
        }
    }

    /// Browser playback is read-only apart from play/pause: there is no way to
    /// move a `<video>` element's playhead from here.
    private func seek(_ track: Playing, width: CGFloat) -> some Gesture {
        // Zero minimum distance so a plain click seeks too - jumping to a
        // point is the more common gesture, dragging the rarer one.
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard canSeek(track), width > 0 else { return }
                scrubbing = min(1, max(0, value.location.x / width))
            }
            .onEnded { value in
                guard canSeek(track), width > 0 else { return }
                let ratio = min(1, max(0, value.location.x / width))
                scrubbing = nil
                MusicService.shared.seek(to: ratio * track.duration)
            }
    }

    private func canSeek(_ track: Playing) -> Bool {
        !context.isPreview && !track.isBrowser && track.duration > 0
    }

    /// A minimum width rather than a fitted one: without it the bar shifts
    /// sideways the moment a track crosses ten minutes.
    private func time(_ text: String, alignment: Alignment) -> some View {
        Text(text)
            .font(WidgetStyle.caption(12))
            .monospacedDigit()
            .rollingValue(text)
            .foregroundStyle(WidgetStyle.secondary)
            .lineLimit(1)
            .fixedSize()
            .frame(minWidth: 34, alignment: alignment)
    }

    // MARK: Transport

    /// Previous and next are unconditional here even though the tile makes
    /// them optional - that switch exists to buy width on a 264pt strip, and
    /// the panel has width to spare. The skip-by-N buttons stay opt-in,
    /// because those are a preference rather than a concession to space.
    @ViewBuilder
    private func transport(_ track: Playing) -> some View {
        if track.isBrowser {
            button(track.isPlaying ? "pause.fill" : "play.fill", 28) { toggle(track) }
        } else {
            let step = max(1, config.int("skip", default: 15))
            HStack(spacing: 24) {
                if config.bool("backward") {
                    button(skipSymbol("gobackward", step), 17) {
                        MusicService.shared.skip(by: -Double(step))
                    }
                }
                button("backward.end.fill", 19) { MusicService.shared.previous() }
                button(track.isPlaying ? "pause.fill" : "play.fill", 28) {
                    MusicService.shared.playPause()
                }
                button("forward.end.fill", 19) { MusicService.shared.next() }
                if config.bool("forward") {
                    button(skipSymbol("goforward", step), 17) {
                        MusicService.shared.skip(by: Double(step))
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    /// Whichever service owns what is on screen. Firing both means pausing a
    /// tab also starts Spotify, and the panel then jumps to another track.
    private func toggle(_ track: Playing) {
        if track.isBrowser { BrowserMedia.shared.playPause() }
        else { MusicService.shared.playPause() }
    }

    /// SF Symbols ships numbered skip glyphs for a handful of intervals only;
    /// anything else falls back to the plain arrow rather than a blank square.
    private func skipSymbol(_ base: String, _ seconds: Int) -> String {
        let numbered: Set<Int> = [5, 10, 15, 30, 45, 60, 75, 90]
        return numbered.contains(seconds) ? "\(base).\(seconds)" : base
    }

    private func button(_ symbol: String, _ size: CGFloat,
                        action: @escaping () -> Void) -> some View {
        Button {
            guard !context.isPreview else { return }
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(WidgetStyle.primary)
                .frame(width: size * 1.5, height: size * 1.4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Empty states

    /// The only thing that ever raises the automation consent dialog, and it
    /// runs solely because the user clicked it.
    private var connect: some View {
        Button {
            guard !context.isPreview else { return }
            MusicService.shared.requestAutomationPermission()
            if browsersEnabled { BrowserMedia.shared.requestPermission() }
        } label: {
            Text("Connect")
                .font(WidgetStyle.label(13))
                .foregroundStyle(WidgetStyle.primary)
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .background(Capsule().fill(WidgetStyle.primary.opacity(0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Three different lines, because they mean different things: a player
    /// open and idle, a browser that will not run our JavaScript, or nothing
    /// open at all.
    private var idle: some View {
        let open = !context.isPreview && MusicService.shared.hasPlayer
        let setup = browserSetupHint
        return VStack(spacing: 4) {
            Text(setup == nil ? (open ? "Not playing" : "Nothing to read")
                              : "A tab has media Docket cannot read")
                .font(WidgetStyle.label(13))
                .foregroundStyle(WidgetStyle.primary)
            Text(setup ?? (open ? "Start something in \(sourceNames)."
                                : "Docket reads \(sourceNames), and video in a scriptable browser tab."))
                .font(WidgetStyle.caption(12))
                .foregroundStyle(WidgetStyle.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    /// The menu item the user has to switch on, or nil when nothing is asking.
    private var browserSetupHint: String? {
        guard !context.isPreview, browsersEnabled, BrowserMedia.shared.needsSetup else { return nil }
        let hint = BrowserMedia.shared.setupHint
        return hint.isEmpty ? nil : hint
    }

    private var sourceNames: String {
        let names = sources.map(\.displayName)
        guard !names.isEmpty else { return "no sources" }
        return names.count == 1 ? names[0] : names.joined(separator: " or ")
    }
}
