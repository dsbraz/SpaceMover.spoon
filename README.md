# SpaceMover.spoon

Move the focused window to a numbered native macOS desktop with Hammerspoon.

## Install

```sh
git clone https://github.com/dsbraz/SpaceMover.spoon.git ~/.hammerspoon/Spoons/SpaceMover.spoon
make -C ~/.hammerspoon/Spoons/SpaceMover.spoon
```

Add to `~/.hammerspoon/init.lua`, then reload Hammerspoon:

```lua
hs.loadSpoon("SpaceMover")
spoon.SpaceMover:bindHotkeys()
```

Hammerspoon needs Accessibility permission. Building the small native helper
requires Apple's Command Line Tools (`xcode-select --install`) or Xcode.

## Behavior

- **Hyper+1…9** (`cmd+ctrl+alt`, without Shift) sends the exact focused window to that desktop.
- Numbering follows the global managed-display order and desktop order within each display, excluding fullscreen Spaces. A destination may be on another monitor; numbering does not restart on the focused monitor.
- The active desktop stays in place; other windows of the application stay where they are.
- Missing desktops are reported, never created.
- Fullscreen windows and windows assigned to multiple Spaces are rejected.
- Movement is confirmed by the native helper (up to 1.5 seconds) and checked again by Lua; a failed confirmation produces an alert.

For stable numbering, disable “Automatically rearrange Spaces based on most recent use”
in macOS Mission Control settings. Separate Spaces per display is recommended.
The standard `hs.spaces.moveWindowToSpace` call can report success without moving
a window on recent macOS versions. This Spoon uses a native helper based on
WhichSpace's bridged SkyLight operation instead. It accepts the exact focused
window ID and does not require WhichSpace, SIP changes, or mouse dragging.
These are private macOS APIs, so compatibility can vary between releases.

## API

```lua
spoon.SpaceMover:moveFocusedTo(3) -- true if submitted/already there; false, reason on failure
spoon.SpaceMover:desktopSpaces() -- global ordered desktop IDs
spoon.SpaceMover:desktopSpaces(hs.screen.mainScreen()) -- optional screen-only query
spoon.SpaceMover:status() -- version and enabled bindings
spoon.SpaceMover:stop() -- delete bindings; already submitted moves finish normally
```

Override the defaults with numeric keys. An empty mapping disables all bindings:

```lua
spoon.SpaceMover:bindHotkeys({
  [1] = { { "ctrl", "alt" }, "1" },
  [2] = { { "ctrl", "alt" }, "2" },
})
```

## License

MIT. Vendored native backend: George Christou / WhichSpace; see
[`native/README.md`](native/README.md) and its original license.

## Validation

Run isolated tests in the Hammerspoon console:

```lua
dofile(hs.configdir .. "/Spoons/SpaceMover.spoon/tests.lua")
```

Locally verified on macOS 27 with Hammerspoon 1.1.1: native movement to another
desktop, unchanged active desktop, and confirmed restoration to the source.
Isolated tests cover global numbering across displays, fullscreen exclusion,
shared-Space deduplication and exact-window cross-monitor target selection.
Version 0.2.0 was also checked with a real Finder window moving from the main
external display to the portrait display: both Space membership and destination
screen matched, and the active Space on every monitor remained unchanged.
