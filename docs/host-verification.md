# Host verification

**Scope: this project.** Evidence that the shared
[host constraints](../../plugin-docs/rules/omarchy-plugin-design.md#omarchyquickshell-host-constraints)
hold on this host, at these versions, plus host facts not yet upstream.

The shared document states the constraints normatively; it carries no evidence,
because evidence is environment-specific. This file is that evidence. Nothing
here restates a constraint as a rule — where a row supports one, the constraint
number is named.

Verified 2026-09-04 against Omarchy 4.0.2, Hyprland 0.56.2, Quickshell 0.3.1,
foot 1.27.0, Alacritty 0.17.0, tmux 3.7c, bash with starship active. Re-verify
when any of those change; every experiment below is cheap and reproducible.

## Environment baseline

| Fact | Value | Relied on by |
|---|---|---|
| Omarchy | 4.0.2 (`ID=omarchy`) | all phases |
| Hyprland | 0.56.2 | all phases |
| Quickshell | 0.3.1 (Arch) | all phases |
| foot / Alacritty / tmux | 1.27.0 / 0.17.0 / 3.7c | phases 2, 4 |
| Monitors | one: `DP-1` 3440x1440, scale 1, at 0,0 | phases 0, 1, 3 |
| Default shell | bash, starship active | phase 2 |
| `bash-preexec` | 0.6.0-1 in `extra` | phase 2 |
| `specialWorkspace` animation | `enabled=true overridden=true speed=3.00 style=slidevert` | phases 0, 1 |
| `borderangle` animation | `enabled=false overridden=true` | phase 1 |
| `hyprctl output` | present, so `output create headless` is available | phase 0 |
| Local test tools | `jq`, `qmllint`, `qmltestrunner` present; Bats and ShellCheck **absent** | phase 0 |

**One monitor at scale 1.** Every multi-monitor and fractional-scale acceptance
criterion in the plan is unverifiable as this machine stands, which is why
PD4 requires each phase report to say whether an output test was physical or
headless.

## Evidence per shared constraint

### Constraint 3 — FileView notifies but does not reload

Tested three write paths against a watched file, with a `Timer` logging `text()`
and a `Process` performing the write:

| Write path | `fileChanged` emitted | `text()` updates |
|---|---|---|
| in-place truncate (`printf > f`) | yes | **no** |
| atomic replace (`mktemp` + `mv`) | yes | **no** |
| through the same FileView (`setText`) | yes | yes |

So an external writer never updates a reader's cache, however it writes. Adding
`onFileChanged: reload()` made the new value appear on the **next event-loop
pass**, not inside the handler — `reload()` is asynchronous.

A further detail not in the shared constraint: a property binding that calls
`text()` is not dirtied when the content changes, so bindings need an explicit
revision counter incremented from the reload signal.

Reproduce with a `ShellRoot` containing a watched `FileView`, a logging `Timer`,
and a rewriting `Process`, run as `quickshell -p <file> -n`. Keep such probes
out of the repository — they run against the live compositor.

Related: the Omarchy shell documents at `plugins/bar/Bar.qml:950-953` that a
watch can *permanently* stop delivering events under rapid writes, and repairs
it with an explicit nudge — the basis for the bounded re-probe the constraint
requires.

This constraint is violated in the current code; see
[known-issues.md](known-issues.md) #2.

### Constraint 2 — one instance per screen, no singleton IpcHandler

`plugins/bar/Bar.qml` is loaded once and instantiates `BarPanel` via
`Variants { model: Quickshell.screens }`; its comment at line 469 states that "a
widget that appears once in the layout is still live once per screen."

`shell.qml:421-425` states the consequence directly: "a fixed IPC target only
ever routes to one of the per-monitor instances."

Omarchy's own workarounds, neither available to a plugin entry point:
`Bar.qml:955` places its `IpcHandler` above the `Variants`, and
`Ui/Panel.qml:48-57` carries a `manageIpc` flag so exactly one instance
registers a shared target.

### Constraint 4 — hyprctl eval does not return query values

`hyprctl eval 'return 1+1'` prints the literal `ok`. So does
`hyprctl eval 'return type(hl.dsp.group)'`. Queries must use `hyprctl -j` or the
Quickshell Hyprland model.

### Constraint 5 — enum options are display labels and stored values

Confirmed against installed third-party plugins: `options` is a flat array of
strings such as `["Meters","CPU","Pulse","Custom"]`, and the selected string is
what persists. There is no slug layer.

### Constraint 6 — manifest settings cannot hide controls conditionally

The manifest schema vocabulary across installed plugins is exactly `key`,
`type`, `label`, `description`, `defaultValue`, `min`, `max`, `step`, `options`,
with `type` one of `boolean`, `integer`, `string`, `enum`. No visibility field
exists.

This plugin's `Panel.qml` is hand-built from `qs.Ui` primitives rather than
schema-driven, so conditional presentation is possible there — and every setting
must be added in both places.

### Constraint 7 — do not claim gating from `package` / `minimumVersion`

Both fields appear in an installed third-party manifest. Neither string occurs
anywhere in `/usr/share/omarchy/shell` or `/usr/share/omarchy/bin`, so nothing
consumes them. Dependencies must be checked at runtime.

### Constraint 8 — plugin paths disappear on uninstall

Plugins live at `~/.config/omarchy/plugins/<id>/`. Reinstalling renames the
previous copy to `.<id>.bak.<timestamp>` — several such directories are present
on this host — so the path is stable across updates and gone after an
uninstall.

## Host facts not yet in the shared document

Candidates for promotion upstream, or to stay local where noted. Promote only
deliberately; the shared document is product-neutral.

### Quickshell.Hyprland type inventory in 0.3.1 — promote

Enough is exposed that shelling out from QML is usually unnecessary:

- `Hyprland`: `toplevels`, `monitors`, `workspaces`, `activeToplevel`,
  `focusedMonitor`, `focusedWorkspace`, `usingLua`, `rawEvent(event)`,
  `dispatch()`, `refreshMonitors()`, `refreshWorkspaces()`, `refreshToplevels()`
- `HyprlandToplevel`: `address`, `handle`, `wayland`, `title`, `activated`,
  `urgent`, `workspace`, `monitor`, `lastIpcObject`
- `HyprlandMonitor`: `id`, `name`, `description`, `x`, `y`, `width`, `height`,
  `scale`, `focused`, `activeWorkspace`, `lastIpcObject`
- `HyprlandWorkspace`: `id`, `name`, `active`, `focused`, `urgent`

`lastIpcObject` is the raw `hyprctl clients` / `monitors` record, so `at`,
`size`, `floating`, `grouped`, and `specialWorkspace` are reachable without a
process spawn — but only as fresh as the last refresh, so pair it with
`rawEvent`.

There is **no** `specialWorkspace` property on `HyprlandMonitor`;
special-workspace visibility comes from `lastIpcObject.specialWorkspace.name`
after `refreshMonitors()`.

`HyprlandToplevel.urgent` and `HyprlandWorkspace.urgent` are first-class, which
is what makes a terminal's own bell a zero-integration signal in phase 2.

Established `rawEvent` idioms: `plugins/bar/widgets/KeyboardLayout.qml:85-101`
and `plugins/services/idle/Service.qml:145-155`.

Event streams describe only changes after subscription, so probe once at
`Component.onCompleted` as well as handling events.

### No event per coordinate of a floating move or resize — promote

Hyprland emits `movewindow` and friends but not a coordinate stream while a
floating window is dragged or resized. A consumer needing a live rectangle needs
a bounded poll for exactly as long as it cares; `refreshToplevels()` is a socket
round trip and is affordable at a few hertz, unlike spawning `hyprctl` + `jq`.

### Animation nodes are global and some ship disabled — promote

`hyprctl -j animations` reports `enabled`, `overridden`, `speed`, `bezier`,
`style` per node. Only an already-`overridden` node can be restored losslessly:
an inherited node reports placeholder values that cannot be written back without
turning it into an override, and the runtime API cannot un-override a node once
written. Any `hyprctl reload` clears a runtime override regardless of who set
it.

On this host `specialWorkspace` is overridden and enabled, while `borderangle`
is overridden and **disabled** — which is why the compositor-side glow option
was dropped from the plan rather than treated as the cheap one.

A looping angle animation forces continuous rendering at the monitor refresh
rate.

### Monitor coordinates are physical; Quickshell's are logical — promote

`hyprctl monitors` reports `width`/`height` in physical pixels with a separate
`scale`, and `x`/`y` as global desktop coordinates. Quickshell's `screen` is
logical. Integer-dividing one by the other truncates, so a surface positioned
from those integers can be off by up to a pixel per axis at fractional scale.

### Headless outputs — promote

```bash
hyprctl output create headless
hyprctl -j monitors | jq -r '.[] | "\(.name) \(.width)x\(.height) scale=\(.scale) at \(.x),\(.y)"'
hyprctl keyword monitor HEADLESS-2,1920x1080@60,3440x0,1.25   # confirm the name first
hyprctl output remove HEADLESS-2
```

Faithful for geometry, focus routing, and workspace migration. Not faithful for
per-output rendering, scanout, or scale filtering, so it is weak evidence for
anything visual — which is the distinction PD4 requires each phase to record.

### Omarchy bash startup ordering — promote

`~/.bashrc` sources `$OMARCHY_PATH/default/bash/rc`, which sources a fixed list
ending in `default/bash/init`, which runs `eval "$(starship init bash)"` when
starship is present. The `source` line sits **above** the "add your own"
section, so anything appended to `~/.bashrc` registers *after* starship. There
is no user drop-in directory.

For a prompt hook this is decisive: it must insert itself at the **front** of
the `PROMPT_COMMAND` array and capture `$?` as its first statement, or
starship's precmd runs first and the exit status is gone.

### shell.json is written through Omarchy's own FileView — promote

`shell.qml:108-113` — `persistShellConfig` calls `userConfigFile.setText(...)`.
That keeps Omarchy's cache correct, and is why a plugin holding a *separate*
`FileView` on the same path sees nothing without `reload()`. This combination is
the most likely way a plugin silently reads frozen settings.

### omarchy-shell costs ~47 ms per call — keep local

Five sequential `omarchy-shell -q shell ping` calls took 0.235 s wall, so ~47 ms
each. Fine for a user action; not fine on a per-prompt or per-keystroke path.
Hardware-dependent, so it stays project evidence rather than a shared claim —
but the *rule* it supports (never fork on an interactive path) is already
PD11.
