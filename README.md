# findmouse

A tiny macOS command-line tool that draws a brief, click-through animation
around the current mouse cursor (and optionally on the screen containing it),
then exits. Built to be bound to a global hotkey so you can find your cursor
on a large or multi-monitor setup at a glance.

## Motivation

On a multi-monitor setup — or just a very large display — it's easy to lose
the cursor. macOS has a built-in "shake to find" gesture, but it relies on
shaking the mouse, which is awkward with a trackball, on a trackpad, or when
you're just glancing back at your screen. `findmouse` solves the same problem
without input: bind it to a hotkey, press it, and a brief radar-style pulse
shows you exactly where the cursor is.

On setups with many monitors, the default ring pulse can still be hard to
spot. `--mode` lets you combine ring pulses with a screen-edge **border**
flash and/or full-width/height **crosshairs**, so the right *monitor* pops
out at the same time as the cursor.

It's also handy for screencasts and demos where you want to draw the viewer's
attention to where you're about to click.

## Install

There are two ways to get `findmouse`. Either works; pick one.

### Option 1 — download a release

1. Grab the latest `findmouse-<version>-macos-universal.tar.gz` from the
   [Releases page](../../releases).
2. Verify the checksum (optional but recommended):
   ```sh
   shasum -a 256 -c findmouse-<version>-macos-universal.tar.gz.sha256
   ```
3. Extract and install:
   ```sh
   tar xzf findmouse-<version>-macos-universal.tar.gz
   cd findmouse-<version>-macos-universal
   sudo install -m 755 findmouse /usr/local/bin/findmouse
   ```

The release tarball ships a universal binary (arm64 + x86_64) requiring
macOS 11+. It is codesigned with an Apple Developer ID and notarized by
Apple, so Gatekeeper accepts it without any `xattr` workaround.

### Option 2 — build from source

```sh
make            # builds ./findmouse
make install    # copies to /usr/local/bin (PREFIX=... to override)
```

No dependencies beyond the macOS SDK and Swift toolchain. The result is a
single ~100 KB binary. Building from source needs macOS 10.15+; the prebuilt
release targets macOS 11+ so it covers Apple Silicon.

### Creating a release (maintainers)

```sh
make release VERSION=0.1.0   # unsigned universal build (for local testing)
make sign    VERSION=0.1.0   # build, codesign, notarize, re-roll the tarball
```

Produces `build/findmouse-0.1.0-macos-universal.tar.gz` plus a `.sha256`
file, ready to upload to a GitHub Release.

`make sign` expects:

- A **Developer ID Application** certificate in the login keychain
  (`security find-identity -v -p codesigning` should list one). Override
  with `make sign SIGN_ID="Developer ID Application: Name (TEAMID)"` if
  the auto-pick is wrong.
- A notarytool keychain profile created once with:
  ```sh
  xcrun notarytool store-credentials "findmouse-notary" \
        --apple-id "you@example.com" \
        --team-id "YOURTEAMID" \
        --password "app-specific-password"
  ```
  Override the profile name with `make sign NOTARY_PROFILE=other-name`.

## Usage

```
findmouse [options]
```

| Flag                 | Default | Description                                                          |
| -------------------- | ------- | -------------------------------------------------------------------- |
| `--mode LIST`        | `rings` | Comma-separated effects: `rings`, `border`, `crosshairs`             |
| `--rings N`          | 4       | Number of concentric rings                                           |
| `--max-radius N`     | 120     | Maximum ring radius (points)                                         |
| `--start-radius N`   | 8       | Starting ring radius (points)                                        |
| `--line-width N`     | 5       | Stroke width (points; border uses 3× this)                           |
| `--color VAL`        | red     | Named color or hex (`#FF8800`, `FF8800AA`)                           |
| `--duration SECS`    | 0.9     | Animation duration per ring / border / crosshairs cycle              |
| `--stagger SECS`     | 0.12    | Delay between successive rings                                       |
| `--detach`           | off     | Re-spawn in background and return to the shell immediately           |
| `--debug`            | off     | Log diagnostic info to stderr (suppresses `--detach`)                |
| `-h`, `--help`       |         | Show help                                                            |

Named colors: `red`, `green`, `blue`, `yellow`, `orange`, `purple`, `pink`,
`teal`, `white`, `black`, `cyan`, `magenta`, `gray`.

### Modes

- **`rings`** — concentric pulse rings expanding outward from the cursor.
  Good at pointing *exactly* where the cursor is.
- **`border`** — a thick rectangle hugging the screen perimeter, fading in
  and out. Good at identifying *which monitor* the cursor is on.
- **`crosshairs`** — full-width and full-height lines passing through the
  cursor. Doubles as a "which screen" and "which row/column" indicator.

Modes compose freely:

```sh
findmouse --mode rings              # default
findmouse --mode border             # just flash the screen edges
findmouse --mode rings,border       # cursor pulse + screen marker
findmouse --mode crosshairs --color cyan
findmouse --mode rings,border,crosshairs --color "#FF8800"
```

### Examples

```sh
# Default red pulse
findmouse

# Big green pulse, fewer rings
findmouse --rings 2 --color green --max-radius 200

# Custom hex colour with alpha
findmouse --color "#00AAFF80"

# Return to the shell instantly; animation continues
findmouse --detach

# Multi-monitor: pulse the cursor AND flash the screen border
findmouse --mode rings,border --detach

# Diagnose multi-monitor placement issues
findmouse --debug
```

## Hotkey integration

`findmouse` is most useful when bound to a global hotkey.

**Hammerspoon** (`~/.hammerspoon/init.lua`):

```lua
hs.hotkey.bind({"cmd", "alt"}, "M", function()
  hs.task.new("/usr/local/bin/findmouse", nil, {"--mode", "rings,border"}):start()
end)
```

**skhd** (`~/.config/skhd/skhdrc`):

```
cmd + alt - m : /usr/local/bin/findmouse --mode rings,border
```

**BetterTouchTool** / **Keyboard Maestro** — bind to *Execute Shell Script*,
and enable "Run asynchronously / in background". When the launcher handles
asynchrony, you can omit `--detach`; otherwise add it. Avoid wrapping the
command in another shell for the fastest response.

**Karabiner-Elements** — bind a key to launch a shell command running
`findmouse`.

## Performance

For the snappiest trigger-to-pulse latency:

- Build with `-O -whole-module-optimization` and `strip -x` (or `make`),
  which trims the binary and helps cold dyld load.
- Prefer letting your launcher run the command asynchronously (e.g.
  BTT/Keyboard Maestro's "run in background" option) instead of `--detach`,
  which avoids the cost of re-spawning the Swift runtime in a child.
- If you bind it to a hotkey and notice noticeable lag on the first invocation
  after a reboot, that's cold dyld + AppKit init (~150–250 ms). Subsequent
  invocations are much faster.

## Notes

- The overlay window uses the `.screenSaver` window level and is click-through,
  so it never steals focus or input.
- It draws on the screen containing the cursor, including external displays.
  An explicit `setFrame(screen.frame, display: true)` after window creation
  works around a quirk where `NSWindow(contentRect:screen:)` alone sometimes
  places the overlay on the wrong display.
- If placement still misbehaves, run with `--debug` to see which screen was
  selected and where the window was placed.
- Total runtime is roughly `duration + rings × stagger + 0.2 s` (≈ 1.6 s with
  defaults); `--mode border` or `--mode crosshairs` alone exits in ~1.1 s.

## License

MIT — see [LICENSE](LICENSE).

## Usage

```
findmouse [options]
```

| Flag                 | Default | Description                                                          |
| -------------------- | ------- | -------------------------------------------------------------------- |
| `--mode LIST`        | `rings` | Comma-separated effects: `rings`, `border`, `crosshairs`             |
| `--rings N`          | 4       | Number of concentric rings                                           |
| `--max-radius N`     | 120     | Maximum ring radius (points)                                         |
| `--start-radius N`   | 8       | Starting ring radius (points)                                        |
| `--line-width N`     | 5       | Stroke width (points; border uses 3× this)                           |
| `--color VAL`        | red     | Named color or hex (`#FF8800`, `FF8800AA`)                           |
| `--duration SECS`    | 0.9     | Animation duration per ring / border / crosshairs cycle              |
| `--stagger SECS`     | 0.12    | Delay between successive rings                                       |
| `--detach`           | off     | Re-spawn in background and return to the shell immediately           |
| `--debug`            | off     | Log diagnostic info to stderr (suppresses `--detach`)                |
| `-h`, `--help`       |         | Show help                                                            |

Named colors: `red`, `green`, `blue`, `yellow`, `orange`, `purple`, `pink`,
`teal`, `white`, `black`, `cyan`, `magenta`, `gray`.

### Modes

- **`rings`** — concentric pulse rings expanding outward from the cursor.
  Good at pointing *exactly* where the cursor is.
- **`border`** — a thick rectangle hugging the screen perimeter, fading in
  and out. Good at identifying *which monitor* the cursor is on.
- **`crosshairs`** — full-width and full-height lines passing through the
  cursor. Doubles as a "which screen" and "which row/column" indicator.

Modes compose freely:

```sh
findmouse --mode rings              # default
findmouse --mode border             # just flash the screen edges
findmouse --mode rings,border       # cursor pulse + screen marker
findmouse --mode crosshairs --color cyan
findmouse --mode rings,border,crosshairs --color "#FF8800"
```

### Examples

```sh
# Default red pulse
findmouse

# Big green pulse, fewer rings
findmouse --rings 2 --color green --max-radius 200

# Custom hex colour with alpha
findmouse --color "#00AAFF80"

# Return to the shell instantly; animation continues
findmouse --detach

# Multi-monitor: pulse the cursor AND flash the screen border
findmouse --mode rings,border --detach

# Diagnose multi-monitor placement issues
findmouse --debug
```

## Hotkey integration

`findmouse` is most useful when bound to a global hotkey.

**Hammerspoon** (`~/.hammerspoon/init.lua`):

```lua
hs.hotkey.bind({"cmd", "alt"}, "M", function()
  hs.task.new("/usr/local/bin/findmouse", nil, {"--mode", "rings,border"}):start()
end)
```

**skhd** (`~/.config/skhd/skhdrc`):

```
cmd + alt - m : /usr/local/bin/findmouse --mode rings,border
```

**BetterTouchTool** / **Keyboard Maestro** — bind to *Execute Shell Script*,
and enable "Run asynchronously / in background". When the launcher handles
asynchrony, you can omit `--detach`; otherwise add it. Avoid wrapping the
command in another shell for the fastest response.

**Karabiner-Elements** — bind a key to launch a shell command running
`findmouse`.

## Performance

For the snappiest trigger-to-pulse latency:

- Build with `-O -whole-module-optimization` and `strip -x` (or `make`),
  which trims the binary and helps cold dyld load.
- Prefer letting your launcher run the command asynchronously (e.g.
  BTT/Keyboard Maestro's "run in background" option) instead of `--detach`,
  which avoids the cost of re-spawning the Swift runtime in a child.
- If you bind it to a hotkey and notice noticeable lag on the first invocation
  after a reboot, that's cold dyld + AppKit init (~150–250 ms). Subsequent
  invocations are much faster.

## Notes

- The overlay window uses the `.screenSaver` window level and is click-through,
  so it never steals focus or input.
- It draws on the screen containing the cursor, including external displays.
  An explicit `setFrame(screen.frame, display: true)` after window creation
  works around a quirk where `NSWindow(contentRect:screen:)` alone sometimes
  places the overlay on the wrong display.
- If placement still misbehaves, run with `--debug` to see which screen was
  selected and where the window was placed.
- Total runtime is roughly `duration + rings × stagger + 0.2 s` (≈ 1.6 s with
  defaults); `--mode border` or `--mode crosshairs` alone exits in ~1.1 s.

## License

MIT — see [LICENSE](LICENSE).
