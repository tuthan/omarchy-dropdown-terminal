# Changelog

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
