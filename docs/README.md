# Documentation map

This project separates **generic** rules from **project-tied** decisions, so the
shared standard can evolve without dragging plugin specifics along, and so a
plugin specific can change without anyone editing a shared standard.

## Generic — lives outside this repository

| Document | Contents |
|---|---|
| [`plugin-docs/rules/omarchy-plugin-design.md`](../../plugin-docs/rules/omarchy-plugin-design.md) | Normative PD1–PD12 product, UI, interaction, safety, theme, and motion rules, plus the numbered Omarchy/Quickshell host constraints |
| [`plugin-docs/templates/project-design-profile.md`](../../plugin-docs/templates/project-design-profile.md) | The adoption profile template a consuming plugin fills in |

The shared rule wins over any wording in this repository. A project document
wins only where the profile records an explicit exception.

**Do not copy normative text from the shared document into this repository.**
Link to it and record which clauses apply. Copying is how a standard silently
diverges.

## Project-tied — lives here

| Document | Contents | Read it when |
|---|---|---|
| [`design-rules.md`](design-rules.md) | The completed adoption profile: applicability matrix for PD1–PD12, state and authority inventory, external mutation inventory, exceptions EX-1 and EX-2, and the per-phase rule gate | Starting any phase, or adding a state, surface, or mutation |
| [`architecture-invariants.md`](architecture-invariants.md) | Engineering invariants A1–A12 specific to this plugin's architecture, each mapped to the shared rule it serves | Adding a feature that touches the helper, the lock, geometry, or state |
| [`host-verification.md`](host-verification.md) | Evidence that the shared host constraints hold on this host at these versions, plus host facts not yet upstream and flagged for promotion | Doubting a host behavior, or after an Omarchy/Hyprland/Quickshell upgrade |
| [`known-issues.md`](known-issues.md) | Latent defects found by review, each with failure mode, confirmation method, fix, and the rule it violates | Before touching the helper; #1 is a wedge that disables the plugin silently |
| [`feature-research-and-plan.md`](feature-research-and-plan.md) | The research record: what was investigated, what is feasible, and why | Wanting the reasoning behind a plan decision |
| [`plan/`](plan/README.md) | The executable plan: one document per phase, each with work items, verification commands, acceptance criteria, and its design-rule gate | Doing the work |

## Which file does a new fact belong in?

| The fact is… | It goes in |
|---|---|
| A rule any Omarchy plugin should follow | The shared document, deliberately promoted — not here |
| How *this* plugin satisfies a shared rule | `design-rules.md` |
| A bounded departure from a shared rule | `design-rules.md`, as an exception with scope, compensating check, and removal condition |
| An engineering rule about this plugin's own architecture | `architecture-invariants.md` |
| A measurement, version, or experiment result | `host-verification.md` |
| Something that is currently wrong | `known-issues.md` |
| Work to be done, with acceptance criteria | The relevant `plan/` phase |
| Why an option was rejected | `feature-research-and-plan.md`, or the phase doc's decision section |

When a project-tied fact turns out to be generic, promote it to the shared
document and replace the local copy with a link. `host-verification.md` marks
its promotion candidates.
