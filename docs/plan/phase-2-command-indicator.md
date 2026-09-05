# Phase 2: command completion indicator

Ships the feature with the most real utility and the most exposure: the bar
icon reports that a long command finished while the terminal was hidden.

This is the only phase that writes into the user's shell startup files. Treat
every design choice below as constrained by two facts: the hook runs on every
single prompt, and a mistake in it breaks the user's shell rather than the
plugin.

Depends on: Phase 0 (0.2 observed state, 0.3 state file, 0.5 logging).

Design gate: [PD1–PD5, PD7, PD9, PD11, PD12, and EX-2](../design-rules.md#phase-rule-gates).

## Ship it in three tiers

There is a working generic indicator before shell integration. The later tiers
add exact command semantics and do require explicit shell setup. Ship them in
order; each is independently useful and each is a fallback if the next proves
too invasive.

### Tier 0: urgency, zero integration

`HyprlandToplevel.urgent` is a first-class property in Quickshell 0.3.1. foot
raises urgency on `BEL` when unfocused (`foot.ini` `bell` / `urgent`), and
`HyprlandWorkspace.urgent` exists too. So:

```qml
readonly property bool terminalUrgent: trackedToplevel ? trackedToplevel.urgent : false
```

That is the entire mechanism. A user who ends a command with `; printf '\a'`
gets an indicator today with no rc-file edits and no new dependency. OSC 777 is
included only if the open verification below proves that foot maps it to
Hyprland urgency rather than only a desktop notification.

Tier 0 is not a substitute for tiers 1 and 2 — it requires the user to opt in
per command, and it carries no exit status or duration. It is worth shipping
because it costs about ten lines, it works on every terminal that raises
urgency, and it is the honest fallback for users who decline shell integration.

### Tier 1: fork-free hooks, file transport

An earlier IPC draft called `omarchy-shell -q` from both the pre-exec and
pre-prompt hook. Measured on this machine: five sequential
`omarchy-shell -q shell ping` calls take 0.235 s wall, so **~47 ms per call**,
and the path costs roughly **90 ms of added latency on every prompt**. The
research doc's guard — "must not delay it for seconds" — is the wrong
threshold. 90 ms on every `cd` is the kind of regression that gets a plugin
uninstalled, and it is paid by users who never run a long command at all.

The hook must therefore be fork-free. Bash can append to a file with builtins
alone:

```bash
printf 'v1\tstart\t%s\t%s\t%s\n' "$_yadtm_session" "$_yadtm_seq" "$EPOCHREALTIME" >> "$_yadtm_events"
printf 'v1\tfinish\t%s\t%s\t%s\t%s\n' "$_yadtm_session" "$_yadtm_seq" "$EPOCHREALTIME" "$_yadtm_status" >> "$_yadtm_events"
```

No subshell, no command substitution, no external binary. `$EPOCHREALTIME` is a
bash builtin variable, so duration needs no `date`. Writes under `O_APPEND` of
this size are atomic, so concurrent shells cannot interleave a line.

Use one versioned, tab-separated record per builtin `printf`, bounded to 512
bytes and containing no command text:

```text
v1<TAB>start<TAB>shell-session<TAB>sequence<TAB>timestamp
v1<TAB>finish<TAB>shell-session<TAB>sequence<TAB>timestamp<TAB>status
v1<TAB>shown|hidden|closed<TAB>helper<TAB>transition-id<TAB>timestamp<TAB>address
```

The QML reducer computes duration from paired start/finish timestamps. Session
and sequence are constructed once/incremented with shell builtins, so neither
record needs a subprocess or command substitution.

The helper appends a lifecycle record only after its matching compositor
transition succeeds. This ordering matters: using QML's current
`terminalVisible` when a delayed finish record is parsed is racy if the user has
already shown the terminal. During replay, a finish creates unread state only
when the latest preceding lifecycle record is `hidden`; `shown` and `closed`
clear it.

This also solves the multi-instance problem that the research doc's
`IpcHandler` broadcast does not. A plugin entry point is instantiated once per
screen (see the plan README) and cannot elect a single IPC owner the way
`Ui/Panel.qml` does with `manageIpc`. A file that every instance reads has no
election, no broadcast, and survives a shell reload.

Reader side, in `Service.qml`:

- `FileView { path: <state_root>/…events; watchChanges: true; onFileChanged: reload() }`
- react to `textChanged`, not to `onFileChanged` — `reload()` is async and
  `text()` inside the handler still returns the previous content, verified
  empirically
- parse all lines, fold them into a session map keyed by shell PID
- **do not trust the watch alone.** Omarchy documents at
  `plugins/bar/Bar.qml:950-953` that a `FileView` watch can permanently stop
  delivering events when changes land in quick succession, and repairs it with
  an explicit nudge. Mirror that: while any session is in the `running` state,
  a 1 Hz `Timer` calls `reload()`. A file read is not a process spawn, so this
  is cheap, and it is armed only while a command is actually running.

Do not truncate or compact the journal in the first release. Truncating after a
read races with an in-flight append and contradicts the “exactly one indicator”
contract. The reader keeps a processed offset and incomplete trailing fragment,
parses only complete new lines, and replays the per-login file from zero after a
QML reload. The runtime file naturally expires at logout/reboot. If measured
growth later justifies compaction, design a generation/rotation handoff first;
do not accept one lost finish as harmless.

### Tier 2: exit status, duration, and policy

With the transport in place, the state machine from the research doc's table is
straightforward and unchanged: `Idle`, `Running`, `Finished ok while hidden`,
`Finished error while hidden`, `Finished while visible`. Its inputs are the
session map, the ordered lifecycle reducer, and `terminalFocused` from Phase
0.2. Current `terminalVisible` is a consistency check, not the historical
hidden-at-finish decision.

Policy, all configurable:

- notify only past `commandNotifyAfterMs`, default 5000
- `130` (SIGINT) is ignored by default; a setting treats it as failure
- an unread bit is cleared when the terminal is shown or focused
- reconstruct running/unread/status by replaying the runtime journal after a
  shell reload; a start without a finish remains running and keeps the 1 Hz
  re-probe armed
- never transmit or persist command text. The hook writes PID, phase,
  timestamp, and status. Nothing else. There is no opt-in for command text in
  this phase; if it is ever added it is a separate, sanitized, truncated,
  non-persisted field, and `YADTM_DEBUG` must not log it either.

## Shell adapters

### Bash

The hostile case, and the default shell here. What the environment actually
looks like:

- `~/.bashrc` sources `$OMARCHY_PATH/default/bash/rc`, which sources
  `$OMARCHY_PATH/default/bash/init`, which runs `eval "$(starship init bash)"`.
- The `source` line sits **above** the "add your own" section, so anything
  appended to `~/.bashrc` is registered **after** starship.
- starship is installed and active on this machine.

So the research doc's instinct is exactly right and now has a concrete cause:
the hook function must be inserted at the **front** of the `PROMPT_COMMAND`
array, because starship's precmd runs first otherwise and `$?` is gone by the
time the hook sees it. Capture `$?` as the very first statement of the
function, before anything else, including any `local` declaration with an
assignment.

Before hand-rolling this: `bash-preexec` 0.6.0-1 is in Arch `extra`. It is the
de-facto library for bash preexec/precmd and is what comparable tools use, and
adopting it removes most of what makes this "the highest-risk adapter". It is
not a free win — `bash-preexec` also takes over `PROMPT_COMMAND`, and its
interaction with starship on this exact version must be tested, not assumed.
Spend the time on that test before writing a `DEBUG` trap by hand; the fallback
is the hand-rolled version and nothing is lost.

Either way, preserve what is already there: do not clobber an existing `DEBUG`
trap, and append to the `PROMPT_COMMAND` array rather than assigning it.

Test matrix: starship (present), atuin, direnv, multiline commands, a command
containing a newline, `C-c` at an empty prompt, `C-c` mid-command, a command
that `exec`s, and a subshell that exits.

### Zsh

`add-zsh-hook preexec` and `add-zsh-hook precmd`. Do not assign to the hook
arrays directly. Low risk.

### Fish

`fish_preexec` and `fish_postexec` events, which fish already suppresses for
empty commands. The cleanest adapter; write it last only because bash is the
default here.

## Installation

`bin/omarchy-dropdown-terminal-shell` with `install`, `remove`, and `status`
actions, following the marker-block pattern the repository already uses twice
(`bin/omarchy-dropdown-terminal-bind`,
`bin/omarchy-dropdown-terminal-special-fallthrough`): a
`# BEGIN/END Dropdown Terminal shell integration` block, a timestamped `cp -p`
backup before editing, and a `remove` that deletes only the marked block.

There is no user drop-in directory in Omarchy's bash setup — `default/bash/rc`
sources a fixed list — so appending to `~/.bashrc` is the only option. That
makes the guard below mandatory rather than defensive.

The sourced file lives at `shell/bash.yadtm` inside the plugin directory.
Plugins live at `~/.config/omarchy/plugins/<id>/`, and reinstalling renames the
old copy to `.<id>.bak.<timestamp>` — so the path survives updates but
disappears when the plugin is uninstalled. The installed line must therefore be:

```bash
# BEGIN Dropdown Terminal shell integration
[[ -r "$HOME/.config/omarchy/plugins/io.github.tuthan.dropdown-terminal/shell/bash.yadtm" ]] \
  && source "$HOME/.config/omarchy/plugins/io.github.tuthan.dropdown-terminal/shell/bash.yadtm"
# END Dropdown Terminal shell integration
```

Without the `[[ -r ]]` guard, uninstalling the plugin produces an error on every
new shell forever. The hook file itself must also be inert unless
`YADTM_TERMINAL=1` is exported, so that ordinary terminal windows are
unaffected — set that marker when the helper launches the terminal.

`install` and `remove` are triggered explicitly from `Panel.qml`, never
automatically on plugin load, and `status` reports whether the block is present,
which shell it targeted, and whether the sourced file still exists.

Before either external edit, open the native Omarchy confirmation pattern with
Cancel selected. It shows the selected rc file, exact guarded marker block,
fields written to the private event journal, backup behavior, and the matching
remove action. A held Enter/Space cannot both open and accept the sheet. The
success message is based on status/read-back of the exact block, not process
exit alone.

The helper injects `YADTM_TERMINAL=1` and the resolved event-file path into only
the terminal it launches. Verify this with foot server mode: if a long-running
terminal server discards or leaks per-launch environment, mark precise command
tracking unsupported for that launch mode rather than instrumenting every
desktop shell.

## Settings

| Key | Type | Options / range | Default |
| --- | --- | --- | --- |
| `urgencyIndicator` | boolean | — | `true` |
| `commandTracking` | boolean | — | `false` |
| `commandNotifyAfterMs` | integer | 0-60000, step 500 | 5000 |
| `commandFailureIndicator` | boolean | — | `true` |
| `commandCancelIsFailure` | boolean | — | `false` |

`commandTracking` defaults off because turning it on is what makes the panel
offer to edit `~/.bashrc`. Toggling it on must not perform the edit; it must
reveal the explicit install button. Both `manifest.json` and `Panel.qml` need
every key, and the conditional reveal is only possible in `Panel.qml`.

The compact bar mapping is centralized and follows PD9: `running`, generic
`attention`, `succeeded`, and `failed` each have a distinct shape/glyph plus
theme color; the tooltip/accessibility text prints the exact word. Urgency never
uses the success glyph.

## Verification

```
# tier 0 — no shell integration
#   hide the tracked terminal, trigger its BEL/urgency path, and verify a
#   generic attention badge appears for that client only and clears on focus

# hook cost — this is the number that decides whether the design is acceptable
# with the hook installed, in an interactive shell:
time (for i in $(seq 1 50); do :; done)   # crude, but any per-prompt fork shows
# better: PS0/PROMPT_COMMAND timing, or compare `time bash -ic exit` before/after

# transport
tail -f "$XDG_RUNTIME_DIR"/io.github.tuthan.dropdown-terminal.events
#   run `sleep 6` in the dropdown; expect exactly one start and one end line,
#   with a plausible EPOCHREALTIME delta and status 0

# policy
sleep 6            # hidden  -> one persistent indicator on every bar
sleep 1            # hidden  -> nothing
false              # hidden  -> nothing (under threshold)
sleep 6; false     # hidden  -> error indicator
sleep 6 then C-c   # hidden  -> nothing by default
sleep 6            # visible+focused -> brief flash only, self-clearing

# prompt integrity
#   the prompt must be byte-identical with and without the hook installed;
#   diff a captured prompt line before and after

# uninstall safety
bash bin/omarchy-dropdown-terminal-shell remove
diff <(grep -c . ~/.bashrc) ...      # only the marked block is gone
mv the plugin dir aside; open a new shell   # must be silent, not an error
```

## Acceptance criteria

- The hook adds no measurable fork to the prompt path, and no visible latency.
- A long command finishing while hidden produces exactly one persistent
  indicator, identical on every bar instance.
- Showing or focusing the terminal clears the indicator.
- Short, empty, cancelled, and visible-at-finish commands follow their
  configured policy.
- No hook output ever reaches stdout or corrupts the prompt; the prompt is
  byte-identical with the hook installed.
- `$?` is captured correctly with starship active.
- Install is idempotent, backs up before editing, and `remove` deletes only the
  marked block.
- Install/remove confirmations are cancel-first, show the exact target/block,
  resist held-key activation, and render success only after read-back.
- After the plugin directory is removed, new shells start silently.
- No command text appears in the events file, the state file, or `YADTM_DEBUG`
  output.
- Tier 0 reacts only to the tracked toplevel's `urgent` property, requires no rc
  edit, and is labeled as generic attention rather than success/failure.
- A finish parsed after the terminal was subsequently shown is classified from
  journal lifecycle order, not current visibility.

## Out of scope

- Background job completion. A command launched with `&` has finished from the
  prompt's point of view the moment the shell returns; true job-control
  reporting needs separate hooks and is a later feature. Document the
  foreground-only semantics in the README rather than half-implementing it.
- Per-tab session accounting. Sessions are keyed by shell PID, which already
  generalizes to one session per tab; Phase 4 consumes that without changes
  here.
- Any notification surface other than the bar icon.

## Open questions

- Does `bash-preexec` 0.6.0 coexist cleanly with `starship init bash` on this
  version? This decides the whole bash adapter and should be answered before
  any of it is written.
- Does foot's OSC 777 path set the Hyprland urgency flag, or only emit a desktop
  notification? Tier 0's usefulness depends on the former.
