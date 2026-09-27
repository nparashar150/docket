# Docket Roadmap

A ranked, honest plan for what this app becomes next.

Everything below is graded for what it actually costs on macOS 26. Markers used throughout:

- **VERIFIED** means it was run on a real machine (macOS 26.5.2, build 25F84, Apple silicon, Xcode 26.6) and produced the stated result.
- **VERIFIED (docs)** means the vendor's own documentation was read and quoted.
- **UNCONFIRMED** means plausible, not tested. Treat it as a task, not a fact.
- **CONFLICTING** means two independent checks disagreed, and the disagreement is written down rather than smoothed over.

---

## 1. The argument

A shelf pinned to a screen edge is good at exactly one thing that nothing else on macOS is good at: **being wrong in your peripheral vision.**

A menu bar app is a click away, so it holds things you go and look at. A notification is a moment, so it holds things that happened once. A desktop widget is behind every window you have open, so it holds things you check when you are not working. A shelf is the only surface that is visible while you work, in a fixed spatial address, without being asked. That makes it the right home for *state you would be wrong about if you did not look*, and the wrong home for everything else.

Three tests follow, and they decided every ranking in this document:

1. **Does it change on its own?** A number you set once (uptime, sunset, a unit conversion) wastes a permanent slot. A number the world changes (badge count, budget burned, latency, minutes to the meeting) earns it.
2. **Would you be wrong if you did not look?** "Am I muted." "Is production green." "Is the call now." "How much of my weekly limit is gone." These are the questions where ambient display changes behaviour rather than saving a click.
3. **Can it signal without being read?** A colour shift, a fill level, a slow pulse, a brief widening. If the only way to get the information out of the tile is to read text at 62pt, it belongs in the panel that already opens on click.

The corollary is a design law, not a preference: **counts, levels, dots and glyphs on the tile; text, lists and names in the detail panel.** That law gets stronger, not weaker, once you know the platform fact in §2.2.

The second half of the argument is strategic. Docket today is a set of hand-written widgets, and the ceiling of that approach is however many widgets one person writes. The evidence is already in the repository: `WidgetKind` in `Sources/Core/Models.swift` carries `.stripe`, `.paddle`, `.shopify`, `.aiUsage` and `.shortcut`, there is a `WidgetCategory.business`, and `Sources/Widgets/Details/RevenueDetail.swift` says in its own doc comment that this build ships no client for any of them. `grep -rn "Keychain\|SecItem" Sources/` returns nothing. Five widgets are drawn and unwired, and that is **one** missing piece, not five: a place to keep a credential, and a generic thing that fetches JSON on a timer.

Build that one piece properly and something larger falls out of it for free. A credential store plus a declarative fetch plus a small layout vocabulary is not just the Stripe widget. It is the answer to "can people make their own widgets," and it means the next twenty integrations are config files written by other people instead of Swift written by you. That is the difference between a good shelf and a surface other people build on.

Third, and this reframes a limitation as a position. macOS gives third-party apps no Live Activities, no way to host another app's widget, and no way to read another app's notifications. Docket does not need any of them. A persistent, glanceable, always-on-screen strip that any local data source can escalate into is the macOS-native version of the thing an iPhone does with a Dynamic Island. The right framing is not that Docket is missing ActivityKit. It is that Docket is the thing ActivityKit would have been for.

---

## 2. Two platform facts that reorder everything

These are not features. They gate features, and they should be read before the roadmap.

### 2.1 Signing identity is the highest-leverage item in this document

macOS anchors a TCC grant to the app's **code signature**. With no certificate, the anchor is the binary's cdhash, so every rebuild is a different app to TCC. The grant silently stops applying: no prompt, no error, and the toggle in System Settings can still read "on." Apple Developer Technical Support has stated the mechanism directly, that TCC uses the code signature to confirm version N+1 is equivalent to version N, and that this requires a stable signing identity which ad-hoc signing does not provide.

Consequences for an unsigned or ad-hoc `.dmg`:

- Accessibility, Full Disk Access, Screen Recording and Automation all break on every update a user installs. Somebody who granted Accessibility in 0.3 loses it in 0.4 and gets no explanation.
- Keychain item ACLs bind to the same designated requirement, so a rolling identity was expected to produce a "wants to use your confidential information" prompt per item on every release. **MEASURED, and the answer is no, for a reason that is worse than the question.** Two ad-hoc binaries were built from the same source with one string changed, giving different cdhashes (`designated => cdhash H"f219..."` against `H"cac3..."`). The second read the generic password the first wrote: status 0, no prompt. But the control says why: `security find-generic-password -w`, an unrelated system binary, read the same secret with exit 0. There is no access restriction to survive. Adding an explicit `SecAccessCreate` trusted-application list naming only the first binary did not change either result.
- **VERIFIED:** the data-protection keychain, which is the one that would restrict by application, is closed to an ad-hoc build. `SecItemAdd` with `kSecUseDataProtectionKeychain` returns **-34018, errSecMissingEntitlement**. It needs `keychain-access-groups`, which needs a team identifier, which needs G5. So on an unsigned release the only keychain available is the legacy file-based one described above.
- Not established: whether a prompt-needing item would have been detected at all. The intended control for that required the data-protection keychain and hit the same -34018. The conclusion above rests on the `security` read instead, which shows no restriction exists rather than that a prompt was suppressed.
- **VERIFIED:** an ad-hoc binary that *claims* a restricted entitlement is killed by AMFI at launch. `codesign -s - --entitlements` with `com.apple.mediaremote.send-playback-commands` exits **137**, no output, no diagnostic. "Just add the entitlement" is never an escape hatch, for anything, ever.
- macOS 26.1 and later will not list a non-bundled executable in the Screen Recording pane at all. Docket is a proper `.app` bundle, so this is fine today, but the permission panes are a moving target on 26.x.

`project.yml` already signs local builds with a real Apple Development identity and already carries a comment noting that ad-hoc signing kills the Location prompt. That comment generalises much further than the file admits.

**Recommendation: treat a stable release identity (Developer ID plus notarization) as a prerequisite epic, not a footnote.** It is roughly one annual fee and one CI change, and it converts about eight items in this document from "support burden" to "shippable." Nothing else here has that leverage. Everything in §4 that costs a TCC grant should be read as *blocked on this*.

The consolation, and it is a large one: the strongest features in this document need **no** TCC grant at all, which is why they are at the top.

### 2.2 The shelf is in every screenshot, and you cannot opt out

`NSWindow.sharingType = .none` stopped affecting ScreenCaptureKit captures in macOS 15 and later, because WindowServer composites everything into one framebuffer that `SCStream` reads directly. The legacy `CGWindowListCreateImage` path that did respect it is **VERIFIED** as a hard compile error against the 26.5 SDK, obsoleted in macOS 15. Apple DTS on the developer forums: at this time there are no public APIs for preventing screen capture.

There is also no public way to *detect* that the screen is being captured, so an automatic "hide during a share" mode would be a guess that fails in the one moment it matters.

So the shelf is in every screenshot, every Zoom, Meet and Teams share, every recording. Not sometimes. Always. This is why §7's rule is hard rather than aspirational, and why the answer is a manual switch plus hotkey rather than a promise the platform cannot keep.

---

## 3. Tier 0: groundwork three features share

Call these out as their own work items, because otherwise each feature carries a third of them and none of them gets built properly.

### G1. Keychain credential store. Effort: S

One `SecItem` wrapper, roughly 80 lines. Generic password items under one service id, keyed by account label. `WidgetConfig` stores the **label only**, never the secret.

This is non-negotiable and the reason is boring. `WidgetConfig.Value` is string, number, bool or list and serialises straight into the single JSON file in Application Support, so a token there is plaintext on disk, in Time Machine, and in any state file a user pastes into a bug report. Prior art with the right promise: MRRDock (`github.com/simonsruggi/MRRDock`) keeps keys in the Keychain, never in the app's JSON, never in logs, never in a backup.

Surfaces in the UI as a Connections list: service, account label, last successful use, Revoke. It never shows a key back, only its last four characters.

**Risk: settled, and it moved.** The ad-hoc ACL re-prompt from §2.1 does not happen, so the `0600` fallback is not needed for that reason and G1 is not hostile to build. What replaced it is a copy problem. On an unsigned release the item lands in the login keychain with no application restriction, so any process running as the user reads the token with one `security` command, and the data-protection keychain that would fix this is closed without G5. The store is still right, because it keeps secrets out of `state.json`, out of Time Machine as plaintext and out of any state file pasted into a bug report. But the Connections UI must not say or imply "only Docket can read this" until G5 ships, because on today's builds that is not true.

### G2. Generic HTTP polling service. Effort: M

`Sources/Services/StockService.swift` is already the template and should be copied, not reinvented. It is an `@Observable @MainActor final class` with a `static let shared`, a `tracked` set so nothing is fetched until the first widget asks, a per-key cached last-good value, and a `stale: Bool`. Its own comment says every field is optional and every failure path returns `nil`, which leaves the cached value in place and only flips `stale`.

That discipline is mandatory for anything money-shaped. **A revenue tile must never render a zero it invented.** A stale cached total drawn as current is the one failure a money readout does not survive.

`Sources/Services/PollGate.swift` already encodes the in-flight and throttle decision as a value. Use it, do not hand-roll the flag.

What is new: request description (method, URL, headers with secret placeholders), a small JSON path evaluator, per-source intervals with a floor, and last-good plus staleness per source.

### G3. Accessibility bridge. Effort: M

Several features below read the Dock's tiles, other apps' windows, or Notification Center. Every one of them shares one TCC grant, one reconnect problem (the target process restarts, the observer dies), and one failure mode (silent empty results after an OS update). That argues for a single service alongside the existing `Sources/Services/*` singletons: one permission story, one reconnect loop, one place that degrades to nothing.

Wrap every AX call in the existing `Sources/Services/Timeout.swift`. AX is synchronous IPC into another process, and a hung app will freeze the shelf. `Timeout.swift`'s own doc comment is already about this exact hazard.

### G4. Escalation channel. Effort: M

One urgency field on `WidgetContext`, rendered by `WidgetTile` as a colour shift, a slow pulse, or a temporary widening. Consumed by the meeting countdown, the mic tile, threshold colouring, alarms, countdowns and any recipe that reports a warn or error state.

Two rules are the feature, not the animation: **one escalating widget at a time**, and respect `accessibilityDisplayShouldReduceMotion`. Three tiles escalating at once is noise, and noise trains people to stop looking, which costs the surface its only real advantage.

This is also the mechanism that makes the §1 claim true. An always-visible strip that can raise its own voice is the thing macOS does not otherwise give a third-party app.

### G5. Stable release signing. Effort: S, and it is §2.1

Listed here so it appears in the sequencing plan as a dependency rather than as advice.

---

## 4. Top tier

Eight features. Each would visibly change how good this app is, and together they are a coherent product rather than a pile.

---

### 4.1 Connected widgets: revenue, and the five stubs made real

**Effort: L** (M once G1 and G2 exist). **Permission: none from macOS.**

**Tile.** One currency figure with a small delta against the same point yesterday. Variants: Today, MRR, This month. A corner dot goes hollow when the figure is cached rather than fresh.

**Panel.** Thirty-day sparkline, the count behind the number ("14 charges"), MRR, active subscribers and refunds where the provider exposes them, one row per configured provider, last-refreshed time. On failure a blunt row: which provider, which HTTP status, Retry.

**Why it matters.** This is the single largest gap between what the app draws and what it does. `RevenueDetail.swift` is honest today about having no client; `WidgetDetail.swift` confirms `.shortcut` and `.aiUsage` have no panel at all. Filling this in is not one widget, it is five, and it is the piece that makes the business category mean something. Dockset ships Stripe, Paddle and Shopify widgets as prior art, so the demand is not hypothetical.

**Where the data comes from.** Prefer providers with a purpose-built aggregate endpoint, because one request gives one number:

- **Polar**: `GET https://api.polar.sh/v1/metrics/` with `start_date`, `end_date`, `interval`, optional `timezone`, and `metrics=` to request only what you need. Returns `periods`, `totals`, `metrics`; 45+ metrics including MRR, ARR, net revenue, active and churned subscriptions. Auth: organisation access token (`polar_oat_…`), scope `metrics:read`. **VERIFIED (docs)**
- **Paddle Billing**: `GET /metrics/revenue`, `/metrics/monthly-recurring-revenue`, `/metrics/active-subscribers`, `/metrics/refunds`, plus `POST /metrics/explore`. Key `pdl_live_apikey_…`, per-entity `*.read` permissions. Rate limit 240 requests per minute per IP; `429` returns `Retry-After` and blocks the IP for 60 seconds. **VERIFIED (docs)**
- **RevenueCat**: `GET https://api.revenuecat.com/v2/projects/{project_id}/metrics/overview` returns `mrr`, `revenue_last_28_days`, `active_subscriptions`, `active_trials`, `new_customers_last_28_days`. Needs a v2 secret key with read on overview metrics. **VERIFIED (docs)**

Where no aggregate exists, sum:

- **Stripe**: there is **no** aggregate revenue endpoint. For today, `GET https://api.stripe.com/v1/balance_transactions?created[gte]=<local midnight epoch>&limit=100` and sum `amount` or `net`. `limit` maxes at 100 and the response carries no total. Use `reporting_category` to separate payment from refund from fee, or `type=charge`, to avoid double-counting payouts. Credential: a **restricted key** (`rk_live_…`), created in the Dashboard with per-resource Read, Write or None; a read-only key cannot modify the account in any way. Minimum scopes for a revenue tile: read on Balance transaction sources and Charges, plus Invoices and Subscriptions if you want MRR. **VERIFIED (docs)**
- **Lemon Squeezy**: sum `/v1/orders`, or price out `/v1/subscriptions`. 300 calls per minute. **VERIFIED (docs)**
- **Gumroad**: `GET https://api.gumroad.com/v2/sales`, token from Settings, Advanced, Applications. Pagination is `next_page_key` and `page_key`; the old `page` parameter is deprecated. **VERIFIED (docs)**
- **Shopify**: custom-app Admin token (`shpat_…`) with `read_orders`, summing orders. Flagged **UNCONFIRMED** in this pass. It also carries real complications: orders include customer PII behind protected-customer-data gating, and `read_orders` only reaches 60 days back without an extra scope. Do not ship it on the strength of this document.

**Permission cost.** Zero macOS permission. Plain outbound HTTPS from a non-sandboxed app: no entitlement, no TCC, no server, no account. The cost is the credential, which is why G1 comes first.

**Explicitly no OAuth.** Raycast's `OAuthService` wraps PKCE, and for the many providers that do not support PKCE it routes through a hosted proxy at `oauth.raycast.com` with per-provider subdomains. That proxy is a server this app must not have. The only viable credential model here is a user-minted read-only token pasted into a secure field. Stripe's restricted keys make that genuinely pleasant. Some services are simply unreachable, and that is the correct trade.

**Biggest risk: Stripe's read allocation, not its rate limit.** Stripe enforces an average of 500 read API requests per transaction over a rolling 30 days, with a floor of **10,000 reads per month** regardless of volume. **VERIFIED (docs)** A 60-second poll is 43,200 reads per month and throttles a small account. Five minutes is 8,640, just under. **Ten to fifteen minutes is the correct default** (MRRDock ships 15). The tile is therefore never truly live and the product has to say so, in the panel, next to the figure.

**Second risk.** Paddle Classic is a separate older API with no metrics endpoints. "Supports Paddle" is two integrations, not a flag.

---

### 4.2 Agent budget

**Effort: S. Permission: none.**

**Tile.** A ring filled to the active limit's percent, the number in the middle, reset time beneath: "31% · resets Tue 20:00." Ring tints amber and red off the severity field. Greyed with a dot when the cached source is stale.

**Panel.** Every limit row as its own bar (session, weekly, weekly scoped with its model scope), each with its own reset countdown. Extra-usage credit state if enabled. Footer: "read from ~/.claude.json, updated N ago" plus a Reveal in Finder button, so the source is never a mystery.

**Why it matters.** This is the best permission-to-value ratio in the entire document, and it is the purest example of the §1 test. A budget you are burning against a clock that resets is *definitionally* a thing you want to see without asking. It needs no key, no account, no network, and no permission. `WidgetKind.aiUsage` already exists in the enum and has no panel, so the slot is reserved and empty.

**Where the data comes from. VERIFIED on a real machine.** `~/.claude.json` (mode 0600) carries a `cachedUsageUtilization` key whose shape is:

```
fetchedAtMs, accountUuid,
utilization: {
  five_hour:  { utilization: 11, resets_at: "…", limit_dollars, used_dollars, locked_reason },
  seven_day:  { utilization: 31, resets_at: "…" },
  seven_day_opus, seven_day_sonnet,
  extra_usage: { is_enabled, monthly_limit, used_credits },
  limits: [ { kind: "session", group, percent: 11, severity: "normal", resets_at, is_active },
            { kind: "weekly_all", group: "weekly", percent: 31, severity: "normal", is_active: true },
            { kind: "weekly_scoped", percent: 2, scope: { model: {…} } } ]
}
```

Percent plus `resets_at` plus `severity` is exactly a ring with a countdown. Read one key, parse, discard.

The Codex parallel is also **VERIFIED**: `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` carries `event_msg` records of type `token_count` whose payload includes `rate_limits.primary.used_percent`, `window_minutes` and `resets_at`.

**Permission cost.** None. These are dot-directories in `$HOME`, outside TCC's protected set (Desktop, Documents, Downloads, Movies, Music, Pictures, iCloud, Trash, removable volumes, other apps' Library data), so a plain read prompts for nothing. Nothing here lives under `~/Library`, which is where macOS 15 and later app-data protection bites. It survives an ad-hoc build entirely, because nothing is keyed to an identity.

It should still be **opt-in behind a consent sheet naming the exact path**, because it is the user's own working directory and the app should be seen asking.

**Biggest risk.** `cachedUsageUtilization` is an undocumented internal field and will be renamed or restructured without notice. It is also a *cache*: on the test machine `fetchedAtMs` was nine days old because the tool had not run. It is fresh precisely while you are working, which is when you care, but the tile must render the age and grey out when stale. Optional-chain everything; read only that one key; never log or copy the file.

**Adjacent, same source, more work.** A "tokens today" tile rolling up per-message usage from `~/.claude/projects/**/*.jsonl` is **VERIFIED** feasible and has the fields you would want (`timestamp`, `message.model`, `message.usage.{input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens}`, `cwd`, `gitBranch`). Two honest problems. The transcript directory measured **912 MB across 539 files**, so only mtime-filtered, byte-offset-incremental reads of these append-only files are acceptable; a full walk every 60 seconds is a battery offence in a resident agent. And there is **no cost field** in the transcripts, only tokens, so any dollar figure is arithmetic against a bundled price table that silently rots. Show tokens as truth and dollars as "est." with the table's date visible, or do not show dollars. Rated **M**, second wave.

---

### 4.3 Badge rail

**Effort: S to M. Permission: see below, and this is the interesting part.**

**Tile.** A row of up to five or six app icons carrying their live badge numbers, sorted by count, dimming to grey at zero. Optional single-total mode. A thin progress arc on any app mid-download or mid-export. Nothing but digits and glyphs, so it is safe on a shared screen by construction.

**Panel.** Every badging app with its count and last-changed time, newest first. Click a row to activate that app. A picker for which apps to watch, and a total at the top.

**Why it matters.** This is the honest answer to "can I peek at Slack," and it is better than the answer everyone reaches for first. One poll loop covers **Slack, Discord, Teams, Telegram, WhatsApp, Mail, Messages, Linear, Notion, everything**, uniformly, with no tokens, no OAuth, no admin approval, no terms-of-service exposure, and nothing leaving the machine. It is also genuinely glanceable, which is the shelf's actual job. It replaces four separate blocked or expensive integrations with one cheap widget.

**Where the data comes from. Two routes, and the evidence differs.**

Route A, the Accessibility walk of `com.apple.dock`. **VERIFIED live, twice, independently, on 26.5.2 with real values.** The Dock's single `AXList` had 27 tiles, each exposing `AXStatusLabel` (the badge text), `AXIsApplicationRunning`, `AXProgressValue`, `AXURL` and `AXTitle`. One probe printed `System Settings: badge=1` with every other tile blank. `AXProgressValue` is the find nobody wrote down: that is the Dock's download, export and copy progress bar, readable per app, and it is what makes the progress arc possible.

Route B, `lsappinfo`. The shipped LaunchServices CLI exposes a per-app `StatusLabel` key: `lsappinfo info -only StatusLabel <app>`. **Partially verified.** The key is present in `lsappinfo -all list` output on 26.5.2 and it ran with **no TCC prompt in a shell that was simultaneously denied `~/Library/Messages`**, which is the important half. But both researchers who tried it got `"StatusLabel"={ "label"=kCFNULL }` because no badge-bearing app happened to be running, so "the label reads 3 when Slack has 3 unreads" is **UNCONFIRMED**. Community reports say it returns NULL specifically for Messages and WhatsApp, with the AX tree as the documented fallback.

**Recommendation:** spend an hour proving Route B with a live badge, because zero permission beats one permission by a wide margin. If it holds, ship B with A as the opt-in fallback for the apps that report nothing. If it does not, ship A, which is verified.

**Permission cost.** Route B: none. Route A: Accessibility, subject to §2.1, and it should share one consent step with every other AX feature via G3.

**Biggest risk, and it must be in the UI copy.** A badge exists only where a **Dock tile** exists, pinned in Apple's Dock or currently running. An app that lives only in Docket's shelf and is not running has no tile and therefore no number, which means this widget looks broken for exactly the users who replaced Apple's Dock entirely. Say so in the panel. Secondary: `StatusLabel` is a **string**, not an integer ("99+", "•", localised words are all real values), so the model is `String` with an opportunistic `Int` parse. And `lsappinfo`'s text output is not an API contract, so the parser will break eventually; the fix is small and local, but it is a fix you will make.

**Say it plainly in the tile name.** Call it badges, not notifications, or it will be filed as broken by everyone whose Slack shows a dot for channel activity rather than a number.

---

### 4.4 Custom widget runtime

**Effort: L. Permission: none.** Full treatment in §6; here is the summary of why it is top tier.

**Tile.** Whichever of five fixed forms the manifest names: value plus label plus symbol, progress ring, sparkline, up to three rows, or plain text. Drawn through the app's own `WidgetSurface` and `WidgetStyle`, so a custom widget is indistinguishable from a built-in.

**Panel.** Manifest-described: a title, a rows block, a footer with last-updated. On failure: the error string, last-good values marked stale, Reveal in Finder.

**Why it matters.** This codebase is about 70% of a widget SDK already, by accident. `WidgetConfig` is an untyped JSON dictionary, so a manifest's defaults block *is* a `WidgetConfig`. `WidgetCatalog.Entry` is a plain data record, so a manifest is literally an `Entry` in JSON. And `Sources/MenuBar/WidgetSettings.swift` already derives a control from the *type* of each default value (bool to Toggle, number to Stepper, string to TextField), which means third-party widgets get a full settings pane for **zero** additional code. That last one is the highest-leverage accident in the repository.

The thing to build is a renderer and a loader, not a plugin architecture.

**Biggest risk.** `WidgetKind` is a closed `String`-backed enum switched exhaustively in at least five places (`WidgetTile.content`, `WidgetCatalog.naturalSize`, `openTarget`, `accentHex`, `WidgetDetail.exists`, `width`). Do not open it. Add exactly one case, `.custom`, and let the instance's config carry a `"plugin"` id. The one genuine refactor is that `WidgetCatalog.entry(_ kind:)` is keyed by kind, so every custom widget would collide on one `Entry` and share one size, name and set of defaults. It needs an instance-aware sibling, `entry(for instance:)`, plus about four call site updates. **Do that as its own diff, with tests, before anything else in this section.**

---

### 4.5 Mic live and mute

**Effort: M. Permission: none.**

**Tile.** Mic glyph. Grey when idle, solid red and gently pulsing while any process is capturing input, slashed grey when the device is muted. Under it, the listening app's name ("Zoom") or "Muted". Compact variant: glyph only, colour is the whole message.

**Panel.** Every process CoreAudio reports as capturing, with icon, name and how long it has been live. A mute toggle per input device plus mute-all. Default input picker. A "warn me when something starts listening" switch. And a distinct state for the most common confusion: device muted while an app is actively capturing.

**Why it matters.** "Am I muted" is the canonical example of a thing you are wrong about and cannot check without interrupting yourself. No API cost, no account, no network, perfect shelf fit, and it is the kind of feature people tell other people about.

**Where the data comes from. VERIFIED on 26.5.2 with a compiled probe:**

- `kAudioHardwarePropertyProcessObjectList` plus `kAudioProcessPropertyIsRunningInput`, `IsRunningOutput` and `BundleID` (the CoreAudio process objects added in macOS 14.2) returned real data: 33 process objects, with a browser's GPU process correctly flagged as running output during video playback. **No TCC prompt appeared.** Asking *who is capturing* queries `coreaudiod`'s public state; it is capturing the audio yourself that needs consent.
- `kAudioDevicePropertyMute` in **input** scope exists and is settable on both the built-in mic and a USB-C headset.
- Note the asymmetry the probe caught: the headset exposed mute but **not** `kAudioDevicePropertyVolumeScalar`, the built-in exposed both. So try mute first and fall back to volume 0; assume neither.
- `AudioObjectAddPropertyListenerBlock` for change notification.

Prior art: KeyMute, SimplyCoreAudio.

**Permission cost.** None. No entitlement, no prompt, no private framework, and it survives an ad-hoc build untouched.

**Biggest risk.** Device mute and in-app mute are different truths. Zoom, Meet and Teams keep their own flag, so a user who mutes in Docket and unmutes in Zoom is still silent and will blame the shelf. The mitigation is a visible third state ("device muted, Zoom is capturing") rather than pretending one switch owns the concept. Secondary: the property listeners fire in bursts, reportedly 9 or more per second and mostly no-change, so dedupe or the tile will thrash.

**Deliberately excluded: live input level metering.** Reading levels needs the microphone TCC grant, which would light the system's orange recording indicator permanently. An app whose job is to tell you when something is listening must not be the thing that is always listening.

---

### 4.6 Meeting countdown with a join link that works

**Effort: S to M. Permission: Calendar, already held.**

**Tile.** Event title truncated over a countdown. Neutral beyond 15 minutes, amber at 5, red and slightly larger at 1. A Join pill replaces the countdown from 2 minutes before until 10 minutes in. **Nothing at all when the next event is hours away**, because an empty tile beats a stale one.

**Panel.** Today's remaining agenda as rows: time, title, calendar, attendee count, Join, Copy link. Duplicate events across calendars deduped by title and time. On the current event, elapsed time, so you can see you are 20 minutes into a 30-minute call. Optional "mute my mic when I join," wired to 4.5.

**Why it matters.** This is table stakes in this category; Dato and MeetingBar have made "next event plus one-click join" an expectation, and a reviewer will dock the app for its absence. It also passes all three §1 tests cleanly. And the machinery exists: `CalendarDetail.swift` already talks to `EKEventStore`, `NSCalendarsFullAccessUsageDescription` is already declared, so there is no new prompt for anyone who has the calendar widget.

**Where the data comes from.** EventKit, plus conference-URL extraction by scanning `EKEvent.url`, `location` and `notes` against per-provider host patterns. There is no public conference-URL property; Calendar's own Join button is internal. This is exactly how the established apps do it. Useful EventKit surface that is not currently used: `EKParticipantStatus` to skip declined events, `EKEvent.availability` for free/busy, `EKSource` for per-account colouring, and `EKEventStoreChangedNotification` so this is push rather than poll. Also `requestWriteOnlyAccessToEvents` (macOS 14+) is a strictly lower consent tier and is the right ask for a quick-add tile.

**Biggest risk.** Link extraction on real invites is a pattern-matching arms race across dozens of services and corporate-rewritten safe links. One event can carry a Zoom link in the location, a dial-in in the notes and a Meet link appended by an add-on, and picking the wrong one sends the user to the wrong room while the meeting starts. Ship five providers that are reliable, rank sources (url, then location, then notes), **show which provider matched**, offer the alternatives in the panel, say "no link found" honestly for the rest, and let users add a pattern. Do not claim broad coverage.

---

### 4.7 Per-display shelves

**Effort: L. Permission: none.**

**Tile.** Not a tile. A property of the shelf.

**Panel.** In Settings, a row per display: name, enable toggle, edge picker, profile picker. Plus a remembered-display list so unplugging and replugging restores the arrangement. Mirror mode shows the same items everywhere; independent mode gives each display its own profile.

**Why it matters.** Across every Dock replacement in this category, the single recurring, universal grievance is that **macOS shows exactly one Dock, on one display**, and it jumps displays when the cursor grazes a bottom edge. uBar's own pitch leads with per-screen bars and a mirror mode. This is the most-requested thing in the whole category and it costs no permissions.

**Where the data comes from.** `NSScreen.screens`, `deviceDescription[NSScreenNumber]`, `didChangeScreenParametersNotification`. `DockPanelController.swift` already resolves exactly one `targetScreen` by display id; this promotes one controller into a keyed set.

**Biggest risk. Lifecycle, not drawing.** Sleep and wake, display disconnect, resolution change and Space transitions each need the panel set reconciled, and the failure mode is an orphaned always-on-top window on a display that no longer exists. It also multiplies every hover, auto-hide and magnification path by n. Multi-display bugs are where the free notch apps in this space spend their bug reports. Budget test time, not just build time.

---

### 4.8 Drop shelf

**Effort: L. Permission: none.**

**Tile.** A shallow well holding the last item's icon or thumbnail with a count chip. **While a drag is in flight anywhere on the system, the well lights and widens**, because the tile is a target before it is a display. Empty state is a dashed well, not a button.

**Panel.** Grid of staged items with thumbnail, name, size. Drag one out, or drag the set. Row actions: Quick Look on space, Reveal in Finder, Copy path, AirDrop (using the sharing service already planned), Remove. Footer: staged size on disk and "clear items older than N days."

**Why it matters.** This is the feature that makes the word "shelf" honest. Dropover and Yoink built a whole category on staging files between two windows, and the reason Dropover won mindshare is that shake-the-pointer-while-dragging summons the shelf at the cursor, needing no second hand. Docket holds files already but has no *transient* staging concept and no Quick Look. And it has a structural advantage over both: it is already on screen, so there is nothing to summon.

**Where the data comes from.** `NSDraggingDestination` on the shelf panel and on the auto-hide reveal strip. `NSFilePromiseReceiver` for promised drops (mail attachments, Photos, browser images) resolved into a staging directory beside `state.json`. Drag-out via file URLs on the pasteboard plus `NSFilePromiseProvider` when the destination wants a copy. `QLPreviewPanel` for preview. `Sources/.../DragOut.swift` already coordinates cross-window drags, so this is that channel inverted.

If shake-to-summon is wanted later, build it on `NSEvent.addGlobalMonitorForEvents(.mouseMoved)`, which needs no Accessibility, rather than an event tap, which costs Input Monitoring.

**Permission cost.** None, and this is the clearest case where being non-sandboxed pays for itself: a sandboxed shelf would need a user-selected staging location and would fight promised files.

**Biggest risk.** The drag lifecycle across a non-activating panel, not the file handling. Auto-hide is the hazard: if the shelf is hidden when the drag starts it must reveal on drag-hover without stealing activation and without dropping the drag session, and it must clean up when a drag dies mid-flight, because a promise that never resolves leaves a zero-byte stub. Second risk: stale references. A staged file the user moves or trashes leaves a tile pointing at nothing, and silently dropping it reads as data loss. Resolve via bookmark data and show a struck-through item rather than removing it.

---

## 5. The rest, grouped and ranked

Same honesty, less detail. Within each group, ordered by value over cost.

### 5.1 Zero-permission, small, ship early

| Feature | Effort | What it is | Risk |
|---|---|---|---|
| **Shortcuts tile** | S | Finish the `.shortcut` stub. `/usr/bin/shortcuts list` and `run <name>`, **VERIFIED** present on 26.5.2 with `run`/`list`/`view`/`sign`, exit 0, no TCC prompt. Guard with `Timeout.swift`. | A shortcut that blocks on input or never returns, hanging behind a tile. Hard timeout, and show a running shortcut as cancellable rather than frozen. |
| **Threshold colouring** | S | Amber and red on tiles that already produce numbers, with hysteresis so a value hovering at the line does not strobe. Deliberately not notifications: the shelf is already in peripheral vision, which is the whole argument for this surface. | Defaults that fire constantly. 80% memory *used* is normal on macOS and would leave every tile permanently amber. Memory *pressure* is the metric that means something. Per-metric defaults derived from the right signal. |
| **Focus-aware profiles and tile visibility** | M | `SetFocusFilterIntent`. `focusFilterID` is already on `DockProfile` and the spec already anticipates this. Extends from profile granularity down to per-widget "show in this Focus." Dockset ships Focus-driven layout switching as prior art. | **VERIFIED and CONFLICTING.** A probe built a `LSUIElement`, ad-hoc signed, non-notarized app in `~/Applications` and confirmed both an `AppIntent` and a `SetFocusFilterIntent` appear in Shortcuts' action library, so **discovery works for exactly this app shape with no entitlement and no TCC**. Delivery (that `perform()` actually fires) was **not** separately tested, and there are forum reports of the intent misbehaving on 26.5. Also filters fire on *activation* only; deactivation is a deliberate no-op, so tiles can stay hidden after a Focus ends. Needs a defined resting arrangement that any activation replaces, never an additive hide/show that can strand a tile. Requires `appintentsmetadataprocessor`, so anyone building outside Xcode loses this silently; add a build-script check. |
| **Package downloads** | S | **VERIFIED live, no auth, no account, no key:** `GET https://api.npmjs.org/downloads/point/last-day/react` returned `{"downloads":34324639,"start":"2026-09-24"}`; `…/downloads/range/last-7-days/<pkg>` gives the series; `GET https://pypistats.org/api/packages/requests/recent` returned `last_day`, `last_week`, `last_month`. Note `pypi.org/pypi/<pkg>/json` returns 200 and carries **no** download counts. | The lag reads as a bug: asked on the 26th, npm's `last-day` returned the 24th. Label the date or every user files "the number is wrong." Unversioned community endpoints, no SLA; poll every 15 to 30 minutes and cache last-good. |
| **Audio output switcher** | S | Which speaker or headset you are on, and switch. CoreAudio `kAudioHardwarePropertyDevices`, `DefaultOutputDevice`, `VolumeScalar`, with listeners. Device enumeration **VERIFIED** on 26.5.2. | It is a control, not a readout, so it fails the always-visible test *unless* the device name itself is the information, which it is for anyone who has talked into their laptop while wearing AirPods. |
| **Battery health** | S | **VERIFIED live** from IOKit `AppleSmartBattery`: `CycleCount 352`, `DesignCapacity 6249`, `AppleRawMaxCapacity 5962` (95% health), `Temperature 3066`, plus `DailyMinSoc`, `DailyMaxSoc`, `TimeAtHighSoc`. `BatteryMetrics.swift` already walks this registry for accessory levels. | Every key is undocumented and differs across Apple silicon, Intel and battery vendors. A missing key must render a dash, never a zero. Health barely moves month to month, so ship it as a Battery *variant*, not a tile of its own. |
| **Sun and moon** | S | **VERIFIED live, keyless:** `api.met.no/weatherapi/sunrise/3.0/sun` returned sunrise 06:11 and sunset 18:13 with azimuths; a matching `/moon` endpoint gives phase, rise and set. Same host, same attribution requirement `WeatherService` already satisfies. Or compute locally with no network. | No technical risk, which is also the problem. Sunset is something you learn once a season; it fails "you would be wrong if you did not look." Weather variant, not a competing tile. |
| **Crypto and FX** | S | **VERIFIED live, keyless:** `api.coinbase.com/v2/prices/BTC-USD/spot` returned `84095.725`; `api.frankfurter.dev/v1/latest?base=USD` returned `EUR 0.87696`, `INR 95.82`. Drops into `StockService`'s existing shape almost unchanged. | Terms of use, not technology. The existing Yahoo chart endpoint is already an undocumented dependency; this adds two more parties who can break or forbid it. And Frankfurter is ECB **daily reference rates**, not a live market rate. Labelling it live would be a lie users will catch. |
| **Air quality** | S | **VERIFIED live, keyless:** Open-Meteo air-quality returned `us_aqi 143`, `european_aqi 60`, `pm2_5 50.3`. Coordinates come from wherever `WeatherService` already gets them. | Free for non-commercial use per Open-Meteo's terms, which is worth reading against a donation-funded project before shipping. Product risk: for many users AQI never moves. It earns the surface in some cities and some seasons and not much elsewhere, so ship it as a weather variant so it costs nothing to ignore. |
| **Deeper system panel** | M | Memory *pressure* (from `host_statistics64`, not "used"), GPU utilisation from the IORegistry `PerformanceStatistics` dictionary on the accelerator node, per-core CPU, load average, uptime, and a top-five process table. All public, all root-free, all extensions to `SystemMetrics`. | Sampling cost. Walking every PID on a timer in an always-on agent that then shows up in "Using Significant Energy" destroys the product's credibility. **Sample the process table only while the panel is open, never for the tile.** |
| **Calendar-aware focus timer** | S | The focus timer refuses a 25-minute block that a 11:10 call will cut in half, and offers the 18 minutes you actually have. Existing `FocusTimer` plus one EventKit query. Auto-ends at the meeting instead of running through the call. | Only that it needs an accurate calendar. Filtering declined and tentative events covers most of it. |
| **Where the day went / time on** | M | Screen time measured by Docket itself. `NSWorkspace.didActivateApplicationNotification` plus `frontmostApplication` for intervals, and **VERIFIED** `CGEventSource.secondsSinceLastEventType(.hidSystemState, …)` returned 16.58 with no Input Monitoring and no prompt, to discount idle. Daily rollups in a small JSON beside `state.json`. One button to delete all history. | Two honest limits that must be stated in the panel rather than papered over. It only measures while Docket is running, so the first day is empty and history never backfills. And everything inside a browser collapses into "Safari," which is where most screen time actually goes. Sleep, lock and fast user switching each need explicit handling or a night's sleep shows up as eight hours of Finder. **This is strictly better than every alternative:** see §8 for why Screen Time and `knowledgeC.db` are dead. |
| **Break ring** | S | A stand-up nudge that knows whether you were actually at the keyboard (idle seconds, above) and shuts up while the mic is live, during a calendar event, or during a Focus. Sits on the existing FocusTimer and Hydration pattern. Notifications requested lazily on first fire. | Nagging. Every break reminder ever shipped gets muted in week two. The only defence is that it must never fire during a meeting or a screen share, and the idle rewind must be generous enough to feel observant rather than clueless. |

### 5.2 Developer and maker tiles, all riding on G1 and G2

| Feature | Effort | Notes | Risk |
|---|---|---|---|
| **Ship queue** | M | `GET https://api.github.com/search/issues?q=is:open+is:pr+review-requested:@me`, plus the `author:@me` variant. Fine-grained read-only PAT (Pull requests: Read, Actions: Read, Metadata: Read). **VERIFIED live:** unauthenticated is 60 per hour (`x-ratelimit-limit: 60` observed on `/rate_limit`), authenticated is 5,000 per hour, and Search has its own separate bucket. Also **VERIFIED** that `GET /repos/{owner}/{repo}` needs no token at all and returned `stargazers_count`, `open_issues_count`, `subscribers_count`, so a stars tile needs zero credential. | GitHub Search is eventually consistent and can lag, so the tile can show "1 review" for a PR you just approved. Needs optimistic local dismissal or it feels broken. A dev with 40 repos wants per-repo CI, which multiplies requests fast; cap the watched list explicitly. |
| **Deploy light** | S | The highest signal-per-pixel tile in this document: one dot, green / amber pulsing / red, with the branch or project beneath. `GET /repos/{o}/{r}/actions/runs?branch=<default>&per_page=5`, or `GET https://api.vercel.com/v6/deployments?limit=5&projectId=…`. Vercel's exact per-endpoint limit for v6 deployments is **UNCONFIRMED**; five-minute polling is plainly safe. | Definitional, not technical. "Is production green" means something different per repo (required checks, all checks, or the deploy itself), so the tile can confidently show green while the thing the user cares about is broken. |
| **Live visitors** | M | Fathom `GET https://api.usefathom.com/v1/current_visitors?site_id=…` is the cleanest realtime endpoint of any provider here and returns a total plus per-pathname, hostname and referrer breakdowns. Umami Cloud uses `x-umami-api-key` against `https://api.umami.is/v1`; `GET /api/websites/{id}/stats` is confirmed, the commonly-cited `/active` is **UNCONFIRMED**, so build on `/stats` and probe `/active`. Plausible v2 is `POST /api/v2/query`, 600 requests per hour, **and the Stats API is a Business-plan feature**. | Fragmentation. Three providers, three auth models, and Plausible gating the whole Stats API behind a plan tier means interested users cannot turn it on and will read that as a Docket bug. Self-hosted Umami adds a login-then-JWT-refresh lifecycle. Google Analytics is deliberately excluded: see §8. |
| **Provider credit** | S | **VERIFIED (docs):** OpenRouter `GET https://openrouter.ai/api/v1/credits` (ordinary API key as bearer) returns total purchased and used; `GET /api/v1/auth/key` returns that key's limit, usage and remaining. | The credential asymmetry, not the API. `/credits` needs a key that can also *spend*, so a read-only feature asks the user to store a live billable credential. Say that out loud in the setup sheet, and recommend a dedicated key with a low spend cap set on the provider's side. |
| **Error rate** | M | `GET https://sentry.io/api/0/projects/{org}/{project}/stats/?stat=received` with an org auth token scoped `project:read`, returning `[timestamp, count]` points. | Mostly the wrong surface. What a dev wants from an error tracker is to be *interrupted*, which is a notification. As a count it works; the moment anyone asks for the issue list it has outgrown 62pt. Sentry's own tracker documents these stats endpoints timing out on large projects, and there is still no cross-project usage endpoint, so a multi-project user needs N requests and gets N chances to hang. |
| **App Store sales** | L | `GET https://api.appstoreconnect.apple.com/v1/salesReports` with `Accept: application/a-gzip`, returning gzipped TSV. The JWT is ES256, `aud: appstoreconnect-v1`, short-lived, signed with the `.p8` PKCS#8 key. Signing is pure CryptoKit (`P256.Signing.PrivateKey(pemRepresentation:)`), so no server and no third-party JWT library. Apple's exact maximum token lifetime is **UNCONFIRMED**; 15 to 20 minutes is the commonly cited range. | The roughly two-day reporting lag makes it structurally wrong for a glanceable "today" tile. It can only ever be a "yesterday" tile, which undercuts the case for permanent screen space. Add gzip and TSV parsing and a per-request JWT mint and the effort is high for a number that does not move while you look at it. This is also the most sensitive credential in the document: insist on a Finance or Sales role key, never Admin. |
| **AI authorship percentage** | M | `~/.cursor/ai-tracking/ai-code-tracking.db`, schema **VERIFIED**. `ai_code_hashes(model, fileName, fileExtension, createdAt)` is populated (28,407 rows on the test machine). | **The one table with the numbers you want is empty in practice.** `scored_commits` has exactly the right columns (`tabLinesAdded`, `composerLinesAdded`, `humanLinesAdded`, `v2AiPercentage`) and 637 rows, and **every one of those columns was NULL** on the test machine. So the feature degrades to "count of edit events by model," which is not a percentage and not what the tile promises. Undocumented private schema of a third-party app on top of that. Open read-only; the owning app may hold a WAL lock. |

### 5.3 Communication, ordered by how much it costs to be honest

| Feature | Effort | Notes | Risk |
|---|---|---|---|
| **Slack DM peek** | L | **VERIFIED (docs):** `conversations.list` and `conversations.info` return `unread_count` and `unread_count_display`, and the docs are explicit that those fields are **included for DM conversations only**. User token (`xoxp-`), scopes `channels:read groups:read im:read mpim:read`. Tier 2 is 20+ per minute, so a 30-second poll is comfortable. Mentions via `search.messages` (user token only, `search:read`). The May 2025 rate-limit crackdown **does not bite**: it caps `conversations.history` and `conversations.replies` at 1 request per minute and 15 objects for commercially distributed non-Marketplace apps, and internal customer-built apps keep 50+ per minute. Setup is a paste, not an OAuth dance: the user creates an app from a shipped manifest in their own workspace and copies the User OAuth Token, which sidesteps the desktop-redirect problem entirely. | **Onboarding kills it before the API does.** Asking someone to create a Slack app, tick four scopes and copy a token loses most users, and in a workspace where the owner has turned on app approval they simply cannot. Second: **channel unread counts are not in the public API at all.** Only DMs expose `unread_count`. This can never be the Slack sidebar people picture, and building to that expectation guarantees disappointment. Third: `search.messages` is marked deprecated in favour of a real-time search method, so the mentions half will need migrating. |
| **Mail unread via Mail.app** | S | Apple Events: `unread count of mailbox`. Reuses exactly the mechanism Now Playing already uses to script players, and `NSAppleEventsUsageDescription` is already declared in `Resources/Info.plist`. Query `unread count` rather than counting message objects, or large mailboxes crawl. | Requires Mail.app to be **running**. **VERIFIED** that a poll against a quit Mail would launch it, and a shelf that boots a mail client to render a number is disqualified. So this is strictly "if Mail is open." Costs Automation TCC, subject to §2.1. |
| **IMAP inbox** | M | Direct IMAP: `STATUS (UNSEEN)` for counts, `IDLE` for near-real-time, `ENVELOPE` for panel headers. Credentials in the Keychain. **VERIFIED (docs):** Gmail app passwords still work for accounts with two-factor enabled; the March 2025 change removed plain-password auth, not app passwords or the protocol. iCloud, Fastmail and self-hosted all take app-specific passwords. Notably this is the way to reach Gmail without the restricted-scope wall in §8. | You are writing a small mail client: TLS, IDLE keepalives, reconnects, per-provider quirks, and an account-setup UI inside an accessory app that has no ordinary window. That last part is the same class of problem that already stops CoreLocation from prompting here, and it is the most likely reason this stalls. |
| **Notification shelf** | L | **CONFLICTING evidence, and this is the most interesting unresolved question in the document.** One probe **VERIFIED live on 26.5.2 with Accessibility only** that `com.apple.notificationcenterui` exposes notifications as an AX tree with **structured children carrying stable identifiers `title` and `body`**, a stable per-notification UUID on the group, and `AXCustomActions` of Show Details, Continue and Close, so a shelf could dismiss and act on a notification rather than merely read it. iPhone-relayed notifications are included and self-label "from iPhone." It also **VERIFIED** that `AXObserverCreate` on that pid succeeds and `AXObserverAddNotification(kAXWindowCreatedNotification)` returns 0, which is the architecture shipping tools use to catch banners as they arrive. A second researcher reports that post-Sequoia Notification Center is SwiftUI and the only thing available is `AXAttributedDescription`, a comma-joined summary that cannot be reliably split into sender and body. The live probe is the stronger evidence and the second finding may describe the desktop-widget path rather than the notification-list path, but **the conflict is not resolved and should be settled by a probe before any work starts.** | Three real risks even if the probe holds. First, the `"Notification Center"` AX window only exists while the panel is open, **VERIFIED**, so a catch-up history read means opening a visible panel, which is unacceptable on a timer. The architecture must be observer-driven banner capture with history kept in Docket's own JSON. The banner-capture path is verified by observer registration plus precedent, **not** by a live banner, because the test notification never drew one. Second, the hierarchy is undocumented and Apple can reshape it in any 26.x point release, at which point the feature goes quiet rather than breaking loudly. Mitigate with a self-check that flags "no notifications seen in N days" and a visible degraded state, plus shape assertions in one parser file. Third, §2.1: this is worthless the moment the grant lapses. |
| **Messages peek** | M | `~/Library/Messages/chat.db`, **VERIFIED** present on 26.5.2 and **VERIFIED** TCC-blocked (`sqlite3 -readonly` returned authorization denied from a shell without Full Disk Access). Schema is stable and documented: `message(ROWID, guid, text, attributedBody, handle_id, date, date_read, is_from_me, is_read)` joined through `chat_message_join` and `chat`. | **Proportionality is the objection, not feasibility.** Full Disk Access is the broadest grant macOS has, and the *count* is already free from the badge rail. Only the preview text needs FDA, so this widget's entire reason to exist is the panel. On top of that, since Ventura the plain `text` column is frequently NULL and the real content is an Apple typedstream (legacy NSArchiver) blob in `attributedBody`, which is not a plist, so `NSKeyedUnarchiver` and `plistlib` both fail and you need a hand-rolled typedstream decoder against an encoding Apple is free to change in a point release. Real names need Contacts TCC on top. Offer this only after somebody has used the badge version and explicitly asked for more. |

### 5.4 System and shelf behaviour

| Feature | Effort | Notes | Risk |
|---|---|---|---|
| **Window peek (titles)** | M | Hover an app on the shelf, see its open windows by name, click to raise. **VERIFIED on 26.5.2:** `AXUIElementCopyAttributeValue(kAXWindowsAttribute)` returned real titles from Terminal, VS Code, Safari, a Chromium browser and Finder, `err=0` on all. Then `kAXTitleAttribute` per window and `AXRaise` plus activation on click. `CGWindowListCopyWindowInfo` is also **VERIFIED alive** on 26.5.2, returning 29 windows with owner name, layer, bounds and window id; only `kCGWindowName` is gated behind Screen Recording, and it does not prompt, it just omits the key. | **Thumbnails are what people picture and thumbnails are dead** (see §8). This ships as a titles list and will be compared unfavourably to Apple's own previews. Electron and Java apps expose poor or duplicated titles. Wrap every AX call in `Timeout.swift`. |
| **Clipboard tip** | S to M | **VERIFIED working from an unprivileged process on 26.5.2:** `NSPasteboard.general` with `changeCount` polling read `changeCount: 7292` and live contents, no permission, and macOS has no iOS-style paste-consent prompt. Also **VERIFIED** that the live pasteboard carried `org.nspasteboard.TransientType`, so the community convention for marking transient and concealed items is genuinely in use and must be honoured so password-manager copies stay out. | Not a capability risk, a trust one, and it lands at "maybe" for two reasons rather than one. A clipboard history is the most sensitive thing this app would ever hold, in an app whose pitch is that it asks for nothing. And a strip of truncated text is close to illegible at 62pt while being a shoulder-surfing hazard in exactly the settings where a shelf is visible. If built: opt-in, off by default, small cap, memory-only unless asked, show item **types** rather than contents on the tile, and never persist across quit. Note that the polished paid notch app's top complaint being "no clipboard" is a hint that people expect this of any always-visible utility. |
| **Toggles tile** | M | Split sharply by cost. Free and public: Keep Awake via `IOPMAssertionCreateWithName`, Finder hidden files and desktop icons via the `com.apple.finder` domain plus a relaunch, screen saver via `open -a ScreenSaverEngine`. Costly: Dark Mode and most System Settings toggles have no public API and need Apple Events to System Events, which is an Automation prompt subject to §2.1. Not possible: there is **no public API to set a Focus mode**, only `SetFocusFilterIntent` to be told about one. | Scope creep into the Automation half, which is where the one-switch clones spend all their bug reports. Ship only the prompt-free toggles and route everything else through the Shortcuts tile, where the user's own shortcut owns the permission. |
| **Temperature and fans** | M | `IOHIDEventSystemClient` for per-die Apple silicon sensors (performance cores, efficiency cores, GPU, SoC, PMIC, ANE, battery, NAND), no root needed, reported working on macOS 26 by a shipping tool. Fans and Intel-era keys from AppleSMC. Being a private framework is precisely why apps using it ship as direct downloads rather than through the store, which matches this distribution exactly. | Sensor identity, not access. The maintainers of the leading open-source tool in this space state plainly that Apple changes sensor keys with every new SoC and that CPU and GPU sensors are thermal zones rather than cores. On an unrecognised machine the honest behaviour is to show **nothing** rather than mislabel a die temperature, and that must be built in, because somebody will run this on hardware that did not exist when the table was written. |
| **Latency** | M | Unprivileged ICMP datagram sockets (`SOCK_DGRAM`/`IPPROTO_ICMP`, the approach Apple's own sample uses on macOS) against a user-chosen host at about 1 Hz behind `PollGate`. **VERIFIED** `/usr/bin/networkQuality` exists (322KB) and can be spawned on demand for capacity, but it deliberately saturates the link, so it is never a poll. | Networks that drop ICMP show a permanently dead widget, so it needs a TCP-connect-time fallback and honest labelling of which method produced the number. The poll is itself traffic and must stop when the network is down and when the machine is on battery and idle. |
| **Overlap strip** | M | Teammate working-hour overlap, from `TimeZone` plus per-person start and end hours in config. Same shape as the existing World Clock's city and zone pair. Pure Foundation, no network, no Contacts. | Legibility. Twenty-four cells across a bottom shelf is about two points per cell, which is a texture rather than a chart. It probably collapses to a "next overlap in 40m" figure on the tile with the band living only in the panel, at which point honestly re-evaluate whether the tile earns its slot. |
| **Tunnel / VPN indicator** | M | `getifaddrs` for `utun*` plus `SCDynamicStore` for the primary service and default route. Explicitly **not** `scutil --nc list`: **VERIFIED** that on the test machine it listed only one configured PPP service and would miss every utun-based client. `NEVPNManager` is not an option, because NetworkExtension needs an entitlement an ad-hoc build cannot carry. | Heuristics all the way down. Inferring "a VPN is on" from a utun interface holding the default route both false-positives (local relays, iCloud Private Relay) and false-negatives (split tunnels). Label what it measured, not a verdict. And note what had to be cut: the Wi-Fi network name, because CoreWLAN redacts SSID and BSSID without both Location authorisation and a wifi-info entitlement. Design network widgets to never name the network. |
| **Commute** | M | `MKDirections.calculateETA`, whose `MKETAResponse.expectedTravelTime` Apple documents as accounting for expected traffic, with `departureDate` set to now. Addresses typed and geocoded with `CLGeocoder`, because CoreLocation will not prompt this app at all, which `LocationService.swift` already records. No Location prompt and no MapKit key. | MapKit request throttling per app, whose budget for a background poller is **UNCONFIRMED**, so a widget recalculating every five minutes all day may simply start failing. Poll only inside a user-set window, which `PollGate` already supports, and cache aggressively. Also a fixed pair of addresses is a static input for a widget whose whole value is dynamism. |
| **Recent files rail** | M | `NSMetadataQuery` over `kMDItemLastUsedDate`, `kMDItemUseCount`, `kMDItemFSContentChangeDate`, live-updating. | **VERIFIED that Spotlight is not a TCC bypass**, which is the finding that decides this. `mdfind -onlyin ~/Desktop` returned **0 results** from an unprivileged process, while `-onlyin ~` returned `~/Library` paths freely. Spotlight honestly enforces per-directory TCC, so covering Desktop, Documents and Downloads costs Files-and-Folders consent per folder (all three **VERIFIED** as `Operation not permitted`), and `~/Library/Application Support/com.apple.sharedfilelist`, the real Recent Documents store, is FDA-only. Without consent the tile shows an oddly empty or Library-heavy list, which reads as broken rather than restricted. Needs an explicit grant affordance and honest copy or the first impression is a bug report. |
| **Ambience (bundled loops)** | S | `AVAudioPlayer` over loops in the bundle, ducking via the same CoreAudio process-object check the mic tile uses. | Two unglamorous ones: bundled audio adds megabytes to a download that currently has none, and every sample needs a licence clean enough for an open-source repository. As a shelf citizen it is a control rather than a readout. |
| **Cache nudge** | M | Free space, and a panel that sizes the usual suspects on demand (caches, DerivedData, simulators, `node_modules`, container disk images, Trash, old downloads) with Reveal in Finder, and never deletes anything itself. Home directory only. | The tile adds nothing over the disk metric that already exists, so all the value is behind a click, which is the definition of a menu bar feature rather than a shelf feature. And a cleanup readout that miscounts, or that a user reads as safe-to-delete advice, costs trust fast. |
| **Mirrored widget text** | M | **VERIFIED live on 26.5.2:** widgets the user has already placed on the desktop or in Notification Center are AX-readable from `notificationcenterui`, with the provider in the identifier and the content in the accessibility description. A weather widget came back as `widget-local:com.apple.weather:…` with "Ghaziabad, Current Location, 22 Celsius, Drizzle, High of 27, Low of 22," and a calendar widget exposed `month-view-current-date` as "SATURDAY, 26 SEPTEMBER". | It only works for widgets the user has already placed somewhere else, and the text quality is entirely at the mercy of that widget's accessibility labelling. Apple's are excellent; third-party ones are frequently a bare image with nothing readable. **The same pattern was VERIFIED for menu bar extras:** Apple's Battery reports "41%, charging" and its Clock reports the full date string, while a third-party extra returned an empty title. So a "mirror anything" feature looks magical in a demo full of Apple items and silently does nothing for most real ones. Charming demo, thin product. |
| **Local IoT (Hue)** | M | The bridge's local HTTPS API after a physical button-press pairing, key in the Keychain. Genuinely local, which is unusual for smart home. | The permission itself. Since macOS 15 an app that touches the LAN without declaring `NSLocalNetworkUsageDescription` is denied **silently**: no prompt, no Privacy entry, connections dropped. And there are persistent reports of Local Network grants being ignored after a reboot on recent releases. A widget that works until the user reboots and then silently shows a dead lamp generates bug reports nobody can fix from this side. Hue-only narrows the audience sharply, and the general version is unreachable: see §8. |

---

## 6. Extensibility: user-created widgets

This is the strategic question in the brief and it deserves a real answer rather than a maybe.

### 6.1 The recommendation

**One declarative manifest for layout, with a data source that is either an HTTP fetch (no code execution) or a script (arbitrary code).**

That split is not a compromise, it is the whole design. An HTTP-only widget executes nothing, which makes it the only version of this feature that is **safe to share** and safe to install with a one-line confirmation. A script widget is arbitrary code and never is. Two trust tiers fall directly out of one format, at no extra cost.

Ship it in that order. The HTTP half is a complete, useful, code-execution-free custom widget feature, and it is also §4.1's engine, so it is being built anyway.

**Do not build WebView widgets.** Four reasons, three specific to this codebase:

1. Each `WKWebView` costs extra processes (WebContent plus Networking). On a shelf holding a dozen widgets that is unacceptable for an always-resident accessory agent.
2. **`.onHover` never fires in this non-activating panel.** That is documented at `TileGlyph.swift` and in `HoverCatcher`, and it is why the Music tile's artwork control is fixed rather than revealed. Every CSS `:hover` in a third-party HTML widget would silently do nothing, and authors would file bugs nobody can fix.
3. The app's entire value proposition is that it reads as macOS. Übersicht is the proof of what happens otherwise: hand people CSS and you get a desktop of mismatched web pages.
4. It defeats the settings generator, so HTML widgets would need their own preferences mechanism.

`WKWebView` does work in this app (its JS runs in Apple-signed helper processes, so hardened runtime is no obstacle). It is possible and still the wrong answer.

In-process JavaScriptCore was also tested and rejected. **VERIFIED:** contrary to widely repeated advice, a `JSContext` running a 3-million-iteration loop, ad-hoc signed with `-o runtime` and **no** `allow-jit` entitlement, returned the correct result on arm64 macOS 26.5.2. So it is available. Rejected anyway: it buys a scripting language without buying a layout system, so you would still need the declarative form for rendering, and then you own a JS API surface forever.

### 6.2 Why this codebase is already most of the way there

| Existing thing | What it gives the SDK |
|---|---|
| `Models.swift` `WidgetConfig`, an untyped `.bool`/`.number`/`.string`/`.list` dictionary | A manifest's `defaults` block **is** a `WidgetConfig`. No new storage type. Note there is **no `.dict` case**, so manifest defaults must be flat scalars and lists, which is a feature, see below. |
| `WidgetSettings.swift` derives a control from the **type** of each default (bool to Toggle, number to Stepper, string to TextField) | Third-party widgets get a full settings pane for **zero** extra code. The highest-leverage accident in the repository, and the reason flat defaults are the right constraint: flat scalars and lists are exactly what this generator can render. |
| `WidgetCatalog.Entry` (kind, name, category, defaults, variants, `supportsCompact`, `selfContained`) | The manifest schema, already designed. `selfContained: false` is already the flag for "needs permission or network." |
| `WidgetSurface`, `WidgetStyle.value/caption/label`, `Color(hex:)` (already fails closed to `.clear`), `rollingValue`, `TileGlyph` | A declaratively described tile is automatically indistinguishable from a built-in. This is the argument that kills WebViews. |
| `MetricProgressRing` (in `SystemActivityTile.swift`), `Sparkline` (in `NetworkActivityTile.swift`) | The ring and sparkline forms already exist as reusable views. |
| `Timeout.swift`, whose doc comment is already about a hung script wedging a poller forever | The exact hazard a script runner has, already solved and already documented. |
| `PollGate.shouldStart`, `StockService`'s track / keep-last-good / stale pattern | The service template, verbatim. |
| `WidgetWriter` | The funnel an interactive custom widget writes through. Already exists. |

### 6.3 The worked example

`~/Library/Application Support/com.namanparashar.plinth/Widgets/github-prs/widget.json`

```json
{
  "id": "dev.namanparashar.github-prs",
  "name": "Open PRs",
  "version": 1,
  "category": "System",
  "author": "naman",
  "about": "https://github.com/nparashar150/docket-widgets/tree/main/github-prs",

  "size":    { "width": 168, "height": 132 },
  "compact": { "width": 88 },
  "tint": "indigo",

  "secrets": [
    { "key": "GITHUB_TOKEN", "label": "GitHub token",
      "help": "Fine-grained token, read-only on pull requests" }
  ],

  "defaults": {
    "login": "nparashar150",
    "includeDrafts": false,
    "interval": 300
  },

  "capabilities": { "network": ["api.github.com"] },

  "source": {
    "http": {
      "url": "https://api.github.com/search/issues?q=is:pr+is:open+author:${login}",
      "headers": {
        "Authorization": "Bearer ${secret.GITHUB_TOKEN}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28"
      },
      "ttl": "${interval}"
    }
  },

  "tile": {
    "kind": "value",
    "value": "$.total_count",
    "label": "open PRs",
    "symbol": "arrow.triangle.pull",
    "zero": { "label": "all clear", "tint": "green" }
  },

  "panel": {
    "title": "Open pull requests",
    "rows": {
      "each": "$.items[*]",
      "limit": 8,
      "text": "$.title",
      "detail": "$.repository_url | basename",
      "badge": "$.number | prefix:#",
      "open": "$.html_url"
    }
  },

  "open": "https://github.com/pulls"
}
```

That manifest **executes nothing**. Every fact in it is **VERIFIED**: the endpoint returns `total_count` and `items[]` with `title`, `number`, `repository_url`, `html_url` and `draft` (queried live, unauthenticated, no extra search parameter required), and `arrow.triangle.pull` is a real SF Symbol (`NSImage(systemSymbolName:)` returned non-nil, as it did for `arrow.triangle.branch`, `chart.line.uptrend.xyaxis`, `curlybraces` and `puzzlepiece.extension`).

`defaults` are flat, so `WidgetSettings` renders a TextField for `login`, a Toggle for `includeDrafts` and a Stepper for `interval` with **no new code**. `${login}` interpolates from config; `${secret.GITHUB_TOKEN}` comes from the Keychain **at fetch time, inside the app process**, so for HTTP sources the secret never leaves Docket at all. That is strictly the best available answer to the secrets problem.

The script form changes only the source:

```json
  "source": { "command": "./prs.sh", "ttl": "${interval}" },
  "capabilities": { "network": ["api.github.com"] },
  "requires": []
```

```sh
#!/bin/sh
# Docket widget. stdout must be one JSON object. stderr shows up in the panel.
set -eu

curl -sS -m 10 \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/search/issues?q=is:pr+is:open+author:$login" \
| /usr/bin/jq -c '{
    value:  .total_count,
    label:  "open PRs",
    symbol: "arrow.triangle.pull",
    tint:   (if .total_count == 0 then "green" else "indigo" end),
    rows: [ .items[:8][] | {
      text:   .title,
      detail: (.repository_url | split("/") | last),
      badge:  ("#" + (.number|tostring)),
      open:   .html_url
    } ]
  }'
```

Run for real against the live API, that printed a correct object with `value`, `label`, `symbol`, `tint` and populated `rows`. **No `requires` entry is needed**, because **VERIFIED:** `/usr/bin/jq` ships with macOS 26.5.2 as a real 1.5MB universal binary (`jq-1.7.1-apple`), not a Command Line Tools stub, and `curl` is always present. So `curl | jq` covers "call a JSON API and reshape it" with zero installed dependencies. (`/usr/bin/python3` ran as 3.9.6 on the test machine only because CLT was installed; on a clean Mac it is a stub, which is what `requires:` exists for.)

### 6.4 The output schema, complete

Every field optional. Flat by design: each maps to a primitive that already exists.

| Key | Type | Renders as |
|---|---|---|
| `value` | number or string | the large figure, via `WidgetStyle.value()` plus `rollingValue` |
| `label` | string | caption |
| `symbol` | string | SF Symbol, validated with `NSImage(systemSymbolName:)`; invalid is dropped and noted in the panel |
| `tint` | string | a palette colour name or `#RRGGBB`, via the existing `Color(hex:)` |
| `progress` | 0 to 1 | `MetricProgressRing` |
| `series` | array of number | `Sparkline` |
| `rows` | array of `{text, detail, badge, symbol, tint, open}` | list tile and panel rows |
| `badge` | string | corner badge |
| `state` | `ok`, `warn`, `error` | tints the tile; warn and error show a dot rather than blanking the value |
| `error` | string | shown in the panel; the tile keeps last-good values and marks itself stale, exactly `StockService`'s semantics |
| `ttl` | number of seconds | overrides cadence for this cycle |
| `open` | string | URL or bundle id for the tile click, feeding `WidgetCatalog.openTarget`, which today returns nil for unknown kinds and leaves the card feeling broken |

Tile forms are **five, fixed**: `value`, `ring`, `spark`, `rows`, `text`. That vocabulary is derived from the twenty tiles that already exist (Clock is value, Time Progress is ring, Network is spark, Reminders is rows), not invented. There is deliberately **no nested layout tree**. That is the line between "a widget that matches the shelf" and a desktop of mismatched web pages.

Transform list, and it stays this short: `basename`, `round:N`, `percent`, `abbrev`, `currency:CODE`, `relative`, `prefix:S`, `suffix:S`.

JSON path support is capped at the `$.a.b[0].c` and `$.items[*]` subset. **Freeze that grammar.** The moment it grows filter expressions and arithmetic it becomes a programming language with no debugger, and the script source exists for anything harder.

Cadence goes in `defaults.interval`, **not** in the filename. SwiftBar's `name.1m.sh` is charming and wrong here, because the interval belongs somewhere the settings generator can expose it as a Stepper without the user renaming a file. Enforce a floor of 60 seconds for scripts, reuse `PollGate.shouldStart` and `withTimeout`, and **never relaunch a script that timed out**: `Timeout.swift`'s doc comment already explains why the thread is stranded.

Environment handed to a script, following the established precedent: `DOCKET=1`, `DOCKET_VERSION`, `DOCKET_PLUGIN_PATH`, `DOCKET_CACHE_PATH`, `DOCKET_DATA_PATH`, `DOCKET_APPEARANCE` (Light or Dark, because a custom tile cannot pick its own colours without it), `DOCKET_POSITION` (a 76pt column and a 168pt card want different text), `DOCKET_COMPACT`, plus every config key and declared secret.

### 6.5 Security, which is the real subject

**The OS provides no safety net whatsoever. VERIFIED.** A shell script was written, given a realistic `com.apple.quarantine` xattr, and run:

```
spctl -a -t exec -vv q.sh  →  rejected (source=no usable signature)
./q.sh                     →  ran-anyway
/bin/sh q.sh               →  ran-anyway
```

Gatekeeper assesses the script as rejected and executes it anyway. Notarization, quarantine and Gatekeeper gate **bundles**, not interpreted scripts. A widget script downloaded from a repository gets exactly zero OS-level checks. Any "we will rely on Gatekeeper" reasoning is void.

**Worse: a spawned script inherits Docket's TCC grants.** macOS attributes a TCC request to the *responsible process*, and responsibility is inherited by children through `fork` and `posix_spawn`. Docket holds `com.apple.security.automation.apple-events` plus Calendar, Reminders, Apple Events and Location usage descriptions. So a widget script gets Docket's Automation grant for free, and `osascript -e 'tell application "Mail" …'` would succeed, attributed to Docket. **A widget script is strictly more dangerous than the same script run by the user in Terminal.**

The mitigation exists and is private: `responsibility_spawnattrs_setdisclaim(posix_spawnattr_t *, int)`, originating in LLVM, reachable from Swift via `@_silgen_name`. Called with 1 before `posix_spawn`, the child becomes responsible for its own permissions, meaning it **loses** Docket's grants, which is exactly what you want. Undocumented, so it needs a degradation path.

**Scripts genuinely can be confined. VERIFIED locally.** `/usr/bin/sandbox-exec` is present and functional on macOS 26.5.2. An allow-default with targeted-deny profile behaved exactly as a widget sandbox should:

```scheme
(version 1)
(allow default)
(deny file-read* (subpath (param "HOMEDIR")))
(allow file-read* (subpath (param "PLUGIN")) (subpath (param "CACHE")))
(deny file-write*)
(allow file-write* (subpath (param "CACHE"))
                   (literal "/dev/null") (literal "/dev/stdout") (literal "/dev/stderr"))
```

Probe results under it: reading the widget's own directory allowed; reading `$HOME/.zshrc` **DENIED**; reading `~/Library/Messages/chat.db` **DENIED**; writing outside the cache **DENIED**; writing the cache allowed; network HTTP 200.

Two honest caveats. `sandbox-exec` has carried a deprecation warning for years but still ships and still works; treat it as defence in depth, never as the thing the model rests on. And **deny-default profiles are impractical to hand-roll**: a first attempt died with SIGABRT before `main`, and `(import "bsd.sb")` plus `(allow process-exec*)` still failed with `/bin/sh: fork: Operation not permitted`. Targeted-deny is what is achievable.

**The trust model, in five rules:**

1. **No install-by-URL, ever.** SwiftBar ships `swiftbar://addplugin?src=<url>`. Combined with the verified fact that a quarantined script runs with zero Gatekeeper check, that is a hyperlink one click from arbitrary code execution inheriting the app's TCC grants. Installation is a file the user places in the Widgets folder, or drags onto the widget library.
2. **Two tiers, from the format.** An `http` manifest executes nothing, so install it with a plain confirmation naming the hosts it will contact. A `command` manifest gets a review sheet showing the **actual script text, scrollable**, the interpreter, and the declared capabilities, with the accept button phrased as what it is: "Run this script every 5 minutes." Keeping the HTTP tier to a one-line confirmation is what keeps the heavy sheet rare enough that people read it.
3. **Capabilities are declared in the manifest and enforced by the generated profile.** `network: ["api.github.com"]`, `read: []`. Declare nothing, get nothing. The review sheet and the enforcement are the same data, so a widget cannot display one set of intentions and be granted another. This is the part xbar and SwiftBar do not have, and it is cheap here precisely because the profile is generated per plugin.
4. **Never a server-side registry.** Any index the app fetches makes "which widgets this user installed" observable. The gallery is a static page of manifests in the same repository as releases, rendered by CI, with the app's only involvement being a menu item that opens it and a folder that accepts a drop. The page must state plainly that listing is not endorsement and must show every script widget's source inline.
5. **A widget can be disabled without being deleted**, and a widget whose script exits non-zero three times running disables itself and says so in its panel. Otherwise a broken plugin is a permanent five-minute process spawn.

**Secrets: the app owns the Keychain item, the script never touches it.** For HTTP sources the secret never leaves the app process. For command sources it is injected as an environment variable at spawn, and **VERIFIED** that `ps -Eww -p <pid>` on 26.5.2 did not expose the environment of a process (it printed only the command line), because macOS restricts that to privileged callers and there is no `/proc`. So env is a reasonable channel. But be honest about the limit: without an app sandbox, nothing isolates a same-user process, and a malicious widget script does not need your secret channel, it can read `state.json` directly. **The threat model is "the widget is the attacker," and the answer to that is the seatbelt profile and the review sheet, not the secret channel.**

**And a developer mode is not a nicety, it is the third thing to build, before the script source.** Folder watch, hot reload, an inspector showing manifest parse errors with the offending key, evaluated JSON path expressions next to what they resolved to, raw stdout and stderr, exit code, duration, Run now. Without it authors debug by staring at a 58pt tile that renders nothing, and the most common outcome is that they give up. Show an in-development widget with a dashed outline so it is never mistaken for a finished one.

### 6.6 Build order for extensibility

1. `.custom` kind, instance-aware catalog lookup, and the generic renderer over the five tile forms, with manifests loaded from disk. **No data source yet.** A manifest with inline literal values is testable and proves the rendering half.
2. `http` source plus the mini JSON path evaluator plus Keychain secrets. Ship here. This is a complete, code-execution-free custom widget feature, and it is the same engine §4.1 needs.
3. Dev mode.
4. `command` source: `posix_spawn`, generated seatbelt profile, disclaim call, review sheet.
5. Shortcuts as a data source (see below), which arguably should jump ahead of 4.

**Shortcuts as a zero-code source deserves special mention.** Any shortcut that returns a number or text becomes a widget, and the user's own shortcut library supplies the integrations, so Docket writes no connectors at all. The security surface is Shortcuts', already audited by Apple, rather than a new one, and each shortcut prompts on its own behalf. Effort M. Risk: latency and prompts. A shortcut can take seconds and can throw its own permission dialogs at an accessory app with no window, which is exactly the failure mode CoreLocation already has here. Needs a hard timeout and a "shortcut needs attention" tile state rather than a hang. Whether a disclaimed child prompts differently is **UNCONFIRMED**.

`WidgetCatalog.swift` is already compiled into the test target and there are existing `WidgetConfigurationTests`, so manifest decoding, JSON path evaluation and the seatbelt profile generator are all unit-testable without a host app. The profile generator especially: given declared capabilities, assert the emitted profile denies `$HOME` and permits only the named hosts.

---

## 7. The privacy line

This app's current promise is one JSON file in Application Support, no account, no server, no analytics, no sync. Some features in this document read revenue figures and message text. That is a categorical escalation, from "knows your CPU load and your stock watchlist" to "has read your DMs." Here is the line that survives it.

### 7.1 The tile is a billboard. Treat it as one.

Not because it is likely to be seen, but because §2.2 proves it **will** be. The shelf is in every screenshot, every share and every recording, and no API can remove it or even detect that it is happening.

So the tile may show: a count, a level, a mention or no-mention dot, a source glyph, a relative timestamp, a colour. The tile may **never** show a sender name, a channel name, a subject line, or message text. Identifiers are content: `#acquisition-northstar` and "recruiter at a competitor" leak plenty without a single word of body text.

This is not a mitigation for a design choice. It is the design.

### 7.2 Content lives in the panel, and the panel is hostile to accidents

The mechanism already exists: panels anchor to their tile on click. Add to it:

- Auto-dismiss on a short idle timer.
- Dismiss on display-configuration change, so plugging into the conference-room projector closes it.
- Dismiss on app switch.
- Never restore an open content panel across launch.
- Never open on hover. A click is the consent gesture, and there is no sticky mode for a content panel.

### 7.3 Screen-safe mode, manual, with a hotkey

One switch collapses every communication and money tile to a neutral dot: no digits, no names, no text. A hotkey and a menu item, because the reliable version of "do not leak into my presentation" is the user flipping it in half a second.

**Do not build an automatic version.** There is no public API to detect screen capture, camera-in-use signals do not cover screen-only shares, and "is a conferencing app frontmost" is a guess that fails in the one moment it matters. Ship the manual switch; do not promise detection the platform cannot deliver. Effort S, and it should ship with the first communication or revenue widget rather than after.

### 7.4 Cache nothing you do not need, and never in the config file

`Sources/Core/Persistence.swift` writes one readable JSON file. Tokens go in the Keychain. Message text lives in memory only and is evicted on panel close. **No message body is ever written to disk.** An app that reads a message store and then makes its own copy of your messages has moved the blast radius, not reduced it.

### 7.5 Per-source opt-in, per-source revocation, visible off state

Each source is a separate widget the user adds, with its own toggle for counts-only versus counts-plus-previews, defaulting to **counts-only**. Turning a source off deletes its cached data and its Keychain item, not just its tile.

For local-file sources (agent usage, coding transcripts), the consent sheet names the **exact path** before the first read. The app has no obligation to prompt for a dot-directory in `$HOME`, and should do it anyway, because being seen to ask is the whole posture.

### 7.6 Earn the permission before asking

The Full Disk Access family (message previews, notification history via the SQLite route) should be reachable only **after** the user has used the zero-permission version and explicitly asked for more, with a sheet naming the file being read and why. Explain before asking, degrade gracefully if refused.

### 7.7 Redact one-time codes

Any surface that can render notification or message bodies pattern-matches and masks one-time codes before display. A six-digit login code rendered anywhere near an always-captured shelf is the worst possible thing for this app to be responsible for. The shipping notification-archive app in this space does exactly this, in memory, and it is worth copying outright.

### 7.8 Say what you do not do, and honour the corollary

In the README and in onboarding:

> Counts are read locally. Message text is fetched only while a panel is open and is never written to disk. Your tokens stay in your Keychain. Docket has no server and makes no network request except directly to the service you connected.

Then honour it: no crash reporter that could capture a panel screenshot, no telemetry, no anonymous usage counts, and no in-app widget store that would make a user's installed widgets observable.

Two things worth saying explicitly in the README as things the app **refuses** to do, because both are technically available and both are the wrong posture:

- It does not read another app's session credentials out of that app's local storage to impersonate a web session. That technique is indistinguishable from credential phishing.
- It does not scrape browser cookie stores.

### 7.9 A money tile has its own honesty requirement

Different failure, same principle. A revenue figure that is silently stale is worse than no figure. Every money and metric tile needs a visible staleness state from day one, a last-refreshed time in the panel, and a poll interval the panel states out loud, because §4.1's read allocation means it is never live.

---

## 8. Would be great, is not possible

This section exists so the same ideas are not re-proposed every six months. Each entry names the reason it dies, with the evidence.

### 8.1 Closed by Apple's own primary source

**Hosting third-party WidgetKit widgets.** Closed, not hard. `/System/Library/Frameworks/WidgetKit.framework/Versions/A/Resources/Info.plist` declares on the `com.apple.widgetkit-extension` point:

```
"EXRequiredEntitlements" => { "com.apple.private.chrono-extension-host" => true }
"NSExtensionPrincipalClassProhibited" => true
```

**VERIFIED** that only `NotificationCenter.app` and `ControlCenter.app` carry that entitlement (`codesign -d --entitlements -` shows it on both). **VERIFIED** that an ad-hoc binary claiming a restricted entitlement is killed by AMFI at launch, exit 137. And **VERIFIED** that there is no Objective-C surface to subvert: ChronoCore, ChronoServices, ChronoKit, WidgetRenderer and ChronoUIServices return zero classes from `objc_copyClassNamesForImage` because they are Swift. **Write this into SPEC.md as settled.** The nearest survivable thing is the widget-text scrape in §5.4, which is a text read of a widget rendered elsewhere, not hosting.

**Live Activities.** `ActivityKit.framework` **is** present in `/System/Library/Frameworks` and in the macOS 26.5 SDK, which is exactly the trap. Its `.swiftinterface` says `@available(macOS, unavailable)` and **VERIFIED** that `ActivityAuthorizationInfo()` is a hard compile error for `arm64-apple-macos26.0`. What macOS 26 has is **iPhone** Live Activities mirrored into the menu bar by ControlCenter over Continuity; **VERIFIED** live via `defaults read com.apple.controlcenter` showing `LiveActivityState = {CompanionPaired:true, SettingEnabled:true, Enabled:true}` and `RemoteLiveActivitiesEnabled = 1`. Those prefs tell you whether the feature is on, nothing about content. There is no third-party Live Activity on macOS to host, and per §1, Docket's own tiles plus G4 are the macOS-native answer.

**Screen Time / app usage from Apple's data.** Dead twice. **VERIFIED** that `DeviceActivityCenter()` is a compile error for `arm64-apple-macos26.0` ("unavailable in macOS"); `DeviceActivity.framework` and `FamilyControls.framework` both ship in the SDK with the types that matter marked `@available(macOS, unavailable)`. And the entitlement `com.apple.developer.family-controls` is application-and-approval-only from Apple and scoped to iOS and iPadOS. `~/Library/Application Support/Knowledge/knowledgeC.db` is **VERIFIED** present and **VERIFIED** `Operation not permitted` without FDA, with an undocumented schema and no compatibility promise. From macOS 13 much of this migrated to Biome, and `~/Library/Biome` exists on the test machine but `streams/public` does not, so the published write-ups do not match reality. **All three lose to counting `NSWorkspace.didActivateApplicationNotification` yourself** (§5.1), which costs nothing, cannot break on an OS update, and has a better privacy story. Ruled out because a zero-permission alternative is strictly better.

**HomeKit.** `com.apple.developer.homekit` must be allowlisted by a provisioning profile, and it cannot be provisioned for Developer ID; it works for development signing and the Mac App Store. On macOS it is Catalyst-only. **The cruel part is the failure mode:** it would work perfectly on the developer's own registered machine and return zero homes, silently, with no error, for every downloader. Route everything home-shaped through the user's own Shortcuts, which carries its own consent.

**HealthKit.** Not supported on macOS or tvOS; even under Mac Catalyst `HKHealthStore.isHealthDataAvailable()` returns false. Steps, rings, heart rate and sleep have no path that does not involve an iOS companion app plus a sync channel, which means an account or CloudKit, which means a server. Dead unless the product's privacy stance changes.

**Wi-Fi network name.** CoreWLAN redacts SSID and BSSID unless the app has Location authorisation **and** `com.apple.developer.networking.wifi-info`. `LocationService.swift` already records that CoreLocation will not prompt an accessory app with no ordinary window, and the entitlement needs a profile. **Design every network widget to never name the network.**

**Native plugin bundles vending SwiftUI views.** **VERIFIED dead three ways.** (a) Host with a real Apple Development identity plus hardened runtime, plugin ad-hoc: `dlopen` fails with "mapping process and mapped file (non-platform) have different Team IDs". (b) Same host plus `com.apple.security.cs.disable-library-validation`: loads fine. (c) **Ad-hoc host plus ad-hoc plugin, which is Docket's actual shipping configuration: fails identically.** So there is no unsigned loophole, and the only route is shipping the entitlement that lets any dylib on disk be injected into a process holding Automation, Calendar and Reminders grants. Swift ABI churn would break every plugin each release anyway.

**"Just add the entitlement," in general.** **VERIFIED** and buried: an ad-hoc binary claiming a private entitlement is SIGKILLed at launch, exit 137, no output, no diagnostic. Any plan routing through a private entitlement is finished before it starts.

### 8.2 Removed or gated APIs

**MediaRemote for universal Now Playing.** The comment in `MusicService.swift` is right, with one correction worth making in the code: **the callback receives `nil`, not an empty dictionary.** **VERIFIED three ways on 26.5.2** against `/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote`:

| caller | result |
|---|---|
| `swift mr.swift` (runs inside Apple-signed `swift-frontend`) | **12 real keys**: Title, Artist, Album, ArtworkData, PlaybackRate |
| the same code compiled and `codesign -s -` ad-hoc | callback fires with **nil** |
| ad-hoc plus faked `com.apple.mediaremote.*` entitlements | **SIGKILL, exit 137** |

`dlopen` succeeds and all four symbols resolve in every case, which is exactly why this keeps getting re-attempted. **The gate is caller identity, not symbol availability, and it is unchanged in macOS 26.** Keep scripting the players over Apple Events, keep the "never launch a player that is not running" rule, and keep `BrowserMedia` as the only route to browser audio.

**This finding also carries a methodology warning worth recording.** The first probe returned twelve real keys and nearly went into the research as "the gating was relaxed in 26." It was not: `swift file.swift` executes inside Apple's signed `swift-frontend`, which passes the platform check. **Any capability probe run through the swift interpreter, `osascript`, or a system-provided CLI inherits an identity a shipped app will not have, and must be re-run as a compiled, ad-hoc-signed binary before it means anything.**

**Window thumbnails.** `CGWindowListCreateImage` is not merely deprecated. **VERIFIED** it is a hard compile error against the 26.5 SDK, "unavailable in macOS: Please use ScreenCaptureKit instead," with `CGWindow.h:271` marking it obsoleted in macOS 15.0. The replacement, `SCScreenshotManager.captureImage`, is async and costs Screen Recording TCC, which since Sequoia and continuing on macOS 26 re-prompts with an "Allow For One Month" dialog and no permanent grant. **For an app that runs at login and never quits, that is a recurring system dialog forever.** Plus §2.1 breaks the grant on every ad-hoc update anyway, and macOS 26.1 reshaped how background processes appear in that pane. Titles via Accessibility survive (§5.4); pictures do not.

**Worth re-examining while you are here:** the same reasoning applies to the wallpaper-hold during a Dock restart, which the spec currently plans to take a Screen Recording hit for. That is one frame during a Dock restart, in exchange for the broadest-looking prompt in System Settings, on a grant that dies every release. Reconsider whether it is worth it.

**Space and workspace switching.** No public API exists for enumerating or switching Mission Control spaces. The routes are private CoreGraphics symbols or synthesised key events through Accessibility. Neither is defensible in an app that currently needs no private API anywhere.

**`com.apple.ncprefs.plist` for per-app notification settings.** **VERIFIED that it no longer exists** at `~/Library/Preferences/` on 26.5.2: `defaults read` reports the domain does not exist. Per-app notification settings appear to have moved into the TCC-protected group container. Every blog post and script pointing at that path is stale.

**Handoff and Continuity activity.** No public read API for other devices' activity. `~/Library/Group Containers/group.com.apple.coreservices.useractivityd` exists and is **VERIFIED** TCC-blocked, and is undocumented. `NSUserActivity` only publishes your own.

**Reading the current Focus directly.** `~/Library/DoNotDisturb/DB/Assertions.json` and `ModeConfigurations.json` are **VERIFIED** `Operation not permitted` without FDA. The supported direction is inverted and free: `SetFocusFilterIntent`, where the system tells the app. Note the asymmetry, because it decides the toggles tile: **there is no public API to *set* a Focus, only to be told one activated.**

### 8.3 Dead by policy, terms of service, or economics

**Discord.** Automating a user account outside the OAuth2 and bot API is forbidden and can terminate the account, and the Developer Policy states that applications may not request or attempt to obtain login credentials from Discord users, including login tokens. A bot token cannot see the user's DMs. The `messages.read` OAuth scope exists only for the local RPC surface and is approval-gated (exact current wording **UNCONFIRMED**; a fetch of the scope table redirected). **This is a policy blocker, not a technical one, and shipping it would ask users to risk their account.** The badge rail covers Discord for free.

**WhatsApp.** Every practical library (whatsapp-web.js, Baileys, WAHA, Evolution) reverse-engineers WhatsApp Web, violates the consumer terms, and gets numbers banned unpredictably; Baileys' own maintainers state they do not condone terms-violating use. The official Business API is for businesses messaging customers, not for reading your own chats. **The failure mode is the user permanently losing their phone number**, which is not a risk a free shelf widget gets to take on someone's behalf. Badge rail only, and note that WhatsApp is one of the apps reported to return NULL from `lsappinfo`, so it specifically needs the AX fallback.

**Microsoft Teams.** Record the good news first, because it is exactly the kind of stale fact that gets repeated for years: **as of 25 August 2025 the metered Teams Graph APIs are no longer metered** and no billing configuration is required; the `model` parameter is ignored. The old per-message charge is gone. The wall that remains is consent: delegated **`Chat.Read` requires admin consent**. A non-admin in a corporate tenant gets the "Need admin approval" screen, and an open-source shelf app is not getting tenant admin consent from a stranger's IT department. Graph also exposes no unread *count* for chats; you would reconstruct it by comparing `lastMessagePreview.createdDateTime` against `chat.viewpoint.lastMessageReadDateTime` (**UNCONFIRMED** end to end). Badge rail covers Teams.

**Telegram.** Not dead, but the wrong ratio, so recorded here. Telegram explicitly sanctions third-party clients: you register at my.telegram.org for `api_id` and `api_hash` and build on TDLib. TDLib genuinely gives per-chat unread counts. The cost is the point: phone-number login with an SMS and two-factor flow inside an accessory app with no ordinary window, a C++ library and its encrypted local message database bundled into Docket, and a full account session living on disk, for one tile. The badge rail gets the number for free.

**Gmail API.** `gmail.readonly` is a **restricted** scope: OAuth verification plus an annual third-party CASA security assessment, unverified apps capped near 100 users behind a warning screen, and first verification commonly running weeks and real money. The "each user creates their own Cloud project" dodge fails too, because Testing-mode refresh tokens expire in seven days and a consumer Google account cannot publish a restricted-scope app without verification. **Replaced by plain IMAP with an app password** (§5.3), which reaches the same data with no review board involved.

**Google Analytics 4 realtime.** `runRealtimeReport` exists, but auth is OAuth2 with a client secret or a service-account JSON. **Shipping a Google OAuth client secret in a public, ad-hoc-signed binary means publishing it**, and a service-account JSON on disk is worse. Fathom, Umami and Plausible give the same tile with one bearer token.

**Google Play revenue.** Not a JSON endpoint. Monthly and daily reports are CSV files deposited in a Cloud Storage bucket read with a GCP service account. A service-account key on disk plus a large client dependency, for one number with a multi-day lag.

**Ko-fi.** Genuinely blocked, architecturally. Ko-fi's own help documentation states the API is currently limited to when a payment is made, a one-way server-to-endpoint notification, and that it cannot even report that a membership ended. A local desktop app has no inbound HTTPS endpoint, there is no local-only version because the data never touches the user's machine, and the only workaround is a relay server. **Offer Buy Me a Coffee instead:** read-only GET-only REST at `developers.buymeacoffee.com` scoped to the creator's own supporters, memberships and extras, with a personal access token.

**Anthropic org spend via the Usage and Cost API.** The endpoints are real (`GET /v1/organizations/usage_report/messages`, `/v1/organizations/cost_report`, `anthropic-version: 2023-06-01`, `bucket_width` of `1m`/`1h`/`1d`, `group_by[]`, polling once per minute). The blocker is the credential: **the documentation states that the Admin API is unavailable for individual accounts.** Workspace keys are rejected. So a solo maker on a personal account cannot mint the key, and the tile would ship as something most people who want it cannot turn on. An org-wide Admin key, able to manage members and keys, is also the most dangerous credential in this document to hand a shelf widget for one number. **§4.2's local files cover the same need with no credential.** Keep it as an advanced field for the minority on a team plan, not as the feature.

**OpenAI usage.** `GET /v1/organization/usage/completions` and `/v1/organization/costs` require an **Admin API key**, and admin keys cannot call non-admin endpoints. Personal orgs do have an owner who could mint one, but whether every personal plan can is **UNCONFIRMED** (the platform page returned 403 during research). The legacy `/v1/usage` and `/dashboard/billing/*` endpoints are undocumented or retired; do not build on them.

**Slack channel unread counts.** The endpoint that would give whole-workspace unreads is `client.counts`, which returns `channels`, `mpims`, `ims` and `threads` groups each with `has_unreads` and `mention_count`. It appears only in the desktop client's own traffic, is undocumented, and typically wants a session token. **UNCONFIRMED and unsupported; do not build on it.** The public API gives DM unread counts and nothing more.

**Reading the local Slack app's session token.** Attractive because it is the only path to complete Slack data with no app, no install and no admin. Ruled out three ways: LevelDB has no concurrent-reader guarantee so Slack must be **fully quit** to read it, which is fatal for a live tile; the technique is indistinguishable from the token phishing Slack users are warned about, and would poison a privacy-positioned app's trust story; and it breaks whenever Slack changes storage. **Put a line in the README saying you deliberately do not do this.**

**Slack Socket Mode for real-time DMs.** Looked perfect for a desktop app: client-initiated WebSocket, no public HTTP endpoint, up to 10 connections. Dead for this purpose, because it runs on an **app-level** token, not a user token, and delivers only events the *bot* can see, which excludes the user's own DMs. Poll `conversations.list` at Tier 2; 30-second granularity is fine for a glanceable tile.

**Borrowing another app's token from the Keychain.** The `gh` CLI prefers the macOS Keychain, and a Keychain ACL grant is keyed to the requesting binary's code signature. For an ad-hoc signed app the signature is unstable across rebuilds, so the grant will not reliably persist and the user is re-prompted unpredictably. **Docket should hold its own credential in its own Keychain item, always.** Same conclusion for reading any other app's Keychain item.

**Mail unread counts without Mail.app running.** No acceptable route. Apple Events needs Automation TCC per target **and launches Mail if it is not running**, which was **VERIFIED** to be the case on the test machine, and a shelf that boots a mail client to render a number is disqualified. `~/Library/Mail` is **VERIFIED** FDA-gated and the `Envelope Index` SQLite under `V*/MailData` is undocumented. There is no unread-count API. The badge rail gives the same number for a permission already being paid for, and IMAP gives it with no macOS permission at all.

**Flight status and transit departures.** `api.adsb.lol/v2/callsign/UAL1` answered without a key and returned `total: 0` for a scheduled flight. ADS-B aggregators carry **live positions of airborne aircraft**, not schedules, gates or delays, so what is buildable keyless is a different product from what people mean by flight status, and it is blank exactly when they care most: before pushback, after landing, outside receiver coverage. Everything with schedules and delays needs a paid key and therefore an account. Transit is worse: no universal keyless feed, only per-city GTFS with per-city breakage.

### 8.4 Ruled out on cost or proportionality, not feasibility

These work. They are still the wrong call, and the reasoning should not be relitigated without new information.

**The usernoted SQLite database as the notification source.** Feasible. `~/Library/Group Containers/group.com.apple.usernoted/db2/db`, moved there in Sequoia specifically to put it behind TCC, **VERIFIED** present on 26.5.2 and **VERIFIED** `Operation not permitted` without FDA. A `record` table whose `data` column is a binary plist with `app`, `titl`, `subt`, `body`, plus `app_id` and `delivered_date` in Core Data epoch. Note the widely-quoted flat `SELECT … title, subtitle, body FROM record` is a tool's convenience view, not the real schema.

Ruled out on **two costs, not one**: Full Disk Access **and** `kTCCServiceSystemPolicyAppData`, the Sequoia group-container prompt ("X wants to access data from other apps"), which is scoped per process instance and is documented re-prompting on every launch for some apps. On a rolling cdhash that becomes an unbounded prompt loop. Add an undocumented schema with a plist payload, poll-only with no change notification, and the fact that the store **does not retain manually dismissed notifications**, so it is "what you have not swiped away," not history. The shipping archive app in this space ships per-major-version adapters (V14, V15, V26) with schema fingerprinting that **pauses capture** on an unknown format, which is an honest confession of the maintenance cost.

The AX route in §5.3 delivers the same notifications with structured fields, a stable UUID, dismiss and open actions, and one grant instead of two. Ruled out on cost, not on feasibility.

**Mirroring arbitrary third-party menu bar items.** **VERIFIED** that AX reads other apps' `AXExtrasMenuBar` fine, and that Apple's own items are richly labelled: Battery reported `"41%, charging"`, Clock reported `"Sat 26 Sep  9:24:52 PM"`, Wi-Fi reported `"Wi-Fi, connected, 2 bars"`. **VERIFIED** that a third-party extra returned an empty title. A "mirror any menu bar item" feature would look magical in a demo full of Apple items and silently do nothing for most real ones.

**Spotlight as a way around Files-and-Folders consent.** **VERIFIED** that it is not. `mdfind -onlyin ~/Desktop` returned 0 results from an unprivileged process while `-onlyin ~` returned `~/Library` paths freely. Spotlight honestly enforces per-directory TCC.

**Live microphone level metering.** Rejected on optics, not feasibility. It requires the microphone TCC grant, which would light the system's orange recording indicator permanently. An app whose job is to tell you when something is listening must not be the thing that is always listening.

**Install-by-URL for widgets.** Rejected on principle: see §6.5 rule 1.

**A curated store or server-side widget registry.** Rejected against the privacy rule. Any index the app fetches makes a user's installed widgets observable.

**Notch HUDs and Dynamic Island theatrics.** Genuinely loved by their users, and the wrong surface here: doing both makes this two apps. The transferable idea is the interaction, not the location, which is **transient expansion on a trigger**, and a shelf can do that on its own edge (G4). Worth noting what the complaints in that space teach, though: the top gripe about the polished paid one is no clipboard and no focus timer, and the top gripe about the free one is multi-display bugs. Docket has the focus timer, §5.4 has the clipboard question, and §4.7 has multi-display, where the budget should go into testing.

**Menu-bar-shaped ideas, deliberately not proposed.** Menu bar item hiding, HUD replacement, unit converters, scratch calculators, uptime readouts, QR generators, colour pickers, sound boards, and anything whose natural form is a searchable list. The test applied throughout: **does it earn its pixels while nobody is clicking?** A badge count, a threshold, a meeting countdown and a revenue figure do. A searchable history, a launcher and a settings grid do not; those want a hotkey. The QR idea survives only reshaped: not a widget, but an action on the drop shelf, where dropping a URL generates the code on demand.

### 8.5 Two things to write into SPEC.md as settled

So they are never re-proposed:

1. WidgetKit hosting is closed by a private entitlement declared in Apple's own framework plist, held only by `NotificationCenter.app` and `ControlCenter.app`, and a restricted entitlement on an ad-hoc binary is SIGKILLed.
2. `CGWindowListCreateImage` is obsoleted, not deprecated: it is a compile error against the 26.5 SDK. Anything needing a window or screen image needs ScreenCaptureKit and a monthly-re-prompting Screen Recording grant.

Both should also amend the existing spec items they contradict: the note that `AXStatusLabel` is "private-ish" (it is an ordinary AX attribute the Dock genuinely publishes and it survived into 26, and `AXProgressValue` is right next to it), and the wallpaper-hold item's assumption that `CGWindowListCreateImage` is merely deprecated.

---

## 9. Sequencing

Ordered by dependency and by value delivered per week of work. Every phase ends with something shippable.

### Phase 0. The prerequisite, and it is boring

| Item | Effort | Why now |
|---|---|---|
| **G5** Stable release signing (Developer ID plus notarization) | S | §2.1. Converts roughly eight features from support burden to shippable. Nothing else has this leverage, and every phase after this one is cheaper because of it. |
| Probe: does a Keychain ACL survive an ad-hoc rebuild without re-prompting? | S | Decides whether G1 is pleasant or hostile. One afternoon. Do it before writing the store. |
| Probe: does `lsappinfo` return a populated `StatusLabel` for a live badge? | S | Decides whether the badge rail costs zero permissions or one. One afternoon, one app with a real badge. |
| Probe: settle the Notification Center AX conflict in §5.3 | S | Two independent checks disagree. Resolve before scheduling any notification work. |

Four small tasks. Together they de-risk most of the roadmap.

### Phase 1. Groundwork plus the cheapest wins

| Item | Effort | Depends on |
|---|---|---|
| **G1** Keychain credential store | S | Phase 0 probe |
| **G2** Generic HTTP polling service | M | G1 |
| **4.2** Agent budget | S | nothing |
| **4.3** Badge rail | S to M | G3 if the AX route wins |
| **G3** Accessibility bridge | M | only if 4.3 needs AX |
| **5.1** Shortcuts tile (finishes the `.shortcut` stub) | S | nothing |
| **7.3** Screen-safe mode | S | ship it alongside the first count or money tile |

By the end of Phase 1 there is a credential store, a fetch engine, and three widgets that need no permission at all, one of which (4.2) nothing else in this category does.

### Phase 2. The connected widgets, and the custom runtime, which are the same engine

| Item | Effort | Depends on |
|---|---|---|
| Instance-aware catalog lookup (`entry(for:)`) as its own diff, with tests | S | nothing, and **do it before 4.4** |
| **4.4** Custom widget runtime, step 1: `.custom` kind plus the five-form renderer, manifests with literal values | L | the refactor above |
| **4.1** Connected widgets: Stripe, Polar, Paddle Billing, RevenueCat, plus the recipe editor | L | G1, G2 |
| **4.4** step 2: `http` source plus mini JSON path plus secrets | M | G1, G2, 4.4 step 1 |
| **5.1** Threshold colouring | S | **G4** |
| **G4** Escalation channel | M | nothing |

Ship point. At the end of Phase 2 the five drawn-and-unwired widgets work, custom widgets exist in a code-execution-free form, and the shelf can raise its voice. This is the phase that changes what the app is.

### Phase 3. The shelf becomes a shelf

| Item | Effort | Depends on |
|---|---|---|
| **4.5** Mic live and mute | M | G4 for the pulse |
| **4.6** Meeting countdown with join link | S to M | G4 |
| **4.8** Drop shelf | L | nothing |
| **5.1** Focus-aware profiles and tile visibility | M | Phase 0 conclusion on `SetFocusFilterIntent` |
| **5.1** Where the day went | M | nothing |
| **5.2** Ship queue and deploy light | M plus S | G1, G2 |
| **4.4** step 3: dev mode (folder watch, hot reload, inspector) | S | 4.4 step 2. **Before the script source, not after.** |

### Phase 4. The expensive and the risky

| Item | Effort | Depends on |
|---|---|---|
| **4.7** Per-display shelves | L | nothing, but budget test time, not build time |
| **4.4** step 4: `command` source, seatbelt profile, disclaim call, review sheet | L | dev mode |
| **4.4** step 5: Shortcuts as a data source | M | 4.4 step 2, and arguably jumps ahead of step 4 |
| **5.1** Deeper system panel, break ring, calendar-aware focus timer | M, S, S | G4 |
| **5.3** Slack DM peek | L | G1, G2, 7.3 |
| **5.3** Mail: Mail.app path then IMAP | S then M | G1 for IMAP |
| **5.4** Window peek (titles) | M | G3 |

### Phase 5. Only with a stable identity, and only if asked for

| Item | Why last |
|---|---|
| **5.3** Notification shelf | Highest value of anything in this group, and the most structurally fragile. Needs Phase 0's conflict resolved, needs G5 shipped, and needs the self-check that flags a silent failure. |
| **5.3** Messages peek | Full Disk Access for a preview whose count is already free. Offer only after somebody has used the badge version and asked for more. |
| **5.4** Clipboard tip | Feasible, cheap, and in tension with the app's own privacy story. Opt-in, off by default, types not contents on the tile. |
| **5.4** Temperature and fans | Private framework with a sensor table that rots with every new SoC. Must show nothing rather than mislabel. |
| **5.2** App Store sales | The most sensitive credential here, for a "yesterday" number that cannot be a "today" tile. |

### What shares what

Three sets of features share groundwork, which is the point of Tier 0:

- **G1 plus G2** are shared by every connected widget (revenue, provider credit, ship queue, deploy light, live visitors, error rate, package downloads, Slack, IMAP) **and** by the custom widget runtime's HTTP source. That is one piece of work serving roughly a dozen features. Build it once and build it like `StockService`.
- **G3** is shared by the badge rail, window peek, the notification shelf and the widget-text scrape. One consent, one reconnect loop, one place that degrades to nothing.
- **G4** is shared by the meeting countdown, the mic tile, threshold colouring, the break ring, alarms, countdowns, and any recipe that reports a warn state. It is also the thing that makes §1's claim about competing with Live Activities actually true.

And one dependency that is easy to miss: the instance-aware catalog lookup is a small mechanical diff that makes the entire extensibility story possible, and doing it late means doing it twice.

---

## 10. Open questions worth an afternoon each

Listed because they change decisions, not because they are interesting.

1. **Does a Keychain ACL survive an ad-hoc rebuild without re-prompting?** Decides whether G1 is the credential store or whether a `0600` file (clearly labelled as weaker) is the honest fallback.
2. **Does `lsappinfo` return a populated `StatusLabel` for a live badge?** Decides whether the badge rail costs zero permissions or one.
3. **Which Notification Center AX story is correct on 26.5.2?** One probe found structured `title` and `body` identifiers plus a stable UUID and custom actions; another reports only a comma-joined `AXAttributedDescription`. The live probe is stronger evidence, and the conflict should be settled before any work is scheduled.
4. **Does `SetFocusFilterIntent.perform()` actually fire on activation for this app shape?** Discovery is **VERIFIED** for an ad-hoc, non-notarized, window-less accessory app. Delivery is not, and there are reports of it broken on 26.5.
5. **Does a disclaimed child process prompt differently for Shortcuts-driven permissions?** Affects whether Shortcuts-as-a-data-source can jump ahead of the script source.
6. **Does FSEvents actually deliver events for TCC-protected directories?** **VERIFIED** that stream creation succeeds for a blocked `~/Downloads`; delivery is **UNCONFIRMED**. Treat it as needing the same consent as reading until proven otherwise.
7. **What is MapKit's request budget for a background poller?** Decides whether the commute tile is viable at all.
8. **Is one frame of held wallpaper during a Dock restart worth a Screen Recording prompt?** Given §2.1 and the monthly re-prompt, probably not. Worth a decision rather than an inherited assumption.
