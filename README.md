# AI Notch

*(The Xcode project, source folder and bundle id keep the original `SideNotch`
name; only the product is called AI Notch.)*

A macOS HUD with no Dock icon and no menu bar item. It sits out of the way as a
small tab on the right edge of the screen; click the tab and it expands into a
black "notch" bar showing three usage rings. Hovering a ring slides out a card
to its left with the details. It collapses again on its own once the pointer
leaves the bar (or immediately, if you click the bar).

Out of the box it shows **your real Claude usage** — the same 5-hour and 7-day
limit numbers Claude Code shows in `/usage` — fed by a status line script.

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
- **Org spend:** the Admin API usage and cost reports
  (`GET /v1/organizations/usage_report/messages`, `/v1/organizations/cost_report`)
  need an Admin API key and are raw HTTP only — good for a "spend this month"
  ring.
- **Local token history:** `~/.claude/projects/**/*.jsonl` records `usage` (input,
  output, and cache tokens) per assistant message with a timestamp. Enough to
  compute your own rolling windows offline; it has no server-side limit
  percentages, so any "% used" derived from it is your own estimate.

There is no public API for the Claude.ai subscription usage numbers themselves —
the status line is the supported way to get them onto your desktop.

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

Three harnesses, each compiled as its own binary against the live sources (a
panel flashes on screen while they run):

| Harness | Checks |
| --- | --- |
| `HitTestingTests` | Clicks reach the tab (collapsed) and the bar (expanded); the transparent rest of the panel stays click-through |
| `AutoCollapseTests` | `HoverWatchdog` timing rules, the bar's on-screen geometry, and that an abandoned bar collapses itself |
| `UsageMonitorTests` | `UsageMonitor` notices a session file written the way the status line script writes it |

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
