# Phase 1: entrance effects

Ships the first user-visible feature: a short glow around the terminal when it
lands. Chosen as the first feature because it is entirely contained in the
plugin directory, is reversible by one setting, and proves the Phase 0 geometry
and visibility model before the command indicator starts editing `~/.bashrc`.

Depends on: Phase 0 (0.2 observed state, 0.6 headless output).

Design gate: [PD1, PD6, PD9, PD10, PD11, PD12, and EX-1](../design-rules.md#phase-rule-gates).

## Design decision: overlay, not compositor

The research doc offers a compositor-only accent (Level A) as the small change
and the Quickshell overlay (Level B) as the recommended one. Level A is not the
small change it appears to be, and the plan drops it:

- `borderangle` on this install is `enabled=false, overridden=true`. Producing a
  rotating accent means flipping a globally disabled animation node on and back
  off, which is a strictly worse snapshot/restore problem than the
  `specialWorkspace` case the helper already solves — and the existing guard
  (`read_special_animation`, `bin/omarchy-dropdown-terminal:135-144`)
  deliberately refuses nodes that are not `enabled == true`, because inherited
  or disabled nodes report placeholder values that cannot be written back
  losslessly. Level A would need a second, weaker restore path for exactly the
  case the first one was written to refuse.
- Whether `hl.dsp.window.set_prop` accepts a **gradient** for
  `active_border_color`, as opposed to a single color, is unverified. The
  plugin's own validation (`bin/omarchy-dropdown-terminal:24`) accepts only
  `rgb()`/`rgba()`. If set_prop is single-color-only, the accent requires
  changing global `general:col.active_border`, which affects every window on the
  system.
- `borderangle` looping forces continuous rendering at the monitor refresh rate,
  which the Hyprland documentation warns about and which contradicts the power
  goals in the risk table.

Level B has none of these properties: it touches no global state, so nothing
needs snapshotting, and its lifetime is under the plugin's control.

If a border accent is still wanted later, the honest version is a static
per-window border color for the duration of the entrance — which the helper can
already do through `set_border_color` — not an animated global node.

## Work items

### 1.1 `TerminalEffects.qml`

One `PanelWindow` in each already-per-screen `BarWidget.qml` instance. Do **not**
add another `Variants { model: Quickshell.screens }` inside the plugin: Omarchy
already instantiates the entry point once per screen, so nesting variants would
create N×N surfaces. Bind the window to its host instance's screen, and let only
the instance whose screen matches `terminalMonitor.name` become visible.
Properties:

- overlay layer, `WlrKeyboardFocus.None`, `ExclusionMode.Ignore`
- `mask: Region {}` — an empty input region, so every click reaches the
  terminal. This is the single most important property in the phase; it is what
  makes the surface non-interactive rather than a transparent input trap.
- `color: "transparent"`
- anchored to all four edges with margins derived from the terminal rect plus an
  effect gutter, or anchored top-left with explicit width and height — either
  works; pick one and keep the geometry math in one place.
- `visible` only while an effect is playing.

The window must be sized in the **logical** pixels of the output it is on.
Hyprland reports monitor `width`/`height` in physical pixels and a separate
`scale`; the helper already divides one by the other
(`compute_geometry_on`, `bin/omarchy-dropdown-terminal:270-283`) and takes the
`printf "%d"` truncation. Quickshell's `screen` is already logical. Use the
Quickshell values for the overlay and do not re-derive them from the helper's
truncated integers, or the overlay is off by up to a pixel per axis at
fractional scale — visible as a hairline gap on a glow outline.

The effect is decorative under PD1/EX-1. It never changes the bar's semantic
state and is never used as the sole signal for attention, command success, or
failure.

### 1.2 Geometry synchronization

Sources, in order of preference:

1. `terminalRect` and `terminalMonitor` from Phase 0.2 — free, event-driven.
2. A bounded poll, `refreshToplevels()` at 4 Hz, armed **only** while an effect
   is on screen. This exists because Hyprland emits no event per coordinate of a
   floating move or resize. It is an in-process socket round trip, not a
   process spawn, so it is affordable; it must still be disarmed the moment the
   effect ends.

Do not add the helper `status` action to this path. With N monitor instances
each spawning `bash` + `hyprctl` + `jq` per sample, a 4 Hz poll on a
dual-monitor system is 24 process spawns per second for a 700 ms animation.

The effect follows a cross-monitor summon by tracking which screen
`terminalMonitor.name` names, and only the matching plugin instance makes its
surface visible or arms the bounded refresh timer.

### 1.3 The glow preset

Play for 600-900 ms starting when the terminal reaches its final position, which
Phase 0.2 reports as `terminalRect.y` settling at the helper's `top_margin`. Do
not start on the visibility event: with `slideFromTop` enabled the window is
still descending, and the helper is holding the `specialWorkspace` animation
suppressed for the whole descent (`show_window`, `bin/omarchy-dropdown-terminal:401-419`).

Composition, cheapest first:

- a rounded-rectangle outline matching the terminal's corner radius, drawn with
  a `Rectangle` border and `layer.enabled` plus a blur, or a small
  `ShaderEffect` — measure both, prefer the one that does not allocate an FBO
  per frame
- an additive glow that fades in over ~120 ms and out over the remainder
- a finite spark burst via `ParticleSystem` with an `Emitter` whose
  `emitRate`/`lifeSpan` are bounded by the intensity setting, and which is
  disabled once it has emitted

Hard lifetime rule: when the animation completes, set `updatesEnabled: false`
and `visible: false`. Verify with a GPU/CPU sampler that the process returns to
its idle baseline; an overlay that keeps a scene-graph animation alive is the
"effects drain battery" risk realized.

Corner radius should follow the user's Hyprland `decoration:rounding` rather
than a constant, or the outline will not sit on the window edge. Read it once
per effect from `hyprctl -j getoption decoration:rounding`, cached, refreshed on
`configreloaded`.

### 1.4 Settings

Two new keys, added to **both** `manifest.json` and `Panel.qml`:

| Key | Type | Options / range | Default |
| --- | --- | --- | --- |
| `entranceEffect` | enum | `Off`, `Glow` | `Glow` |
| `effectIntensity` | integer | 0-100, step 10 | 50 |

Omarchy enum options are user-visible display strings that double as the stored
value, so they are cased for display and compared case-insensitively in QML.
Later presets append to `options`; never reorder or rename an existing entry,
because the stored value is the string.

Controls use installed `qs.Ui` components and `qs.Commons` typography, spacing,
color, border, and radius tokens. The custom outline/particle primitives are
confined to the overlay under EX-1; no hardcoded theme color or fixed panel
chrome is introduced.

`reduceMotion` is deliberately **not** added here. It is a master switch across
Phases 1 and 3, and adding it in the phase that has only one animation invites a
half-implementation. Phase 1 ships `entranceEffect: Off` as the escape hatch and
Phase 3 introduces `reduceMotion` covering both.

### 1.5 `Embers` follow-up

After `Glow` passes the phase gate, add the warmer “burning edge” style without
changing the geometry/surface contract:

- append `Embers` to the stable `entranceEffect` enum; never rename/reorder the
  existing `Off` and `Glow` values
- use a thin amber/red irregular halo plus a moving perimeter highlight, not a
  full-screen flame shader
- emit a finite, capped set of sparks (initial cap: 12), each confined to a
  small gutter around the terminal, and delete/disable them after lifetime
- drive the effect from one normalized progress/generation so rapid show/hide
  cancels every stale callback
- reduced motion later maps `Embers` to a static warm outline or no effect

Profile it separately from `Glow`. If it cannot return to the same idle baseline
or introduces visible clipping at fractional scale, keep it experimental and
ship only `Glow`.

## Verification

```
# input pass-through: the single most important check
# summon the terminal, and while the glow plays, click inside the terminal
# and type. Keystrokes must land in the terminal, not be swallowed.
hyprctl -j layers | jq '.. | objects | select(.namespace? != null) | .namespace'
#   the effect namespace must appear only while playing, and vanish after

# geometry at fractional scale (requires Phase 0.6)
hyprctl output create headless
hyprctl keyword monitor HEADLESS-2,1920x1080@60,3440x0,1.25
#   summon on each output in turn; the outline must sit on the window edge
#   with no hairline gap and no overhang on either

# cross-monitor summon
#   summon on DP-1, then press the hotkey with HEADLESS-2 focused;
#   the effect must appear on HEADLESS-2 only

# idle cost
#   with the terminal hidden and again with it visible-but-settled,
#   the shell process must show no continuous render work

# theme and scaling
#   test a light, dark, square-corner, thick-border, translucent, and
#   high-contrast theme; then repeat at the minimum and maximum text scale
```

## Acceptance criteria

- The effect never intercepts input: clicks and keystrokes reach the terminal
  throughout, verified manually and by the empty input mask.
- The outline aligns with the terminal edge at scale 1 and at fractional scale,
  on both a real and a headless output.
- The effect appears on the output the terminal was summoned to, including after
  a cross-monitor summon, and on no other output.
- The effect starts when the descent finishes, not when the workspace becomes
  visible.
- After the animation, the surface is unmapped and the process returns to its
  idle baseline; nothing renders continuously while the terminal is hidden.
- `entranceEffect: Off` results in no surface being created at all, not a
  transparent one.
- No global compositor setting is read-modify-written anywhere in this phase.
- The effect follows theme colors/radius and remains decorative; disabling it
  changes no status meaning.

## Out of scope

- A literal flame simulation. The bounded `Embers` follow-up above is allowed
  only after `Glow` proves placement, scaling, click-through, and idle cleanup.
- The pet, which reuses this surface — Phase 3 generalizes
  `TerminalEffects.qml` into a coordinator; Phase 1 should not pre-generalize it.
- Any per-window or global border color change.

## Open questions

- Does `hl.dsp.window.set_prop` accept a gradient for `active_border_color`?
  Answering this decides whether a static gradient border is available as a
  cheap `reduceMotion` substitute in Phase 3. Test on a scratch window.
- Does an overlay-layer surface with an empty input region still block the
  terminal's own resize edges under `special_fallthrough`? The
  `allowSpecialFallthrough` setting changes pointer routing while the dropdown
  is open, and the interaction with an overlay gutter is untested.

## Implementation record — 2026-09-05

The Glow slice is implemented in `TerminalEffects.qml` and loaded lazily by
each existing `BarWidget.qml` screen instance. It uses the observed terminal
rectangle and monitor, a bounded settle/refresh lifecycle, the Hyprland
rounding query cache, an empty input region, and a finite particle cap. The
`entranceEffect` (`Off`/`Glow`) and `effectIntensity` (0–100, step 10) settings
are present in both the manifest and the native settings panel. The Embers
variant remains the explicitly gated follow-up above and is not enabled before
Glow receives the live placement and input-pass-through check.
The lifecycle also re-arms from terminal-monitor transitions, never arms a
non-owner output, preserves a configured zero radius, and makes intensity 0
fully invisible.

Automated verification on this checkout: `bash tests/run.sh` (60 checks),
`qmllint` for all plugin QML files, `jq empty manifest.json`, `bash -n` for all
helpers, and `git diff --check` all pass. Live compositor checks are pending in
this shell because `hyprctl -j monitors` cannot connect to a Hyprland socket;
the headless-output, fractional-scale, input-pass-through, theme, and idle
sampler checks must be run from the active Omarchy session before release.
