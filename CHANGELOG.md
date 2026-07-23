# Changelog

All notable changes to Mosaico are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.2] - 2026-07-23

### Fixed

- The "Impostazioni…" menu item did nothing: the SwiftUI `Settings` scene is
  only reachable through unreliable private selectors in a menubar-only app,
  so the settings window is now managed directly and opens reliably
- Clarified pause/resume and re-tile in the menu (play/pause glyphs); both
  remain reachable by menu and hotkey (⌃⌥Q, ⌃⌥R) while tiling is paused

## [0.1.1] - 2026-07-23

### Added

- App icon and menubar icon: three golden-ratio tiles; the app icon is
  generated from an editable SVG source (`Resources/AppIcon.svg`) via
  `Scripts/make-icon.swift`
- Per-window exclusion toggle in the menubar: the window list shows a
  checkmark on excluded windows and clicking toggles them in and out of
  tiling instantly; leftover title-based rules from previous sessions are
  listed separately for cleanup
- Floating windows (dialogs, fixed-size windows) are kept above tiled ones,
  so they no longer disappear behind the tiling
- Display focus/move commands work with any monitor arrangement: if no
  display lies in the requested direction (e.g. stacked monitors), they
  cycle through displays in spatial order
- Local code-signing setup documented in the README

### Changed

- Runtime window exclusion is tracked by window id, immune to dynamic title
  changes; title-based rules are only used to persist across restarts
- The menubar window list is driven by observable state and stays current
  as windows are adopted, closed, excluded or re-enabled
- Internal cleanup: dead code from the abandoned virtual-workspace design
  removed, drop-zone geometry and window rules extracted into pure
  functions, resize-adoption unified into a single code path, self-tests
  extended from 14 to 31 checks

### Fixed

- Windows on non-visible Spaces were wrongly pruned from the model (the
  Accessibility API reports them as invalid while they still exist), which
  emptied the menubar window list over time
- Excluded windows vanished from the menubar list after switching Space;
  they now stay listed while their app is running
- An excluded window could be re-tiled after its title changed while still
  showing as excluded
- Settings decoding is now tolerant per-binding: an invalid saved shortcut
  no longer resets the whole configuration

## [0.1.0] - 2026-07-21

Initial release.

### Added

- Automatic BSP tiling with yabai-compatible semantics: second-child
  insertion at the focused window (spiral layout), split orientation from the
  longest side, rotate/mirror/balance/swap/warp operations, configurable
  gaps and padding
- Native macOS Spaces integration: one independent tiling tree per Mission
  Control space per display; layout is applied only to the visible space;
  windows moved across spaces (via Mission Control or hotkey) are relocated
  to the correct tree automatically
- Drop zones with live visual overlay: drop on a window's center to swap,
  on its top/bottom half to stack vertically, on its left/right half to
  split horizontally; works with plain drags and across displays
- Edge-aware manual resizing: the divider on the side of the dragged edge
  moves, so neighbors on that side absorb the freed space; resizes are
  adopted on mouse release (robust with apps that don't emit Accessibility
  resize events, e.g. Electron)
- Global hotkeys via Carbon `RegisterEventHotKey` with a rebindable
  vim-style preset (focus/swap/warp H/J/K/L, layout operations, move to
  display/space)
- Move window to native space N (⇧⌥1…7) using a simulated titlebar grab plus
  the native ⌃N Mission Control switch
- Mouse integration on a dedicated high-priority thread: ⌥+drag to move,
  ⌥+right-drag to resize split ratios, pointer-follows-focus with
  anti-hijack guards, zero added click latency
- Window rules: auto-float for dialogs, sheets, system-floating windows
  (picture-in-picture) and non-resizable/non-movable windows; app exclusion
  list and per-window exclusion rules editable from the menubar and settings
- Settings window (gaps, mouse behavior, shortcut recorder, exclusions,
  launch at login) persisted as JSON in Application Support
- Menubar menu with all tiling actions, pause/resume and re-tile
- Self-test mode (`--selftest`) covering the layout engine, and a
  diagnostics mode (`--diag`) for permissions and window discovery
- Build script producing a standalone `Mosaico.app` bundle and zip
