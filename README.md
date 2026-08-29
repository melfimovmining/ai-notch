# AI Notch

*(The Xcode project, source folder and bundle id keep the original `SideNotch`
name; only the product is called AI Notch.)*

A macOS HUD with no Dock icon and no menu bar item. It sits out of the way as a
small tab on the right edge of the screen; click the tab and it expands into a
black "notch" bar showing three usage rings — four, once you connect an API
key for spend. Hovering a ring slides out a card
to its left with the details. It collapses again on its own once the pointer
leaves the bar (or immediately, if you click the bar).

Out of the box it shows **your real Claude usage** — the same 5-hour and 7-day
limit numbers Claude Code shows in `/usage` — fed by a status line script. Add
an Admin API key and a fourth ring counts down your remaining **API credit**;
see [Connecting API spend](#connecting-api-spend).

## Install it

```sh
./install.sh
```

That builds the app, copies **AI Notch.app** to `/Applications` (or `~/Applications` if the
first is not writable), registers it to **open at login**, and launches it.

```sh
./install.sh --no-login   # install without the login item
./install.sh --uninstall  # remove the login item and the installed copy
```

Launch at login uses `SMAppService.mainApp` — the modern API — so the entry
appears in **System Settings › General › Login Items**, where you can turn it
off like any other app. You can also toggle it from SideNotch itself:
right-click the tab and use **Open at Login** (the checkmark reflects the real
system state, so it stays honest if you change it in System Settings).

The registration records the app's *current path*, so install first and register
second — which is the order `install.sh` uses. Move the app afterwards and the
login item goes stale; re-run `./install.sh` to fix it. Registering a copy that
lives outside `/Applications` (e.g. straight out of `build/`) reports
`not found`, which is why the installer copies first.

Under the hood the installer calls the app with its own flags, handled before
any UI is created:

```sh
/Applications/AI Notch.app/Contents/MacOS/SideNotch --login-status
/Applications/AI Notch.app/Contents/MacOS/SideNotch --register-login
/Applications/AI Notch.app/Contents/MacOS/SideNotch --unregister-login
```

## Running it during development

**Xcode:** open `SideNotch.xcodeproj`, pick the `SideNotch` scheme, press ⌘R.

**No Xcode (command line only):**

```sh
./build.sh
open 'build/AI Notch.app'
```

The app has no Dock icon and no menu bar (`LSUIElement`), so **to quit it,
right-click the tab (or the expanded bar) and choose "Quit AI Notch"** — or
`pkill -x "AI Notch"`.

## Collapsed and expanded

SideNotch starts collapsed: a 12pt tab on the right edge, level with the middle
of where the bar will appear, widening slightly on hover so it is easy to grab.

- **Click the tab** to expand into the full bar; **click the bar** to collapse.
- **It auto-collapses** 0.6s after the pointer leaves the bar. Moving back within
  that window cancels the countdown, and a 6pt margin around the bar keeps it
  open when you clip its edge. An open right-click menu suspends the countdown.
- The state is remembered across launches (`UserDefaults`, key `isExpanded`);
  the very first launch is collapsed.
- The tab and the bar share a vertical centre, so the one grows out of the other
  rather than jumping.
- Only the visible part claims mouse events. Collapsed, that is a 18×72pt strip
  at the screen edge; everything else in the panel stays click-through, so the
  windows underneath keep receiving clicks. `Layout.interactiveFrameInPanel(expanded:)`
  is the single source of truth for that region, and `PanelState.onChange` keeps
  `PassthroughView.interactiveRect` in step.
- Because the app never activates, `acceptsFirstMouse` is overridden on both the
  container and the SwiftUI hosting view — otherwise the first click would only
  focus the panel instead of hitting the tab.
- Auto-collapse polls `NSEvent.mouseLocation` every 0.15s while expanded rather
  than trusting `onHover`: an inactive app is not guaranteed a mouse-exited event
  once the pointer moves over another app's window. `HoverWatchdog` holds the
  timing rules with no AppKit in sight, so they are testable directly; the
  controller only supplies "is the pointer on the bar".

Tuning knobs: `HoverWatchdog(grace:)` for the delay, `pointerMargin` and
`pollInterval` in `NotchPanelController`.

## Connecting real Claude usage

Claude Code hands its [status line](https://code.claude.com/docs/en/statusline)
command a JSON blob on stdin that already contains everything the rings need:

```json
"rate_limits": {
  "five_hour": { "used_percentage": 73.0, "resets_at": 1738425600 },
  "seven_day": { "used_percentage": 7.0,  "resets_at": 1738857600 }
},
"context_window": { "total_input_tokens": 155000, "context_window_size": 1000000, "used_percentage": 15.6 },
"cost": { "total_cost_usd": 0.4213 }
```

`scripts/statusline-sidenotch.sh` acts as your status line, stashes that blob in
`~/.sidenotch/sessions/<session_id>.json`, and prints an ordinary status line so
the terminal keeps working. SideNotch watches that directory and redraws.

**Install:**

```sh
chmod +x ~/SideNotch/scripts/statusline-sidenotch.sh
```

then add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/SideNotch/scripts/statusline-sidenotch.sh",
    "refreshInterval": 60000
  }
}
```

Claude Code re-runs the script on every assistant message, when a rate-limit
window resets, and on the `refreshInterval` timer — so the rings stay current
without SideNotch making a single network call. Until a session reports in, the
app shows placeholder numbers.

What the three rings map to:

| Ring | Source | Card |
| --- | --- | --- |
| Orange | `rate_limits.five_hour` | Current session + all models |
| Green | `rate_limits.seven_day` | All models + current session |
| Yellow | `context_window` | Context used + current session, titled with model and session cost |

Caveats worth knowing:

- `rate_limits` is only sent for **Claude.ai Pro/Max accounts**, and only after
  the session's first API response. Each window also disappears once it resets.
  Missing windows render as "Waiting for data" rather than a wrong number.
- Percentages cover your whole account, so every session agrees on them. The
  context and cost figures are per session — SideNotch shows the session that
  reported most recently.
- The script writes atomically (`mktemp` + `mv`) so the app never reads half a
  file, and prunes session files older than a day.

### Other sources you could wire in

`UsageMonitor` is the only thing that knows where numbers come from, so swapping
or adding a source is a contained change:

- **Anthropic API rate limits (API keys, not subscriptions):** every Messages
  API response carries `anthropic-ratelimit-{requests,input-tokens,output-tokens}-{limit,remaining,reset}`
  headers — `*-limit`/`*-remaining` are counts, `*-reset` is an RFC 3339
  timestamp. Exact and cheap to read, but they describe your *organization's*
  API rate limits, not a Claude subscription.
- **Org spend:** built — see [Connecting API spend](#connecting-api-spend)
  below.
- **Local token history:** `~/.claude/projects/**/*.jsonl` records `usage` (input,
  output, and cache tokens) per assistant message with a timestamp. Enough to
  compute your own rolling windows offline; it has no server-side limit
  percentages, so any "% used" derived from it is your own estimate.

There is no public API for the Claude.ai subscription usage numbers themselves —
the status line is the supported way to get them onto your desktop.

## Connecting API spend

The fourth ring counts down your remaining **API credit**. It is separate from
the three rings above in every way that matters: those read local files and work
offline, this one talks to the network and needs a credential you supply. If the
key is missing or rejected the ring is simply absent or shows an error — the
other three carry on.

**The ring only appears once a key is set.** Right-click the tab →
**Set Admin API Key…**, then **Set Credit Balance…**.

| Ring | Remaining credit, draining from full to empty |
| --- | --- |
| Card, row 1 | `$8.86 left · 25%` against "of $35.10 recorded" |
| Card, row 2 | Spend since the balance was recorded, tokens, and your priciest model |

The ring is green above 25% remaining, yellow below it, orange below 10%.

### What has to be typed in, and why

**Anthropic publishes no endpoint for the credit balance, and none for top-ups.**
Not in the Admin API reference — which covers organizations, invites, users, RBAC,
workspaces, rate limits, API keys and CMEK, and nothing billing-related — and not
anywhere else. The Console shows the balance because it renders the figure
server-side behind your session cookie; there is no REST route an API key can
call. `cost_report` returns only usage costs (`tokens`, `web_search`,
`code_execution`, `session_usage`); credit purchases never appear in it.

So the balance is an **anchor you enter once**, and the app subtracts spend from
it every minute:

```
remaining = the balance you recorded − API spend since you recorded it
```

That is fully automatic until you **buy credits**, which the app cannot see. When
spend passes the recorded balance the ring goes orange and reads
**"Out of credit — bought more? Right-click → Set Credit Balance"**, rather than
drifting silently or showing a negative number. Re-enter the figure from the
Console and it resumes.

If you would rather not maintain it at all, leave the balance unset: the ring
falls back to showing plain month-to-date spend.

### The credential

This is the part that most often goes wrong. The two endpoints are part of the
**Admin API**, and they do not accept an ordinary API key:

- An **Admin API key** (`sk-ant-admin01-…`), created in the Console under
  Organization settings → API keys, **or**
- an `org:admin` **OAuth token**, **or**
- a **personal key that is not scoped to a workspace**.

A workspace-scoped key is rejected with 401 even though it sends messages
perfectly well, and the Admin API is unavailable to accounts with no
organization, where the routes 404. AI Notch calls the API when you save a key
and tells you which of those happened, rather than leaving you with a silent
"Unavailable" on the ring.

The key is stored in the **Keychain**, not `UserDefaults`. This matters: an Admin
API key is not read-only. The same credential can list and deactivate your
organization's API keys, change member roles, and remove members. A plist in
`~/Library/Preferences` is readable by anything running as you.

### Endpoints and cadence

```
GET /v1/organizations/cost_report?starting_at=…&bucket_width=1d&group_by[]=description
GET /v1/organizations/usage_report/messages?starting_at=…&bucket_width=1d
```

Both are raw HTTP — deliberately absent from every Anthropic SDK, and there is
no Swift SDK regardless — so `AdminAPI.swift` speaks REST with `URLSession`.
Polling is once a minute, the documented sustained rate; the data itself only
settles within about five minutes of a request, so faster buys nothing.

Four details worth knowing if you touch this code:

- **`amount` is a decimal string in cents.** `"123.45"` means $1.2345. It stays
  a `Decimal` from parse to display — converting to `Double` before rounding
  loses half-cent figures, because $5.005 is not representable in binary and
  truncates down to $5.00.
- **Both reports paginate.** One request caps at 31 daily buckets, and an anchor
  older than a month needs more; `AdminAPI` follows `next_page` until the report
  is exhausted, with a 400-bucket stop so a bad cursor cannot loop forever.
- **Buckets are UTC days.** The window starts at the beginning of the anchor's
  UTC day, which counts any spend earlier that same day. That errs towards
  *under*-stating your remaining balance, never over-stating it.
- **The bar's height follows the ring count** (`Layout.ringCount`), so gaining or
  losing this ring re-parks the whole panel.
- **`CostMonitor` is `@MainActor`, and that is load-bearing.** Publishing a
  metric can change the ring count, which resizes the panel — an AppKit call.
  Without the annotation `poll` resumes on a background cooperative thread
  after its `await` and the window resize trips AppKit's main-thread
  assertion, crashing on the first successful poll. The requests themselves
  still run off-main; only the state change comes back.

## The icon

`tools/MakeIcon.swift` draws the icon in SwiftUI and writes a full `.iconset`:
a dark tile, a usage ring sweeping orange → yellow → green through 73%, a
sparkle at its centre, and the notch bar clipped into the right edge — the app
in miniature.

```sh
swiftc -parse-as-library -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  -module-name MakeIcon tools/MakeIcon.swift SideNotch/Shapes.swift SideNotch/Layout.swift \
  -o build/makeicon
./build/makeicon SideNotch/Resources/AppIcon.iconset
iconutil --convert icns SideNotch/Resources/AppIcon.iconset \
  --output SideNotch/Resources/AppIcon.icns
```

Every size is rendered from the vector artwork rather than downscaled from one
1024px master, and sizes at or below 40px get **simplified artwork** — no bar,
no glyph, one fat ring — because the full composition turns to mush at 16px.

Note: on macOS 26 with a monochrome icon appearance selected, the system draws
*all* app icons desaturated, Apple's included. The `.icns` here is full colour.

## How it is put together

| File | Role |
| --- | --- |
| `SideNotchApp.swift` | `@main`; no window scene, just the app delegate |
| `AppDelegate.swift` | Sets `.accessory` activation policy, starts the monitor, builds the panel |
| `NotchPanel.swift` | The `NSPanel` subclass, hit-testing, screen placement |
| `NotchView.swift` | Composes the bar and the hover card |
| `RingView.swift` | One ring: track, progress arc, icon, percentage |
| `DetailCard.swift` | The hover card: header, progress bars, captions |
| `Shapes.swift` | `NotchShape` (bar with inverse fillets) and `CardShape` (tail) |
| `Layout.swift` | Every geometry constant, in one place |
| `PanelState.swift` | Collapsed/expanded state, persisted, with a hit-region callback |
| `HoverWatchdog.swift` | Pure timing rules for auto-collapse |
| `LoginItem.swift` | `SMAppService` wrapper plus the installer's CLI flags |
| `Metric.swift` | Ring/row model plus the placeholder data |
| `UsageSnapshot.swift` | Decodes the status line JSON, maps it to rings |
| `UsageMonitor.swift` | Watches `~/.sidenotch/sessions/`, republishes metrics |
| `AdminAPI.swift` | Raw-HTTP client for the Admin API usage and cost reports |
| `AdminCredentials.swift` | Keychain storage for the admin key; the balance anchor |
| `CostMonitor.swift` | Polls those reports once a minute, maps them to the balance ring |

Panel behaviour worth knowing:

- `styleMask: [.borderless, .nonactivatingPanel]` — hovering or right-clicking
  never steals focus from the app you are actually working in.
- `level = .statusBar` and `collectionBehavior = [.canJoinAllSpaces, .stationary,
  .fullScreenAuxiliary, .ignoresCycle]` — stays on top, on every Space, and over
  full-screen apps.
- The panel is deliberately much wider and taller than the black bar so the card
  and its shadow have room. `PassthroughView.hitTest` returns `nil` outside the
  bar, so that transparent area does **not** eat clicks meant for windows below.
- `reposition()` re-parks the panel on
  `NSApplication.didChangeScreenParametersNotification`, so plugging in or
  removing a display keeps it glued to the right edge.
- The monitor refreshes on file changes *and* on a 30-second timer, so the
  "Resets in 51 min" countdowns keep ticking while nothing else happens.
- The bar's height is a function of how many rings it holds, so gaining or
  losing the balance ring re-parks the whole panel (`Layout.ringCount`).

## Changing things

- **Which rings exist, and what their cards say:** `UsageMapper.metrics(from:)`
  in `UsageSnapshot.swift`. Placeholder values live in `Metric.samples`.
- **Icons:** the `symbol` field — any SF Symbol. The three are placeholders for
  real service logos.
- **Size and spacing:** `Layout.swift`. `panelWidth`/`panelHeight` derive from the
  rest, so the panel resizes itself when you change a ring or the card.
- **Position:** `edgeInset` / `topInset` in `NotchPanelController` (both `0`, i.e.
  flush to the screen edge and to the bottom of the menu bar).
- **After adding or removing a Swift file:** `python3 tools/gen_xcodeproj.py`
  regenerates the Xcode project from whatever is in `SideNotch/`.

## Tests

```sh
./tools/run-tests.sh
```

Four harnesses, each compiled as its own binary against the live sources (a
panel flashes on screen while they run):

| Harness | Checks |
| --- | --- |
| `HitTestingTests` | Clicks reach the tab (collapsed) and the bar (expanded); the transparent rest of the panel stays click-through |
| `AutoCollapseTests` | `HoverWatchdog` timing rules, the bar's on-screen geometry, and that an abandoned bar collapses itself |
| `UsageMonitorTests` | `UsageMonitor` notices a session file written the way the status line script writes it |
| `CostMapperTests` | Cost/usage reports decode from the documented shapes; cents-denominated `amount` strings become the right dollars; the balance counts down and never goes negative |

`tools/tests/` also holds three diagnostics that print rather than assert:
`GeometryDump` (interactive rects), `WindowDump` (live panel frame and window
level), `IconDump` (which icon macOS resolves for a bundle).

## Previewing without running

`tools/Snapshot.swift` renders the view offscreen to a PNG, with an optional
hovered ring index and an optional status line payload — handy for checking
layout changes quickly:

```sh
swiftc -parse-as-library -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  -module-name SnapshotTool tools/Snapshot.swift \
  SideNotch/{Metric,Layout,Shapes,RingView,DetailCard,NotchView,UsageSnapshot,UsageMonitor}.swift \
  -o build/snapshot

./build/snapshot out.png 0                                   # placeholder data, top ring hovered
./build/snapshot out.png 0 ~/.sidenotch/sessions/*.json       # a real captured session
SNAPSHOT_COLLAPSED=1 ./build/snapshot tab.png                 # the collapsed tab
```
