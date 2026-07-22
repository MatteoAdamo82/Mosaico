# Changelog

All notable changes to Mosaico are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
