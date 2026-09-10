# Changelog

## 2.3.0

- Add precise-failure villain encounters with bundled bug and ghost packs,
  bounded 14-second resolution, input-safe interaction, interruption cleanup,
  and encounter voice/sound cues.
- Add per-species bond memory with daily petting/celebration caps, bounded
  decay, bravery odds, visible tiers, and a confirmed reset action.
- Add friendship-based voice unlocks and rare Inseparable idle happiness;
  existing 2.2 tone lines remain available at every bond tier.
- Add a `Playful` pet activity mode with faster idle decisions, longer route
  steps, and no idle sleep while the terminal is visible.

## 2.2.0

- Add room-aware whole-border pet roaming with wall, descending-climb, ledge,
  carried, hover, and corner-compensation posture handling across all bundled
  packs.
- Add drag-to-relocate, optional pointer-awareness halos, and versioned runtime
  position memory with a single atomic writer.
- Add validated authored voice lines and optional rate-limited `pw-play`/
  `paplay` sound cues, both off by default and reduced-motion safe.
- Add the pet review-sheet and voice validation tools, pack-specific atlas
  remaps, deterministic route/voice tests, and the Phase 6 settings.

## 2.1.0

- Polish pet locomotion with authored pixel stride timing, inline turnarounds,
  anchor continuity, direction-aware facing, and resize-safe edge remapping.
- Add bounded tap-and-hold petting with reduced-motion behavior and rate-limited
  hearts, plus petInteraction and petRoaming settings.
- Upgrade bundled pet manifests to version 2 and validate stride, speed,
  optional actions, and projected-anchor continuity.

## Unreleased

- Add finite Fire / burn, Firework, Thunder, Snow, and Rain entrance effects,
  plus original fluffy Cat and Corgi pet packs using the validated atlas
  contract.
- Complete phase 3 decorative pet support: a validated penguin pack, bounded
  perimeter motion, click-through coordinator lifetime, precise completion
  reactions, and shared reduced-motion behavior.
- Complete phase 2 command completion indicators: generic Hyprland urgency,
  precise fork-free Bash/Zsh/Fish journal adapters, hidden-at-finish replay,
  scoped launch environment, and explicit reversible shell integration.
- Fix Phase 2 release blockers: terminal-close cleanup, Bash `DEBUG` trap
  preservation, PID-scoped shell sessions, and replay-only completion flashes.
- Complete phase 1 entrance effects: a theme-aware, click-through glow that
  follows the terminal across outputs, waits for the reveal to settle, and
  cleans up its bounded animation and particle surface.
- Complete phase 0 foundation: event-driven Hyprland observation, bounded
  helper actions, lock-free diagnostics, and atomic versioned runtime state.
- Migrate legacy `address` and `special-animation` runtime markers to the
  prefixed state files. Legacy marker repair remains supported for one release
  so an interrupted pre-upgrade run can restore its animation snapshot.
- Add fixture-driven helper tests and documented headless-output setup.
- Repair Quickshell object-model observation, raw close-event address matching,
  immediate post-interruption animation recovery, and monitor-object lookup.
- Associate late terminal launches with observed launcher-process PIDs, keep
  pending adoption markers durable, serialize idempotent fallthrough edits,
  and report Ctrl + Grave conflicts before binding installation.
