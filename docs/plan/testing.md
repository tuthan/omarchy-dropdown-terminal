# Testing facilities

Owned by [phase 0](phase-0-foundation.md) item 0.6. Every phase's acceptance
criteria assume these exist.

## The single-monitor problem

The development machine has one output: `DP-1`, 3440x1440, scale 1, at 0,0.
Phases 1, 3, and 4 all claim multi-monitor and fractional-scale acceptance
criteria, and none of them can be exercised as the machine stands. The plugin's
most intricate existing code — `compute_geometry_on`, `live_geometry`, the
cross-monitor summon branch, and the `focus_window` ordering that stops
Hyprland migrating the special workspace mid-hide — is precisely the code that
only multi-monitor testing touches.

## Headless output

```bash
# create
hyprctl output create headless
hyprctl -j monitors | jq -r '.[] | "\(.name) \(.width)x\(.height) scale=\(.scale) at \(.x),\(.y)"'

# place it to the right of DP-1 with a fractional scale
hyprctl keyword monitor HEADLESS-2,1920x1080@60,3440x0,1.25

# stacked instead of side-by-side, which exercises the parked-y math
hyprctl keyword monitor HEADLESS-2,1920x1080@60,0x-1080,1.25

# remove
hyprctl output remove HEADLESS-2
```

Confirm the output name from `hyprctl monitors` rather than assuming
`HEADLESS-2`; the suffix depends on what else has been created in the session.

A headless output does not exercise real per-output rendering, scanout, or
scale filtering. So every acceptance claim must record which it was verified
on. "Verified on headless" is a real result for geometry, focus routing, and
workspace migration; it is weak evidence for sprite sharpness and glow
alignment, which need a second physical monitor or an honest note that they are
unverified.

Stacked geometry deserves its own pass. `compute_geometry_on` parks the window
at `monitor_y - (window_height + 60)`, and on a monitor placed above another
that parked position lands inside the neighbour's rectangle. `window_on_screen`
tests intersection against **any** monitor, so a parked window on a stacked
layout can report on-screen and take the hide branch instead of the recover
branch. Whether that misclassification is reachable in practice is unknown and
is worth deliberately trying to trigger.

## Fixture tests

Phase 0 chooses a self-contained Bash assertion runner because `bats` is not
installed on the development machine and the pure-function tests do not need a
framework. Run the fixture suite with:

```bash
bash tests/run.sh
```

The runner uses the checked-in fixtures and exported `hyprctl` stubs; it never
dispatches to the compositor or edits the user's configuration.
`jq`, `qmllint`, and `qmltestrunner` are already present. ShellCheck is also
absent and should be added to CI when available rather than treated as a current
local prerequisite.

```text
tests/
  fixtures/hyprland/
    clients-single.json          one dropdown client, visible
    clients-concurrent.json      unrelated window plus launched PID candidate
    clients-hidden.json          one dropdown client, parked off-screen
    clients-group.json           2-5 grouped clients (phase 4)
    clients-stacked-parked.json  parked client overlapping a stacked neighbour
    clients-legacy-ws.json       client on the pre-special workspace
    monitors-single.json         DP-1 only
    monitors-dual-scaled.json    DP-1 plus a 1.25-scale neighbour
    monitors-stacked.json        a monitor above another
    animations-omarchy.json      specialWorkspace overridden, borderangle disabled
  run.sh
```

Capture fixtures with `hyprctl clients -j`, `hyprctl monitors -j`, and
`hyprctl -j animations` in the state being captured, and commit them. Sanitize
window titles before committing — a captured title can contain a file path, a
hostname, or a command line.

Test only the pure functions. Good candidates, all of which are currently
untested and all of which have subtle input validation:

| Function | Why it is worth testing |
| --- | --- |
| `compute_geometry_on` | scale division, integer truncation, monitor-origin anchoring, the 4%/24px top margin floor |
| `live_geometry` | falls back correctly when the live query is unreadable |
| state read/write (0.3) | missing, empty, invalid, future-version, and stale-address documents |
| `read_special_animation` | must reject non-overridden, disabled, zero-speed, and empty-style nodes |
| `restore_special_animation` | must round-trip a saved tuple byte-for-byte |
| `repair_special_animation` | repairs a marker immediately after lock acquisition |
| launch client selection | only a new client from the launched process lineage is adopted |
| binding status | reports existing Ctrl + Grave conflicts and blocks silent duplicates |
| `lua_string` | control-character rejection, backslash and quote escaping |
| `window_on_screen` | intersection maths, and the deliberate "unreadable means on-screen" behavior |
| `workspace_selector` | numeric versus named workspaces |
| `is_private_dir` / `state_dir` | mode bits, symlink refusal, ownership |

Anything that dispatches to the compositor is an integration test. Those stay in
each phase's manual checklist; do not try to mock `hyprctl`, because the value
of those paths is entirely in the compositor's real asynchronous behavior, which
is what every comment in the helper is about.

## Manual checklist conventions

Each phase doc carries its own verification block. Two conventions across all
of them:

- **Run every check twice on a dual-output setup**: once with the dropdown's
  monitor focused, once with the other focused. Most of the helper's hardest
  bugs were in that difference.
- **Include a `SIGKILL` case wherever global state is touched.** The helper
  parks its animation snapshot on disk specifically because `SIGKILL` cannot be
  trapped, and `repair_special_animation` is the only thing that recovers it.
  Test it: `pkill -9 -f omarchy-dropdown-terminal` mid-summon, then confirm the
  next invocation restores `specialWorkspace` to `speed=3.00 style=slidevert`.

```bash
# baseline to compare against after any animation-touching change
hyprctl -j animations | jq -r '(.[0]//[])[] | select(.name=="specialWorkspace")
  | "\(.name) enabled=\(.enabled) overridden=\(.overridden) speed=\(.speed) style=\(.style)"'
# expected on Omarchy: specialWorkspace enabled=true overridden=true speed=3.00 style=slidevert
```

## Quickshell behavior probes

Several plan decisions rest on Quickshell semantics that are not documented in
the installed type info. Probing them is cheap: a throwaway `ShellRoot` with no
windows, run with `quickshell -p <file> -n`, prints to stdout and exits on
`Qt.quit()`. That is how the `FileView` reload behavior in the plan README was
established, and it is the right tool for the two open questions in phase 0:
which signal follows an async `reload()`, and whether `refreshToplevels()`
mutates or replaces `HyprlandToplevel` instances.

Keep such probes out of the repository. They are throwaway, they run against
the live session, and a committed one will eventually be run by someone who
does not realize it connects to their compositor.
