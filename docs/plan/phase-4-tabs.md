# Phase 4: tabs experiment

The only phase that can legitimately end in a decision not to ship. It is a
proof of concept first and a feature second, and the gate below is binding: if
the prototype fails any core case, the Hyprland-group backend stays behind an
experimental setting and the tmux backend is evaluated separately. The phase
may correctly end with tabs not shipping.

Depends on: Phase 0 (0.3 versioned state, which was designed for this).

Independent of Phases 1, 2, and 3.

Design gate: [PD2–PD5 and PD7–PD12](../design-rules.md#phase-rule-gates).

## Why groups, and why a prototype first

There is no terminal-independent Wayland API for adding a tab to an existing
terminal window. foot and Alacritty have no native Linux tabs, and Alacritty
explicitly delegates tabs and splits to a window manager or multiplexer. Ghostty
and kitty have their own tab models, but the plugin's whole premise is using the
system's configured terminal, so it cannot depend on any one emulator's private
API.

Hyprland groups are compositor-native tab stacks with a working group bar —
titles, click and scroll selection, close behavior, colors, rounding — and a
real shell per tab. That is the right shape. What is unproven is groups of
**floating** windows on a **named special workspace**, driven by a helper whose
entire animation strategy was written for exactly one client.

The prototype exists to answer that before any refactor is written, because the
refactor is large and is worthless if the answer is no.

## Prototype gate

Run these against two to five grouped foot windows on
`special:dropdown-terminal`, by hand, before writing any of the refactor:

1. Two to five grouped floating foot windows survive on the named special
   workspace without Hyprland untiling, re-centering, or ungrouping them.
2. Show and hide work, including the custom top-down animation.
3. Click and scroll selection in the group bar work while the dropdown is open.
4. Closing the active tab keeps the rest; closing the last tab behaves
   predictably.
5. The visible group moves between monitors with different scale factors
   without losing members or geometry.
6. Auto-hide on focus loss and `special_fallthrough` behave with a group.
7. An Omarchy shell restart recovers all members, not one.
8. The native group bar's geometry is measured: determine whether it changes
   client `at`/`size`, covers terminal content, and stays clickable on the
   overlay/special workspace.
9. `no_anim`, opacity, float, size, and workspace rules apply correctly to every
   member; no inactive member flashes during reveal.
10. Killing the active member and each background member position leaves a
    deterministic survivor; killing all members yields a clean closed state.
11. An unrelated user-created group or terminal on the same workspace is never
    adopted, joined, moved, or closed.
12. `configreloaded` and group lock/unlock states cannot strand a partial group.

Case 1 is the make-or-break: if Hyprland will not keep a floating group intact
on a hidden special workspace, nothing downstream matters. Case 5 requires the
headless output from Phase 0.6.

Two known unknowns to settle inside the prototype, because the current
animation strategy depends on the answers:

- **Does a floating group move as one box?** `reveal_parked`
  (`bin/omarchy-dropdown-terminal:380-393`) parks the window in the same
  synchronous Lua block as the workspace reveal, specifically to defeat
  Hyprland's re-centering of floating windows. If a group's members do not
  share one geometry box, that block has to move each member, and it must still
  be one synchronous block or the re-centering wins.
- **Do `no_anim` and `opacity` apply per member or per group?** The same block
  masks the window so the centred frame is never shown. If those props are
  per-member, the mask must be applied to every member and lifted from every
  member, and a member missed leaves a visible flash.

## Helper refactor, if the gate passes

1. Extend the Phase 0.3 state document: `clients` becomes genuinely multi-entry
   and `active` tracks the focused member. The shape already exists, so this is
   not a migration.
2. Add `new-tab`, `next-tab`, `previous-tab`, `close-tab`.
3. **Classify every new action's lock semantics explicitly.** `new-tab` must
   take the `flock -n` drop-duplicate path, not the `flock -w 3` queueing path.
   One hotkey press arrives once per monitor instance
   (`bin/omarchy-dropdown-terminal:98-102`); on the queueing path a
   dual-monitor system spawns **two terminals per keypress**. `next-tab` and
   `previous-tab` are also drop-duplicate. `close-tab` is drop-duplicate.
4. Launch the new terminal while the current dropdown is focused, so Omarchy's
   launcher inherits the active terminal's working directory. This means
   `new-tab` cannot be a no-op when the dropdown is hidden — decide whether it
   summons first or refuses.
5. Group the new client with the tracked dropdown, then float, size, and move
   the group as one unit.
6. Treat the group as one geometry unit during show, hide, and cross-monitor
   moves. Update `active` from group and focus events.
7. Keep a locked, identified group so unrelated windows cannot be absorbed.
   Never select clients by terminal class alone — the recovery scan at
   `bin/omarchy-dropdown-terminal:559-568` already keys on workspace membership,
   which is the right instinct, but with tabs it must return every match rather
   than `head -n 1`.
8. Preserve the last tab: closing it either closes the dropdown or resets it,
   per an explicit setting, never silently leaves an empty group.

Recovery is the item most likely to be underestimated. What makes the current
design self-healing is that any client found on the special workspace is
adopted as *the* terminal. With tabs, adoption must reconstruct group
membership and the active member from `hyprctl -j clients` alone, because the
state file may be stale or gone. Write that function first and test it against
fixtures from Phase 0.6 before the dispatch code.

## The group bar is the user's

Group bar appearance is a global Hyprland setting. The plugin must not silently
rewrite it. Use whatever theme the user has; if a themed group bar is wanted
later, it is a documented, opt-in Omarchy customization with the same
marker-block and restore discipline as
`bin/omarchy-dropdown-terminal-special-fallthrough`.

## Fallback: tmux windows

Operationally much simpler — the compositor still tracks exactly one window, so
every animation, geometry, and recovery path in the helper keeps working
unchanged. The costs are real: a tmux dependency, a changed default shell
experience, nested-tmux friction over SSH, and a tab bar rendered inside the
terminal grid rather than by the compositor.

It also interacts with Phase 2: inside tmux, each pane is a separate shell with
its own PID, so the PID-keyed session map works, but "the terminal is visible"
no longer implies "the tab that finished is visible". Either accept that
imprecision or read the active tmux window, which needs a fork.

The manifest cannot declare a `tmux` dependency — `package` and `minimumVersion`
appear in one third-party manifest but are not read anywhere in
`/usr/share/omarchy/shell` or `/usr/share/omarchy/bin`. So the backend must
check for `tmux` at runtime and degrade with a notification, never fail
silently.

Ship it as an optional backend, not the default.

## Explicitly rejected: a Quickshell tab bar

Do not build a custom tab bar that tries to reparent terminal surfaces. Wayland
gives clients separate surfaces by design, and Quickshell cannot embed an
existing terminal window as a child widget. Such a bar could only ever be a
controller for grouped windows or tmux — added complexity in front of a backend
that still has to exist. The group bar and the tmux status line are already
that controller.

## Settings

| Key | Type | Options / range | Default |
| --- | --- | --- | --- |
| `tabsBackend` | enum | `Off`, `Hyprland group (experimental)`, `tmux` | `Off` |
| `closeLastTab` | enum | `Close dropdown`, `Keep one tab` | `Close dropdown` |

Enum option strings are the stored value, so the "(experimental)" suffix is
permanent once shipped. Either accept that, or name it `Hyprland group` and
carry the experimental warning in the `description` field and in `Panel.qml`.
Prefer the latter.

Optional global shortcuts for new/next/previous/close are registered the same
way as the existing `GlobalShortcut` in `Service.qml:80-86`, which means they
fire once per monitor instance — see refactor item 3.

## Verification

```
# gate, by hand, before any refactor
hyprctl -j clients | jq '[.[] | select(.workspace.name == "special:dropdown-terminal")
  | {address, floating, grouped, at, size, monitor}]'
#   grouped must list the peers; floating must stay true; at/size must agree

# duplicate keypress
#   bind new-tab, press once on a dual-monitor setup, count new clients: must be 1

# recovery
#   with 3 tabs open, restart the Omarchy shell, then summon:
#   all 3 must come back with a sane active member
rm -f "$XDG_RUNTIME_DIR"/io.github.tuthan.dropdown-terminal.state.json
#   summon: must reconstruct all members from hyprctl alone

# foreign window adoption
#   launch an app from a menu while the dropdown is focused; it must never
#   join the group. The existing cleanup path already returns such windows
#   to the focused workspace — verify it still does with a group.

# cross-monitor (requires Phase 0.6)
hyprctl keyword monitor HEADLESS-2,1920x1080@60,3440x0,1.25
#   summon the group on each output; no member may be lost or left behind
```

## Acceptance criteria

- Tabs survive toggle, focus loss, shell reload, and monitor transfer.
- Closing one tab never loses the others; closing the last follows the setting.
- A foreign window is never adopted into the group.
- The configured default terminal remains in use; no emulator-specific API.
- One keypress creates exactly one tab, on any number of monitors.
- The user's group bar theme is untouched.
- With `tabsBackend: Off`, the helper's behavior is byte-for-byte what it is
  today.

That last criterion is the one worth enforcing hardest. The refactor touches the
address handling that every other feature depends on, so the off path must be
provably unchanged.

## Out of scope

- Tab reordering, renaming, or persistence across reboots.
- A themed group bar.
- Splits or panes in either backend.

## Open questions

- Does Hyprland 0.56.2 keep a floating group intact on a hidden named special
  workspace? Unanswerable without the prototype, and everything else waits on
  it.
- Can a group be locked such that Hyprland will not add a window to it
  automatically? If not, item 7 needs a different mechanism.
- With tmux, is it acceptable that "terminal visible" no longer means "the
  finished tab is visible" for Phase 2's clearing rule?
