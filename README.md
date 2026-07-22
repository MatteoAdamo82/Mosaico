# Mosaico

A tiling window manager for macOS in a single app.

No Homebrew formulas, no config files, no SIP tampering: drag the app into
Applications, grant one permission (Accessibility), and your windows organize
themselves. Everything is configurable from a GUI.

Mosaico replaces a typical yabai + skhd + menubar-plugin setup with one
self-contained menubar app, aimed at people who want automatic tiling without
the terminal-heavy setup those tools require.

## Features

- **Automatic BSP tiling** — windows split the screen binary-tree style; new
  windows split the focused one (spiral layout), with configurable gaps and
  padding
- **Native macOS Spaces integration** — one independent tiling tree per
  Mission Control space; layout is only ever applied to the visible space
- **Drop zones with visual overlay** — drag a window onto another: center
  swaps them, top/bottom half stacks vertically, left/right half splits
  horizontally; the target zone highlights while you drag
- **Edge-aware manual resize** — drag any window edge and the neighbors on
  that side absorb the space, yabai-style
- **Global hotkeys** — vim-flavored preset (focus/swap/warp with H/J/K/L),
  fully rebindable from the settings window
- **Mouse support** — pointer follows focus (optional); ⌥+drag moves,
  ⌥+right-drag resizes; move a window to another space with ⇧⌥1…7
- **Smart rules** — dialogs, sheets, picture-in-picture and non-resizable
  windows float automatically; exclude whole apps or single windows from
  tiling via the menubar
- **GUI settings** — gaps, shortcuts recorder, exclusions, launch at login;
  persisted as JSON

## Requirements

- macOS 14 or later (Apple Silicon and Intel)
- Accessibility permission (requested on first launch)
- For the move-to-space hotkeys (⇧⌥1…7): the Mission Control keyboard
  shortcuts ⌃1…⌃7 must be enabled in System Settings → Keyboard → Shortcuts

## Installation

1. Download `Mosaico.zip` from the releases page and unzip it
2. Drag **Mosaico.app** into **Applications**
3. First launch: right-click → Open → Open (the build is not notarized yet)
4. Grant **Accessibility** when prompted

The ⊞ icon appears in the menubar and tiling starts immediately.

### Building from source

```sh
swift build                       # debug build
.build/debug/Mosaico --selftest   # run layout-engine self tests
.build/debug/Mosaico --diag       # print discovery/permissions diagnostics
Scripts/make-app.sh               # produce dist/Mosaico.app and dist/Mosaico.zip
```

Only the Xcode Command Line Tools are required; the project has no
third-party dependencies.

#### Code signing for local development

macOS ties the Accessibility permission to the app's code signature. With
plain ad-hoc signing (the default when no identity is available) the
signature changes on every build, so macOS silently invalidates the
permission and you have to re-grant it after each rebuild.

To avoid that, `Scripts/make-app.sh` signs with a certificate named
**"Mosaico Dev"** when one exists in your keychain, and only falls back to
ad-hoc signing otherwise. Create your own self-signed certificate once:

```sh
# Generate a self-signed code-signing certificate (10 years)
openssl req -x509 -newkey rsa:2048 -keyout mosaico-key.pem -out mosaico-cert.pem \
  -days 3650 -nodes -subj "/CN=Mosaico Dev" \
  -addext "keyUsage=digitalSignature" \
  -addext "extendedKeyUsage=codeSigning" \
  -addext "basicConstraints=CA:false"

# Import the key and certificate into your login keychain
security import mosaico-key.pem -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
security import mosaico-cert.pem -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign

# Trust it for code signing (macOS will ask for your password)
security add-trusted-cert -p codeSign -k ~/Library/Keychains/login.keychain-db mosaico-cert.pem
```

Verify with `security find-identity -p codesigning` — you should see
`"Mosaico Dev"` listed. From then on, rebuilds keep the same signature and
the Accessibility grant survives. On the first signed build macOS may show a
keychain prompt for `codesign`: choose "Always Allow".

Keep the generated `.pem` files out of version control (the repo's
`.gitignore` already excludes them). Note that a self-signed certificate
only helps on your own machine — distributing to other people still runs
into Gatekeeper, which is what the Developer ID + notarization roadmap item
is about.

## Default shortcuts

| Shortcut | Action |
|---|---|
| `⌥ H/J/K/L` | Focus window west/south/north/east |
| `⌥ S / G` | Focus display west/east |
| `⇧⌥ H/J/K/L` | Swap windows |
| `⌃⌥ H/J/K/L` | Warp (move window + new split) |
| `⇧⌥ R` | Rotate layout |
| `⇧⌥ Y / X` | Mirror along Y / X axis |
| `⇧⌥ T` | Toggle float (centered) |
| `⇧⌥ M` | Maximize / restore |
| `⇧⌥ E` | Balance all windows |
| `⇧⌥ S / G` | Move window to display west/east |
| `⇧⌥ 1…7` | Move window to space N |
| `⇧⌥ P / N` | Move window to previous/next space |
| `⌃⌥ Q` | Pause / resume tiling |
| `⌃⌥ R` | Re-tile everything |

All bindings can be changed from Settings → Shortcuts.

## How it works

Mosaico is built on the public Accessibility API (`AXUIElement`) for reading
and moving windows, plus two well-known SPIs — `_AXUIElementGetWindow` for
stable window identity and the `CGSCopyManagedDisplaySpaces` family for
native Spaces awareness (the same interfaces used by tools like yabai and
AltTab). It does **not** require disabling SIP and does **not** inject a
scripting addition.

Moving a window to another space works by simulating a titlebar grab while
triggering the native ⌃N Mission Control switch, which carries the window
along — the same technique yabai uses when running without its scripting
addition.

## Development status

**Early development (0.1.x).** The app is my daily driver and the core is
stable: tiling, native-Spaces handling, hotkeys, drop zones and the settings
UI all work. Expect rough edges around less common window types and
multi-display setups.

Current UI language is Italian; localization is on the roadmap.

### Known limitations

- The bundled build is ad-hoc/self-signed: Gatekeeper requires right-click →
  Open on first launch, and macOS re-asks for the Accessibility permission
  when the signing identity changes
- Native fullscreen windows are left unmanaged until they exit fullscreen
- Per-window exclusion rules match the exact window title, so they don't
  stick for windows that retitle dynamically (browser windows, editors)

## Roadmap

- [ ] Developer ID signing + notarization (removes the Gatekeeper friction
      and the permission re-prompts)
- [ ] Homebrew cask
- [ ] English localization of the UI
- [ ] Better multi-display support (per-display rules, display-aware presets)
- [ ] Configurable auto-float rules from the GUI
- [ ] Optional window borders / focus highlight
- [ ] Layout presets (columns, monocle) alongside BSP

## License

[MIT](LICENSE)
