# Implementation plan

Plan date: 2026-09-04

These documents are the executable plan derived from
[`../feature-research-and-plan.md`](../feature-research-and-plan.md). The
research doc remains the record of what was investigated and why; where the two
disagree, these documents win. The decisions that changed or sharpened an
earlier research proposal are listed under
[Implementation decisions](#implementation-decisions) with their evidence.

## Binding design rule

This project adopts the reusable [`General Omarchy plugin design rules`](../../../plugin-docs/rules/omarchy-plugin-design.md) through its completed [`Dropdown Terminal design-rule profile`](../design-rules.md). The profile records authority ownership, failure language, external mutations, two bounded visual exceptions, and the PD rule gate for every phase. A phase cannot pass on functional behavior alone; its listed design-rule checks are part of acceptance.

## Execution order

| Doc | Numbered research feature | Ships |
| --- | --- | --- |
| [phase-0-foundation.md](phase-0-foundation.md) | Shared foundation | No user-visible feature |
| [phase-1-entrance-effects.md](phase-1-entrance-effects.md) | §2 Glow/burning border | Glow on summon |
| [phase-2-command-indicator.md](phase-2-command-indicator.md) | §1 Hidden command completion | Completion indicator |
| [phase-3-pet.md](phase-3-pet.md) | §3 Pet | One pet pack |
| [phase-4-tabs.md](phase-4-tabs.md) | §4 Tabs | Experimental tabs |

Effects and the command indicator are swapped relative to the research doc's
numbered feature sections (the research delivery summary now mirrors this
execution order).
Neither depends on the other; both depend only on Phase 0. Effects are
reversible, self-contained, and touch nothing outside the plugin directory,
while the indicator writes into the user's shell startup files, which is the
largest trust and support-burden step in the whole plan. Shipping effects first
also exercises the Phase 0 geometry and visibility model under real load before
`~/.bashrc` is involved. Reverse the two if the command indicator is the feature
that actually matters to users; nothing in the plan breaks.

Phases 3 and 4 are independent of each other and of Phase 2. Phase 4 is the only
phase that can end in a decision not to ship.

## Host facts and evidence

The host behaviors this plan depends on are normative in the shared
[Omarchy/Quickshell host constraints](../../../plugin-docs/rules/omarchy-plugin-design.md#omarchyquickshell-host-constraints),
and the evidence that they hold here — versions, measurements, experiment
results, and the type inventory — is recorded in
[`../host-verification.md`](../host-verification.md). Neither is restated in
this plan; a phase names the constraint it relies on.

Two consequences worth stating once, because they shape every phase:

- **The development machine has one monitor at scale 1** (`DP-1`, 3440x1440).
  Every multi-monitor and fractional-scale acceptance criterion below is
  unverifiable as the machine stands, so phase 0 makes a headless second output
  a documented prerequisite and PD4 requires each phase report to say whether an
  output test was physical or headless.
- **Bats and ShellCheck are absent**; `jq`, `qmllint`, and `qmltestrunner` are
  present. Choosing and installing a shell test harness is part of phase 0
  rather than an assumed capability.

Defects already found against these constraints are in
[`../known-issues.md`](../known-issues.md). Issue #1 wedges the plugin silently
and is scheduled in phase 0.

## Cross-cutting conventions

- **Runtime state** lives under the directory chosen by `state_dir()` in the
  helper, which is `XDG_RUNTIME_DIR` when it passes the privacy check and
  `/tmp/omarchy-dropdown-terminal-$UID` otherwise. Reuse that function; do not
  add a second state root.
- **File names** in that directory are prefixed `io.github.tuthan.dropdown-terminal.`
  because the state root may be `XDG_RUNTIME_DIR` itself, shared with other
  programs. The existing lock file already follows this; `address` and
  `special-animation` predate the rule and are renamed in Phase 0.
- **Atomic writes** are `mktemp` in the same directory then `mv`, matching
  `bin/omarchy-dropdown-terminal-special-fallthrough`.
- **Config edits** use a `-- BEGIN/END Dropdown Terminal <feature>` marker block,
  a timestamped `cp -p` backup, and an idempotent enable/disable pair, matching
  the two existing config-editing scripts.
- **Global compositor state** is snapshotted before it is changed, parked on
  disk so a `SIGKILL`ed run can be repaired by the next one, and restored from
  an `EXIT` trap. Follow `suppress_special_animation` exactly; do not invent a
  second mechanism.
- **Debug logging** goes behind one environment variable, `YADTM_DEBUG`. Command
  strings are never logged.
- **Dependencies** are checked at runtime, not declared: the helper already
  needs `hyprctl`, `jq`, `awk`, `flock`, `stat`, `date`, `timeout`, and
  `omarchy`. Any new hard dependency (`tmux`) must degrade to a notification,
  because the manifest cannot express it.

## Implementation decisions

Some rows describe an earlier research draft that has since been corrected in
the research document itself. They remain here as a compact decision record.

| Earlier question or proposal | Implementation decision | Evidence |
| --- | --- | --- |
| Numbered research sections put completion before effects | Effects before the command indicator | Effects are self-contained; the indicator edits `~/.bashrc` |
| Per-hook Omarchy IPC | Fork-free file append; IPC only as an optional nudge | Measured ~47 ms per call, ~90 ms added to every prompt |
| One `IpcHandler` broadcasts to all bar widgets | Runtime file that every instance reads | A plugin entry point cannot elect a single IPC owner; Omarchy needs `manageIpc` for exactly this |
| Helper `status`/`geometry` as the visual source of truth | Read `Hyprland.toplevels`/`monitors` in QML; keep status diagnostic | Avoids `bash`+`hyprctl`+`jq` per poll per monitor instance |
| “Animate `borderangle` once” is a small change | Reclassified as not-small, and gradient support unverified | The node ships `enabled=false`; per-window gradient via `set_prop` is unconfirmed |
| Enum settings valued `off`/`glow`/`embers` | Display-cased stable option strings | Omarchy enum options are the stored value and are user-visible |
| Advanced options hidden until enabled | Conditional presentation only inside `Panel.qml` | The manifest schema has no visibility field |
| Shell adapter inside the removable plugin directory | Guarded source line plus uninstall cleanup | Plugin removal would otherwise break every new shell |
| Hand-rolled Bash `DEBUG`+`PROMPT_COMMAND` adapter | Evaluate `bash-preexec` first | It is packaged, and is what comparable tools use |
| Versioned JSON state in both Phase 0 and Phase 4 | Phase 0 owns it; Phase 4 extends it | Removes the duplication and forces the migration question early |
| Multi-monitor and fractional-scale acceptance criteria | Gated on a headless second output created in Phase 0 | The machine has one output at scale 1 |
