# Architecture invariants

**Scope: this project.** Engineering invariants for the dropdown terminal that
are *not* covered by the shared design rules, recorded here so a new feature
cannot violate one in a file that carries none of the explanatory comments.

## Where each kind of rule lives

| Kind of rule | Where it lives | Authority |
|---|---|---|
| Product, UI, interaction, safety, theme, motion (PD1–PD12) | [`plugin-docs/rules/omarchy-plugin-design.md`](../../plugin-docs/rules/omarchy-plugin-design.md) | Generic, normative, shared across plugins |
| Host constraints of Omarchy/Quickshell/Hyprland | Same document, "Omarchy/Quickshell host constraints" | Generic, normative |
| How this plugin adopts those rules, its authorities, mutations, and exceptions | [`design-rules.md`](design-rules.md) | Project profile; binding for [`plan/`](plan/README.md) |
| Evidence that the host constraints hold on this host, at these versions | [`host-verification.md`](host-verification.md) | Project evidence log |
| Engineering invariants specific to *this* plugin's architecture | This file | Project |
| Defects found against all of the above | [`known-issues.md`](known-issues.md) | Project |

Nothing normative is restated here. Where an invariant exists to satisfy a
shared rule, the rule ID is named rather than paraphrased — the shared rule wins
over any wording in this file.

---

## A1. The user's configured terminal is never replaced

The plugin launches through `omarchy launch terminal` so `xdg-terminal-exec`
selects the configured emulator. No feature may require foot, Alacritty, kitty,
or Ghostty, or depend on any emulator's private tab, split, or IPC API.

This is the invariant that decided the tabs design — compositor-native groups or
a multiplexer, never an emulator's own tab model — and it is why command status
needs shell integration: the plugin cannot read the terminal's PTY.

Serves PD4 (record unsupported terminals rather than assuming one).

**Violation smell.** A code path that reads a terminal's config, sends it an
escape sequence expecting a private response, or branches on window class to
decide a capability.

## A2. One named special workspace, membership by tracked address only

`special:dropdown-terminal` is owned by the helper. Managed clients are tracked
by explicit address. A client is never selected by window class, title, or PID
alone — a class match would adopt the user's other terminals.

Windows that inherit the workspace by being launched *from* the dropdown are
returned to the focused workspace, never absorbed into the managed set.

Serves PD2 (managed membership has one authority) and PD12 (one gesture, one
mutation).

**Violation smell.** `select(.class == …)` anywhere in a membership decision.
Recovery that adopts the first client on the workspace when the model holds
several.

## A3. The helper mutates the compositor; QML observes and renders

The split is deliberate: the helper holds the lock, dispatches window and
workspace changes, and owns geometry authority; QML observes state, decides
presentation, and renders. QML does not dispatch window management. The helper
owns nothing the user looks at.

A feature needing both belongs on both sides of the line, not in whichever file
was easier to edit.

Serves PD2 (one writer per state domain).

**Violation smell.** `Hyprland.dispatch()` in QML for anything the helper
already owns. Presentation logic in the helper. A QML component that reads the
helper's state file to decide what to draw when the compositor already knows.

## A4. Every helper action declares its lock mode

One lock guards all mutation. Each action is classified explicitly, and the
classification is a comment next to the action, not folklore:

| Action | Lock mode | Rationale |
|---|---|---|
| `toggle` | `flock -n`, drop | One keypress arrives once per screen; extras are duplicates |
| `hide` | `flock -w`, queue | Reconciliation; must not be lost |
| `cleanup` | `flock -w`, queue | Reconciliation |
| `status` | **no lock** | A query must never block behind a mutation, and must never mutate |
| `new-tab` | `flock -n`, drop | Otherwise one keypress creates N terminals |
| `next-tab` / `previous-tab` / `close-tab` | `flock -n`, drop | User-initiated; duplicates are not intent |

Serves PD12 and host constraint 2.

**Violation smell.** A new action added to the whitelist without touching the
lock comment. Any query on a lock path. A mutation path that can hold the lock
without a bound — see [known-issues.md](known-issues.md) #1 for what that costs.

## A5. Geometry anchors to a named monitor, never to the desktop

Never to `(0,0)`, and never to "the focused monitor" when the window lives
elsewhere. Summon anchors to the focused monitor; hide anchors to the monitor the
window is actually on. Guessing wrong lets Hyprland migrate the special
workspace mid-animation and visibly re-centre the window on the wrong screen.

Quickshell surfaces are positioned from Quickshell's logical values, not from
the helper's truncated physical-divided-by-scale integers.

Serves PD10 (logical coordinates and fractional scaling).

**Violation smell.** A coordinate computed without a monitor origin. A surface
sized from `hyprctl monitors` integers.

## A6. Reconciliation actions never create a terminal

`hide`, `cleanup`, and `status` exit early when no managed terminal exists. Only
a user-initiated toggle may launch one.

A timer-driven or polled action that *can* launch a terminal will eventually
launch one at 3am.

Serves PD5 (no unrequested mutation).

**Violation smell.** A background action that reaches the launch path. A
`status` query that repairs state as a side effect.

## A7. Global compositor state is snapshotted, parked, restored, and repairable

The temporary `specialWorkspace` animation override is the only global mutation,
and it is disclosed by the `slideFromTop` setting. Its discipline is the
template for any future one: snapshot the explicit current tuple, refuse the
change when a lossless restore is impossible, park the snapshot on disk because
`SIGKILL` cannot be trapped, restore from an `EXIT` trap, and let the next
invocation repair a stale marker under a staleness bound.

Recorded as a row in the [external mutation inventory](design-rules.md#external-mutation-inventory).

**Violation smell.** A restore that reconstructs values instead of replaying the
saved tuple. A repair path placed where a wedged run can prevent it from
running. Any second mechanism for the same job.

## A8. Local state is a cache; the compositor is the truth

Every persisted handle is revalidated before use, and every read path recovers
from a missing, empty, corrupt, or future-version document by asking the
compositor. The recovery scan is what makes the design self-healing; the state
file is an optimization.

Serves PD2 (never use a cache as the authority) and PD3 (a failed read is a
visible state, not a default).

**Violation smell.** `cat state; use it`. A parse failure that exits instead of
falling back. Recovery that returns one match when the model holds several.

## A9. Command text is never transmitted, persisted, or logged

Duration and exit status are sufficient for the indicator. This holds under
`YADTM_DEBUG` as well. If command text is ever added it is a separate opt-in,
sanitized, truncated, and still never persisted — and the privacy fields must
appear in the install confirmation.

Recorded in the [external mutation inventory](design-rules.md#external-mutation-inventory)
under shell command tracking.

**Violation smell.** A hook that captures `$BASH_COMMAND` or `$history[1]`. A
debug branch that logs the journal line verbatim.

## A10. Off means absent

A disabled feature creates no surface, arms no timer, and registers no handler.
It is not a transparent surface at `opacity: 0`, and not a paused animation. The
test is `hyprctl -j layers` plus an idle CPU sample, not a screenshot.

Serves PD11.

**Violation smell.** `visible: false` where the component is still loaded and
ticking. A settings check inside an animation frame rather than around the
component.

## A11. A feature flag's off path stays byte-identical

Especially for the tabs refactor, which touches the address handling every other
feature depends on. With the backend off, observable behavior must be what it is
today, and that is an acceptance criterion rather than an aspiration.

Serves PD4 (an experimental label means the non-experimental path is unaffected).

**Violation smell.** A refactor that changes the single-client path "while we're
in here". An off path that shares newly written state code with no test pinning
the old behavior.

## A12. The entrance is window motion under a suppressed workspace animation

Hyprland has no per-workspace animation control and cannot reverse a `slidevert`
special workspace, so the reveal is made instant and the visible motion is an
animated window move. This is why A7's machinery exists at all, and why the
suppression is held for the whole descent instead of being restored immediately.

Consequence for anything that renders around the terminal: arm **after** the
rect settles, not when the workspace becomes visible. During the descent the
window is still moving and its top edge is off-screen.

Serves PD11 (a trigger tied to an actual completed transition).

**Violation smell.** An overlay armed from the visibility event. A restore of
the animation node before the move has finished.
