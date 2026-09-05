# Known issues

**Scope: this project.** Defects found by reading the code against the platform
behavior in [host-verification.md](host-verification.md), on 2026-09-04. None were
reported by a user; all are latent. Ordered by severity.

Each entry records what is wrong, how it fails, how it was confirmed, and which
rule it violates — a `PD` rule from the shared
[design rules](../../plugin-docs/rules/omarchy-plugin-design.md), a numbered
[host constraint](../../plugin-docs/rules/omarchy-plugin-design.md#omarchyquickshell-host-constraints),
or a project [architecture invariant](architecture-invariants.md).

Phase 0 implementation status: issues 1, 3, 4, and 5 are addressed in
`bin/omarchy-dropdown-terminal`; issue 2 is addressed by the revision-driven
`FileView` reload in `Service.qml`. The entries below remain as the failure-mode
record and regression-test rationale for future changes.

## 1. `wait_window_y` can never time out

`bin/omarchy-dropdown-terminal:249-264`

The deadline is computed in **microseconds** and compared against a value in
**seconds** — off by a factor of 10^6, so the comparison is never true and the
timeout never fires.

```bash
deadline="$(awk -v n="${EPOCHREALTIME:-0}" -v t="$timeout" \
  'BEGIN { printf "%.0f", n * 1000000 + t * 1000000 }')"   # microseconds
...
now="${EPOCHREALTIME%%.*}"                                 # seconds
(( now >= deadline )) && return 1
```

Confirmed by running the same arithmetic directly: with `timeout=0.65`,
`deadline=1788512474479123` and `now=1788512473`. The ratio is exactly
1,000,000.

**How it fails.** The function is the only exit condition for a `while :` loop
that polls the window's `y` every 20 ms. It therefore returns only when the
window actually reaches the target position. If it never does, the loop spins
forever, spawning `hyprctl` **and** `jq` per iteration — roughly 100 processes a
second, indefinitely.

The consequences compound, because the stuck run holds the lock and has armed
the animation restore on `EXIT`:

- Every later `toggle` hits `flock -n` and **exits 0 silently**. The hotkey
  becomes a complete no-op with no error anywhere.
- `hide` and `cleanup` give up after `flock -w 3`.
- `specialWorkspace` stays suppressed at `speed=0.1` for the rest of the
  session, so Omarchy's own `SUPER+S` scratchpad loses its animation too.
- The on-disk repair marker cannot help: `repair_special_animation` runs *after*
  the lock is taken, so no new invocation ever reaches it.

**How to reach it.** Any state where the window does not arrive at the target:

- the tracked client closes during the poll — `y` becomes empty and the loop
  continues (a plain `exit` in the terminal races with auto-hide)
- the user drags or resizes the window mid-animation
- a user window rule pins the position or size of the terminal's class, so the
  move is ignored
- Hyprland clamps the parked position, which the `reveal_parked` comment says it
  does for windows whose centre falls outside the monitor — the hide path moves
  the window to exactly such a position

**Fix.** Compare like units, and add a second exit condition. Either compute
both sides in microseconds, or drop the float arithmetic entirely and bound the
loop by iteration count, which is what the 20 ms sleep already implies:

```bash
local attempts=$(awk -v t="$timeout" 'BEGIN { printf "%d", (t / 0.02) + 1 }')
for ((i = 0; i < attempts; i++)); do
  client_exists "$address" || return 1     # window vanished: stop waiting
  ...
  sleep 0.02
done
return 1
```

The `client_exists` check matters independently: without it, a closed window is
still a spin, just a bounded one.

**Violates.** PD11 (an operation with no bounded lifecycle), PD12 (a user
gesture that silently causes no mutation), PD3 (a failure that presents as
nothing rather than as a visible state), and invariants
[A4](architecture-invariants.md#a4-every-helper-action-declares-its-lock-mode)
and [A7](architecture-invariants.md#a7-global-compositor-state-is-snapshotted-parked-restored-and-repairable)
— the repair path sits behind the lock the wedged run holds, so it can never
run.

**Priority.** Fix in Phase 0. Every later phase adds actions behind the same
lock, so the wedge gets easier to hit, not harder.

## 2. Settings are frozen at plugin load

`Service.qml:16-20`

`shellConfigFile` sets `watchChanges: true` with no `onFileChanged: reload()`,
so `shellConfigFile.text()` returns the file content from load time forever.

Because `setting()` (`Service.qml:180-185`) prefers `persistedSetting()` over
the injected `settings` property, the stale file value **shadows** the fresh
value. `Panel.persistSettings()` does write through to `shell.json` and does
assign `hostWidget.settings` locally — its comment at `Panel.qml:51-54` explains
why — and that fresh value is then discarded by the stale read.

**Symptom.** The settings panel shows the new value, and the terminal keeps
using the old one. Change the width to 60%: the panel reads 60, and the next
summon is still the previous width. It stays that way until the Omarchy shell
restarts. A key that has never appeared in `shell.json` works once, because
`persistedSetting()` returns `undefined` and the injected value wins — then it
freezes on the next reload.

**Confirmed.** Empirically, with a throwaway Quickshell config: after an
external write, `text()` returned the stale value on every subsequent read;
adding `onFileChanged: reload()` made the new value appear on the next
event-loop pass. Both an in-place truncate and an atomic `mktemp`+`mv` replace
behave the same way, so how Omarchy writes the file is irrelevant — and Omarchy
writes it through its *own* `FileView` (`shell.qml:108-113`), which is why its
cache stays correct and this went unnoticed.

**Fix.** `onFileChanged: reload()`, plus a revision counter for the bindings —
`reload()` is async, so reading `text()` inside the handler still returns the
old content, and a binding over `text()` is not dirtied by the content
changing. Detailed in [plan/phase-0-foundation.md](plan/phase-0-foundation.md)
item 0.1.

**Violates.** Host constraint 3, and PD2 — a presentation cache is acting as
the settings authority.

## 3. A slow terminal launch orphans the window

`bin/omarchy-dropdown-terminal:610-640`

First launch polls for a new client 40 times at 0.1 s — a 4 second budget — then
`exit 0`. A terminal that maps later is never moved to the special workspace and
its address is never recorded.

**How it fails.** The window stays on the user's current workspace as an
ordinary floating terminal. The next toggle finds no client on
`special:dropdown-terminal` and no legacy match, so it **launches another one**.
Repeat and the workspace accumulates orphans.

**How to reach it.** A cold start under load, a heavier emulator than foot, or a
first run that has to build a font cache. Not reachable on this machine with a
warm foot, which is why it has not been seen.

**Fix.** Either extend the budget and keep polling while the launcher process is
still alive, or record a launch-in-progress marker so the next toggle adopts the
window instead of spawning a second one. The second is better: it also handles
the case where the terminal maps after the script has exited.

**Violates.** PD3 (a timeout becomes silence rather than a visible state) and
invariant [A8](architecture-invariants.md#a8-local-state-is-a-cache-the-compositor-is-the-truth)
— recovery does not consider a window the plugin created but never adopted.

## 4. A failed lock-file open makes the hotkey a silent no-op

`bin/omarchy-dropdown-terminal:98-102`

```bash
exec 9>"$state_root/io.github.tuthan.dropdown-terminal.lock" 2>/dev/null || true
if [[ "$action" == "toggle" ]]; then
  flock -n 9 || exit 0
```

If the redirect fails, `|| true` swallows it and `flock -n 9` then fails on a
bad file descriptor, which is indistinguishable from "another instance holds the
lock" — so the toggle exits 0 and nothing happens, forever, with no output.

`state_dir()` already `die`s on an unusable state directory, so this needs
something narrower: a read-only filesystem, a descriptor limit, or SELinux. Low
probability, but the failure is invisible and permanent.

**Fix.** Distinguish the two cases. Verify the descriptor opened before treating
a `flock` failure as a duplicate press, and `die` with a message if it did not.

**Violates.** PD12 (one gesture must cause one mutation, and a failed gesture
must not be indistinguishable from a duplicate) and PD3.

## 5. Monitor name is interpolated into a jq program

`bin/omarchy-dropdown-terminal:264-271`

```bash
filter="select(.name == \"$target\")"
mon_json="$(hyprctl monitors -j | jq -c ".[] | $filter" | head -n 1)"
```

`$target` comes from `hyprctl`, so this is not a live injection path, but it is
string interpolation into a program where `--arg` exists and is already used
everywhere else in the file. A monitor description containing a quote would
produce a jq syntax error and an empty geometry rather than a clear failure.

**Fix.** `jq --arg target "$target" '.[] | select(.name == $target)'`, and
select the numeric-id branch with `--argjson`.

**Violates.** PD3 — a malformed monitor description yields empty geometry
rather than a visible failure. The file's own convention is `--arg` everywhere
else.

## Not bugs, but worth knowing

- **Stacked monitors and the parked position.** `compute_geometry_on` parks the
  window at `monitor_y - (window_height + 60)`. On a monitor placed *below*
  another, that position lands inside the neighbour's rectangle, and
  `window_on_screen` tests intersection against **any** monitor — so a parked
  window could report on-screen and take the hide branch instead of the recover
  branch. Whether it is reachable in practice is untested; see
  [plan/testing.md](plan/testing.md).
- **`borderangle` ships disabled** on Omarchy (`enabled=false overridden=true`),
  which is why the compositor-side glow option was dropped from the plan rather
  than treated as the cheap one.
