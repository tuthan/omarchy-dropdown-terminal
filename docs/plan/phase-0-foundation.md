# Phase 0: state, observability, and a testable environment

No user-visible feature ships in this phase. It exists because every later
phase needs to answer three questions cheaply and correctly — where is the
terminal, is it visible, is it focused — and because two of the mechanisms the
later phases assume are currently either broken or untestable on this machine.

Prerequisite for: all phases.

Design gate: [PD2, PD3, PD4, PD5, PD11, and PD12](../design-rules.md#phase-rule-gates).

## Goals

1. Fix the settings-staleness bug so the canonical-source design in
   `Service.qml` actually works.
2. Give QML a correct, cheap, event-driven view of terminal address, monitor,
   geometry, visibility, and focus, without spawning a process per sample.
3. Replace the plain-text `address` state file with a versioned JSON document
   that can hold multiple addresses later, with recovery and migration.
4. Add a lock-free helper `status` action for diagnostics and shell-side parity, not as QML's normal geometry source.
5. Make multi-monitor and fractional-scale behavior testable at all.

## Work items

### 0.1 Fix the FileView reload bug

`Service.qml:16-20` watches `~/.config/omarchy/shell.json` but never reloads
it, so `persistedSetting()` is frozen at plugin load. Add
`onFileChanged: reload()`.

The failure is worse than "sibling instances lag", because
`Service.setting()` prefers `persistedSetting()` over the injected `settings`
property. `Panel.persistSettings()` does write through to `shell.json` and does
assign `hostWidget.settings` locally, so the fresh value is present on the
panel's own instance — and is then shadowed by the stale file read. Once a key
exists in `shell.json` its value is pinned at plugin-load time for every
instance, the panel's included.

The subtlety that makes this more than a one-liner: `reload()` is asynchronous,
so any code reading `text()` in the same handler still sees the old content.
The readers here are the `readonly property` bindings on lines 41-47, which are
computed from `setting()` → `persistedSetting()` → `text()`. Those bindings do
not re-evaluate when the file content changes, because `text()` is a function
call and `__text` changing does not invalidate them reliably.

Introduce an explicit revision counter that the bindings depend on:

- `property int configRevision: 0`
- `onFileChanged: reload()` on the `FileView`
- `onTextChanged: configRevision++` (or `onLoaded`, whichever the type emits
  after an async reload completes — verify both, `textChanged` is listed in the
  type and is the more precise signal)
- every `readonly property` that calls `setting()` gains a
  `configRevision, ` reference so the binding is dirtied
- the first event in a rapid settings-edit burst arms a bounded 1 Hz settle
  timer for a few reloads, then stops it; this catches the final value if the
  watch dies during successive slider/file writes without polling forever

Verify by editing `widthPercent` in `shell.json` by hand and confirming the next
summon uses the new width with no shell restart. This is the acceptance test
that the whole per-monitor settings design has never actually passed.

### 0.2 Move Hyprland observation into QML

Add to `Service.qml` a small observed-state block, replacing any need to shell
out for geometry:

- `readonly property var trackedToplevel` — the entry in `Hyprland.toplevels`
  whose `address` matches the tracked address.
- `readonly property bool terminalVisible` — true when any
  `Hyprland.monitors[i].lastIpcObject.specialWorkspace.name` equals
  `special:dropdown-terminal`.
- `readonly property bool terminalFocused` — `Hyprland.activeToplevel` address
  equals the tracked address.
- `readonly property rect terminalRect` — from
  `trackedToplevel.lastIpcObject.at` and `.size`.
- `readonly property var terminalMonitor` — the `Hyprland.monitors` entry whose
  `id` matches `trackedToplevel.monitor`, for `scale`, `x`, `y`.

Refresh policy, driven by `Hyprland.rawEvent` following the idiom in
`plugins/bar/widgets/KeyboardLayout.qml:85-101`:

| `event.name` | Action |
| --- | --- |
| `activespecial`, `activespecialv2` | `refreshMonitors()` |
| `focusedmon`, `focusedmonv2` | `refreshMonitors()` |
| `activewindow`, `activewindowv2` | nothing; `activeToplevel` already tracks it |
| `openwindow` | `refreshToplevels()` when the tracked address is unset |
| `closewindow` | `refreshToplevels()`; clear tracked address if it matches |
| `movewindow`, `movewindowv2` | `refreshToplevels()` |
| `configreloaded` | `refreshMonitors()`; a reload clears runtime animation overrides |

`Component.onCompleted` must call all three refreshes once, because the event
stream only describes changes after subscription — the research doc is right
about this and it applies to the Quickshell model too.

Hyprland emits **no** event for each coordinate of a floating move or resize, so
a manual drag or resize by the user leaves `terminalRect` stale. Do not fix this
with a general poll. Phases 1 and 3 own a bounded poll that runs only while an
overlay is on screen; outside those windows a stale rect has no consumer.

### 0.3 Versioned runtime state

Replace `$state_root/address` with `$state_root/io.github.tuthan.dropdown-terminal.state.json`:

```json
{
  "version": 1,
  "clients": ["0x..."],
  "active": "0x...",
  "updatedAt": 1757000000
}
```

Phase 0 only ever writes a single-element `clients` array; the shape exists so
Phase 4 does not have to migrate again.

Requirements:

- Atomic write: `mktemp` in `$state_root`, write, `mv`. Never truncate in place;
  a reader can be mid-read.
- Read path tolerates a missing file, invalid JSON, a future `version`, and a
  `clients` array whose entries no longer exist. Each case falls back to the
  existing recovery scan, which is what actually makes the current design
  self-healing.
- Migration: if the legacy `address` file exists and the new file does not, read
  it, write the new document, and unlink the legacy file. Keep this branch for
  at least one release, then delete it — note the removal in the changelog.
- Preserve the two-step recovery already in
  `bin/omarchy-dropdown-terminal:559-568`: first any client on
  `special:dropdown-terminal`, then any client on the legacy workspace names.
  A multi-address model must scan for *all* matches, not `head -n 1`, or Phase 4
  loses tabs on every shell restart.

Rename `special-animation` to
`io.github.tuthan.dropdown-terminal.special-animation` at the same time, for the
prefix rule in the plan README. `repair_special_animation` must check the old
name too for one release, or an in-flight suppression from a pre-upgrade run is
never repaired and the user's `specialWorkspace` animation stays flattened.

### 0.4 Lock-free `status` action

Add `status` to the action whitelist at `bin/omarchy-dropdown-terminal:14`,
emitting one JSON object on stdout: `version`, `clients`, `active`, `monitor`,
`visible`, `focused`, `x`, `y`, `width`, `height`. These duplicate facts QML
can already observe; the action exists for debugging and non-QML consumers,
not as a visual polling API.

Three hard constraints:

- **It must not take the lock.** The `flock -w 3` path would serialize a status
  query behind an in-flight animation and stall the caller for up to three
  seconds; the `flock -n` path would return nothing when the lock is held. Move
  the `exec 9>` / `flock` block so `status` returns before it, or gate it on
  `$action`.
- **It must not launch a terminal.** The fall-through path at the bottom of the
  script launches one when no client is found. `status` joins `hide` and
  `cleanup` in the early-exit guard at line 600, printing an empty document.
- **It must not repair.** `repair_special_animation` runs unconditionally at
  line 553. A polled status action must not perform compositor writes; move the
  repair call so it is skipped for `status`.

With 0.2 in place, QML should not need this action at all in the normal path.
It exists for the shell-side integration in Phase 2, for debugging, and as the
answer to "what does the helper think is true" when QML and the helper disagree.

### 0.5 Debug logging

One environment variable, `YADTM_DEBUG=1`, enables `printf ... >&2` tracing in
the helper and `console.log` in QML. Log actions, addresses, geometry, lock
acquisition and rejection, and animation snapshot/restore pairs. Never log
command strings, even in Phase 2, even when debugging is on — the setting that
opts into command text is separate and does not exist yet.

### 0.6 Make the untestable testable

Two facilities, both documented in `docs/plan/testing.md` as part of this phase:

**A second output.** `hyprctl output create headless` adds a virtual monitor;
set a fractional scale on it and the multi-monitor and scaling criteria in
Phases 1, 3, and 4 become real tests. Document the create, the scale command,
and the removal command. Every phase that claims a multi-monitor acceptance
criterion must state whether it was verified on real hardware or on a headless
output, because the headless path does not exercise real per-output rendering.

**Fixture-driven helper tests.** Capture `hyprctl clients -j` and
`hyprctl monitors -j` into `tests/fixtures/hyprland/` and test the pure
functions — geometry computation, state parsing and recovery, animation tuple
round-tripping, `lua_string` escaping — against them. There is no test harness
in this repository today, so this item includes choosing one; `bats` is the
conventional choice for bash and is packaged. Keep it to the pure functions:
anything that dispatches to the compositor is an integration test and belongs in
the manual checklist, not the suite.

**Stacked-monitor parking regression.** `compute_geometry_on` parks a window at
`monitor_y - (window_height + 60)`. When another monitor is stacked above, that
rectangle can fall inside the neighbour and `window_on_screen` currently
reports true because it tests intersection with any monitor. Deliberately
reproduce this layout. The eventual classification must use the intended owner
monitor plus special-workspace/park state, not any-output intersection, so a
parked window takes the recovery branch rather than being hidden again.

### 0.7 Bring existing external mutations under PD5

The existing direct-binding and special-fallthrough helpers modify files outside
the plugin directory. Before new settings/actions copy those patterns, make the
current UX comply with the project [external mutation inventory](../design-rules.md#external-mutation-inventory):

- right-clicking the bar icon must not write `~/.config/hypr/bindings.lua`
  immediately; open a native confirmation/preflight that shows the exact chord,
  target file, effect, backup, and removal path, with Cancel selected
- toggling `allowSpecialFallthrough` must show the exact
  `~/.config/hypr/input.lua` managed block and explain the pointer-focus effect
  before enabling; disabling/removal names only that block
- add/read back `status` for both helpers so the panel reports installed,
  unavailable, or unsupported instead of inferring success from process exit
- held Enter/Space cannot open and accept a confirmation in one gesture; no
  letter key performs either mutation
- preserve the existing backup, atomic replacement, reload, and config-error
  checks, and add idempotent remove where missing

### 0.8 Fix the helper defects found by review

Four latent defects in `bin/omarchy-dropdown-terminal`, documented with failure
modes and fixes in [`../known-issues.md`](../known-issues.md). They belong in
phase 0 because every later phase adds actions behind the same lock, which makes
the first one easier to hit, not harder.

| Issue | Defect | Priority |
|---|---|---|
| #1 | `wait_window_y` compares a microsecond deadline against a seconds clock, so its timeout can never fire | **Fix first** |
| #3 | A terminal that maps after the 4-second launch budget is orphaned, and the next toggle launches another | Fix in this phase |
| #4 | A failed lock-file open is indistinguishable from a held lock, so the hotkey becomes a permanent silent no-op | Fix in this phase |
| #5 | Monitor name interpolated into a `jq` program instead of passed with `--arg` | Fix opportunistically |

Issue #1 is the one that matters. Because the only exit condition is the window
reaching its target position, a window that never arrives — closed mid-poll,
dragged by the user, pinned by a window rule, or clamped by the compositor —
leaves the helper spinning at roughly 100 process spawns a second, holding the
lock, with `specialWorkspace` left suppressed for the rest of the session and
the on-disk repair path unreachable behind the lock it holds. Every subsequent
toggle exits 0 silently.

Fix it by comparing like units *and* adding a second exit condition, so a
vanished window stops the wait rather than merely bounding it:

```bash
local attempts=$(awk -v t="$timeout" 'BEGIN { printf "%d", (t / 0.02) + 1 }')
for ((i = 0; i < attempts; i++)); do
  client_exists "$address" || return 1
  ...
  sleep 0.02
done
return 1
```

Add a regression test for each in the fixture suite from 0.6 where the defect is
in a pure function (#5 is; #1's arithmetic is), and a manual case where it is
not (#3, #4).

## Verification

```
# 0.1 — settings staleness
jq '.bar.layout' ~/.config/omarchy/shell.json   # note widthPercent
# edit widthPercent by hand, then summon; width must change with no restart

# 0.3 — state migration and recovery
rm -f "$XDG_RUNTIME_DIR"/io.github.tuthan.dropdown-terminal.state.json
printf '0xdeadbeef\n' > "$XDG_RUNTIME_DIR/address"     # stale legacy file
# summon: must recover by scanning, rewrite valid JSON, not launch a second terminal
echo 'not json' > "$XDG_RUNTIME_DIR"/io.github.tuthan.dropdown-terminal.state.json
# summon: must recover, not die

# 0.4 — status is lock-free and inert
bash bin/omarchy-dropdown-terminal status | jq .
# while a summon animation is in flight, status must return immediately
# with no terminal running at all, status must print an empty document and exit 0

# 0.6 — second output
hyprctl output create headless
hyprctl keyword monitor HEADLESS-2,1920x1080@60,3440x0,1.25
hyprctl -j monitors | jq -r '.[] | "\(.name) scale=\(.scale)"'
```

## Acceptance criteria

- A setting edited in `shell.json` takes effect on the next summon, on every
  monitor instance, with no shell restart.
- After a shell reload, a monitor hotplug, an interrupted toggle, a corrupt
  state file, and a stale state file, the reported address, monitor, geometry,
  visible, and focused values are all correct.
- A `status` query never blocks on the lock, never launches a terminal, and
  never writes compositor state.
- Legacy `address` and `special-animation` files are migrated and repaired.
- No mutation path can hold the lock without a bound: a window that closes,
  is dragged, or never reaches its target ends the wait, and a `SIGKILL`ed run
  is repaired by the next invocation ([known-issues.md](../known-issues.md) #1).
- A failed lock acquisition is distinguishable from a duplicate press, and the
  failing case says so rather than exiting silently.
- The fixture test suite runs from a single command and passes.
- A headless second output with a fractional scale can be created and removed
  from documented commands.
- A parked window that overlaps a vertically stacked neighbour is still
  classified as parked for its owner and takes the recovery path.
- Binding and special-fallthrough changes show exact cancel-first preflight,
  report read-back status, and can be removed without touching unrelated config.

## Out of scope

- Any overlay surface, sprite, IPC handler, or shell hook.
- Multi-client state beyond the array shape.
- Fixing the missing per-coordinate move/resize events; consumers arrive in
  Phase 1.

## Implementation verification record

- `bash tests/run.sh` passes the checked-in fixture suite (44 checks), covering
  fractional geometry, state migration/recovery, multi-client recovery,
  stacked parking, animation tuple parsing and immediate repair, escaping,
  bounded waits, launch-process association and late markers, Quickshell model
  accessors, raw close-event normalization, status lock independence,
  idempotent fallthrough mutation, binding-conflict reporting, and both
  config-helper read-back/removal paths.
- `qmllint Service.qml Panel.qml BarWidget.qml`, `bash -n` on all helpers, and
  `git diff --check` pass.
- The live `status` actions return valid JSON without a tracked client. The
  machine still has one physical output at scale 1; no headless output was left
  attached, so compositor summon/drag and real multi-output rendering remain
  manual checks using the create/scale/remove commands above.

## Open questions

- Which signal fires after an async `FileView.reload()` in 0.3.1 —
  `textChanged`, `loaded`, or both? Verified empirically that the value is
  visible on the next event-loop pass; the exact signal still needs to be
  pinned before 0.1 is written, because the revision counter hangs off it.
- Does `Hyprland.refreshToplevels()` update `lastIpcObject` on existing
  `HyprlandToplevel` instances, or replace the objects? If it replaces them, any
  property bound to `trackedToplevel` needs to survive the swap.
