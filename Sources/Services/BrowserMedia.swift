import AppKit
import CoreServices
import Foundation
import Observation

/// The browsers Docket can actually talk to.
///
/// Verified on this machine: all four ship the standard automation dictionary
/// - `execute … javascript` for the Chromium three, `do JavaScript` for
/// Safari - and every one of them resolves by bundle id. Firefox ships no
/// sdef at all and is deliberately absent: there is nothing there to address.
///
/// Never address a browser by *name*. `application "Brave Browser"` resolves
/// to Helium here - a Brave fork that inherited the LaunchServices name - so
/// a name lookup can silently drive the wrong app. Bundle ids only, which is
/// also what `NSAppleEventDescriptor(bundleIdentifier:)` wants.
public enum BrowserApp: String, CaseIterable, Sendable {
    case helium = "net.imput.helium"
    case brave = "com.brave.Browser"
    case dia = "company.thebrowser.dia"
    case safari = "com.apple.Safari"

    var bundleID: String { rawValue }

    var displayName: String {
        switch self {
        case .helium: "Helium"
        case .brave: "Brave"
        case .dia: "Dia"
        case .safari: "Safari"
        }
    }

    /// Safari's dictionary and its settings both differ from Chromium's.
    var isSafari: Bool { self == .safari }

    /// The exact menu path to the switch that lets us read playback state,
    /// because "enable the setting" on its own sends people hunting.
    var setupHint: String {
        isSafari
            ? "Safari ▸ Settings ▸ Developer ▸ Allow JavaScript from Apple Events"
            : "\(displayName) ▸ View ▸ Developer ▸ Allow JavaScript from Apple Events"
    }
}

/// A video or audio element playing in a browser tab.
///
/// This used to say `mediaSession` artwork is absent on the sites that matter
/// and that the placeholder was therefore the honest rendering. The probe
/// never asked for artwork, so that was an assumption rather than a finding:
/// the same metadata object that yields a clean title and artist carries an
/// `artwork` array, and the sites named as populating one populate the other.
/// Asked for now. Absent is still handled, because a site that sets no
/// artwork is a real case rather than a wrong guess.
public struct BrowserTrack: Sendable, Equatable {
    public var title: String
    /// The `mediaSession` artist, falling back to the host name.
    public var site: String
    public var isPlaying: Bool
    public var elapsed: TimeInterval
    public var duration: TimeInterval
    public var browser: BrowserApp
    /// Largest `mediaSession` artwork the page offers, if any.
    ///
    /// The URL rather than the image: this struct crosses back from a
    /// serial queue on every poll, and downloading inside that would stall
    /// the poll and refetch the same picture eight times a second.
    public var artworkURL: URL?

    /// 0…1, never NaN - a live stream reports no duration.
    public var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }
}

/// Now Playing for browser tabs.
///
/// Two things are true and shape everything here:
///
/// 1. Enumerating every tab is cheap - one plural-form Apple Event returns all
///    115 tabs of 4 windows in ~10 ms, less than a single Spotify query. Doing
///    it *per tab* is 9 ms each and is the only way to get this wrong, so the
///    found tab is cached and re-queried alone.
/// 2. Reading playback state needs JavaScript, which every browser ships
///    switched off. Without it a matching URL tells us a media tab *exists*,
///    not that anything is playing - so we never invent a track from a URL.
///    We say what to switch on instead.
@MainActor @Observable
public final class BrowserMedia {
    public static let shared = BrowserMedia()

    /// Last good reading. A failed poll leaves it alone rather than blanking
    /// the tile whenever a script times out.
    public private(set) var track: BrowserTrack?

    /// The cover for `track`, once it has arrived.
    ///
    /// Separate from the track because the track is replaced on every poll,
    /// eight times a second at the shelf's rate, while the picture behind it
    /// changes only when the video does.
    public private(set) var artwork: NSImage?

    /// The colour the panel stands on, from the same bytes.
    public private(set) var tint: ArtworkTint?
    /// A browser has media tabs open but will not run our JavaScript.
    public private(set) var needsSetup = false
    /// Menu path for the browser behind `needsSetup`; empty when it is false.
    public private(set) var setupHint = ""
    /// Automation consent for the browser has never been granted. Separate
    /// from `MusicService`'s: consent is per target app.
    public private(set) var needsPermission = false

    /// Honours the widget's `browsers` toggle.
    public var enabled = true {
        didSet {
            guard enabled != oldValue, !enabled else { return }
            track = nil
            needsSetup = false
            setupHint = ""
            cached = nil
        }
    }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var polling = false
    /// Set once a script has hung; cleared only when the user asks to connect.
    @ObservationIgnored private var blocked = false
    @ObservationIgnored private var lastProbe: Date = .distantPast
    /// Consecutive probes that ran out of time.
    @ObservationIgnored private var timeouts = 0

    /// When we last spoke to the browser ourselves.
    @ObservationIgnored private var lastCommand: Date = .distantPast

    /// How long after one of our own commands a timed-out probe is treated as
    /// our own traffic rather than as the player refusing.
    ///
    /// Long enough to cover a burst of clicks plus one probe's budget, short
    /// enough that something genuinely unresponsive still gives up within a
    /// few seconds of the last press.
    private static let commandGrace: TimeInterval = 5

    /// When the last full rescan ran.
    @ObservationIgnored private var lastRescan: Date = .distantPast
    /// How rarely a full rescan may run while a cached tab still answers.
    private static let rescanInterval: TimeInterval = 12
    @ObservationIgnored private var cached: BrowserBridge.TabRef?

    /// Back off hard when there is nothing to watch. A rescan walks every tab,
    /// and "no media tab is open" is the overwhelmingly common case.
    private var interval: TimeInterval {
        // Slightly under a second: the throttle compares against the *start*
        // of the previous probe, so a strict 1.0 plus ~20ms of round trip
        // lands just past the next tick and degrades to every other one.
        if let track { return track.isPlaying ? 0.85 : 3 }
        return needsSetup ? 30 : 15
    }

    private init() {}

    // MARK: Lifecycle

    /// Idempotent; every Now Playing tile shares one poll.
    public func start() {
        guard timer == nil else { return }
        refresh()
        // Ticks every second; `interval` decides which ticks actually probe.
        // A two-second timer put a hard floor under the poll rate, so asking
        // for one-second updates while playing quietly had no effect and the
        // scrubber still moved in two-second steps.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Reading

    public func refresh() {
        guard enabled else { return }
        let now = Date.now
        guard PollGate.shouldStart(inFlight: polling,
                                   blocked: blocked,
                                   sinceLastStart: now.timeIntervalSince(lastProbe),
                                   interval: interval) else { return }
        polling = true
        lastProbe = now
        let tab = cached
        // A full rescan is several Apple Events per browser and can stall for
        // minutes on one unresponsive tab, so it is rationed. While something
        // is merely paused the cached tab answers cheaply every poll; the
        // rescan only has to be often enough to notice playback starting
        // somewhere else. Running one every 3s is what wedged this service.
        // Time alone, not what we believe is playing. `track` is the last
        // good reading and `playPause()` flips it optimistically, so keying
        // off it meant a closed or navigated tab - whose cached read returns
        // nothing - could keep reporting "still playing" and never earn a
        // rescan. A playing cached tab short-circuits inside poll() anyway, so
        // allowing the rescan costs nothing while playback is healthy.
        let rescan = tab == nil || now.timeIntervalSince(lastRescan) >= Self.rescanInterval
        if rescan { lastRescan = now }
        Task { [tab, rescan] in
            // Same lesson as MusicService: an Apple Event to an app we have no
            // consent for can block forever, and a blocked script with no
            // timeout wedges the poll for the life of the process.
            // A scan has to enumerate every tab and then JavaScript-probe
            // several candidates; across a hundred-odd tabs that is simply
            // slower than a re-query of one known tab. Budgeting both the same
            // made every cold scan "time out" on a machine with a lot open.
            //
            // The test is whether a rescan is coming, NOT whether a tab handle
            // exists. Holding the handle through a pause - which is what makes
            // resume possible - meant a paused track took the rescan path on
            // the 3s budget, timed out, and three strikes later blocked the
            // browser outright with the tile stuck on Connect.
            let budget: Double = rescan ? 8 : 3
            let result = await withTimeout(seconds: budget) {
                await BrowserBridge.poll(cached: tab, rescan: rescan)
            }
            if let result {
                self.timeouts = 0
                self.apply(result)
            } else {
                self.stalled()
            }
        }
    }

    /// A probe that did not come back in time.
    ///
    /// Slowness is not refusal. Treating the first timeout as a permanent
    /// block meant one slow scan disabled browser support for the life of the
    /// process, with the tile stuck on Connect and nothing left to retry it.
    private func stalled() {
        polling = false
        // Back off rather than hammering a browser that is busy.
        lastProbe = .now
        // Our own traffic, not a refusal.
        //
        // Commands and probes share one serial queue, and an Apple Event to a
        // browser is not quick. Pressing play and pause quickly puts several
        // toggles in that queue, the probe behind them misses its budget
        // through no fault of the browser, and three of those in a row
        // blocked browser support outright: the reading dropped, the tile fell
        // back to Connect, and the only way out was a consent dialog for
        // consent that had already been given. Which is to say the widget
        // broke because it was being used.
        //
        // A probe that times out while we are still talking says nothing
        // about whether the browser will answer, so it does not get a strike.
        // A browser that is genuinely refusing stops being spoken to and
        // starts collecting them within a few seconds.
        guard Date().timeIntervalSince(lastCommand) >= Self.commandGrace else { return }
        timeouts += 1
        guard timeouts >= 3 else { return }
        blocked = true
        needsPermission = true
        // Drop the last reading. Keeping it meant the tile showed a stale
        // paused track forever *and* hid the Connect button, which is the
        // only thing that clears `blocked` - there was no way back.
        track = nil
    }

    /// Downloads the cover, at most once per URL.
    ///
    /// Guarded on the URL rather than on the track: a poll that finds the
    /// same video again must not refetch, and the shelf polls while the
    /// panel is open. A failure leaves `artwork` nil and is not retried for
    /// that URL, because the fallback is already a reasonable picture and a
    /// retry loop against someone's CDN is not worth a decoration.
    private func adoptArtwork(_ url: URL?) {
        guard url != artworkURL else { return }
        artworkURL = url
        artwork = nil
        tint = nil
        guard let url else { return }
        Task { [weak self] in
            var request = URLRequest(url: url)
            request.timeoutInterval = 6
            // Decorative, so a stale one from the cache is preferable to
            // spending a request on it.
            request.cachePolicy = .returnCacheDataElseLoad
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = NSImage(data: data)
            else { return }
            // Detached on purpose: this Task body inherits main isolation
            // from the actor it was started on, and a 16x16 decode plus a
            // histogram is not main-thread work.
            let tint = await ArtworkTint.extracted(from: data)
            guard let self, artworkURL == url else { return }
            artwork = image
            self.tint = tint
        }
    }

    @ObservationIgnored private var artworkURL: URL?

    private func apply(_ poll: BrowserBridge.Poll) {
        defer { polling = false }
        needsPermission = poll.denied
        cached = poll.tab

        if let found = poll.track {
            track = found
            adoptArtwork(found.artworkURL)
            needsSetup = false
            setupHint = ""
            // The handle is kept even while paused: it is the only way to
            // resume. Dropping it here made the play glyph permanently dead
            // after one pause, because `playPause()` needs a tab to talk to.
            // Not pinning to a paused tab is handled in the poll itself,
            // which keeps rescanning until it finds one actually playing.
            return
        }

        // Only a clean "nothing is playing" clears the tile; a script that
        // failed mid-video keeps the last good reading on screen.
        if poll.searched { track = nil }
        needsSetup = poll.setup != nil
        setupHint = poll.setup?.setupHint ?? ""
    }



    // MARK: Transport

    /// The only control offered. `next`/`previous` are meaningless for a video
    /// element and the sites that do have playlists each need their own DOM
    /// poking - a dead button is worse than no button.
    ///
    /// Resume can still be refused: JavaScript injected over Apple Events
    /// carries no user activation, so autoplay policy has the last word. The
    /// next poll (≤2 s) corrects the optimistic flip either way.
    public func playPause() {
        guard let current = track, let tab = cached else { return }
        track?.isPlaying.toggle()
        lastCommand = .now
        Task { await BrowserBridge.toggle(tab, browser: current.browser) }
    }

    // MARK: Permission

    /// The only place allowed to raise the automation consent dialog, and it
    /// runs solely because the user asked for it.
    public func requestPermission() {
        // An Automation prompt is only shown for the frontmost app, and an
        // accessory agent with no ordinary window never becomes frontmost -
        // so briefly become a regular app, ask, then slip back.
        let policy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        blocked = false
        polling = false
        timeouts = 0
        lastCommand = .distantPast
        lastProbe = .distantPast
        Task {
            await BrowserBridge.ask()
            NSApp.setActivationPolicy(policy)
            self.refresh()
        }
    }
}

// MARK: - Apple event plumbing

/// Everything that talks to a browser, kept off the main thread and serialised
/// onto one queue - `NSAppleScript` is not documented as thread-safe and a 2 s
/// poll has no use for concurrency.
enum BrowserBridge {
    /// Where the media was found. Indices, because that is all a Chromium or
    /// Safari tab specifier accepts; `url` is only used to notice drift.
    struct TabRef: Sendable, Equatable {
        var browser: BrowserApp
        var window: Int
        var tab: Int
        var url: String
    }

    struct Poll: Sendable {
        var track: BrowserTrack?
        var tab: TabRef?
        /// Media tabs exist in this browser but its JavaScript gate is shut.
        var setup: BrowserApp?
        /// Automation consent was refused for every browser we tried.
        var denied = false
        /// A rescan actually reached a browser, so "no track" is a fact and
        /// not a script that failed. A browser we cannot read leaves the tile
        /// exactly as it was.
        var searched = false
    }

    private static let queue = DispatchQueue(label: "com.namanparashar.plinth.browser")

    private static func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    // MARK: Polling

    static func poll(cached: TabRef?, rescan: Bool) async -> Poll {
        await offMain {
            // The cheap path: one JavaScript call against the tab we already
            // know about. A rescan only happens once it stops reporting media.
            var result = Poll()

            if let cached, isRunning(cached.browser) {
                switch read(cached, browser: cached.browser) {
                case .track(let track, let url):
                    let ref = TabRef(browser: cached.browser, window: cached.window,
                                     tab: cached.tab, url: url)
                    // A playing tab short-circuits outright. A paused one
                    // only does so when no rescan is due: hitting play in
                    // another tab still has to be able to take over, but not
                    // at the cost of scanning every browser every few seconds.
                    if track.isPlaying || !rescan { return Poll(track: track, tab: ref) }
                    result.track = track
                    result.tab = ref
                case .denied:
                    return Poll(denied: true)
                case .none, .gated:
                    break  // fall through to a rescan
                }
            }

            guard rescan else { return result }

            var sawBrowser = false
            for browser in BrowserApp.allCases where isRunning(browser) {
                sawBrowser = true
                guard let candidates = tabs(of: browser) else { continue }
                // At least one browser answered, so "nothing is playing" is a
                // fact about the world rather than a failed script.
                result.searched = true
                for candidate in candidates.prefix(Self.probeLimit) {
                    switch read(candidate, browser: browser) {
                    case .track(let track, let url):
                        var tab = candidate
                        tab.url = url
                        // A playing tab wins outright. Returning the *first*
                        // tab with media meant a paused one found earlier in
                        // the scan beat the video actually playing elsewhere,
                        // so starting playback in another tab changed nothing.
                        if track.isPlaying {
                            return Poll(track: track, tab: tab, searched: true)
                        }
                        if result.track == nil {
                            result.track = track
                            result.tab = tab
                        }
                        // Keep looking. Breaking out on a paused tab meant a
                        // video playing further down the same browser was
                        // never reached, so pausing one tab and playing
                        // another never synced.
                        continue
                    case .gated:
                        // The gate is a property of the browser, not the tab:
                        // no other tab of it will answer either.
                        result.setup = result.setup ?? browser
                    case .denied:
                        result.denied = true
                    case .none:
                        continue
                    }
                    break
                }
            }
            // No browser open at all is also a fact: whatever was playing
            // has certainly stopped.
            if !sawBrowser { result.searched = true }
            return result
        }
    }

    /// How many candidate tabs a rescan is willing to poke. Listing every tab
    /// is one Apple Event and free; each probe is its own round trip.
    private static let probeLimit = 5

    static func toggle(_ tab: TabRef, browser: BrowserApp) async {
        await offMain {
            guard isRunning(browser) else { return }
            _ = run(javascript: Script.toggle, in: tab, browser: browser)
        }
    }

    /// Raises the Automation consent dialog by actually sending an event.
    ///
    /// Not `AEDeterminePermissionToAutomateTarget(…, askUserIfNeeded: true)`:
    /// that call blocks indefinitely rather than prompting, which is precisely
    /// why the Connect button appeared to do nothing at all. A real (and
    /// trivial) Apple Event is what makes macOS ask.
    static func ask() async {
        await offMain {
            for browser in BrowserApp.allCases where isRunning(browser) {
                _ = script("tell application id \"\(browser.bundleID)\" to return name")
            }
        }
    }

    // MARK: Tab discovery

    /// URLs worth probing. Deliberately short: a miss costs one extra Apple
    /// Event, and the JavaScript probe is what actually decides.
    private static let mediaHosts = [
        "youtube.com/watch", "youtube.com/shorts", "youtube.com/live",
        "music.youtube.com", "netflix.com/watch", "twitch.tv/", "vimeo.com/",
        "primevideo.com", "hotstar.com", "disneyplus.com", "open.spotify.com",
        "soundcloud.com", "music.apple.com", "crunchyroll.com/watch",
        "dailymotion.com/video", "coursera.org/learn", "udemy.com/course",
    ]

    /// Every tab of every window in one round trip, filtered to plausible
    /// media URLs. Nil means the browser could not be read at all.
    private static func tabs(of browser: BrowserApp) -> [TabRef]? {
        guard case .value(let descriptor) = script(Script.list(browser)),
              let raw = descriptor.stringValue
        else { return nil }

        var found: [TabRef] = []
        for line in raw.split(separator: "\n") {
            let fields = line.components(separatedBy: "\t")
            guard fields.count >= 3, let window = Int(fields[0]), let index = Int(fields[1])
            else { continue }
            let url = fields[2].lowercased()
            guard mediaHosts.contains(where: url.contains) else { continue }
            found.append(TabRef(browser: browser, window: window, tab: index, url: fields[2]))
        }
        return found
    }

    // MARK: Reading one tab

    enum Reading {
        case track(BrowserTrack, url: String)
        /// The tab has no playable media, or the specifier no longer resolves.
        case none
        /// "Allow JavaScript from Apple Events" is off.
        case gated
        case denied
    }

    private static func read(_ tab: TabRef, browser: BrowserApp) -> Reading {
        switch run(javascript: Script.probe, in: tab, browser: browser) {
        case .gated: return .gated
        case .denied: return .denied
        case .failed: return .none
        case .value(let descriptor):
            guard let json = descriptor.stringValue, !json.isEmpty,
                  let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return .none }

            let title = (object["t"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return .none }
            let duration = max(0, object["d"] as? Double ?? 0)
            let elapsed = max(0, object["c"] as? Double ?? 0)
            let track = BrowserTrack(
                title: clean(title),
                site: object["a"] as? String ?? "",
                isPlaying: (object["p"] as? Bool) == false,
                elapsed: duration > 0 ? min(elapsed, duration) : elapsed,
                duration: duration,
                browser: browser,
                artworkURL: (object["w"] as? String).flatMap {
                    // http is refused on purpose. The picture is decorative
                    // and not worth a cleartext request.
                    let url = URL(string: $0)
                    return url?.scheme == "https" ? url : nil
                }
            )
            // See MediaReading: the page side already drops elements with
            // neither a duration nor a position, but a title can arrive with
            // neither behind it.
            guard MediaReading.isMeaningful(title: track.title,
                                            duration: track.duration,
                                            elapsed: track.elapsed) else { return .none }
            return .track(track, url: object["u"] as? String ?? tab.url)
        }
    }


    /// Document titles carry a notification count and a site suffix that the
    /// tile has no room for. `mediaSession` titles have neither, so this only
    /// ever fires on the fallback path.
    private static func clean(_ title: String) -> String {
        var text = title
        if text.hasPrefix("("), let close = text.firstIndex(of: ")"),
           Int(text[text.index(after: text.startIndex)..<close]) != nil {
            text = String(text[text.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        for suffix in [" - YouTube", " | Netflix", " - Twitch"] where text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count))
        }
        return text
    }

    // MARK: Primitives

    static func isRunning(_ browser: BrowserApp) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty
    }

    enum Outcome {
        case value(NSAppleEventDescriptor)
        case gated
        case denied
        case failed
    }

    private static func run(javascript: String, in tab: TabRef, browser: BrowserApp) -> Outcome {
        script(Script.execute(javascript, tab: tab, browser: browser))
    }

    /// Compiled scripts, keyed by source.
    ///
    /// Confined to the serial `browser` queue - every call reaches here via
    /// `offMain`, so no locking is needed. Recompiling per poll was the single
    /// biggest cost in a profile of this app's music poll; the same applies
    /// here. Per-tab sources embed indices, so the cache is capped rather than
    /// left to grow a new entry for every tab ever watched.
    nonisolated(unsafe) private static var compiled: [String: NSAppleScript] = [:]

    private static func script(_ source: String) -> Outcome {
        let script: NSAppleScript
        if let cached = compiled[source] {
            script = cached
        } else {
            guard let made = NSAppleScript(source: source) else { return .failed }
            made.compileAndReturnError(nil)
            if compiled.count >= 32 { compiled.removeAll() }
            compiled[source] = made
            script = made
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard let error else { return .value(result) }
        let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
        // -1743 not permitted, -1744 consent never asked for.
        if code == -1743 || code == -1744 { return .denied }
        // 12 from Chromium, 8 from Safari, both meaning the JavaScript switch
        // is off. Low integers that another app could plausibly reuse, hence
        // the message check as well.
        let message = (error[NSAppleScript.errorMessage] as? String) ?? ""
        if (code == 12 || code == 8) && message.contains("Apple Events") { return .gated }
        return .failed
    }
}

// MARK: - Script sources

/// The AppleScript and JavaScript this service sends.
///
/// The JavaScript is kept free of double quotes and backslashes so embedding
/// it in an AppleScript string literal needs no escaping at all.
private enum Script {
    /// Collects `<video>`/`<audio>` from the document and one level of
    /// same-origin iframe, prefers whatever is actually playing, then the
    /// longest - which skips autoplaying ad and preview clips.
    ///
    /// Cross-origin iframes are unreachable by design, so an embedded player
    /// on a third-party page cannot be read. Every direct watch page
    /// (youtube.com/watch, /shorts, netflix.com/watch) keeps its element in
    /// the top document, so the common cases are fine.
    private static let finder = """
    var o=[];function g(d){try{d.querySelectorAll('video,audio').forEach(function(v){o.push(v)})}\
    catch(e){}}g(document);try{document.querySelectorAll('iframe').forEach(function(f){\
    try{if(f.contentDocument)g(f.contentDocument)}catch(e){}})}catch(e){}\
    o=o.filter(function(v){return v.duration>0||v.currentTime>0});\
    o.sort(function(a,b){return (a.paused-b.paused)||(b.duration-a.duration)});
    """

    /// `mediaSession.metadata` first - YouTube, Netflix, Spotify Web,
    /// SoundCloud and Twitch all populate it and it yields a clean title and
    /// artist. `document.title` is the dirty fallback.
    ///
    /// Returns a JSON *string*: Chromium's coercion of a JavaScript object
    /// into an Apple Event record is unreliable, a string is not.
    static let probe = """
    (function(){\(finder)if(!o.length)return '';var v=o[0],w,\
    m=(navigator.mediaSession&&navigator.mediaSession.metadata)||null;\
    w=(m&&m.artwork&&m.artwork.length)?m.artwork[m.artwork.length-1].src:'';\
    return JSON.stringify({t:m&&m.title?m.title:document.title,\
    a:m&&m.artist?m.artist:location.hostname,p:v.paused,c:v.currentTime,\
    d:isFinite(v.duration)?v.duration:0,u:location.href,w:w})})()
    """

    static let toggle = """
    (function(){\(finder)if(!o.length)return '';var v=o[0];\
    if(v.paused){var p=v.play();if(p&&p.catch)p.catch(function(){})}else{v.pause()}\
    return 'ok'})()
    """

    static func execute(_ javascript: String, tab: TabRef, browser: BrowserApp) -> String {
        let id = browser.bundleID
        let specifier = "tab \(tab.tab) of window \(tab.window)"
        return browser.isSafari
            ? "tell application id \"\(id)\" to do JavaScript \"\(javascript)\" in \(specifier)"
            : "tell application id \"\(id)\" to execute \(specifier) javascript \"\(javascript)\""
    }

    /// The **active** tab of every window, as `window`⇥`index`⇥`url` lines.
    ///
    /// Deliberately not every tab. Chromium suspends background tabs, and
    /// injected JavaScript in a suspended tab never runs - the Apple Event
    /// simply never returns. Measured here: probing one background tab hung
    /// for over two minutes, while the active tab of the same window answered
    /// instantly. One hang is enough to consume the whole scan budget, so only
    /// awake tabs are ever probed.
    ///
    /// The cost of that is real: a video playing in a background tab is not
    /// found. There is no way around it - we cannot run code in a tab the
    /// browser has put to sleep.
    ///
    /// Still one plural-form Apple Event rather than one per window.
    static func list(_ browser: BrowserApp) -> String {
        // Safari has no `active tab`; its equivalent is `current tab`, and it
        // exposes no index for it, so address it as tab 1 of that window -
        // `execute` special-cases Safari anyway.
        let selection = browser.isSafari
            ? """
              set us to URL of current tab of windows
              set ix to {}
              repeat with w from 1 to count of us
                  set end of ix to 1
              end repeat
              """
            : """
              set us to URL of active tab of windows
              set ix to active tab index of windows
              """
        return """
        tell application id "\(browser.bundleID)"
            \(selection)
        end tell
        set out to {}
        repeat with w from 1 to count of us
            set end of out to ((w as text) & tab & ((item w of ix) as text) & tab & (item w of us))
        end repeat
        set AppleScript's text item delimiters to linefeed
        return out as text
        """
    }
}

private typealias TabRef = BrowserBridge.TabRef
