# Phase 3: pet packs

Ships an optional animated pet on the terminal's edge, and the master
`reduceMotion` setting that both this phase and Phase 1 respect.

Depends on: Phase 1 (the overlay surface and its geometry synchronization).

Design gate: [PD1, PD6, PD7, PD9–PD12, and EX-1](../design-rules.md#phase-rule-gates).

Independent of Phase 2. Can be skipped entirely without affecting any other
phase; it is the only phase whose value is purely aesthetic, so it is also the
first candidate to drop if the earlier phases run long.

## Scope decision

Ship three pets against one fixed action contract: penguin, fluffy cat, and
corgi. The renderer and controller are species-agnostic; each pack is
validated independently before its manifest is loaded. This keeps new pets
cheap to add without allowing one sprite sheet to redefine the contract.

Pet interaction — click, drag, feed — was explicitly out of scope for Phase 3.
Phase 5 supersedes that boundary for bounded click-and-hold petting; drag and
other interactions remain out of scope. During Phase 3 the overlay had an empty
input region by construction (Phase 1.1), which kept the terminal usable. Phase
5 now punches only the bounded, resize-safe hole described in its item 5.0.
That is a separate feature with its own input-routing design.

## Animation and personality contract

“Cute” is an authored timing and pose contract, not just a sprite sheet. The
penguin ships with these actions:

| Action | Intent | Target timing |
| --- | --- | --- |
| `peek` | eyes/head appear from behind the top edge | 100-140 ms |
| `enter` | short hop onto the edge with mild stretch | 180-240 ms |
| `land` | one squash frame and at most two dust particles | 80-120 ms |
| `idle` | blink/breathe with long quiet holds | 1-4 s loop |
| `walk` | top-edge locomotion with a planted contact point | 90-140 ms/frame |
| `corner` | authored turn between top and side tracks | 250-400 ms |
| `climb` | dedicated side-facing frames | 120-180 ms/frame |
| `dance` | focus reaction, wave or two-step | 450-700 ms |
| `success` | hop, wing raise, two-frame sparkle | about 620 ms |
| `failure` | concerned look and small shake, never an alarming loop | under 800 ms |
| `exit` | drop/duck behind the edge if time permits | under 180 ms |
| `sleep` | rare low-activity idle | slow loop |

The first appearance is a roughly 500 ms `peek -> enter -> land -> idle`
sequence. A first focus may dance; later focus reactions are rate-limited to one
per eight seconds. Success/failure reactions are optional when Phase 2 is not
installed. Tier 0 urgency is not treated as success or failure because it has
no exit semantics.

All pet poses and effects are decorative under PD1/EX-1. A success or failure
pose may run only from a precise Phase 2 event; idle, focus, and urgency-driven
motion never borrow those semantic poses or glyphs.

## Planned files

```text
TerminalEffects.qml or FloatingTerminalOverlay.qml  shared click-through surface
PetController.qml                                   priority, cooldowns, generation
PetMotion.qml                                       perimeter projection and paths
PetSprite.qml                                       atlas frames and timing
PetEffects.qml                                      bounded dust/hearts/stars
bin/omarchy-dropdown-terminal-pet-validate          one-shot external-pack validator
assets/pets/{penguin,cat,corgi}/
  pet.json
  pet.png
  bar.png
  LICENSE
  SOURCE
```

Keep movement, reaction, and frame correction separate:

```text
screen position = perimeter projection(edge, u)
                + reaction offset
                + per-frame anchor correction
```

No two animation layers write the same base `x`/`y` property.

## Work items

### 3.1 Generalize the overlay into a coordinator

Phase 1 shipped `TerminalEffects.qml` as a single-purpose glow surface. This
phase turns it into a coordinator hosting two independent visual layers on the
same click-through surface:

- the finite entrance effect from Phase 1
- a long-lived pet layer

The two have different lifetimes, which is the reason they need a coordinator
rather than one component: the effect unmaps after ~800 ms, while the pet stays
for as long as the terminal is visible. The surface must stay mapped while
either layer wants it, and unmap when neither does.

Consequence for Phase 1's hard lifetime rule: `updatesEnabled: false` on
completion becomes "when no layer is active". Keep the rule; move the condition.

### 3.2 Perimeter motion model

Represent the pet's position as `{edge, u}`, or equivalently one normalized
scalar split into four named edge segments. Derive x, y, and facing from that
value plus the terminal rect. This makes walking across the top, climbing a
side, and traversing the bottom one continuous model rather than three
unrelated animations, and it means a terminal resize relocates the pet without
discarding progress.

Add a short ballistic reaction offset for jumps on top of the derived position.
Mirror only actions declared mirror-safe; corner and climb frames can require
dedicated orientations. Each frame supplies a contact anchor so changing
silhouette never makes feet/flippers skate along the border. Round only the
final sprite origin for pixel sharpness, not the terminal rectangle.

The pet must clamp to the visible rect. At the terminal's final position the
top edge sits at `top_margin`, which the helper computes as at least 24 logical
pixels below the monitor origin (`bin/omarchy-dropdown-terminal:280`), so a pet
standing on the top edge has room. During the descent it does not — which is
one more reason the pet layer, like the glow, arms only after the rect settles.

### 3.3 State machine

```text
hidden -> enter/fall -> land -> idle
                         |       |
                         |       +-> walk/climb -> idle
                         |       +-> random look/sleep -> idle
                         +-> celebrate -> dance -> idle
terminal hidden -> pause -> hidden
```

Triggers:

| Trigger | Transition |
| --- | --- |
| terminal rect settles after a summon | `hidden -> enter` |
| terminal focused | `idle -> celebrate` (rate-limited) |
| unread command completion from Phase 2 | `idle -> celebrate` on next reveal |
| idle timer, infrequent | `idle -> random action -> idle` |
| terminal hidden | any `-> pause -> hidden` |

The Phase 2 trigger is optional: if Phase 2 has not shipped, the pet has one
fewer reason to dance and nothing else changes. Do not make Phase 3 depend on
Phase 2.

Controller priority is explicit: hidden/closed, invalid geometry/output,
enter/exit, failure, success, first-focus dance, corner/climb completion,
walking, idle/sleep. Every action owns an increasing generation token; delayed
callbacks and animation completions are ignored when a higher-priority event
has advanced it. This prevents a stale landing callback from restarting the pet
after hide.

Use declarative `NumberAnimation`, `SequentialAnimation`, and
`ParallelAnimation` for motion, one timer for variable sprite-frame durations,
and one slow decision timer while visible and idle. Do not copy a continuous
40 ms JavaScript physics loop. Cap presentation at 12-24 fps; the pet is
decorative and a higher rate buys nothing at sprite resolution.

### 3.4 Power behavior

The pet is the one long-lived animation in the whole plugin, so it is the one
that can actually cost battery:

- Animation stops when the terminal is hidden — not "pauses the timer" but
  `updatesEnabled: false` on the surface, and unmapped if the glow is also
  inactive.
- No full-screen animated surface ever stays alive in the background. Verify by
  checking `hyprctl -j layers` after hiding the terminal: the namespace must be
  gone.
- The idle random-action timer must not tick while hidden.
- `petActivity` bounds how much animation runs while visible.

### 3.5 Assets and licensing

- Original or generated sprites, or assets with explicit redistribution terms.
- Each `assets/pets/<species>/` pack carries a `LICENSE` and a `SOURCE` file recording
  author, origin, and terms, beside the sheet.
- The repository is MIT (`LICENSE`); a sprite sheet under incompatible terms
  cannot ship in-tree. Resolve licensing before drawing the state machine
  against a specific sheet's frame layout.

The bundled packs are data and PNG images only. Use a fixed 32x32 transparent
canvas, at most eight frames per row, integer render scale, `smooth: false`, and
`mipmap: false`. `bar.png` is separately authored for roughly 20 px display;
do not shrink a detailed atlas frame and assume it remains readable.

`pet.json` is versioned and includes atlas/frame dimensions, render scale,
actions, frame indices, per-frame durations, loop flags, per-frame contact
anchors, and bounded fallback action names. `idle` is required. Validate before
loading:

- canonical paths stay below the pack directory; reject absolute paths, `..`,
  symlinks, devices, sockets, FIFOs, and executable content
- JSON and PNG files have per-file and total size limits; verify PNG signature
  and dimensions
- bound rows, columns, actions, frames/action, frame durations, total
  non-looping duration, render scale, and metadata lengths
- every frame/anchor is in range; fallback chains have no cycle
- failure falls back to the bundled penguin or disables the pet with one
  concise diagnostic, never prevents the widget from loading

Bundled assets are validated in tests/build review. If external packs are
enabled, run the validator helper once when a pack is selected or changes; QML
alone cannot safely prove file type, ownership, canonical path, or symlink
status. Validation is never placed on an animation/frame path.

The architectural lessons from Bitmochi, Omagotchi, and Omarchy Pets are useful,
but their art/code is not copied by default. Record exact source revision,
author, license, and modifications for every imported file.

### 3.6 `reduceMotion`

One boolean, covering both phases:

| Behavior | `reduceMotion: false` | `reduceMotion: true` |
| --- | --- | --- |
| Entrance effect | selected finite finish plus particles | static border accent, or nothing |
| Pet | full state machine | static sprite, or hidden |
| Bar icon (Phase 2) | bounce / shake | colored dot only |
| Infinite animation | idle actions run | none, anywhere |

It must stop **all** infinite sprite animation, not merely slow it. The
Phase 2 icon animations are in scope even though Phase 2 shipped earlier — that
is why the setting lives here rather than being introduced twice.

If a static border accent is chosen as the reduced-motion substitute for the
glow, it depends on the open question from Phase 1: whether
`hl.dsp.window.set_prop` accepts a gradient, or only a single color. A single
color is sufficient; do not block on the answer.

## Settings

| Key | Type | Options / range | Default |
| --- | --- | --- | --- |
| `petEnabled` | boolean | — | `false` |
| `petSpecies` | enum | `Penguin` | `Penguin` |
| `petActivity` | enum | `On focus`, `Always while visible`, `Celebrations only` | `On focus` |
| `reduceMotion` | boolean | — | `false` |

A one-option enum for `petSpecies` looks odd in the generic settings UI. Either
omit it from `manifest.json` until a second pack exists and keep it only in
`Panel.qml`, or ship it as a placeholder — decide when the panel is laid out,
and note that enum option strings are the stored value and must never be
reordered or renamed afterwards.

When external/dynamic packs are supported, keep `petSpecies` as a validated
string controlled by the hand-built panel rather than using display text as a
pack ID. Every setting still needs a manifest default and a matching
`Panel.qml` control where applicable; dependent controls are hidden/enabled in
the panel because the manifest has no conditional schema.

## Verification

```
# no clipping on any edge
#   walk the pet a full lap at widthPercent=20 and 100, heightPercent=20 and 100
#   nothing may render outside the effect gutter or overlap the bar

# input
#   with the pet visible, click and type everywhere along the terminal edge,
#   including on top of the pet; every event must reach the terminal

# no animation while hidden
hyprctl -j layers | jq '.. | objects | .namespace? // empty'
#   hide the terminal; the effect namespace must disappear
#   sample process CPU: must return to idle baseline

# rapid show/hide
#   hammer the hotkey; the pet must never be left mid-fall, duplicated,
#   or stranded at a stale position

# fractional scale (requires Phase 0.6)
hyprctl keyword monitor HEADLESS-2,1920x1080@60,3440x0,1.25
#   sprites must not blur or land on half-pixels

# reduce motion
#   with reduceMotion on, no sprite animates and no glow particles emit,
#   including the Phase 2 bar icon

# deterministic controller tests
#   inject a fixed random sequence; hide/resize/failure/focus during every
#   action; no stale generation may resume, and no timer may remain after hide
```

## Acceptance criteria

- No clipping on any terminal edge at any configured size.
- No input interception anywhere, including directly over the pet.
- No animation and no mapped surface while the terminal is hidden.
- Correct behavior under rapid show/hide/focus changes: no duplicate pets, no
  stranded state, no animation resuming after a hide.
- Clean rendering at scale 1 and at fractional scale.
- `reduceMotion` stops every infinite animation across Phases 1, 2, and 3.
- Every sprite sheet has recorded author, source, and license, compatible with
  MIT redistribution.
- Every frame's contact anchor remains within one logical pixel of the intended
  border track through animation, resize, and fractional-scale rounding.
- Invalid or hostile pack fixtures are rejected without loading code or
  preventing the dropdown from working.

## Out of scope

- Drag, feed, and other pet interactions beyond Phase 5's bounded click-and-hold petting.
- Pet persistence across shell reloads. The pet re-enters on the next summon;
  remembering where it was standing was judged not worth the state. Superseded
  by Phase 6 item 6.3, which adds a single-writer runtime document for it.

## Resolved implementation questions

- A single `Image` with one variable-duration `Timer` is used instead of
  `SpriteSequence`/multiple animated sprites, because the fixed atlas contract
  needs per-action frame lists and bounded timing in one place.
- `reduceMotion` is plugin-local: the available Omarchy configuration exposes
  no reliable global reduced-motion preference for this plugin to consume.

## Implementation record — 2026-09-06

Phase 3 is implemented with three bundled, MIT-compatible generated packs:
penguin, fluffy cat, and corgi. `TerminalEffects.qml` now coordinates the
finite selectable entrance finishes (glow, fire/burn, firework, thunder, snow,
and rain) and the
long-lived pet surface, while `PetController.qml`, `PetMotion.qml`,
`PetSprite.qml`, and `PetEffects.qml` keep state, perimeter projection, frame
timing, and bounded effects separate. Finite actions restore the idle sprite,
queued reactions drain after autonomous actions, and perimeter movement turns
at exact edge boundaries before changing between walk and climb frames.
Precise Phase 2 results are mapped from `succeeded`/`failed` to the pet's
`success`/`failure` actions only when the completion event qualifies; generic
urgency is never used.

The species setting resolves only to validated bundled packs.
`reduceMotion` remains plugin-local after checking the available Omarchy
configuration for a reliable global preference. Bundled and hostile-pack
fixtures are covered by a decoding validator with manifest-dimension checks,
and atlas load errors are surfaced in the settings panel. Live
multi-output, fractional-scale, input-pass-through, and CPU-idle checks still
require an active Omarchy/Hyprland session.
