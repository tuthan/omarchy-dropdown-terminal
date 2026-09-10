# Phase 6 (release 2.2): pet world

Status: complete. Plan date: 2026-09-09. Implementation completed 2026-09-10.

Ships every item Phase 5 listed as out of scope except villains, encounters,
and the bond meter, which are the 2.3 release in
[phase-7-pet-villains.md](phase-7-pet-villains.md) at the user's direction
(2026-09-09).

1. Whole-border roaming for the three bundled packs, including the descending
   climb and bottom-edge hang art that Phase 5 deferred.
2. Drag-to-relocate: pick the pet up and drop it anywhere on an allowed edge.
3. Hover reactions and bounded pointer following.
4. Voice lines ("insult mode"): authored speech bubbles on precise command
   results and petting, in four tones.
5. Sound cues, off by default.
6. Pet position persistence across shell reloads.

Depends on: Phase 5 (planner, input region, manifest version 2, `PetRoute.js`).

Design gate: [PD1–PD4, PD6, PD7, PD9–PD12, and EX-1](../design-rules.md#phase-rule-gates).
PD2 and PD3 join the pet gate for the first time because this phase adds a
persisted state document. The design-rule revisions in item 6.0 land before
any input or state code.

Nothing in the Phase 5 out-of-scope list is dropped: what is not here is in
Phase 7. Where a host constraint makes an item impossible as literally worded,
the item says what is possible, what is not, and why, and ships the possible
part. The decisions this plan needed from the user were taken on 2026-09-09
and are recorded at the end.

## Findings that change the Phase 5 premises

Two facts were established while planning this phase by inspecting the shipped
2.1 assets. Both change work items below and are corrected in the Phase 5 doc.

### The atlases are full; the manifests use 39 of 64 cells

Phase 5 assumed "every pack has 25 unused cells" that new actions could be
drawn into. Rendering each `pet.png` and counting opaque pixels per 32x32
cell shows all 64 cells of all three packs contain drawn art. The unreferenced
25 cells are finished poses, not empty space.

| Pack | Cells referenced by `pet.json` | Cells with drawn art | Opaque px in unreferenced cells |
| --- | --- | --- | --- |
| penguin | 39 | 64 | 53–386 |
| cat | 39 | 64 | 47–493 |
| corgi | 39 | 64 | 312–489 |

Consequence: new pet actions in this phase are mostly a **mapping** task, not
a drawing task. Only the penguin needs new cells (its bottom-edge hang pose),
and it has three near-empty cells to draw into once its `sleep` mapping is
corrected (see below). No pack grows beyond the 8x8 atlas contract.

### The cat and corgi manifests copy the penguin's frame indices

`assets/pets/cat/pet.json` and `assets/pets/corgi/pet.json` differ from each
other only in `name`, and their frame indices are the penguin's. The cat and
corgi sheets have their own row layouts, so several shipped actions show the
wrong pose:

| Action | Manifest cells | What those cells are on the cat sheet | On the corgi sheet |
| --- | --- | --- | --- |
| `idle` | 16–19 | walk cycle, side view | walk cycle, side view |
| `walk` | 24–27 | sitting and turning poses | turning sequence |
| `climb` | 12–14 | front-facing blink/wink | front-facing expressions |
| `corner` | 8–11 | idle blinks | idle expressions |
| `sleep` | 60–63 | two sleep frames plus two running-away frames | two sleep frames plus two running-away frames |
| `happy`, `turn` | 16, 17 | walk frames (placeholders in every pack) | walk frames |

The penguin's own mapping is also imperfect: `sleep` 60–63 includes a
behind-the-edge bump (60) and an almost empty cell (61), and `climb` 12–14 are
front-facing flipper frames rather than the back-view clinging frames in
32–34. This is recorded as known issue #6. Item 6.1 fixes all of it and adds
a test that stops it recurring.

## Scope decision

Order inside the phase follows dependency, not glamour:

```text
6.1 atlas audit and remap        every later item needs correct cells and anchors
6.2 whole-border roaming         drag drops onto allowed edges; Phase 7 villains spawn on "the pet's edge"
6.3 position persistence         Phase 7's bond document reuses the same writer discipline
6.4 drag-to-relocate             establishes pointer grab handling that hover (and Phase 7 villain clicks) reuse
6.5 hover and pointer following  establishes the region-union rule Phase 7 extends
6.6 voice lines                  the bubble and PetVoice.js are reused by Phase 7 encounters
6.7 sound                        cues attach to events defined by 6.4–6.6
6.8 settings and panel
6.9 validator, planner, tests
6.10 release plumbing
```

Rough size, for sequencing only: 6.1 M, 6.2 M, 6.3 S, 6.4 M, 6.5 S, 6.6 M,
6.7 S, 6.8 S, 6.9 M, 6.10 S. Items 6.1 and 6.2 are the ones a schedule slip
would hit, because they are art review and cannot be parallelized with code
that depends on the cells they choose.

## Planned files

```text
PetLayer.qml            mask gains: optional gaze halo; drag cursor
PetController.qml       allowedEdges, anchor compensation, family-aware reactions, drag, hover/gaze, voice, persistence hooks
PetMotion.qml           posture-family anchors (wall, ledge), room per edge, pointer-to-edge projection
PetSprite.qml           manifest version 3, edge-anchor validation
PetEffects.qml          speech bubble
PetRoute.js             allowedEdges, towardU approach planning, nearestEdgePoint()
PetVoice.js             pure line selection: no-repeat, templating, event set (new)
PetSound.qml            lazy cue player around one Process (new)
Service.qml             pet state file, voice/sound/drag/halo/remember readers, commandLatestStatus
Panel.qml               new controls, diagnostics
manifest.json           five new schema entries, version 2.2.0
bin/omarchy-dropdown-terminal-pet-validate
                        version 3 rules, edge-anchor rules, distinct-cell rule
bin/omarchy-dropdown-terminal-pet-sheet
                        dev tool: labeled atlas + per-action strips for review (new)
bin/omarchy-dropdown-terminal-voice-validate
                        one-shot lines.json validator (new)
assets/pets/{penguin,cat,corgi}/pet.json, pet.png
                        remap, version 3, hang/climbDown/notice/carried, plus alert/brave/cower/victory
                        mapped now so Phase 7 needs no atlas change
assets/voice/lines.json, LICENSE                                          (new)
assets/sounds/{pet,success,failure,land}.ogg, LICENSE, SOURCE            (new)
docs/design-rules.md    PD12 row revision (halo); state inventory row (position); EX-1 scope
docs/host-verification.md
                        implicit pointer grab on layer-shell, pw-play availability, QtMultimedia presence
docs/known-issues.md    #6 cat/corgi frame-index copy
tests/run.sh            structural assertions; copy-paste guard across packs; hostile voice fixture
tests/qml/tst_pet_route.qml      approach, U-shape, nearestEdgePoint
tests/qml/tst_pet_voice.qml      no-repeat, templating, event set (new)
```

## Work items

### 6.0 Design-rule revisions

All four land in `docs/design-rules.md` before code, mirroring Phase 5 item 5.0.

**PD12 row.** The input region on the pet surface becomes the union of:

- the pet sprite rectangle (Phase 5);
- an optional gaze halo around the pet sprite, only while `petHoverHalo` is
  not `Off`;

Phase 7 adds the villain sprite rectangle to this union. From the union, the
terminal's active resize-sensitive rectangle is subtracted exactly as Phase 5
item 5.0 defines it (the client rectangle grown by `general:border_size`, plus
`general:extend_border_grab_area` when `resize_on_border` is on). The
subtraction rule is unchanged and applies to every part of the union.
`WlrKeyboardFocus.None` stays. A pressed button keeps delivering motion to the surface until release
under the Wayland implicit grab; that is the only way pointer events can leave
the region, and it ends the moment the button is released. The row states the
halo's cost plainly: pixels inside the halo are pet input, so a click there
reaches neither the desktop nor any window under the halo. That is why the
halo defaults to `Off` and why the panel copy says so.

**State inventory row.** One new row; Phase 7 adds the bond row beside it
under the same writer rule:

| State shown or acted on | Source | Writer/authority | Missing/unsupported behavior | Freshness/reconciliation |
|---|---|---|---|---|
| Pet position | `<state root>/io.github.tuthan.dropdown-terminal.pet-state.json` | The `Service.qml` instance whose screen hosts the terminal, via `FileView` atomic writes | Missing, invalid, future-version, stale, or species-mismatched documents are ignored; the pet enters at the Phase 5 default position; debug log only | Written on settle events with a 2 s coalescing timer; read once when the pet layer is created |

**EX-1 scope.** Extends the decorative-rendering exception to the speech
bubble. The bubble uses host tokens for fill, border, radius, and type, so it
is a positioned container, not new chrome. Compensating checks are unchanged:
click-through except the declared union, bounded counts, complete
reduced-motion path, all activity stops while hidden.

**PD1 note.** Voice lines derive only from the same precise, qualifying shell
events that already drive `success`/`failure`, plus petting. Urgency, focus,
and idle time never produce a line that mentions a result. Lines may quote
the exit status and coarse duration because those are the two facts the
journal carries; they may never claim what the command was (invariant A9).

**PD11 note on processes.** A `Process` per *discrete, rate-limited user
event* (a sound cue at most every 700 ms, a state write at most every 2 s) is
recorded as within the rule; the rule's prohibition targets frames, hover
motion, and polls. The grab-margin query per reveal is the precedent.

### 6.1 Atlas audit and remap

Deliver `bin/omarchy-dropdown-terminal-pet-sheet PACK_DIR OUT.png`, a
development tool (never on a runtime path) that renders the atlas at 4x with
cell numbers and, below it, one strip per action in manifest order with
anchors marked. Every remap below is reviewed against that output before it
is committed. The "candidate cells" columns are what the labeled sheets show
today; the review confirms or adjusts them. The `alert`, `brave`, `cower`, and
`victory` rows are mapped and validated in this phase even though only Phase 7
plays them, so 2.3 needs no atlas or anchor work.

**Penguin** (sheet rows: 0 peek/enter/land, 1 flipper poses, 2 idle, 3–4
side/back views, 5 dance/success, 6 sad, 7 exit/sleep):

| Action | Current | Candidate cells | Notes |
| --- | --- | --- | --- |
| `peek` | 0, 1 | 0, 1 | unchanged |
| `enter` | 2, 3, 4 | 2, 3, 4 | unchanged |
| `land` | 5, 6 | 5, 6 | unchanged |
| `idle` | 16–19 | 16–19 | unchanged |
| `walk` | 24–27 | 24–27 | unchanged |
| `turn` | 16, 17 (placeholder) | 37, 38 | side to three-quarter; flip at midpoint |
| `happy` | 16, 17 (placeholder) | 21, 22, 20 | flipper flap loop |
| `corner` | 8–11 | 10, 11 | lean then flippers up |
| `climb` | 12–14 | 32, 33, 34 | back view; anchor x 2, y 16; wall at frame left |
| `climbDown` | — | 34, 33, 32 | same cells reversed, authored durations |
| `hang` | — | 7, 60, 61 (redrawn) | new art: dangling from the bottom edge, anchor y 2 |
| `notice` | — | 39, 38 | look up |
| `alert` | — | 11, 12 | flippers up |
| `brave` | — | 8, 9 | hop forward |
| `cower` | — | 53, 54 | crying, shiver |
| `victory` | — | 45, 46, 47 | sparkle |
| `carried` | — | 51, 55 | back turned, dangling |
| `dance` | 40–43 | 40–44 | music notes |
| `success` | 44–46 | 45, 46, 47 | sparkles |
| `failure` | 48–50 | 48, 49, 50 | unchanged |
| `exit` | 56–58 | 56, 57, 58, 59 | full duck |
| `sleep` | 60–63 | 62, 63 | frees 60, 61 for `hang` |

**Cat** (rows: 0 peek/enter/land, 1 idle expressions, 2 walk, 3 sit/turn, 4
climb/hang/pounce, 5 dance/success/hearts, 6 sad/loaf, 7 sleep/exit):

| Action | Candidate cells | Notes |
| --- | --- | --- |
| `peek` | 0, 1 | eyes over edge, head out |
| `enter` | 2, 3, 4 | |
| `land` | 5, 6 | |
| `idle` | 8, 9, 10, 11 | blink/wink |
| `walk` | 16–23 | full 8-frame cycle; stride re-timed |
| `turn` | 26, 24, 27 | side, front, other side |
| `happy` | 44, 45 | hearts |
| `corner` | 31, 30 | look up, back |
| `climb` | 32, 33, 34 | vertical cling; anchor x 2, y 16 |
| `climbDown` | 34, 33, 32 | |
| `hang` | 35, 35 | hanging from ledge; second frame is the same cell with a longer hold until a second pose is drawn |
| `notice` | 31, 8 | |
| `alert` | 49, 38 | startled, crouch |
| `brave` | 38, 39 | pounce |
| `cower` | 56, 48 | |
| `victory` | 46, 47 | |
| `carried` | 37, 36 | stretched, in-box |
| `dance` | 40, 41 | |
| `success` | 42, 43 | |
| `failure` | 48, 57 | |
| `exit` | 62, 63 | run away |
| `sleep` | 50, 51, 52, 53 | loaf, zzz |

**Corgi** (rows: 0 peek/enter/land, 1 expressions, 2 walk, 3 turn, 4
back/side, 5 ledge/celebrate, 6 dance/success/hearts, 7 sad/sleep/exit):

| Action | Candidate cells | Notes |
| --- | --- | --- |
| `peek` | 0, 1, 2 | |
| `enter` | 4, 5 | |
| `land` | 6, 7 | |
| `idle` | 8, 11, 8, 12 | |
| `walk` | 16–23 | |
| `turn` | 26, 24, 28 | |
| `happy` | 55, 54 | hearts, roll |
| `corner` | 39, 38 | |
| `climb` | 32, 33, 34, 35 | back view; anchor x 2, y 16 |
| `climbDown` | 35, 34, 33, 32 | |
| `hang` | 40, 42, 43 | hanging from ledge |
| `notice` | 15, 9 | |
| `alert` | 9, 14 | bark, howl |
| `brave` | 29, 5 | run, leap |
| `cower` | 56, 57 | |
| `victory` | 52, 53 | confetti |
| `carried` | 44, 41 | |
| `dance` | 48, 49, 50 | |
| `success` | 51, 52 | |
| `failure` | 58, 59 | |
| `exit` | 62, 63 | |
| `sleep` | 60, 61 | |

**Anchors are re-authored per pose**, not copied. The Phase 5 centring rule
(x 16 on every floor action) and transition rule (≤ 1 logical px between
chained actions in both mirror states) stay for transitions **within one
posture family** and are what the review checks. Transitions between families
(corners, landings, reactions on a wall or ledge) change the contact point by
design and are handled by anchor compensation, not by the validator; both the
families and the compensation are defined in 6.2.

**Regression guard.** `tests/run.sh` gains a copy-paste check: for each pair
of bundled packs, the `idle`, `walk`, and `climb` frame arrays must not all be
identical. The validator gains a **distinct-cells rule**: within one manifest,
two actions may share a cell only if one is listed in the other's `sharesWith`
array; `hang` reusing cell 35 twice inside one action is allowed because the
rule is between actions.

### 6.2 Whole-border roaming for bundled packs

Phase 5 fell back to the top edge because no pack had wall-safe descending
frames. Review of this plan found three further blockers in the geometry, not
the art, and all four are addressed here: side and bottom anchors put the body
inside the terminal; a corner changes the contact point, so no anchor rule
can make it seamless; at large terminal sizes there is no output space outside
an edge at all; and every resting or reacting action is drawn for a floor.

**Posture families.** Every action belongs to one family, decided by its name
in the validator. The family fixes which anchor region is legal, and the
anchor region is what keeps the body outside the terminal on every edge.

| Family | Edges | Contact | Anchor rule (version 3) | Actions |
| --- | --- | --- | --- | --- |
| floor | top | feet on the top border, body above | x 16 (centring rule), y 24–32 | `peek`, `enter`, `land`, `idle`, `walk`, `turn`, `happy`, `sleep`, `dance`, `success`, `failure`, `exit`, `notice`, `alert`, `brave`, `cower`, `victory`, `carried`, `corner` |
| wall | left, right | paws on the side border, body outward | x 0–6, y 12–20, `mirrorSafe: true`; drawn with the wall at the **left** of the frame; `PetMotion.wallSide` mirrors on the left edge so the projected anchor becomes `32 − x` | `climb`, `climbDown`, optional `wallIdle`, `wallHappy` |
| ledge | bottom | paws on the bottom border, body below | x 16, y 0–4, `mirrorSafe: true` | `hang`, optional `ledgeIdle`, `ledgeHappy`, `cornerBottom` |

Sprite origin stays `contact − projectedAnchor × renderScale`, as today.
`hang` is the bottom-edge locomotion action with a `stride` like `walk`;
direction mirroring on the bottom edge is already reversed in `mirrorFor`.
The validator rejects any anchor outside its family's region with a
diagnostic naming the action and frame.

**Transitions within a family** keep the Phase 5 rule: projected anchors of
the last and first frames agree within 1 logical px in both mirror states.

**Transitions across families cannot satisfy that rule** and are not asked
to. At the bottom-right corner the wall anchor (2, 16) and the ledge anchor
(16, 2) differ by 14 px on each axis, and the contact point itself moves
from the side border to the bottom border. The same is true of the existing
top-to-side `corner` once wall anchors are enforced. Cross-family switches are
handled by **anchor compensation** in `PetController`:

1. At the switch, compute the sprite-origin delta the anchor change implies:
   `delta = (oldProjectedAnchor − newProjectedAnchor) × renderScale`, plus the
   contact-point move when the edge changes.
2. Load that delta into `PetMotion.reactionX/Y`, so the sprite does not move
   on the frame of the switch.
3. Animate `reactionX/Y` back to 0, linear, over the duration of the corner
   action being played (`corner`, `cornerBottom`), or over 160 ms when the
   pack has none. The pet visibly swings around the corner rather than
   popping.
4. `reactionX/Y` are already the layer that the hop and the drag use, so no
   second writer touches position (Phase 3 layering rule). A compensation in
   progress is cancelled and zeroed by `invalidate()` like any reaction.

The validator's transition list is therefore split: within-family pairs are
checked; cross-family pairs (`walk → corner`, `corner → climb`, `climb →
corner`, `corner → walk`, `climbDown → hang`, `hang → climb`, `climbDown →
cornerBottom`, `cornerBottom → hang`, and every landing or reaction on a wall
or ledge) are listed as compensated and exempt. Version 2 packs keep passing
because their check is unchanged and runs only for version 2.

**Room: an edge is allowed only when the body fits outside it.** `PetMotion`
clamps the sprite inside the output, and the helper places the terminal with
a top margin of at least 24 px. So `PetMotion` gains `roomLeft`, `roomRight`,
`roomBottom`, and `roomTop` from `terminalRect` and `hostScreen`, and an edge
is allowed only when:

- a side edge has at least `(frameWidth − wallAnchorX) × renderScale` px of
  output beyond it (30 px for the bundled packs at scale 1). At
  `widthPercent` 100 there is none, and neither side is allowed;
- the bottom edge has at least `(frameHeight − ledgeAnchorY) × renderScale`
  px below the terminal. At `heightPercent` 100 the bottom border itself is
  below the output, and the bottom is not allowed;
- the top edge is always allowed: it is where the pet enters, and the
  helper's top margin (4 % of the output height, at least 24 px) covers the
  bundled packs at scale 1. A pack whose `anchorY × renderScale` exceeds that
  margin is clamped exactly as in 2.1; the review-sheet tool prints a warning
  for it and the validator does not reject it.

`PetController.allowedEdges` = edges permitted by the setting ∩ pack
capability ∩ room, recomputed on every geometry change. A pet standing on an
edge that just lost room takes the existing "edge not allowed" path (`exit`,
then `peek → enter → land` on the top edge).

**Effective roaming.** `PetController.effectiveRoaming` is derived from
`allowedEdges`, and the panel says which constraint applies:

| Setting | Pack has | Room | Effective | Panel note |
| --- | --- | --- | --- | --- |
| `Top edge` | anything | — | top | — |
| `Whole border` | climb + climbDown + hang | all | four edges | — |
| `Whole border` | climb + climbDown, no hang | all | top and both sides | "Pack has no bottom-edge hang frames; the pet turns around at the lower corners" |
| `Whole border` | no wall-safe climbDown | — | top | Phase 5 note, unchanged |
| `Whole border` | any | no side room | top, plus bottom when it has room and the pack has hang | "No room beside the terminal at this width; the sides are unavailable" |
| `Whole border` | any | no bottom room | without the bottom | "No room below the terminal at this height; the bottom is unavailable" |

**Resting and reacting off the floor.** Floor-authored `idle`, `sleep`,
`happy`, `dance`, `success`, and `failure` never play on a wall or ledge; the
controller picks by family:

| State | floor (top) | wall (sides) | ledge (bottom) |
| --- | --- | --- | --- |
| rest between steps | `idle` | never rests: on a wall edge the planner's step length is the whole remaining edge, so the pet climbs to the next corner in one step | `ledgeIdle`, else `hang` frame 0 held |
| sleep | `sleep` | not chosen | not chosen |
| petting | `happy` | `wallHappy`, else current `climb` frame held; hearts burst | `ledgeHappy`, else `hang` frame 0 held; hearts burst |
| success / failure | action plus hop | current `climb` frame held plus an outward bump (`reactionX` ±6 px over 300 ms) and the action's effect burst | `hang` frame 0 held plus a downward bump and the burst |
| focus dance | `dance` | queued until the pet is next on the floor | queued |
| hover notice | `notice` | held frame, facing unchanged | held frame |
| drag landing | `land` and dust | `climb` frame 0 held for the `land` duration, dust | `hang` frame 0 held for the `land` duration, dust |
| after any reaction mid-climb | — | the climb resumes toward the corner it was heading to | the hang step resumes |

The speech bubble (6.6) sits above the pet on the floor, beside it on the
outside on a wall, and below it on a ledge. Phase 7 runs encounters on the
floor only, so `alert`, `brave`, `cower`, and `victory` need no wall or ledge
variants in 2.3.

**Planner.** `PetRoute.planStep` gains `allowedEdges`; a corner whose next
edge is not allowed becomes a turnaround; on wall edges the step spans the
remaining edge. Tests cover: no `bottom` without hang or room; no side edge
without room; a wall step always ends at a corner.

**Speed on vertical edges** uses `climb.stride`; the validator's 12–80 px/s
bound applies to `climbDown` and `hang` too.

Reduced motion: unchanged from Phase 5; the pet stands on the top edge.

### 6.3 Pet position persistence across shell reloads

Scope is exactly the Phase 3 and Phase 5 exclusion: the pet reappears where
it was after `omarchy-shell` restarts or the plugin reloads, within one login
session. Cross-login memory is the Phase 7 bond's job, not position's; the
runtime directory is cleared at logout, which is the desired lifetime.

**Document.** `<state root>/io.github.tuthan.dropdown-terminal.pet-state.json`,
where the state root is what the helper's existing `state-root` action
returns and `Service.qml` already caches in `runtimeStateRoot`.

```json
{ "version": 1, "revision": 17, "writer": "DP-1", "species": "Penguin",
  "edge": "top", "fraction": 0.62, "direction": -1, "savedAt": 1789000000 }
```

**Writer.** The owning `Service.qml` instance (the one whose screen hosts the
terminal) through a `FileView` with `atomicWrites: true` and `setText()`.
`PetController` calls `service.savePetState(...)` on settle events: route
step end, geometry remap, petting end, drag landing, sleep start, and hide.
`Service` coalesces with a 2 s timer so a burst of settles is one write, and
writes immediately on hide because the next event may be the reload itself.
`saveFailed` is logged under `YADTM_DEBUG` and otherwise ignored; position is
a nicety, and PD3 does not require a visible state for a lost nicety.
Non-owning instances never write.

**Ownership hand-off.** `Service.qml` exists once per output, so "the owner"
changes when the terminal moves to another monitor while a coalesced write is
pending. The protocol, which Phase 7's bond document reuses:

1. Ownership is `hostMatchesTerminal`. On losing it, an instance flushes any
   pending write immediately, then stops writing.
2. A new owner calls `reload()` and waits for the result before its first
   write, so it never writes a snapshot older than the previous owner's flush.
   If no content arrives within 1 s it proceeds with its own state.
3. Every document carries `revision` (monotonic) and `writer` (screen name).
   A write whose read baseline has a lower `revision` than the file now holds
   is logged under `YADTM_DEBUG` as a lost race.

Position is a single scalar where the latest settle wins, so a lost race here
costs nothing; the protocol exists so that the bond document, whose values
accumulate, can add a read-modify-write merge on top of it.

**Reader.** When `PetLayer` is created and `petRememberPosition` is on,
`Service` reads the document once. It is used only if: `version` is 1,
`species` equals the current species, `savedAt` is within 12 hours, `edge` is
allowed by the current effective roaming, and `fraction` is finite in 0–1.
Anything else is ignored with a debug line.

**Reveal with a remembered position.** The Phase 3 `peek → enter → land`
sequence is authored for the top edge, so:

- remembered `top`: the sequence plays at the remembered fraction and
  direction, replacing the fixed 12 % start;
- remembered side or bottom: the sequence plays at the top corner adjacent to
  that edge, and the first planner step is forced along the perimeter toward
  the remembered point using the `towardU` planner input added in 6.9. The
  pet walks back to where it was rather than teleporting onto a wall.

**Settings interaction.** `Whole border → Top edge` with a remembered side
position falls into the "not allowed" branch and the default start is used.
Species change discards the document at the next write. `petRememberPosition`
off means no read and no write, and the existing file is left alone.

### 6.4 Drag-to-relocate

**Host fact to verify first** (record in `host-verification.md`): a layer-shell
surface that receives a button press keeps receiving pointer motion after the
pointer leaves its input region, until the button is released. This is the
Wayland implicit grab and is how every drag on every Wayland client works; the
probe is a throwaway `ShellRoot` with a small masked `PanelWindow` logging
`positionChanged` while dragging out of the mask. If the probe fails, drag
cannot be implemented on this host and the item reports that with the log;
nothing else in the phase depends on the answer.

**Gesture.** On press, petting starts as in Phase 5. If the pointer moves more
than 8 logical px from the press point while held, petting is interrupted and
`carried` begins: the sprite follows the pointer with the press offset
preserved, the cursor becomes `Qt.ClosedHandCursor`, the pet plays the
`carried` loop (fallback `idle`), and `PetMotion.reactionX/Y` carry the
displacement from the perimeter point so the base `travelU` stays untouched
and no second writer touches position (Phase 3 layering rule).

**Release.** `PetRoute.nearestEdgePoint(rect, allowedEdges, x, y)` returns the
nearest point on the allowed perimeter segments and its `edge` and `u`. Then:

- distance ≤ 160 px: the pet snaps its perimeter position to that point,
  `reactionX/Y` animate from the drop displacement to 0 over 220 ms
  (`OutQuad`), then the landing action for the edge's posture family plays
  with its dust burst: `land` on the floor, the held `climb` frame on a wall,
  the held `hang` frame on the ledge (table in 6.2);
- distance > 160 px: same, but the displacement animation is 320 ms and the
  hearts burst is replaced by a dust burst; the pet "falls back" to the
  border. It never stays off the perimeter.

Direction after landing points toward the farther corner of the new edge so
the next step has room.

**Interrupts.** Hide, geometry remap, species change, `petInteraction` off,
and `reduceMotion` on all end the drag through `invalidate()`; the eventual
release is dropped by the press-generation check exactly as petting releases
are. A precise success or failure during a drag is **queued** (unlike during
petting) because the pet is not on the track; it drains after `land`.

**Priority.** `carried` sits with `petting` between `success` and
`first-focus dance` in `priorityOrder`.

**Persistence.** A landing is a settle event and is saved (6.3).

**Reduced motion.** Drag works; `carried` is one static frame; the release
snaps with no displacement animation and no burst.

**Setting.** `petDrag`, boolean, default `true`, effective only while
`petInteraction` is on.

### 6.5 Hover reactions and pointer following

**Constraint, stated once.** The compositor delivers pointer position to this
surface only inside its input region, and reading `hyprctl cursorpos` is a
process per poll, which PD11 forbids. Quickshell's Hyprland module exposes no
cursor position. So the pet can know where the pointer is only when the
pointer is over pet input. "Cursor following" therefore means following the
pointer *within pet input*, and the size of that input is a user decision
with a stated cost.

**Tier 1, always available with `petInteraction`.** The pet `MouseArea` gains
`hoverEnabled: true`. On enter from `idle`, `walk`, or `sleep`, the pet plays
`notice` (fallback `idle`) and faces the pointer. Facing is quantized into
three zones relative to the anchor (left, centre, right) so bindings change
only on zone change, never per motion event. On exit, `idle` resumes after a
400 ms hold. One `notice` per 2 s. Sleep is woken by hover exactly as by
press today.

**Tier 2, opt-in gaze halo.** `petHoverHalo` enum `Off`, `Small`, `Large`
(default `Off`) adds a rectangle of 24 or 48 logical px around the sprite to
the mask, minus the grown terminal rectangle. Inside the halo:

- the pet notices and faces the pointer as in tier 1;
- if the pointer dwells ≥ 600 ms on one side, the pet takes one planner step
  of 1–3 strides toward it (`towardU`), at most once per 4 s, only from
  `idle`;
- a press inside the halo but outside the sprite is consumed and does nothing.

Panel copy states the cost: "Clicks inside the halo reach the pet layer, not
the desktop or a window behind it. The terminal itself is never covered."

**Reduced motion.** `notice` is a single frame for 600 ms; no follow step.

### 6.6 Voice lines

**Setting.** `petVoice` enum `Off`, `Kind`, `Sassy`, `Savage`, default `Off`.
Stored strings are stable. Every tone is available to everyone in this release
and stays so: Phase 7 never locks a selected tone, it adds extra lines that the
bond unlocks on top of the chosen tone.

**Triggers and facts.** A line may fire on:

| Event | Source | Facts a line may use |
| --- | --- | --- |
| precise qualifying `failed` | `commandLatestFinishKey` change with `commandLatestResult === "failed"` | exit status, duration bucket |
| precise qualifying `succeeded` | same, `"succeeded"` | duration bucket |
| petting release | 5.4 | none |
| rare idle | decision timer, 5 % of idle decisions, `Kind` and `Sassy` only | none |

`Service.qml` publishes `commandLatestStatus` (the integer already stored in
`session.commands[key].status`) alongside the existing result and duration.
Duration buckets are `under 10 s`, `10–60 s`, `1–10 min`, `over 10 min`;
the bubble never prints a precise duration because the indicator already
does, and the pet is decoration (PD1).

**Lines file.** `assets/voice/lines.json`, bundled and validated once by
`bin/omarchy-dropdown-terminal-voice-validate` (jq), never on a frame path:

```json
{ "version": 1,
  "tiers": { "Kind": {...}, "Sassy": {...}, "Savage": {...} },
  "species": { "Cat": { "Sassy": { "failed": [ "..." ] } } } }
```

Each tier maps event → array of 6–40 lines. A line is a string or an object
`{ "text": "...", "minPeakTier": 0–3 }`; the object form exists so Phase 7 can
add unlockable lines without changing the format, and the 2.2 file uses only
strings. The events in this release are `failed`, `succeeded`, `petting`, and
`idle`; the validator carries the known list as data so Phase 7 can extend
it. A line is ≤ 72 printable characters,
no control characters, no newlines, and the only templates are `{status}` and
`{duration}`. Species overrides are optional and merged in front of the tier
list. The validator rejects unknown events, unknown templates, empty arrays,
and any line containing a `$`, backtick, or `{` other than the two templates,
so a line can never look like shell.

**Content rules**, checked in review, not by code: lines roast the command
outcome, never the person; no identity attributes, no slurs, no profanity in
`Kind` or `Sassy`, at most "damn"/"heck"-level in `Savage`; nothing that could
be read as a claim about what the command did beyond its status and duration.
Examples: `Kind`/failed: "Exit {status}. Happens to the best of us.";
`Sassy`/failed: "Exit {status}? Bold strategy."; `Savage`/succeeded after
`over 10 min`: "Only {duration}. I aged."

**Selection.** `PetVoice.js` is a pure library: `pickLine(lines, tier, event,
species, recent, random)` merges species overrides, excludes the last 5 lines
shown, fills templates, and returns the line. It takes an optional `unlocks`
argument (a peak tier, Phase 7) and skips lines whose `minPeakTier` exceeds
it; unset means every line is available. Tests inject fixed randoms.

**Bubble.** In `PetEffects.qml`: one bubble at a time, host tokens only
(`Color.background` fill at the panel's alpha, `Color.foreground` text,
`Color.popups.border`, `Style.cornerRadius`, `Style.font.bodySmall` which is the PD7 data
floor), a 6 px tail toward the anchor, positioned above the sprite and
clamped inside the output, flipped below the sprite when the pet is on the
bottom edge. Visible for 2.4 s plus 40 ms per character, capped at 4 s; fades
over 160 ms. Dismissed by hide, by a new bubble, and by `invalidate()`. Rate
limit: one bubble per 8 s. The bubble is not part of the input region.

**Reduced motion.** The bubble appears and disappears without fades; timing
unchanged. `Off` means no bubble ever, and the lines file is never read
(A10).

### 6.7 Sound cues

**Decision: an external player per cue, not QtMultimedia.** `QtMultimedia`
is installed (`/usr/lib/qt6/qml/QtMultimedia`, `SoundEffect` exported) but
importing it would load an audio backend into `omarchy-shell` for every user
of the plugin, including the default with sound off, unless the import is
behind a `Loader`; even then the backend stays resident after the first cue.
`pw-play` and `paplay` are both present on the reference machine and are the
Omarchy audio stack's own tools. A `Process` per discrete rate-limited cue is
recorded as within PD11 in 6.0, and A10 holds trivially: with sound off,
nothing is loaded and nothing runs.

**Player.** `PetSound.qml`, created by a `Loader` only while `petSound` is
not `Off`, wraps one `Process`. `play(cue)` is ignored if a cue played within
the last 700 ms or the process is still running. Command:
`pw-play --volume <v> <file>`; fallback `paplay --volume <v×65536> <file>` if
`pw-play` is absent at startup (checked once with a `command -v` process at
enable time, not per cue). If neither exists the panel says
`Unavailable: pw-play or paplay not found` and no process is ever started.

**Cues** (`assets/sounds/*.ogg`, original or CC0, `LICENSE` and `SOURCE`
beside them; ≤ 48 KB each; ≤ 300 ms). Phase 7 adds `villain` and `victory`.

| Cue | Event |
| --- | --- |
| `pet` | petting release |
| `success` | pet `success` starts |
| `failure` | pet `failure` starts, soft |
| `land` | `land` after a drag |

Volumes: `Quiet` 0.35, `Normal` 0.7. `tests/run.sh` checks each file's `OggS`
signature and size bound with `stat` and `head -c 4`, with no decoder.

**Setting.** `petSound` enum `Off`, `Quiet`, `Normal`, default `Off`. Sound is
independent of `reduceMotion`; the panel places the two controls apart so the
independence is visible.

### 6.8 Settings and panel

| Key | Type | Options | Default | Effect |
| --- | --- | --- | --- | --- |
| `petDrag` | boolean | — | `true` | Drag the pet to another edge position |
| `petHoverHalo` | enum | `Off`, `Small`, `Large` | `Off` | Pointer awareness radius around the pet |
| `petVoice` | enum | `Off`, `Kind`, `Sassy`, `Savage` | `Off` | Speech bubbles |
| `petSound` | enum | `Off`, `Quiet`, `Normal` | `Off` | Sound cues |
| `petRememberPosition` | boolean | — | `true` | Restore position after a shell reload |

All are plugin-local preferences under the profile's "no confirmation needed"
rule.

Panel, Pet section, kept flat (PD8):

- Description line becomes: "A decorative pet lives on the terminal edge. Tap
  or hold to pet it, drag to move it. It never changes the meaning of the
  command indicator."
- Toggle `Flow` grows to: `Pet`, `Reduce motion`, `Respond to clicks`,
  `Drag to move`, `Remember position`. Tooltips state the on and off meaning
  as today.
- Captions with `ButtonGroup`s: `Pet species`, `Activity`, `Roaming`,
  `Voice`, `Pointer awareness`, `Sound`.
- The diagnostic line becomes a `Column` of lines, one per active limitation:
  asset, roaming, interaction, sound-unavailable. Each is one sentence in the
  shared vocabulary. Phase 7 adds its own lines to the same column.

`Service.qml` adds five readers with the `petActivity` pattern and unknown
enum values falling back to defaults.

### 6.9 Validator, planner, and tests

**Validator** (`bin/omarchy-dropdown-terminal-pet-validate`):

- Pet manifest version 3: `hang` required for whole-border, optional
  `notice`, `alert`, `brave`, `cower`, `victory`, `carried`, `cornerBottom`
  with restricted fallbacks (`notice → idle`, `alert → idle`, `brave →
  dance`, `cower → failure`, `victory → success`, `carried → idle`). The
  `kind` field is reserved: a manifest declaring any `kind` other than `pet`
  is rejected until Phase 7 adds the villain contract.
- Posture families and their anchor regions from 6.2, including the optional
  `wallIdle`, `wallHappy`, `ledgeIdle`, `ledgeHappy` with fallbacks restricted
  to `climb` and `hang` respectively.
- Distinct-cells rule and `sharesWith` from 6.1.
- Transition pairs split into checked within-family pairs, extended with
  `walk → notice`, `notice → idle`, `idle → alert`, `alert → brave`,
  `alert → cower`, `brave → victory`, `cower → victory`, `cower → failure`,
  `victory → idle`, `carried → land`, `climb ↔ climbDown`, `climb ↔ wallIdle`,
  `hang ↔ ledgeIdle`; and listed, exempt, compensated cross-family pairs
  (`walk → corner`, `corner → climb`, `climb → corner`, `corner → walk`,
  `climbDown → hang`, `hang → climb`, `climbDown → cornerBottom`,
  `cornerBottom → hang`). For version 2 packs the Phase 5 list runs unchanged.
- Versions 1 and 2 keep loading unchanged; version 3 is required for
  whole-border roaming and the new optional actions, and the panel says which
  version a pack declares when a feature is unavailable because of it.

**Planner** (`PetRoute.js`): `allowedEdges`, wall steps spanning the edge,
`towardU` (bounded approach that never overshoots), `nearestEdgePoint()`.
Tests: no `bottom` without hang or room; no side without room; a wall step
always ends at a corner; approach stops exactly at the requested standoff
distance; `nearestEdgePoint` picks the right segment at every corner and on
every allowed-edge subset.

**Motion** (`PetMotion.qml`): room values for a 3440x1440 output at
`widthPercent` 20/90/100 and `heightPercent` 20/45/100 in a qmltestrunner
test with a stub screen, and the anchor-compensation delta for each corner.

**Voice**: `PetVoice.js` tests with injected randoms: no-repeat window,
species override precedence, template filling, rejection of unknown
templates and events, string and object line forms, and `unlocks` filtering
with and without the argument.

**Structural** (`tests/run.sh`): copy-paste guard; version 3 for all three
packs; a manifest with `kind: "villain"` is rejected; lines file validates
and a fixture with a `$` line is rejected; sound files pass signature and
size; manifest version `2.2.0` and five schema entries; the design-rule
revisions are recorded; `PetSound.qml` is behind a `Loader` gated on
`petSound`.

### 6.10 Release plumbing

- `manifest.json` version `2.2.0`; five schema entries with the descriptions
  above.
- `CHANGELOG.md` entry under `2.2.0`.
- README "What's new in 2.2" replacing the 2.1 block; pets section rewritten
  for whole-border roaming, drag, hover, voice, sound, and position memory.
- `docs/plan/README.md` execution-order row and dependency paragraph.
- `docs/design-rules.md` phase gate row and the 6.0 revisions.
- `docs/host-verification.md`: implicit-grab probe result, `pw-play`/`paplay`
  presence, `QtMultimedia` presence and the reason it is not used.
- Phase 3 and Phase 5 "Out of scope" bullets marked superseded by this
  phase.

## Verification

```
# 6.1 atlas remap
bin/omarchy-dropdown-terminal-pet-sheet assets/pets/cat /tmp/cat-sheet.png
#   every action strip shows the intended pose; anchors sit on feet, paws, or ledge
bash bin/omarchy-dropdown-terminal-pet-validate assets/pets/{penguin,cat,corgi}
#   all pass at version 3; then duplicate one cell across two actions without sharesWith
#   and confirm the distinct-cells rejection names both actions
bash tests/run.sh
#   copy-paste guard passes; then copy penguin idle/walk/climb arrays into cat and confirm it fails

# 6.2 whole border
#   Whole border, each pack: one full lap at widthPercent 20 and 90, heightPercent 20 and 45
#   sides: body outside the terminal, belly to the wall on both sides, no pixel over client content
#   bottom: pet hangs below the edge, paws on the border, direction mirroring correct
#   corners: record a lap and step frames; the sprite never jumps, it swings through the corner
#   over the corner action's duration (anchor compensation); contact stays on the border
#   widthPercent 100: sides excluded, panel says no room beside; bottom still used if heightPercent < 100
#   heightPercent 100: bottom excluded, panel says no room below
#   resize from 90 to 100 % while the pet is on a side: exit, then re-enter on top
#   remove hang from a copy of the cat pack: the pet turns at the lower corners and the panel says so
#   pet the pet mid-climb: held climb frame, hearts, then the climb resumes; no floor frame appears on a wall
#   `sleep 6; false` while the pet hangs on the bottom: held hang frame, downward bump, failure burst

# 6.3 persistence
#   pet at fraction ~0.6 of the top edge; omarchy-shell restart (or plugin reload);
#   summon: peek/enter/land plays at ~0.6, not at 0.12
#   pet on the right edge; reload; summon: enters at the top-right corner and walks down to its place
#   corrupt the file: default start, one YADTM_DEBUG line, file untouched
#   switch species: old document ignored
#   disable Remember position: no file write on hide (inotifywait on the state root)
#   two outputs (headless): summon on A, pet walks, summon on B within 2 s of a settle:
#   the document's writer changes to B and its revision only increases (inotifywait + jq)

# 6.4 drag
#   probe first: throwaway ShellRoot, masked PanelWindow, log positionChanged after leaving the mask while held
#   pick up on the top edge, drop on the right edge: climb pose, body outside the terminal, land dust
#   drop 300 px away from any edge: pet returns to the nearest allowed point, no pet left off-border
#   Top edge mode: drop near the right edge lands on the nearest top-edge point
#   hide mid-drag: no carried loop after re-summon; release after re-summon does nothing
#   precise success mid-drag: reaction plays after landing, once
#   drag with resize_on_border on: press in the grab ring must still start a resize, never a drag

# 6.5 hover
#   Off halo: pointer over the sprite → notice, faces the pointer; over the desktop beside it → nothing
#   Small halo: pointer 20 px beside the pet → notice; click there → nothing happens anywhere (documented)
#   dwell 1 s on the halo's left side → one step toward the pointer, at most one per 4 s
#   move the pointer rapidly across the sprite: facing changes at most on zone boundaries
#   hyprctl -j layers: no new surface; the pets namespace only

# 6.6 voice
bash bin/omarchy-dropdown-terminal-voice-validate assets/voice/lines.json
#   passes; a copy with a line containing $HOME fails naming the tier, event, and index
#   Sassy: run `sleep 6; false` → bubble with "Exit 1"; run `sleep 6; kill -9 $$` in a subshell → status 137 line
#   two failures 3 s apart → one bubble (8 s limit), both pet reactions still play
#   hide during a bubble → gone; reduce motion → bubble without fade
#   confirm no bubble ever follows urgency, focus, or a command shorter than commandNotifyAfterMs

# 6.7 sound
#   Off: no process ever (strace -f -e execve on omarchy-shell shows no pw-play)
#   Quiet: pet release → one pw-play; two releases within 700 ms → one
#   rename pw-play and paplay out of PATH in a test shell → panel Unavailable, no process
#   reduce motion on, sound Normal → cues still play (independence is intentional)

# structural
bash tests/run.sh
qmltestrunner -input tests/qml/tst_pet_route.qml
qmltestrunner -input tests/qml/tst_pet_voice.qml
```

Multi-output and fractional-scale checks reuse the Phase 3 procedure on a
headless output and record whether they were physical or headless (PD4).

## Acceptance criteria

- Every bundled pack renders the intended pose for every action, verified
  against the review sheet, and no two bundled packs share `idle`, `walk`,
  and `climb` frame arrays.
- All three bundled packs roam every edge that has room, with the body
  outside the terminal, belly to the wall on sides, hanging on the bottom, and
  no floor-authored frame ever shown on a wall or ledge. Edges without room
  are excluded and the panel says why. Corners are continuous: the sprite
  origin never jumps, and anchor compensation completes within the corner
  action's duration.
- After a shell reload the pet re-enters at its remembered position when the
  document is valid, and behaves exactly as 2.1 when it is not. Moving the
  terminal to another output while a write is pending loses no write.
- Drag never leaves the pet off the border, never starts from the resize grab
  ring, and is cut cleanly by hide, resize, and setting changes.
- Hover reactions cost no process and no per-motion timer; the halo's input
  cost is stated in the panel and is off by default.
- Voice lines fire only from precise qualifying events, petting, and the
  rare idle line, which never mentions a result; they never contain command
  text, never repeat within five, and never exceed one per 8 s.
- Sound is absent as a process and a library when off, at most one cue per
  700 ms when on, and visibly unavailable when no player exists.
- Every new setting round-trips through `shell.json`, appears in the panel,
  and falls back to its default on unknown values.
- With every new setting at its default and the pet off, observable behavior
  is byte-identical to 2.1 (A11).
- `reduceMotion` removes every loop, fade, and follow step.

## Not deferred

Every bullet of the Phase 5 "Out of scope" list is a work item here or in
Phase 7:

| Phase 5 bullet | Where it ships |
| --- | --- |
| Insults (voice lines) | 6.6 |
| Villains, encounters, bond meter | Phase 7 (release 2.3), by the user's decision of 2026-09-09 |
| Drag-to-relocate | 6.4 |
| Hover reactions or cursor following | 6.5, with the region constraint stated and the halo option |
| Sound | 6.7 |
| Pet position persistence across shell reloads | 6.3 |
| Drawing `climbDown` for bundled packs; whole-border roaming | 6.1, 6.2 |

## Decisions taken

Recorded from the user on 2026-09-09:

1. Villains, encounters, and the bond meter are release 2.3 (Phase 7). This
   phase keeps everything else.
2. `petVillains` will default on in Phase 7.
3. The gaze halo defaults `Off`.
4. Two bundled villains; no third.

## Resolved implementation choices

1. New pet actions come from remapping the existing full atlases; only the
   penguin's `hang` is drawn new, into cells freed by fixing its `sleep`
   mapping.
2. Actions belong to posture families (floor, wall, ledge) with their own
   anchor regions, enforced by the validator in version 3; corners and other
   cross-family switches are made continuous by anchor compensation in the
   controller, and edges without output room are excluded per geometry.
3. Position state lives in the runtime directory with one writer: the
   `Service.qml` instance hosting the terminal, through `FileView` atomic
   writes. Phase 7's bond document follows the same rule.
4. Pointer following is bounded to pet input by the host; the halo is the
   user's explicit trade of desktop clicks for awareness.
5. Sound uses `pw-play`/`paplay` per rate-limited cue, not an in-process
   audio backend.
6. The Phase 7 actions (`alert`, `brave`, `cower`, `victory`) are mapped and
   validated here so the 2.3 release touches no atlas.
