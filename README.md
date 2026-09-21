# trisplit

Window grid manager for macOS, powered by [Hammerspoon](https://www.hammerspoon.org/).

Define a resizable grid (cols × rows) per monitor, assign apps to slots, and
restore your entire workspace with one hotkey — or drag windows around in a
native panel that moves the **real windows** while you drag.

![trisplit panel](docs/screenshot.png)

## Features

- **Per-monitor grids** — any `cols × rows` layout on every screen, with 4px gaps.
- **Named configurations** — switch between multiple layouts (Dev, Meeting, …)
  from the panel or with a hotkey cycle.
- **Native panel** — a real AppKit window (not a floating webview hack) with a
  live map of your desktop at true scale.
- **Drag = move** — dragging a chip in the panel moves the actual window
  instantly; dragging between slots swaps windows.
- **Multi-window apps** — slots can target a specific window of an app
  (`App#2` = the app's 2nd standard window), and the tray shows one chip per
  window with its title.
- **Hotkeys per slot** — `⌘⌥1…9` moves the focused window to slot N and
  remembers it; `⌘⌥⇧1…9` focuses the app/window assigned to slot N.
- **Monitor arrangement** — drag whole monitors in the panel's desktop map
  (with snapping, magnetic edges and alignment guides) and apply the new
  arrangement to macOS via [displayplacer](https://github.com/jakehilborn/displayplacer).
  Includes a **Reset** button that restores the previous arrangement.
- **Menu bar icon** — monochrome template icon with one-click panel access.
  Hammerspoon's own menu bar / Dock icons are hidden.
- **macOS native styling** — system colors (`Canvas`, `AccentColor`, …),
  automatic light/dark mode, SF typography.
- **Persistent state** — layouts live in `~/.hammerspoon/trisplit.json`.

## Requirements

- macOS with Apple Silicon or Intel (uses `swiftc` for the optional panel app).
- [Hammerspoon](https://www.hammerspoon.org/) ≥ 1.0 with Accessibility permission.
- Optional: [displayplacer](https://github.com/jakehilborn/displayplacer) for
  monitor arrangement (`brew install displayplacer`). Without it, everything
  works except the "Apply to macOS" button.

## Installation

```sh
git clone https://github.com/dibanez/trisplit ~/.hammerspoon/trisplit
echo 'require("trisplit")' >> ~/.hammerspoon/init.lua
```

Reload Hammerspoon (`⌘⇧R` in its console, or `hs -c "hs.reload()"`).

The first run creates `~/.hammerspoon/trisplit.json` with a default 3×1 grid
per connected monitor.

### Optional: the native panel app

Without this, the panel opens as an `hs.webview` window (fully functional).
With it, the panel is a real AppKit `NSWindow`:

```sh
cd ~/.hammerspoon/trisplit
make build        # or: ./build.sh
```

`build.sh` compiles `app/main.swift` with `swiftc` into `TrisplitPanel.app`.
trisplit auto-detects the bundle next to `init.lua` and prefers it.

## Usage

### Panel

Open with the menu bar icon or `⌘⌥P`.

- **Config selector** (top left) — switch, create (`+`) and delete (`🗑`,
  two-step confirm) named configurations.
- **Desktop map** — your monitors at true scale, showing each monitor's grid.
  Drag chips from the tray (bottom) onto slots, or between slots. Every drag
  moves the real window immediately.
- **`✕` on a chip** — unassigns the app from the slot (the window stays put).
- **col / fil steppers** — resize each monitor's grid; slots are preserved.
- **Aplicar / Apply** — re-run the whole layout (launches missing apps).
- **Drag a monitor box** — rearrange monitors; a banner appears with
  **Aplicar a macOS** (via displayplacer) and **Restablecer**.

### Hotkeys

| Shortcut | Action |
|---|---|
| `⌘⌥0` | Apply the active configuration |
| `⌘⌥⇧0` | Cycle to next configuration and apply |
| `⌘⌥P` | Open the panel |
| `⌘⌥1…9` | Move the focused window to flat slot N (and persist it) |
| `⌘⌥⇧1…9` | Focus the app/window assigned to slot N |

Flat slot numbering walks monitors left-to-right (then top-to-bottom) and each
monitor's slots row-major. Slots beyond 9 have no hotkey but work everywhere else.

### Multi-window apps

Drop the same app twice and trisplit targets its different windows. The
underlying spec syntax is `AppName#N` (1-based index over the app's standard,
non-minimized windows, ordered by window id). `App` alone means window #1.

### App name aliases

`Code` ↔ `Visual Studio Code` are aliased automatically. Add more in the
`ALIASES` table in `init.lua`.

## Configuration file

`~/.hammerspoon/trisplit.json`:

```json
{
  "active": 1,
  "configs": [
    {
      "name": "Dev",
      "monitors": {
        "Built-in Retina Display": { "cols": 3, "rows": 1, "slots": ["", "", ""] },
        "Odyssey G95C": { "cols": 3, "rows": 1, "slots": ["OpenChamber", "Code", "Claude"] }
      }
    }
  ],
  "arrange": {},
  "arrangeOriginal": {}
}
```

- `slots` has exactly `cols × rows` entries; `""` = empty slot.
- Monitor keys are the exact names reported by `hs.screen:name()`.
- `arrange` holds pending monitor offsets (points); `arrangeOriginal` is the
  snapshot used by **Restablecer**.

## Lua API

Loading the module exposes a global `trisplit`:

```lua
trisplit.apply()               -- apply active config
trisplit.openPanel()
trisplit.state()               -- raw state table
trisplit.panelState()          -- panel payload (screens, apps, arrange…)
trisplit.flatSlots()           -- ordered slot list across monitors
trisplit.slotFrame(n)          -- hs.geometry of flat slot n
trisplit.moveFrontToSlot(n)    -- ⌘⌥N backend
trisplit.focusSlot(n)          -- ⌘⌥⇧N backend
trisplit.liveMove(screen, idx, app) -- panel drag backend
trisplit.applyArrangement(offsets)  -- displayplacer wrapper
```

## Testing

```sh
make test        # or: ./tests/run.sh
```

Three suites, ~2 minutes total, run against your live Hammerspoon session
(with backup/restore of your config file):

| Suite | What it covers |
|---|---|
| `unit` | pure logic: grid math, spec parsing, config migration, aliases, panel payload contract |
| `integration` | real window moves (`liveMove`, `moveFrontToSlot`, `focusSlot`), persistence round-trips, displayplacer parsing |
| `panel-js` | the panel's JS: chip drag/swap, removal, tray drop, grid steppers, new-config flow, monitor drag, state normalization |

The suites open and close Finder windows and move them around; run them when
you don't mind windows being shuffled for ~30s.

## Repository layout

```
init.lua            # the whole engine (loaded via require("trisplit"))
panel.html          # panel UI (WKWebView content, shared by both panel modes)
app/main.swift      # native AppKit panel wrapper (optional)
build.sh            # compiles TrisplitPanel.app
icon.png            # menu bar template icon
tests/              # unit + integration + panel JS suites (./tests/run.sh)
docs/               # screenshots
```

## Troubleshooting

- **Panel doesn't move windows** — grant Accessibility permission to
  Hammerspoon (System Settings → Privacy & Security → Accessibility).
- **Windows not placed on the right monitor** — monitor names must match
  `hs.screen:name()` exactly; open the panel once and re-save the config to
  fix names after hardware changes.
- **"Apply to macOS" does nothing** — install displayplacer:
  `brew install displayplacer`. The expected path is
  `/opt/homebrew/bin/displayplacer` (Intel: adjust `DISPLAYPLACER` in
  `init.lua`).
- **Fullscreen windows** — trisplit exits fullscreen before placing a window.
- **Locked screen** — applying a layout while the login/lock screen is up is
  skipped on purpose.

## License

MIT — see [LICENSE](LICENSE).
