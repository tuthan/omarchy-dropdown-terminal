# Phase 5 (release 2.1): pet motion polish and click-to-pet

Status: implemented; automated verification passed; host matrix pending. Plan date: 2026-09-09.

Ships two user-visible changes and the settings toggles that control them:

1. Pet locomotion that reads as walking: constant pixel speed, foot-synced
   frames, no anchor pops, no backward-facing side traversal.
2. A bounded input region over the pet sprite so the user can tap or hold to
   pet it, with an authored reaction.

Depends on: Phase 3 (pet packs, perimeter model, controller).

Design gate: [PD1, PD6, PD7, PD9–PD12, and EX-1](../design-rules.md#phase-rule-gates),
with the PD12 revision in item 5.0 landing before any input code.

Insult mode is release 2.2, planned in
[phase-6-pet-world.md](phase-6-pet-world.md); villains, pet-versus-villain
encounters, and the bond meter are release 2.3, planned in
[phase-7-pet-villains.md](phase-7-pet-villains.md). They ride on the same
track and reaction system, so this phase is the base they build on; nothing
here should anticipate them beyond the optional-action mechanism in item 5.5.

## Why the current motion looks wrong

Observed: the pet "moves but circles and looks backward". These are the
mechanical causes in the shipped code, each with a concrete fix below.

| Symptom | Cause | Where |
| --- | --- | --- |
| Zooms around the border | Step length is a fraction of the perimeter, so speed scales with terminal size. At the default 90 % x 45 % on a 3440x1440 output one walk step covers about 1650 px in 2.6 s, over 600 px/s for a 32 px sprite. | `startRouteAction` in `PetController.qml` |
| Feet slide | Frame duration is authored per pack and independent of travel speed. | `PetSprite.qml` frame timer, `PetController.qml` walk animation |
| Pops sideways when it starts or stops | `idle` anchors at x 16 while `walk` anchors at x 28; mirrored, that becomes x 4. Every idle/walk transition shifts the sprite 12 px, a mirrored one 24 px. | `assets/pets/*/pet.json`, `projectedAnchorX` in `PetSprite.qml` |
| Faces the wrong way on a side | Travel is always clockwise and `climb` is not mirror-safe, so the same upward-facing frames are used to descend the right edge and to ascend the left edge with its back to the wall. | `project()` in `PetMotion.qml`, `actionForEdge` in `PetController.qml` |
| Stop-start rhythm | Each step is one `InOutSine` chunk followed by a fixed nine second idle. | `walkAnimation`, `randomDecisionTimer` |
| Snaps into corners | A corner turn is only taken when a step lands within 1e-5 of the edge boundary; otherwise the pet idles at the corner and turns on the next tick. | `finishWalk`, `startRouteStep` |
| Instant flip | Changing facing is an immediate horizontal mirror with no turn frames. | `mirrorFrame` binding in `PetController.qml` |

## Scope decision

Motion polish ships first inside this phase because click-to-pet produces a
reaction on top of the same position, and a reaction that pops or flips looks
broken regardless of how good the input plumbing is.

Default roaming is restricted to the **top edge**: the pet walks back and
forth between the two upper corners and turns around instead of climbing.
Whole-border roaming remains available and is fixed for facing, but it needs a
descending climb action that no bundled pack has today, so it degrades to
top-edge roaming until a pack supplies one. This keeps the release shippable
without redrawing every side-edge frame for three packs.

Click-to-pet is tap and hold only. Drag-to-relocate is a stretch item with its
own input-routing considerations and is the first thing cut if the phase runs
long.

## Planned files

```text
PetLayer.qml            input region (mask) bound to the sprite, minus the resize grab rect
PetController.qml       direction, pixel-speed planner, turn action, petting priority
PetMotion.qml           signed travel, wall side, direction-aware facing, per-edge remap on resize
PetSprite.qml           optional actions, mirror by wall side; frame timing stays authored
PetEffects.qml          hearts burst
PetRoute.js             pure step planner (new), unit-testable without a compositor
Panel.qml               two new controls in Animation & pets
Service.qml             two new settings readers, cached grab margin from hyprctl getoption
manifest.json           two new schema entries, version 2.1.0
bin/omarchy-dropdown-terminal-pet-validate
                        manifest version 2, optional actions, anchor continuity, stride
assets/pets/{penguin,cat,corgi}/pet.json, pet.png
                        anchor audit, climb mirror-safety, happy and turn frames
docs/design-rules.md    PD12 row revision for the pet input region
tests/run.sh            structural assertions for this phase; the Phase 3 "keeps normalized
                        progress on resize" assertion is replaced by a per-edge remap check
tests/qml/tst_pet_route.qml
                        planner tests (new, qmltestrunner)
```

## Work items

### 5.0 Design-rule revision for PD12

Phase 3 declared any pet interaction out of scope because the pet stands where
the terminal's resize handles live. This phase revises the PD12 profile row
before any code:

- The pet overlay window may carry an input region equal to the sprite
  rectangle **minus the terminal's active resize-sensitive rectangle**. When
  `resize_on_border` is on, that is the IPC client rectangle grown on every
  side by `general:border_size` plus `general:extend_border_grab_area`, because
  Hyprland's `at`/`size` exclude the border and the border grab ring extends
  outward from it. When it is off, only `general:border_size` is reserved, so
  an inactive resize ring cannot consume the pet's clickable body.
- The region exists only while `petInteraction` is on, the pet is active, and
  the sprite is visible. Hidden, reduced-to-static, or reaction-less states do
  not change the rule; an invisible pet has an empty region.
- `WlrKeyboardFocus.None` stays. Pointer input on the pet never moves keyboard
  focus. Typing while holding the pet must continue to reach the terminal.
- Only the pet window carries a region. The entrance-effect surface stays
  fully click-through.

Also mark the Phase 3 "Out of scope" bullet as superseded by this phase.

### 5.1 Signed travel and wall side (PetMotion)

`travelU` stays the single source of truth, but the controller may now
decrease it. PetMotion gains:

- `direction` (+1 or -1), set by the controller, never inferred from the
  animation.
- `facing` derived from edge **and** direction: on `top` +1 faces right and -1
  faces left; on `bottom` the reverse; on `left`/`right` the value is `up` or
  `down`.
- `wallSide` for vertical edges: `left` or `right`, so the sprite can mirror
  climb frames to keep the pet's belly to the wall.
- `topEdgeSpan` helpers exposing the normalized `u` of both upper corners so
  the top-only planner has exact bounds.

Projection and clamping are unchanged. Rounding stays on the final sprite
origin only.

**Geometry-change policy.** Preserving normalized `u` across a resize is wrong
for a pet that must stay on one edge: `u = 0.30` is on the top of a 1000x500
terminal and on the right side of a 500x500 one. On every `terminalRect`
change while the pet is active:

1. Cancel any running route animation and the planned step; the stored
   from/to `u` values are stale.
2. Remap position by **edge and fraction along that edge**, captured before
   the change: the pet stays on the same edge at the same proportional
   position. This is a jump cut, the same as today, and is acceptable because
   the terminal itself just moved.
3. Enter `idle` and let the planner replan on the next decision tick. No
   action restarts and no generation token is reused.

If the pet is on an edge the current roaming mode does not allow, whether
because the setting changed, the pack lost wall-safe climb after a species
switch, or a version 1 pack is selected, the controller plays `exit` and then
the normal `peek -> enter -> land` sequence at the top-edge start position.
Those actions are required by the contract, so the return route never depends
on optional frames. The same path handles `Whole border -> Top edge` while the
pet is mid-climb.

A petting hold that spans a resize ends: the remap runs through the normal
interruption path and the eventual release is dropped by the generation check.

### 5.2 Pixel-speed planner (PetRoute.js and PetController)

Replace the fraction-of-perimeter step with a pure planner that works in
pixels and converts to `u` at the last moment:

```text
input : edge, u, direction, roaming mode, terminal rect, pack stride, random
output: target u, direction, duration ms, sequence of actions
```

Rules:

- **Speed is constant in logical pixels**, derived from the pack:
  `speed = walk.stride * renderScale / sum(walk.durations)`. A 10 px stride
  over a 440 ms cycle is about 23 px/s at scale 1; packs may author faster.
  Bound speed to 12–80 px/s in the validator so a hostile pack cannot make
  the pet strobe.
- **Durations are the authored durations.** The runtime never rescales
  locomotion frame timing, so the stride guarantee holds exactly. Instead the
  validator bounds `walk` and `climb` frame durations to 41–250 ms, which is
  a maximum presentation rate of 24 fps and a minimum of 4 fps. The Phase 3
  "12–24 fps" guidance is read as a rate cap, not a floor; a 110 ms walk frame
  is a hold, not a dropped frame. A pack whose stride and durations produce a
  speed outside the bound is rejected with a diagnostic naming both numbers.
- **Step length** is random between 3 and 12 strides, clamped to the distance
  left on the current edge in the current direction.
- **Easing** is linear. The visual ease comes from the authored `turn` and
  `idle` frames at each end, not from `InOutSine` on position.
- **Turnaround** happens when the remaining distance is below one stride, or
  with a 25 % chance at the end of any step. In top-edge mode a corner always
  turns around; in whole-border mode it plays `corner` and continues.
- **Idle gaps** between steps are random between 3 and 9 seconds, replacing
  the fixed 9 s timer. Sleep probability and timeout are unchanged.
- **Foot sync** follows from the two rules above: one full frame cycle
  covers exactly one stride because speed is defined from the same durations
  the sprite plays. There is no second timing source to drift against. The
  frame timer restarts on each route step so the cycle begins on the first
  frame at the planned start.

The planner is a `.pragma library` JavaScript file with no QML dependencies so
it can be tested with `qmltestrunner` against fixed random sequences. The
controller keeps ownership of generation tokens, priorities, and timers.

### 5.3 Anchor continuity and facing

- **Validator rule, centring**: every mirror-safe action that the pet can
  stand in, that is `idle`, `walk`, `turn`, `happy`, `sleep`, `dance`,
  `success`, `failure`, and `land`, must anchor at exactly `x = 16` on every
  frame. Mutual agreement is not enough: a pack anchoring everything at x 28
  agrees with itself and still pops 24 px when mirrored, because the projected
  anchor becomes 32 - 28 = 4. Only the frame centre is its own mirror image.
- **Validator rule, transitions**: for every pair of actions the controller
  can chain (`land -> idle`, `idle <-> walk`, `walk <-> turn`, `turn -> idle`,
  `idle <-> happy`, `walk -> happy`, `idle <-> sleep`, `idle -> dance`,
  `idle -> success`, `idle -> failure`, `walk -> corner`, `corner -> climb`,
  `climb -> corner`, `corner -> walk`), compute the projected anchor of the
  last frame of the first action and the first frame of the second, through
  both mirror states and multiplied by `renderScale`. The difference must be
  at most 1 logical px in each axis. At render scale 2 or above this forces
  exact equality in atlas pixels, which is the intended outcome. This is the
  same 1 px limit the acceptance criteria use.
- `corner` and `climb` are exempt from the centring rule because they are not
  mirror-safe, but they are still bound by the transition rule against their
  neighbours for the wall side they are drawn for.
- **Pack audit**: re-anchor the three bundled packs to satisfy the rule.
  Where a frame is genuinely drawn off-centre, shift the pixels rather than the
  anchor; the atlas contract is 32x32. (Correction, 2026-09-09: the bundled
  atlases have no unused cells. All 64 cells of every pack contain drawn art
  and the manifests reference 39 of them; see the Phase 6 findings and known
  issue #6.)
- **Climb mirroring**: inspect the climb frames of each pack. Where the art is
  a side view clinging to a wall, mark `climb` `mirrorSafe: true` and let
  `wallSide` choose the mirror. Where it is not, the pack is limited to
  top-edge roaming regardless of the setting, with a one-line diagnostic in
  the panel ("Pack has no wall-safe climb; roaming limited to top edge").
- **Turn action**: mirror flips happen only at the midpoint of a `turn`
  sequence, never while walking. Packs without `turn` fall back to `idle` for
  one frame duration before flipping, which is still better than flipping
  mid-stride.

### 5.4 Click and hold to pet (PetLayer, PetController, PetEffects)

Input region, in `PetLayer.qml`:

```qml
mask: Region {
  item: interactionEnabled ? petController.spriteItem : null
  regions: [ Region {
    intersection: Intersection.Subtract
    // local terminal rect grown by grabMargin on every side
    x: localTerminalX - grabMargin; y: localTerminalY - grabMargin
    width: terminalRect.width + 2 * grabMargin; height: terminalRect.height + 2 * grabMargin
  } ]
}
```

`grabMargin` is read once per reveal by `Service.qml` with one process running
three `hyprctl -j getoption` queries, cached, and refreshed on Hyprland
`configreloaded`. It is `border_size + extend_border_grab_area` when
`resize_on_border` is on, and `border_size` otherwise. This is one process per
summon, not per frame, and stays within PD11. If the read fails, the fallback
is the conservative 64 px margin plus a debug log line.

Consequence for the click target: with the contact anchor at y 30 and the
normal 2 px border margin, most of the scale-1 sprite body remains clickable;
when resize-on-border is enabled, the larger grab ring is reserved and the
clickable band becomes smaller. If the remaining region for the selected pack
and scale is under 8 logical px tall, the layer disables the region and the
panel shows "Pet too small to click at this scale".

Bound to sprite geometry, so it follows the pet without any per-frame code.
Empty whenever `petInteraction` is off or the pet is inactive.

Pointer handling lives in a `MouseArea` over the sprite inside the pet window,
`acceptedButtons: Qt.LeftButton`, `cursorShape: Qt.PointingHandCursor`, hover
disabled. No `HoverHandler`, no per-move work.

Controller behaviour:

| Event | Pet state | Result |
| --- | --- | --- |
| press | idle, walk, climb, turn | interrupt, play `happy` looped while held |
| press | sleep | wake: one `idle` blink, then `happy` on the next press |
| press | peek, enter, land, exit, success, failure, dance | ignored; the press is consumed but nothing changes |
| release after < 250 ms | any petting | finish current `happy` cycle, one hearts burst, return to idle |
| release after ≥ 250 ms | any petting | finish current `happy` cycle, hearts burst, return to idle |
| hold beyond 6 s | petting | pet stops looping and returns to idle even if still held; a new press restarts |
| terminal hidden during hold | petting | normal hide path; the release is ignored by generation check |
| precise success or failure during hold | petting | reaction plays now; release is ignored; new press required to pet again |

Priority: insert `petting` between `success` and `first-focus dance`. A precise
success or failure reaction interrupts petting **immediately**; petting
interrupts idle, sleep, walk, climb, corner, and turn. Petting never revives a
hidden pet.

Consequence for the controller: today `observeCommandCompletion` celebrates
only from `idle` and queues otherwise. This phase adds `petting` to the set of
states that celebrate at once, alongside `idle`. Walking, climbing, and the
other states keep the existing queue-and-drain behaviour. After the
interruption the button may still be held; the pet stays in the reaction and
then returns to idle, the eventual release carries a stale press generation
and is ignored, and petting does not resume until a new press.

Rate limits: hearts bursts at most one per 1.5 s; `happy` may loop at most 6 s
per press. Bursts use the existing `PetEffects` particle budget with a
`hearts` preset of at most 6 particles.

Reduced motion: press swaps to the first `happy` frame for 600 ms, no loop, no
particles. Release does nothing extra.

Queued reactions: a success or failure already queued before the press, for
example one that arrived during a walk, is drained on the next `enterIdle`,
which now happens when petting ends. A press does not drop it.

Stretch, cut first: drag-to-relocate. While pressed and moved more than 8 px,
the sprite follows the pointer and the mask follows the sprite; on release the
pointer position is projected to the nearest `u` on the allowed edges and the
pet plays `land`. Requires the mask to be updated during the drag and a
decision about pointer capture on layer-shell surfaces, which is why it is not
in the committed scope.

### 5.5 Pack manifest version 2

Add `version: 2` alongside `version: 1`, both accepted by the validator and
`PetSprite.validPack`. Version 2 adds:

| Field | Required | Meaning |
| --- | --- | --- |
| `actions.walk.stride` | yes | logical pixels travelled per full walk cycle, 4–32 |
| `actions.climb.stride` | when `climb` is used | same, for vertical travel |
| `actions.happy` | optional | petting reaction, looping, 2–6 frames |
| `actions.turn` | optional | turnaround, non-looping, 2–4 frames, flips at the midpoint |
| `actions.climbDown` | optional | descending climb; enables whole-border roaming |
| `fallbacks.happy` | when absent | must name `dance` or `success` |
| `fallbacks.turn` | when absent | must name `idle` |

Version 1 packs load unchanged with a derived stride of 10 px and no optional
actions. Bundled packs are upgraded to version 2 with `happy` and `turn`
drawn into free atlas cells. `climbDown` is not drawn in this release; Phase 6
item 6.1 maps it, and the other new actions, from the existing atlas cells.

Validator changes: version switch, stride bounds, speed bounds, optional
action sequences validated with the same `seqok` rule, fallback targets for
new actions restricted as above, and the anchor continuity rule from 5.3.

### 5.6 Settings and panel

| Key | Type | Options | Default | Effect |
| --- | --- | --- | --- | --- |
| `petInteraction` | boolean | — | `true` | Input region over the pet; tap and hold to pet |
| `petRoaming` | enum | `Top edge`, `Whole border` | `Top edge` | Which edges the planner may use |

Both are plugin-local visual preferences under the profile's "no confirmation
needed" rule. Enum option strings are the stored value and are never renamed.

`petInteraction` defaults on because the pet itself is off by default, the
region is exact, and it never covers the terminal. Reviewers may argue for
default off under PD12; if so, flip only the default and the tooltip.

Panel changes, all inside the `Animation & pets` tab, in the existing Pet
section:

- The description line changes from "click-through pet" to "A decorative pet
  lives on the terminal edge. Tap or hold it to pet it. It never changes the
  meaning of the command indicator."
- The `Pet` / `Reduce motion` row becomes a `WrappedButtonGroup`-style row with
  a third toggle, `Respond to clicks`, bound to `petInteraction`. Tooltips:
  on: "On: tap or hold the pet to pet it. Clicks anywhere else still reach the
  terminal." off: "Off: the pet is fully click-through."
- A new caption `Roaming` with a two-option `ButtonGroup`: `Top edge` ("Walk
  back and forth along the top edge.") and `Whole border` ("Climb the sides
  and cross the bottom. Needs a pack with wall-safe climb frames; otherwise the
  top edge is used and a note appears here.").
- The pack diagnostic line already present shows the roaming limitation from
  5.3 when it applies.
- Controls stay visible when the pet is off, matching `Pet species` and
  `Activity`, so the manifest schema and panel agree.

`Service.qml` adds `petInteraction` and `petRoaming` readers following the
`petActivity` pattern, with unknown enum values falling back to the default.

### 5.7 Release plumbing

- `manifest.json` version `2.1.0`; two schema entries with the descriptions
  above.
- `CHANGELOG.md` entry under a new `2.1.0` heading.
- README "What's new in 2.1" replacing the 2.0 block; demo video optional.
- `docs/plan/README.md` execution-order row for this phase.

## Verification

```
# speed and stride
#   penguin at widthPercent=20 and 100: time one walk step with a stopwatch;
#   px/s must match walk.stride / cycle within 10 % at both sizes

# anchor continuity
bash bin/omarchy-dropdown-terminal-pet-validate assets/pets/penguin
#   must pass; then set every standing anchor to x 28 and confirm it fails
#   (centring), then move one walk anchor y by 1 with renderScale 2 and
#   confirm it fails (transition, scaled)

# no pops
#   record 5 s of idle -> walk -> turn -> walk -> idle at renderScale 1;
#   step through frames; the contact point must not move more than 1 px
#   between consecutive frames except during the planned travel

# facing
#   Whole border with a pack marked climb mirrorSafe: on both side edges
#   the pet's front faces the wall; Top edge: the pet never leaves the top

# geometry change
#   Top edge, pet walking: change widthPercent 100 -> 20 mid-step; the pet must
#   stay on the top edge at the same fraction and be idle, no stale step runs
#   Whole border, pet mid-climb: switch the setting to Top edge; the pet must
#   exit and re-enter on the top edge via peek/enter/land

# input, petInteraction on
#   click the upper body of the pet: happy plays, terminal gets no click
#   click the pet's feet where they overlap the border: terminal gets the click
hyprctl keyword general:resize_on_border true
#   with the pet standing on the top edge, press in the grab ring outside the
#   client rect but under the sprite: a resize must start, the pet must not react
#   press in the grab ring beside the pet: a resize must start
hyprctl keyword general:resize_on_border false
hyprctl keyword general:extend_border_grab_area 30
#   grabMargin follows after the reload but remains border_size while
#   resize_on_border is false; the pet's body stays clickable
#   set resize_on_border true and reload to verify the larger ring is reserved
#   click anywhere else along the border and inside the terminal: terminal gets it
#   hold the pet and type: characters appear in the terminal
hyprctl -j layers | jq '.. | objects | select(.namespace? == "io.github.tuthan.dropdown-terminal.pets")'
#   the pets layer is present only while the terminal is visible

# input, petInteraction off
#   click directly on the pet: terminal gets the click, pet does not react

# reduce motion
#   press the pet: one static happy frame, no hearts, no loop

# rapid show/hide while holding
#   hammer the hotkey with the button held; no stale happy loop may resume,
#   no timer may remain after hide, no hearts may spawn on a hidden surface

# completion during a hold
#   hold the pet, let a qualifying command finish in the terminal: success or
#   failure must start within one frame; keep holding through it, then release:
#   the pet must be idle, not happy, and no second reaction may play
#   repeat with a walk in progress before the press: the queued reaction must
#   play once, after the release, not twice

# planner
qmltestrunner -input tests/qml/tst_pet_route.qml
#   fixed random sequences: steps never exceed edge bounds, top-edge mode
#   never yields a side edge, turnaround always occurs within one stride of a
#   corner, durations equal distance / speed

# structural
bash tests/run.sh
```

Multi-output and fractional-scale checks reuse the Phase 3 procedure on a
headless output and record whether they were physical or headless.

## Acceptance criteria

- Walk speed is independent of terminal size and within 10 % of the pack's
  authored stride speed.
- No projected anchor movement above 1 logical px on any transition in the
  validator's pair list, in either mirror state, at every render scale a
  bundled pack declares.
- The pet never traverses a side edge with its back to the wall. Packs without
  wall-safe climb frames are held to the top edge with a visible note.
- Corners are handled inline: a step that reaches a corner turns around or
  turns the corner in the same sequence, never by idling at the corner first.
- With `petInteraction` on, clicks reach the terminal everywhere except the
  part of the sprite outside the terminal rectangle; keyboard focus never
  moves; the region is empty whenever the pet is hidden or inactive.
- With `petInteraction` off, the overlay is fully click-through, identical to
  2.0.
- Petting is interruptible by hide, success, and failure; it never revives a
  hidden pet; hearts respect the particle budget and rate limit.
- `reduceMotion` removes every loop and particle from petting.
- Version 1 packs still load and behave at least as well as in 2.0; version 2
  bundled packs pass the validator including anchor continuity.
- Both new settings round-trip through `shell.json`, appear in the Animation &
  pets tab, and unknown values fall back to defaults.

## Out of scope

Superseded: every bullet below is a Phase 6 or Phase 7 work item; see
[phase-6-pet-world.md](phase-6-pet-world.md), "Not deferred", and
[phase-7-pet-villains.md](phase-7-pet-villains.md). The list is kept as the
record of what 2.1 shipped without.

- Villains, insults, encounters, bond meter (insults: Phase 6 item 6.6;
  villains, encounters, bond: Phase 7).
- Drag-to-relocate unless the stretch item lands.
- Hover reactions or cursor following.
- Sound.
- Pet position persistence across shell reloads.
- Drawing `climbDown` for bundled packs. Whole-border roaming for bundled packs
  waits on that art.

## Resolved implementation choices

1. `petInteraction` defaults on. The input region is exact, the pet remains
   disabled by default, and the terminal client plus resize grab ring are
   subtracted from the region.
2. Bundled packs ship without `climbDown`; selecting `Whole border` visibly
   falls back to top-edge roaming until wall-safe descending art is supplied.
3. Both new settings are in the manifest schema and the native `Panel.qml`,
   with defensive readers in `Service.qml`.
4. Bundled packs use a 10 px stride and a 440 ms walk cycle, producing about
   22.7 logical px/s at scale 1. The validator rejects packs outside 12–80
   px/s so future stride values must be authored alongside their frame timing.
