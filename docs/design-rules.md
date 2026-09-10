# Dropdown Terminal design-rule profile

Adopts: [`General Omarchy plugin design rules`](../../plugin-docs/rules/omarchy-plugin-design.md)

Source lineage: the shared rules generalize [OmaSafe design principles and language](../../omasafe-plugin/docs/design/02-design-principles.md). OmaSafe-specific security copy, glyph tables, exact durations, and component inventory do not automatically apply here.

Reviewed against:

- Plugin manifest version: 1.4.2
- Repository baseline: `c56ffad` at the 2026-09-04 research pass
- Omarchy: 4.0.2
- Hyprland: 0.56.2
- Quickshell: 0.3.1
- Review date: 2026-09-04

This profile is binding for the implementation plan under [`docs/plan/`](plan/README.md). A phase is not complete until its listed PD rules and project exceptions pass.

Companion project documents, which record project-tied facts rather than restating shared rules:

- [`architecture-invariants.md`](architecture-invariants.md) — engineering invariants A1–A12 specific to this plugin, each mapped to the PD rule or host constraint it serves.
- [`host-verification.md`](host-verification.md) — evidence that the shared host constraints hold at the versions above, plus host facts flagged for promotion upstream.
- [`known-issues.md`](known-issues.md) — latent defects found by review, each mapped to the rule it violates.
- [`README.md`](README.md) — which document a new fact belongs in.

## Applicability matrix

| Rule | Status | YADTM application | Verification |
|---|---|---|---|
| PD1 State facts; decoration never impersonates status | Required | Glow and pet motion are decorative. Tier 0 says `Terminal needs attention`, never `Command finished`; success/failure is reserved for paired shell events. | Cover/disable decorative layers and verify status meaning does not change; remove the precise adapter and verify no success/failure claim remains. |
| PD2 Keep authorities and sources separate | Required | Helper owns managed membership/actions; Quickshell Hyprland owns live geometry/focus/urgency; `shell.json` owns persisted settings; the event journal owns ordered command/lifecycle history. | Force stale/corrupt state and source disagreement; verify precedence and recovery in Phase 0/2 fixtures. |
| PD3 Missing and unsupported states are visible | Required | Use `Unavailable`, `Unsupported: <value>`, `Not configured`, and verified empty states. Never turn a missing client, adapter, asset, or tab backend into success/zero. | Missing helper, malformed/future JSON, missing integration path, unsupported terminal/shell, invalid pet pack, and failed tab backend fixtures. |
| PD4 Show quality, limits, freshness, and test coverage | Required | Disclose urgency's generic limitation, shell/terminal support, experimental tabs, headless versus physical monitor evidence, and unverified group behavior. | Phase reports record host versions and whether output tests were physical or headless. |
| PD5 External mutations are explicit, exact, and reversible | Required | Shell rc integration, direct Hyprland binding, special-fallthrough override, and any optional group styling show exact targets/effects and provide idempotent install/status/remove plus backups. | Cancel/default-focus, install twice, remove twice, abrupt uninstall, interrupted write, and exact restore tests. |
| PD6 Use the host kit and tokens before local primitives | Required with EX-1 | `Panel.qml` controls use installed `qs.Ui`; layout/color/type/radius/spacing use `qs.Commons`. Product-specific glow/pet drawing is allowed only by EX-1. | Inventory custom `Rectangle`, shader, particle, sprite, `MouseArea`, color, size, and font usage. |
| PD7 Typography is a semantic scale with a data floor | Required | Settings, status words, adapter paths, exit codes, durations, and tab labels use host roles; data is `bodySmall` or larger. | Render panel at Omarchy minimum/default/maximum base sizes and inspect clipping/elision/tooltips. |
| PD8 Prefer flat hierarchy and repeatable rhythm | Required | Extend the existing hand-built panel with flat sections and native rows; avoid a separate card for every feature. | Review panel hierarchy with border/fill removed and at narrow/large text layouts. |
| PD9 Semantic state uses word, shape, and color together | Required with EX-2 | Bar space may show only a glyph/shape plus color, but accessible text/tooltip names `running`, `attention`, `succeeded`, or `failed`; these states remain distinct in monochrome. | Desaturated screenshots and tooltip/accessibility checks for every icon state. |
| PD10 The theme owns surfaces | Required | Panel and overlays derive palette, border, radius, and scale from the active theme/host. No fixed-theme plate or hardcoded semantic hex color. | Light, dark, square-corner, thick-border, translucent, and high-contrast theme passes at scale 1 and fractional scale. |
| PD11 Motion explains change and stops with its surface | Required with EX-1 | Every glow/pet/icon animation has a trigger, duration, generation/cancellation rule, reduced-motion behavior, and hidden cleanup. No process runs per frame or prompt except builtin journal append. | Interrupt every action with hide/close/reload; inspect layers/timers/processes and idle CPU/RSS afterward. |
| PD12 One interaction model; input and focus are explicit | Required | Phase 6 extends the Phase 5 profile row: the overlay is non-focusable and click-through except for the union of the pet sprite and optional gaze halo while `petInteraction` is enabled. That union subtracts the terminal client rectangle grown by `general:border_size + general:extend_border_grab_area` when `resize_on_border` is enabled, and by `general:border_size` otherwise, so resize handles remain terminal input without shrinking the pet target for an inactive ring. Pixels inside an enabled halo belong to the pet surface and therefore reach neither the desktop nor a window behind it; the halo defaults to `Off`. Only the pet surface carries a region; keyboard focus remains `WlrKeyboardFocus.None`. Helper locking guarantees one mutation across per-screen instances. | Keyboard/pointer/pass-through, held-key, focus-loss, resize-grab, multiple-screen duplicate, halo, and model-refresh tests. |

## State and authority inventory

| State shown or acted on | Source | Writer/authority | Missing/unsupported behavior | Freshness/reconciliation |
|---|---|---|---|---|
| Plugin settings | `~/.config/omarchy/shell.json` | Omarchy shell/panel persistence | Last valid value plus visible unavailable diagnostic when parsing fails | `FileView.onFileChanged: reload()`, post-reload revision, bounded settle reload after a burst |
| Managed terminal membership | plugin runtime JSON | `bin/omarchy-dropdown-terminal` under its lock | Recover validated live client or closed/unavailable; never silently adopt a foreign window | Atomic replace, live `hyprctl -j` recovery, stale-member pruning |
| Geometry, monitor, visibility, focus | Quickshell Hyprland model and raw IPC object | Hyprland | Overlay hides rather than drawing at a default origin | Raw events plus bounded `refreshToplevels()` while a visual consumer is active |
| Generic attention | `HyprlandToplevel.urgent` | terminal/application through compositor | No badge when absent; never promoted to completion | Live Quickshell property; clears through normal focus/application behavior |
| Precise running/result state | append-only runtime event journal | shell builtin hooks plus helper lifecycle events | `Not configured` when adapter absent; malformed records skipped and counted diagnostically | Async `FileView.reload()`, offset/tail reducer, 1 Hz re-probe only while a command is running |
| Pet action/asset state | validated `pet.json` and bundled PNG | bundled pack; one-shot validator for external packs | Bundled penguin fallback or pet disabled with a concise unavailable/unsupported reason | Validate on selection/change; never on a frame path |
| Pet position | `<state root>/io.github.tuthan.dropdown-terminal.pet-state.json` | The `Service.qml` instance whose screen hosts the terminal, via `FileView` atomic writes | Missing, invalid, future-version, stale, or species-mismatched documents are ignored; the pet enters at its default position; debug log only | Read once on layer creation and after owner/config changes; settle writes are coalesced to 2 s and carry a monotonic revision |
| Tab membership/active tab | runtime JSON reconciled with `hyprctl -j clients` group data | helper under nonblocking mutation lock | `Off` or experimental unavailable; existing single terminal remains usable | Reconcile before/after each action and after compositor/shell reload |

## External mutation inventory

| Action | Exact target | Required preflight/confirmation | Backup and atomicity | Removal/rollback |
|---|---|---|---|---|
| Install direct toggle binding | `~/.config/hypr/bindings.lua` | Native confirmation shows binding, target file, and whether an existing chord conflicts | Existing timestamped backup/marked insertion behavior retained and made atomic where needed | Explicit status/remove action; unrelated bindings preserved |
| Enable special fallthrough | `~/.config/hypr/input.lua` | Confirmation names pointer-focus effect and exact managed block | Existing marked block, temporary file/rename, backup | Disable removes only the block and reloads/validates Hyprland |
| Install shell command tracking | Selected Bash/Zsh/Fish rc file | Cancel-first confirmation shows file, exact guarded source block, shells affected, privacy fields, and removal path | `cp -p` timestamped backup and atomic replacement | Idempotent remove; missing plugin path is a guarded no-op |
| Temporary special-workspace animation suppression | Live Hyprland animation state plus runtime recovery marker | No per-toggle dialog; this is an established implementation detail disclosed by the `slideFromTop` setting | Snapshot exact explicit state before mutation; runtime marker and `EXIT` restoration | Next invocation repairs a stale marker after `SIGKILL`; setting off avoids mutation |
| Optional tabs/group styling | Global Hyprland group settings, only if ever offered | Separate opt-in confirmation with exact current/new values | Exact snapshot and restore; never bundled with enabling tabs | Disable restores prior values; default plan leaves user theme untouched |

Plugin-local visual settings (`entranceEffect`, pet settings, intensity, reduced motion) are reversible preferences and do not need confirmation. Enabling one never authorizes shell/config edits.

## Custom visual primitives and exceptions

### EX-1 — Product-specific decorative rendering

- Rules affected: PD6 and PD11.
- Scope: the terminal border glow/embers, bounded particles, pixel-art pet sprite, and its contact/effect layers only. Settings panels and controls remain host-native.
- Reason: the Omarchy UI kit has no border-following effect or sprite primitive; these visuals are the product feature rather than replacement panel chrome.
- Compensating checks: colors/radius/scale derive from host/theme; input region is empty; particle/frame/timer counts are bounded; reduced motion is complete; all activity stops and the layer unmaps while hidden.
- Review/removal condition: inventory every custom primitive per release. Remove or simplify any effect that cannot pass click-through, theme, fractional-scale, interruption, or idle-baseline tests.

### EX-2 — Compact bar status wording

- Rules affected: PD9.
- Scope: the collapsed bar icon may not have room to print a status word inline.
- Reason: the bar widget is intentionally compact.
- Compensating checks: shape/glyph plus color distinguish state without hue, the tooltip/accessibility text prints the exact word, and expanded settings/status views print words.
- Review/removal condition: revisit if the host adds an accessible-name/status API that is stronger than the tooltip.

## Phase rule gates

| Phase | Binding rules | Additional gate |
|---|---|---|
| [0 — foundation](plan/phase-0-foundation.md) | PD2, PD3, PD4, PD5, PD11, PD12 | Authority/failure inventory and external-mutation behavior are testable before feature work. |
| [1 — entrance effects](plan/phase-1-entrance-effects.md) | PD1, PD6, PD9, PD10, PD11, PD12; EX-1 | Theme, input, fractional geometry, reduced/off path, and idle cleanup pass. |
| [2 — command indicator](plan/phase-2-command-indicator.md) | PD1–PD5, PD7, PD9, PD11, PD12; EX-2 | Urgency is labeled generically; shell integration has cancel-first exact confirmation and privacy/rollback checks. |
| [3 — pet](plan/phase-3-pet.md) | PD1, PD6, PD7, PD9–PD12; EX-1 | Decorative actions cannot impersonate command state; assets, anchors, interruptions, and hidden cleanup pass. |
| [4 — tabs](plan/phase-4-tabs.md) | PD2–PD5, PD7–PD12 | Experimental limitations stay visible; no foreign group/window or global style is mutated implicitly. |
| [5 — pet interaction](plan/phase-5-pet-interaction.md) | PD1, PD6, PD7, PD9–PD12; EX-1 | Motion uses authored stride timing; the bounded pet input region preserves terminal resize handles and never takes keyboard focus. |
| [6 — pet world](plan/phase-6-pet-world.md) | PD1–PD4, PD6, PD7, PD9–PD12; EX-1 | Voice lines derive only from precise qualifying events; the input-region union (pet, optional halo) still subtracts the terminal and its resize ring; the position document has one writer; sound is absent as process and library when off. |
| [7 — pet villains](plan/phase-7-pet-villains.md) | PD1–PD4, PD6, PD7, PD9–PD12; EX-1 | Villains derive only from precise qualifying failures the user saw; the villain rectangle joins the region union under the same subtraction; the bond document has one writer and a visible unavailable state; every encounter path ends on a bound or the first interrupt. |

## Project review checklist

- [ ] New UI copy is factual and uses the shared unavailable/unsupported/not-configured vocabulary.
- [ ] Every status maps centrally to word, shape/glyph, and theme color.
- [ ] Every new setting exists in both `manifest.json` and `Panel.qml` and has a defensive `Service.qml` fallback.
- [ ] New panel controls use installed `qs.Ui` components and `qs.Commons` tokens.
- [ ] Every change outside the plugin directory is explicit, previewable, reversible, and tested after abrupt plugin removal.
- [ ] Visual effects are click-through, interruptible, reduced-motion aware, and inactive while hidden.
- [ ] Tests record theme, font size, output scale/layout, physical versus headless status, and host versions.
- [ ] Exceptions remain bounded to EX-1 and EX-2 or this profile is revised before implementation.
