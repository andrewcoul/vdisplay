# vdisplay

A tiny command-line tool that creates a **virtual display on macOS**, with any resolution and refresh rate you choose, and no dummy plug.

```
$ vdisplay --width 3440 --height 1440 --hz 160 --keep-awake
vdisplay: created "Virtual Display" displayID=29 serial=1  3440x1440 @ 160Hz
vdisplay: preventing display sleep while running
^C
vdisplay: removing display 29
vdisplay: display 29 removed after 100 ms
```

The display exists while the process runs; stopping it (Ctrl-C or `SIGTERM`) removes the display.

Typical uses:
- Headless Mac mini or game-streaming hosts (Sunshine/Moonlight, VNC, Screen Sharing).
- Streaming at your client's resolution and refresh rate.
- Testing ultrawide or high-refresh layouts.

It is roughly 200 lines of Objective-C in a single file, with no dependencies.

## Requirements

- macOS on Apple silicon. Tested on macOS 27 with an M6 Mac mini; earlier versions with `CGVirtualDisplay` should work but are untested.
- Xcode Command Line Tools (`xcode-select --install`).
- It must run inside a logged-in GUI session (Terminal, or a LaunchAgent), not over a bare SSH session without a user logged in.

## Build and install

```sh
make            # builds ./vdisplay
make install    # installs to ~/.local/bin (override with PREFIX=/usr/local)
```

## Usage

```
vdisplay [--width N] [--height N] [--hz N] [--name NAME] [--serial N] [--hidpi] [--keep-awake]
```

| Flag | Default | Meaning |
|---|---|---|
| `--width`, `--height` | `3440` × `1440` | Resolution in pixels |
| `--hz` | `160` | Refresh rate. Lower fallbacks (144/120/100/60) are offered too. |
| `--name` | `Virtual Display` | Name shown in System Settings → Displays |
| `--serial` | `1` | Serial number. Use different values to run several displays at once. |
| `--hidpi` | off | Also offer a Retina (2×) mode |
| `--keep-awake` | off | Prevent display sleep while running. Recommended for streaming, or captures come out black. |

List displays, including the virtual one (vendor `0xeeee`):

```sh
python3 tools/list-displays.py
system_profiler SPDisplaysDataType
```

## Start at login

```sh
make install
sed "s#/Users/YOU#$HOME#" launchd/com.github.vdisplay.plist > ~/Library/LaunchAgents/com.github.vdisplay.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.github.vdisplay.plist
# stop and remove:
launchctl bootout gui/$(id -u)/com.github.vdisplay
```

## How it works and caveats

vdisplay uses `CGVirtualDisplay`, a **private, undocumented** CoreGraphics API. BetterDisplay, DeskPad and Chromium's test tooling use the same API. Because it is private:

- **A macOS update can break it** without warning.
- **It is not App Store-safe.**

Lessons learned getting removal right:

- **WindowServer defers display reconfiguration while displays are asleep.** If you release a virtual display during display sleep, it lingers as a "ghost" until the next wake. A ghost also blocks re-creating a display with the same serial. vdisplay declares user activity (`IOPMAssertionDeclareUserActivity`) before tearing down, so removal happens immediately. To clear ghosts left by other tools, run `caffeinate -u -t 2`.
- **Teardown is asynchronous.** vdisplay waits until the display ID actually leaves the online display list (up to 5 s) before exiting. It exits with code `3` if the display is still online.
- **Teardown needs a real run loop.** It uses `CFRunLoopRun()` rather than `dispatch_main()`, with callbacks on a private serial queue and no termination handler, as Chromium does.

## Credits

Prior art and references:
- [DeskPad](https://github.com/Stengo/DeskPad)
- [FluffyDisplay](https://github.com/tml1024/FluffyDisplay)
- Chromium's `ui/display/mac/test/virtual_display_util_mac.mm`
- the [go-macos/virtualdisplay](https://pkg.go.dev/github.com/go-macos/virtualdisplay) notes

## License

MIT
