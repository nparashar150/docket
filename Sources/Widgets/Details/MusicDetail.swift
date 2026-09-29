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

    /// The ground the chrome paints, if the artwork gave one.
    ///
    /// Static because the chrome asks before this view exists, and it asks
    /// through the same `playing` resolution so the colour can never belong
    /// to a different track than the one on screen.
    @MainActor
    static func ground(instance: WidgetInstance, context: WidgetContext) -> ArtworkTint? {
        MusicDetail(instance: instance, context: context).playing?.tint
    }

    fileprivate var playing: Playing? {
        guard !context.isPreview else { return nil }
        let native = MusicService.shared.nowPlaying.map(Playing.init(native:))
        let browser = browsersEnabled
            ? BrowserMedia.shared.track.map {
                Playing(browser: $0, artwork: BrowserMedia.shared.artwork,
                        tint: BrowserMedia.shared.tint)
            }
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

    /// Ink, pinned to the ground when there is one.
    ///
    /// `WidgetStyle.primary` and `.secondary` follow the system appearance,
    /// which is right on a vibrant plate and wrong on a ground whose
    /// brightness this app fixed: in a forced-light appearance they would go
    /// dark and disappear into it. The same reasoning StickyNoteDetail
    /// already uses for its ink on fixed paper.
    private var hasGround: Bool { playing?.tint != nil }

    private var ink: Color { hasGround ? .white : WidgetStyle.primary }

    /// Opaque rather than `Color.secondary`, whose translucency caps its
    /// contrast no matter what is behind it.
    private var subInk: Color { hasGround ? Color(white: 0.8) : WidgetStyle.secondary }

    private var trackInk: Color {
        hasGround ? .white.opacity(0.48) : WidgetStyle.secondary.opacity(0.3)
    }

    // MARK: Artwork

    /// Clipped twice on purpose: the fill is rounded before the image is laid
    /// over it, and `.fill` aspect ratio overflows the frame after it.
    ///
    /// Square only for square artwork. A cover is square and a video
    /// thumbnail is 16:9, and cropping the second to the first threw away
    /// 44% of its width from the middle outward, which is how a drag race
    /// became a man standing in front of nothing. Wide artwork gets a wide
    /// frame and is fitted into it instead.
    private func artwork(_ image: NSImage?) -> some View {
        let wide = (image?.size.width ?? 0) > (image?.size.height ?? 1) * 1.2
        let side: CGFloat = 170
        return RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(hasGround ? .black.opacity(0.22) : WidgetStyle.primary.opacity(0.08))
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        // Fitted when the shape of the frame is the shape of
                        // the picture, so nothing is thrown away.
                        .aspectRatio(contentMode: wide ? .fit : .fill)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 52, weight: .medium))
                        .foregroundStyle(hasGround ? .white.opacity(0.35)
                                                   : WidgetStyle.primary.opacity(0.3))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .frame(width: wide ? 298 : side, height: wide ? 168 : side)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            // Only with a ground, and black rather than tinted: a shadow in
            // the ground's own hue on the ground itself is invisible.
            .shadow(color: hasGround ? .black.opacity(0.45) : .clear, radius: 22, y: 10)
            .overlay {
                if hasGround {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                }
            }
            .accessibilityLabel("Artwork")
    }

    // MARK: Track

    private func titles(_ track: Playing) -> some View {
        VStack(spacing: 2) {
            Text(track.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ink)
            Text(track.artist)
                .font(WidgetStyle.caption(13))
                .foregroundStyle(subInk)
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
                    Capsule().fill(trackInk)
                    Capsule()
                        .fill(ink)
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
            // One control, so it had better look deliberate. A lone glyph
            // under the scrubber reads as something left unfinished.
            play(track.isPlaying) { toggle(track) }
        } else {
            let step = max(1, config.int("skip", default: 15))
            HStack(spacing: 14) {
                if config.bool("backward") {
                    secondary(skipSymbol("gobackward", step), 15) {
                        MusicService.shared.skip(by: -Double(step))
                    }
                }
                secondary("backward.end.fill", 17) { MusicService.shared.previous() }
                play(track.isPlaying) { MusicService.shared.playPause() }
                secondary("forward.end.fill", 17) { MusicService.shared.next() }
                if config.bool("forward") {
                    secondary(skipSymbol("goforward", step), 15) {
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

    /// The one you came for.
    private func play(_ playing: Bool, action: @escaping () -> Void) -> some View {
        Button {
            guard !context.isPreview else { return }
            action()
        } label: {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: 21, weight: .semibold))
                // Optical, not geometric: play.fill is a triangle whose mass
                // sits left of its box, so centring the box leaves it looking
                // shoved to one side inside a circle. Pause is symmetric and
                // needs none.
                .offset(x: playing ? 0 : 1.5)
        }
        .buttonStyle(TransportButton(primary: true, ink: ink))
        .accessibilityLabel(playing ? "Pause" : "Play")
    }

    private func secondary(_ symbol: String, _ size: CGFloat,
                           action: @escaping () -> Void) -> some View {
        Button {
            guard !context.isPreview else { return }
            action()
        } label: {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold))
        }
        .buttonStyle(TransportButton(primary: false, ink: ink))
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

/// Transport controls that answer a click and say which one is the point.
///
/// Every control used to be the same bare glyph at a different point size on
/// `.plain`, which draws no pressed state at all: play and pause read as
/// merely the largest of five rather than the one the panel is for, and
/// nothing acknowledged being clicked. A filled disc for the primary and
/// plain glyphs either side is the hierarchy Apple Music uses, and it is the
/// same disc-deepens-and-shrinks response `TileGlyph` already gives the
/// shelf, so the two surfaces answer a press the same way.
///
/// Ink is passed in rather than taken from `WidgetStyle`. When the panel is
/// standing on a colour drawn from the artwork, its brightness is fixed by
/// this app rather than by the system, so a semantic colour here would go
/// dark in a forced-light appearance and disappear into it. The title and
/// the scrubber were already pinned for that reason; these were missed.
private struct TransportButton: ButtonStyle {
    var primary: Bool
    var ink: Color

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let side: CGFloat = primary ? 46 : 34
        return configuration.label
            // The secondaries sit back a little so the primary leads without
            // having to be enormous.
            .foregroundStyle(ink.opacity(primary ? 1 : (pressed ? 1 : 0.7)))
            .frame(width: side, height: side)
            .background {
                if primary {
                    Circle().fill(ink.opacity(pressed ? 0.26 : 0.14))
                }
            }
            // Round, so the corners of the box do not swallow a click meant
            // for the neighbour.
            .contentShape(Circle())
            .scaleEffect(pressed ? 0.92 : 1)
            .animation(.snappy(duration: 0.14), value: pressed)
    }
}
