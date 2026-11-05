# Sidecheck

A tiny personal macOS menu-bar app: hover the pointer at the **middle-right edge** of any screen and a panel pops out — now a full **app platform** with an iPadOS-style home screen, tappable apps, swappable widgets, and five themes.

![ipad](docs/screenshots/theme-ipad.png)

## The app platform

The panel is a tiny launcher/OS:

- **Home screen** — two widget slots + an app grid (+ dock and search pill on themes that want them). Long-press anything → **edit mode** (jiggle): rebind a widget slot to any app, remove it, hit Done.
- **Apps** — tap an icon to open the full app page:
  - **Monitor** — CPU ring + per-core bars + history, Memory, Battery, Network, Disk, GPU (model identity; utilization isn't exposed by public macOS APIs), uptime
  - **Battery / Network / Disk** — focused detail views with big sparklines
  - **Settings** — everything below
- **Home widgets** — any app's compact widget can sit on the home screen, so the data you care about is visible the instant the panel opens. Bindings persist.

## Themes

Three themes on one theme-agnostic base — each theme picks its own **frame size**, **home template** (icon tiles / terminal list), **icon corner radius** (0.224 squircle for iPad, 0.5 circles for Vita bubbles), and decorations (dock, search pill, header clock):

| Theme | Frame | Look |
|---|---|---|
| **Liquid Glass** | 380×680 | dark vibrancy + drifting aurora |
| **iPad** | **720×540 (4:3 landscape)** | light wallpaper, squircle icon grid, dock, search pill, clock |
| **Cyberdeck** | 380×680 | phosphor terminal, scanlines, `» TEXT MENU` home template |

![cyberdeck](docs/screenshots/theme-cyberdeck.png)

## Customization (Settings app)

- **Panel size** — 75–125% scale of the theme frame, applied live
- **Open/close animation** — Slide (edge drawer) / Pop (fade + bouncy spring) / Zoom (grows from the edge), plus a speed slider (0.15–0.5 s)
- **Home widgets** — rebind either slot to any app
- **Appearance** — theme picker
- Reduce Motion is respected everywhere (fade-only entrance, static backgrounds, no jiggle)

## Behavior & controls

- Hover the right-edge hot zone (middle 40% of screen height) → panel opens after a short dwell; move away → hides after a grace period. Works on every display.
- **Pin** keeps the panel open while you interact.
- **Switching themes while the panel is open is seamless**: the window snaps to the new theme's exact frame (flush right, vertically centered) while the old look dissolves into the new one — the window is the single sizing authority (`NSHostingView.sizingOptions = []`), so nothing re-anchors it.
- Menu bar: Show panel · Enabled · Theme submenu · Launch at Login · Quit.
- Never steals keyboard focus; floats over fullscreen apps; no permissions needed (`NSEvent` monitors only).

## Build & run

```bash
swift run                       # dev build, runs in place
./Scripts/make_app.sh           # release build → build/Sidecheck.app
open build/Sidecheck.app
cp -R build/Sidecheck.app /Applications/   # to install
```

## Architecture notes

- `Apps/PanelApp.swift` — `AppID` (monitor, settings) + `WidgetKind` (home widget flavors; battery/network/disk widgets open Monitor); adding an app = one case + `fullView` branch
- `Apps/HomeStore.swift` — widget slots + edit mode, persisted (`homeWidgetSlots`)
- `Apps/HomeScreen.swift` — theme-driven home (widget slots, grid/terminal launcher, dock)
- `Apps/AppViews.swift` — full app pages + IORegistry GPU name helper
- `ThemeStore.swift` — `ThemeSpec` design tokens incl. `frameSize`, `homeStyle`, `iconCornerRadiusRatio`
- `PanelController.swift` — NSPanel, size scale, animation presets, live re-frame
- `Widgets/StatsStore.swift` — 1 Hz CPU/memory/network + 15 s battery/disk/uptime sampling, 60-sample history
- Panel settings persist: `themeID`, `panelScale`, `panelAnimationStyle`, `panelAnimationSpeed`, `homeWidgetSlots`

## Dev/test hooks

```bash
SIDECHECK_AUTOSHOW=1 SIDECHECK_OPENAPP=settings .build/release/Sidecheck
```

`SIDECHECK_AUTOSHOW=1` pops (and pins) the panel 2 s after launch; `SIDECHECK_OPENAPP=<appId>` navigates to an app. Show/hide events log to stderr.

## Roadmap

- [ ] More apps (top processes, now-playing)
- [ ] Multi-page home + drag-to-rearrange icons
- [ ] More themes (the Vita bubble look may return as a template)
- [ ] Configurable hot zone (edge side, width, span)

---
*v0.3 — apps, themes, and knobs. Built overnight by an agent while its human slept.* 🌙
