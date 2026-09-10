# Phase 7 (release 2.3): villains, encounters, and the bond meter

Status: planned. Plan date: 2026-09-09.

Ships the pet's company and memory:

1. Villains: a bug or a ghost climbs onto the terminal edge after a precise,
   qualifying command failure.
2. Encounters: the pet stands up to the villain or needs the user's help, in a
   bounded state machine that always ends within 14 seconds.
3. Bond meter: a per-species 0–100 bond that petting, celebrations, and
   encounters move, persisted across logins, shown in the panel, and
   consumed by bravery odds, extra voice lines unlocked by friendship, and
   rare unprompted happiness.
4. The encounter-specific voice lines and sound cues that Phase 6 left slots
   for.

Depends on: Phase 6 (remapped atlases with `alert`, `brave`, `cower`, and
`victory`; wall and ledge anchor semantics; the input-region union rule and
its subtraction; the speech bubble and `PetVoice.js`; `PetSound.qml`; the
single-writer state discipline from position persistence).

Design gate: [PD1–PD4, PD6, PD7, PD9–PD12, and EX-1](../design-rules.md#phase-rule-gates).
The design-rule revisions in item 7.0 land before any villain or bond code.

Decisions taken on 2026-09-09: villains and bond are split out of 2.2 into
this release, at the user's direction; `petVillains` defaults on; two bundled
villains ship, keyed on exit-status class.

## Why a separate release

Phase 6 is a backlog sweep with one new mechanism per item. This phase is one
feature with many moving parts: a second sprite on the pet surface, a
sub-state machine that has to be interruptible at every beat, a persisted
score with daily arithmetic, and copy for every outcome. Shipping it alone
means its host matrix (interrupt every beat with hide, resize, reload, and a
setting change, on two outputs) gets a release's worth of attention rather
than sharing one with seven other items.

## Planned files

```text
PetLayer.qml            mask union gains the villain sprite rectangle
PetController.qml       encounter priority slot, hand-offs to PetEncounter, bond hooks
PetSprite.qml           contract kinds (pet | villain)
PetEffects.qml          puff preset for vanish/defeated
PetRoute.js             no change; towardU and allowedEdges landed in Phase 6
PetEncounter.qml        villain instance, encounter state machine (new)
PetEncounter.js         pure encounter resolution and timing tables (new)
PetBond.js              pure bond arithmetic: caps, decay, tiers, bravery chance (new)
PetVoice.js             encounter events, `minPeakTier` unlocks
PetSound.qml            villain and victory cues
Service.qml             bond document reader/writer, petVillains reader
Panel.qml               Villains toggle, Bond rows, Reset bond, diagnostics
manifest.json           one new schema entry, version 2.3.0
bin/omarchy-dropdown-terminal-pet-validate
                        kind switch (pet | villain), villain contract
assets/villains/{bug,ghost}/villain.json, villain.png, LICENSE, SOURCE   (new)
assets/voice/lines.json  encounter events per tier
assets/sounds/{villain,victory}.ogg, SOURCE                              (new)
docs/design-rules.md    PD12 row (villain rectangle), state inventory (bond), EX-1 scope
docs/known-issues.md    none expected
tests/run.sh            villain packs validate; hostile villain fixtures; encounter and bond structure
tests/qml/tst_pet_encounter.qml  deterministic outcomes and interruption (new)
tests/qml/tst_pet_bond.qml       caps, decay, tiers, bravery (new)
tests/qml/tst_pet_voice.qml      peakTier unlocks, encounter events
```

## Work items

### 7.0 Design-rule revisions

**PD12 row.** The input-region union from Phase 6 item 6.0 (pet sprite,
optional gaze halo) gains the villain sprite rectangle while a villain is
visible and `petInteraction` is on. The subtraction of the terminal's active
resize-sensitive rectangle, as Phase 5 item 5.0 defines it, applies to the
villain rectangle too. `WlrKeyboardFocus.None` stays. The villain rectangle
exists only during an encounter; there is never a villain without an
encounter.

**State inventory row.**

| State shown or acted on | Source | Writer/authority | Missing/unsupported behavior | Freshness/reconciliation |
|---|---|---|---|---|
| Pet bond | `${XDG_STATE_HOME:-~/.local/state}/io.github.tuthan.dropdown-terminal/bond.json` | The `Service.qml` instance whose screen hosts the terminal, via `FileView` atomic writes (the Phase 6 position-writer rule) | Missing → all species at 0 with the tier word `Wary`; unreadable or future version → panel shows `Unavailable` and no write ever happens until a successful read | Read on load and on `FileView` change; other instances are readers only; writes coalesced to one per 2 s and forced on hide |

**EX-1 scope.** Extends the decorative-rendering exception to villain sprites
and the `puff` particle preset, and to the panel-side bond track (a
`Rectangle` pair on host tokens, because the host kit has no progress
component). Compensating checks are unchanged.

**PD1 note.** A villain is a decorative reading of a real, precise event: a
qualifying `failed` result from the shell integration. The choice between the
bug and the ghost is keyed on the exit status class (1–127 versus 128 and
above, which is a signal death in POSIX shells). That mapping never appears
as a status claim anywhere but in which sprite shows up; the bar tooltip and
indicator are unchanged. Urgency, focus, and idle time never spawn a villain.

### 7.1 Villain pack contract and validator

`assets/villains/<id>/villain.json`, `villain.png`, `LICENSE`, `SOURCE`. Same
32x32 cell contract as pets; atlas at most 8 columns by 4 rows; the villain
declares its own `renderScale`, which need not equal the pet's.

`villain.json` carries `kind: "villain"`, `version: 1`, and:

| Action | Required | Loop | Notes |
| --- | --- | --- | --- |
| `appear` | yes | no | rises from behind the edge, ≤ 400 ms total |
| `idle` | yes | yes | |
| `walk` | yes | yes | `stride` 4–32; speed 12–60 px/s (slower cap than pets so the pet can always outpace it) |
| `taunt` | yes | yes | 2–6 frames |
| `flee` | yes | no | ≤ 600 ms |
| `defeated` | yes | no | ≤ 900 ms |
| `vanish` | yes | no | ≤ 300 ms |
| `hang`, `climb` | optional | yes | needed only to appear on non-top edges; without them a villain spawns only while the pet is on the top edge |

Anchors follow the Phase 6 edge semantics: standing actions centred at x 16;
`climb` in the wall family (x 0–6, y 12–20, `mirrorSafe: true`); `hang` in the ledge family
(x 16, y 0–4). Fallbacks are restricted: `taunt → idle`, `flee → vanish`,
`defeated → vanish`; no other fallback is accepted.

`bin/omarchy-dropdown-terminal-pet-validate` gains a `kind` switch. Absent or
`pet` uses the pet contract; `villain` uses the table above. The file-tree,
ownership, symlink, size, PNG signature, dimension, and decode rules are
shared and unchanged. `PetSprite.validPack` mirrors the switch so a villain
manifest is never accepted as a pet or the reverse. `tests/run.sh` gets the
three hostile fixtures (traversal path, symlink, executable content) for a
villain pack, copied from the pet fixtures.

### 7.2 Bundled villains

Generated as original MIT-compatible assets with `SOURCE` records like the
pets. Two ship; a third is not planned and would follow the same contract.

| Id | Look | Spawns after | Personality |
| --- | --- | --- | --- |
| `bug` | a round beetle with antennae | precise qualifying `failed` with status 1–127 | scuttles, taunts by wiggling antennae |
| `ghost` | a small pale process ghost | precise qualifying `failed` with status ≥ 128, or status 130 when `commandCancelIsFailure` is on | drifts, taunts by looming |

`Service.qml` already publishes `commandLatestStatus` from Phase 6 item 6.6;
the villain chooser reads it alongside `commandLatestResult` and
`commandLatestQualifies`.

### 7.3 Spawn rules

A spawn is requested when a qualifying `failed` event is observed and all of
these hold: `petVillains` is on, the pet is `active`, `reduceMotion` is off,
command tracking is installed, the last encounter ended more than 90 s ago,
and no encounter is running.

- Encounters happen on the **floor** (top edge) only in this release. The
  pet's `alert`, `brave`, `cower`, and `victory` are floor actions (Phase 6
  posture families), and the bundled villains climb nothing. If the pet is on
  a wall or ledge, or in any state other than `idle`, `walk`, or `sleep`, the
  request is queued for at most 20 s and starts when the pet is next idle on
  the floor; after 20 s, or on hide, it is dropped and the ordinary `failure`
  reaction is not replayed.
- When the encounter starts, the pet's own `failure` reaction for that event
  is **not** played; the encounter is the reaction.
- A failure that happened while the terminal was hidden never spawns a
  villain on the next reveal; the queued `failure` reaction from Phase 3
  already tells that story, and a villain arriving for something the user did
  not see would read as a status claim (PD1).
- Exactly one villain at a time. A second qualifying failure during an
  encounter is queued as an ordinary `failure` reaction (one at most, the
  existing `pendingReaction`) and drains after cleanup; the 90 s cooldown
  means it never becomes a second encounter.
- **Spawn distance is bounded by the villain's speed**, not by the edge:
  `d = clamp(120, villainSpeed × 3.5 s + 64, roomOnEdge)` px from the pet, on
  the side the pet is facing away from; `roomOnEdge` is the distance from the
  pet to that corner. At the maximum villain speed of 60 px/s that is at most
  274 px, so the approach always completes inside its 4 s budget. If neither
  side has 120 px the encounter is skipped and the ordinary `failure`
  reaction plays.
- A villain pack that declares `climb` or `hang` is accepted but those actions
  are not used in this release; the panel does not mention them.

### 7.4 Encounter state machine

Owned by `PetEncounter.qml`, which instantiates the villain's `PetSprite` and
`PetMotion` inside the existing pet `PanelWindow` and coordinates with
`PetController` through explicit calls.

**Ownership.** `PetController.beginEncounter()` bumps the generation, stops
animations, and returns the token; from that call until cleanup the pet is
owned by `PetEncounter`, which drives the pet's action through the controller's
`beginSequence`-style entry points with that one token. Every encounter
callback and timer checks the token, so the controller's `invalidate()` ends
the encounter for free. `encounter` is inserted into `priorityOrder` directly
below `enter/exit` and above `failure`, `success`, `petting`, and `carried`.
While an encounter is active the controller **routes** events instead of
acting on them:

| Event during an encounter | Handling |
| --- | --- |
| precise `success` | consumed by the encounter: villain `flee`, pet `victory`, then cleanup; the success burst plays with `victory` |
| precise `failure` | queued as the ordinary `pendingReaction`, drained after cleanup |
| pet press | `cower` stage: one re-roll, immediately, with `p + 0.25`; no `happy` loop, release ignored. Any other stage: consumed, nothing changes |
| pet press then move > 8 px (drag) | the user's gesture wins: encounter ends as an interrupt, drag proceeds |
| villain press | `cower` stage: assisted branch. Other stages: consumed |
| hover on pet | no `notice`; facing unchanged |
| focus | `focusQueued`, drained after cleanup as today |
| geometry change, hide, species change, `petVillains` off, `reduceMotion` on | interrupt: villain hidden with no exit animation; pet takes the normal interruption path; nothing resumes |

Petting never delays resolution: the re-roll resolves on the press, and the
brave branch it may trigger starts at once.

**Stages and budgets.** One hard deadline covers the whole encounter: a 14 s
timer started at `appear`. When it fires, whatever the stage, the villain is
hidden, the pet goes to `enterIdle`, and the bond records nothing. The stage
budgets below sum to 14 s on the longest path so the deadline is a guard, not
the normal ending.

```text
appear     villain: appear → idle                                      pet: unchanged            ≤ 0.5 s
approach   villain: walk toward pet (towardU), stop at 64 px           pet: alert at ≤ 96 px     ≤ 4.0 s
             timeout with ≥ 32 px separation → standoff at the current distance
             timeout closer than 32 px      → villain vanish, cleanup, nothing recorded
standoff   villain: taunt                                              pet: alert hold           1.2–2.0 s
resolve    roll bravery p = PetBond.braveryChance(bond)
  brave    pet: brave (one stride toward villain) → victory            villain: defeated → vanish  ≤ 2.0 s
  cower    pet: cower loop                                             villain: taunt loop        ≤ 5.0 s, then:
             user clicks villain      → villain flee, pet victory (assisted)                       ≤ 1.5 s
             user pets the pet        → one re-roll with p + 0.25; brave branch as above           ≤ 2.0 s
             precise success arrives  → villain flee, pet victory                                  ≤ 1.5 s
             timeout                  → villain vanish, pet failure (existing action)              ≤ 1.0 s
cleanup    villain hidden; pet enterIdle; queued reactions drain; bond updated (7.6)
```

Longest path: 0.5 + 4.0 + 2.0 + 5.0 + 2.0 (re-roll at the last moment) plus
0.5 of `vanish` inside the brave budget = 13.5 s. A re-roll is accepted only
while at least 2.5 s remain before the deadline; a later press is consumed
and ignored. `PetEncounter.js` holds the pure parts: `resolve(bond, random,
assistedReroll)` returns the branch, `spawnDistance(speed, room)` returns the
distance, and the budget table is data so tests can assert every path and
that every path sum is ≤ 14 s.

The approach uses the Phase 6 `towardU` planner input so the villain never
overshoots the standoff distance, and its walk speed is bounded below the
pet's so a dragged pet is never caught.

**Reduced motion.** No villains at all. The setting stays visible with the
note "Villains are paused while Reduce motion is on".

### 7.5 Encounter input, effects, voice, and sound

**Input.** The villain sprite rectangle joins the mask while visible (7.0).
A left press on it during `cower` triggers the assisted branch; during any
other stage it is consumed and ignored. Cursor over it is the pointing hand.
Hover over it triggers one `taunt` cycle, rate-limited to one per 3 s.
Clicking the pet during `cower` is the ordinary petting press and also
triggers the re-roll.

**Effects.** `PetEffects` gains a `puff` preset (4 particles, host tokens)
for `vanish` and `defeated`, and reuses the `success` sparkles for `victory`.

**Voice.** `assets/voice/lines.json` gains the events `villainAppear`,
`victory`, `assisted`, and `defeat` per tier, validated by the Phase 6 voice
validator whose known-event list is extended. The Phase 6 limit of one bubble
per 8 s applies unchanged **outside** encounters; inside one, the budget is
at most one line per stage and three per encounter, and the encounter's last
line starts the 8 s clock for whatever follows. Lines may name the villain
kind and nothing about the command beyond what Phase 6 already allows.

**Sound.** `PetSound` gains `villain` (on `appear`) and `victory` cues,
`assets/sounds/villain.ogg` and `victory.ogg` (≤ 300 ms and ≤ 900 ms), under
the same 700 ms rate limit and the same `Off` default.

### 7.6 Bond meter

**Document.** `${XDG_STATE_HOME:-$HOME/.local/state}/io.github.tuthan.dropdown-terminal/bond.json`,
directory created `0700` by the writer on first save:

```json
{ "version": 1, "revision": 41, "writer": "DP-1", "updatedAt": 1789000000,
  "species": { "Penguin": {
    "bond": 62, "peakTier": 2,
    "pets": 140, "wins": 4, "assists": 2, "losses": 1,
    "lastInteractionDay": 20706, "decayChargedThroughDay": 20706,
    "countersDay": 20706, "dayPets": 3, "dayCelebrations": 1 } } }
```

Days are days since the epoch in local time. Three markers per species keep
three different questions apart: `lastInteractionDay` (when did the user last
do anything with this pet), `decayChargedThroughDay` (which absent days have
already been charged), and `countersDay` (which day the daily caps refer to).
`updatedAt` is informational only. `peakTier` is the highest tier ever
reached and never decreases.

**Arithmetic**, in `PetBond.js`, pure and tested:

| Event | Change | Daily cap |
| --- | --- | --- |
| petting release | +1 | +10 |
| celebrated precise success | +2 | +6 |
| encounter won alone | +5 | none |
| encounter won with help | +3 | none |
| encounter lost | −1 | none |

Range 0–100. Tiers: 0–24 `Wary`, 25–49 `Warming up`, 50–74 `Friends`,
75–100 `Inseparable`. Bravery chance `p = 0.15 + 0.70 × bond / 100`. Every
increment sets `lastInteractionDay = today`, resets the day counters when
`countersDay ≠ today`, and raises `peakTier` if the new tier is higher.

**Decay** is charged on load and at each local-midnight boundary while the
shell runs, by `applyDecay(species, today)`:

```text
for each day d in (decayChargedThroughDay, today], oldest first, at most 10 days:
  if d > lastInteractionDay + 3: bond = max(0, bond − 2)
decayChargedThroughDay = today
```

Same-day reloads are idempotent because the range is empty. An absence is
charged once, on the first load after it, never again. An interaction resets
the grace period through `lastInteractionDay` without touching the charged
marker. A document missing the new markers (there are none in the wild, but
the reader is defensive) treats both as `today`, so nothing is charged
retroactively. Decay never lowers `peakTier`.

**Writer and reader.** The Phase 6 ownership hand-off protocol applies (item
6.3): only the `Service.qml` instance hosting the terminal writes; a losing
owner flushes at once; a new owner reads fresh before its first write;
`revision` and `writer` are recorded. Because bond values accumulate, writes
are **read-modify-write over a delta log**, not snapshots:

1. Every bond mutation is queued in memory as a delta (`species`, `kind`).
2. A flush cycle (coalesced to one per 2 s, forced on hide and on ownership
   loss) does `reload()` → parse → apply the queued deltas to the fresh
   values, with caps evaluated against the fresh `countersDay` counters →
   `revision + 1` → `setText()` with `atomicWrites`.
3. If a `FileView` change notification arrives between the read and the
   write, the cycle re-runs once with the deltas still queued. On `saved`
   the applied deltas are dropped; on `saveFailed` they are kept for the next
   cycle and a debug line is logged.

`Service` never writes a bond file it could not parse; an unreadable or
future-version file yields the panel word `Unavailable`, bond features run at
tier 0, deltas are discarded, and the file is left for the user to inspect or
delete (PD3, A8). Other instances read through `FileView` change notification.

**Panel.** In the Pet section, a `Bond` caption and one row per bundled
species with the tier word, the number, and a compact track: word, shape, and
color together (PD9). The host kit has no progress component
(`/usr/share/omarchy/shell/Ui/` inventoried on 2026-09-09), so the track is a
`Rectangle` pair using `Color.accent` on `Color.popups.border` at `Style.cornerRadius`,
recorded under EX-1 in 7.0 and replaced by a host component if one appears. A
`Reset bond` `Button` opens the host `ConfirmDialog` naming the file and the
species; the reset writes zeros, including `peakTier`, and does not delete the
file. The bond is never shown in the bar (EX-2 stays narrow).

**Privacy.** The file holds counts and day numbers, nothing else.

### 7.7 What the bond changes

| Bond | Effect | Where |
| --- | --- | --- |
| current bond | bravery chance in encounters | 7.4 |
| `peakTier` | unlocks **additional** lines within the chosen tone: lines tagged `minPeakTier` 1–3 in `lines.json` become eligible at `Warming up`, `Friends`, and `Inseparable` | `PetVoice.pickLine(..., unlocks = peakTier)` |
| `Inseparable` (current) | 10 % of idle decisions play `happy` unprompted, `Always while visible` only | `decideIdleAction` |

No tone is ever locked or downgraded: the tone the user selected in 2.2 keeps
every line it had, and friendship only adds to it. Unlocks are keyed to
`peakTier`, which never decreases, so a break from the terminal (decay) can
lower bravery but never removes lines the user has already heard. The panel
shows one sentence under `Voice`: "Friendship unlocks more lines: N of M
available for <species>."

### 7.8 Settings and panel

| Key | Type | Options | Default | Effect |
| --- | --- | --- | --- | --- |
| `petVillains` | boolean | — | `true` | Encounters after precise qualifying failures |

A plugin-local preference under the profile's "no confirmation needed" rule.
`Reset bond` mutates state inside the plugin's own state directory and uses
the host `ConfirmDialog` because it discards data.

Panel changes, all in the Pet section, flat (PD8):

- `Villains` joins the toggle `Flow`. Tooltips: on: "On: after a tracked
  command fails, a villain visits and the pet reacts to it." off: "Off: no
  villains; failures play the ordinary reaction."
- `Bond` rows and `Reset bond` from 7.6.
- New diagnostic lines in the shared vocabulary: "Villains need command
  tracking" when `petVillains` is on and the integration is not installed
  (PD3: not configured is visible); "Villains are paused while Reduce motion
  is on"; "Encounters happen on the top edge" whenever `Whole border` is
  selected; "Bond: Unavailable" with the file path when the document cannot
  be read.

`Service.qml` adds the `petVillains` reader following the `petInteraction`
pattern.

### 7.9 Tests

- `tst_pet_encounter.qml` (pure): every resolve branch with injected randoms;
  every path in the budget table sums to ≤ 14 s; `spawnDistance` at speeds 12
  and 60 px/s and rooms of 100, 300, and 1000 px; a re-roll requested with
  under 2.5 s left is refused.
- `tst_pet_controller_encounter.qml` (through the controller): instantiate
  `PetController` with a stub `service` object (visible, focused, penguin,
  `Always while visible`, injected `randomValues`) and drive it:
  `observeCommandCompletion` with a failed result starts an encounter from
  idle and does not play `failure`; the same from a wall queues it and starts
  it after the pet returns to the floor; a second failure during the
  encounter drains as one `failure` after cleanup; a success during `cower`
  produces `victory` and no later `success`; a press during `cower` re-rolls
  without a `happy` loop and the release is ignored; press-and-move ends the
  encounter and starts a drag; `terminalVisible = false` at each stage leaves
  no running timer and `petState === "hidden"`; the 14 s deadline fires when
  every stage timer is stalled by the stub.
- `tst_pet_bond.qml`: daily caps hit exactly; decay charges each absent day
  once and a same-day reload charges nothing; an interaction on day 10 after
  a charge through day 9 leaves the charge in place; the −20 per-load bound;
  `peakTier` never decreases including through reset-free decay; tier
  boundaries at 24/25, 49/50, 74/75; bravery chance at 0, 50, 100; a corrupt
  document is never overwritten; two delta logs applied to the same fresh
  document in either order give the same result.
- `tst_pet_voice.qml`: `minPeakTier` filtering by `unlocks`; encounter events
  accepted; an unknown event rejected; the per-encounter budget of three.
- `tests/run.sh`: both villain packs validate; the three hostile villain
  fixtures fail; a pet manifest with `kind: "villain"` is rejected as a pet;
  `PetEncounter.qml` is instantiated inside `PetLayer`'s window and creates no
  `PanelWindow`; manifest version `2.3.0` and the `petVillains` entry; the
  design-rule revisions are recorded.

### 7.10 Release plumbing

- `manifest.json` version `2.3.0`; one schema entry.
- `CHANGELOG.md` entry under `2.3.0`, stating that friendship unlocks extra
  lines and that no 2.2 tone loses anything.
- README "What's new in 2.3" replacing the 2.2 block; pets section gains
  villains and bond.
- `docs/plan/README.md` and `docs/design-rules.md` rows already exist; update
  status.
- `docs/host-verification.md`: any new host fact met while implementing
  (none anticipated; the surface, region, and writer mechanisms are Phase 6's).

## Verification

```
bash bin/omarchy-dropdown-terminal-pet-validate assets/villains/{bug,ghost}
#   pass; hostile fixtures (traversal, symlink, executable) fail
#   feed a villain.json to the pet path (copy into a pet pack dir): rejected as a pet

# spawn and resolve
#   `sleep 6; false` → bug appears at most 274 px from the pet, approaches within 4 s, standoff, resolves
#   time every path with a stopwatch: none exceeds 14 s from appear to idle, including re-roll at the last moment
#   `sleep 6; sh -c 'kill -9 $$'` → ghost
#   bond 0: mostly cower; click the villain → flee + assisted victory; pet the pet → re-roll
#   bond 90: mostly brave
#   `sleep 6; false` twice 10 s apart → one encounter; one ordinary failure reaction after cleanup
#   fail while hidden, then summon → ordinary queued failure reaction, no villain
#   pet on a side edge (Whole border), fail → encounter starts only after the pet is back on top
#   widthPercent 20 on a 1920 px output with the pet at a corner (< 120 px both ways) → no encounter

# interrupts
#   hide mid-encounter → both sprites gone, no timers (YADTM_DEBUG), no resume on summon
#   resize mid-encounter → encounter ends, pet remaps, villain does not return
#   drag the pet mid-approach → encounter ends; villain never catches the pet
#   reduce motion on mid-encounter → ends; panel says villains are paused
#   Villains off mid-encounter → ends

# input
#   click the villain: terminal receives nothing; click beside it: terminal receives it
#   hover the villain: one taunt, at most one per 3 s
hyprctl -j layers | jq '.. | objects | select(.namespace? == "io.github.tuthan.dropdown-terminal.pets")'
#   exactly one pets layer while visible, none while hidden, no second surface for the villain

# bond
qmltestrunner -input tests/qml/tst_pet_bond.qml
#   pet 12 times in a minute → +10 exactly; celebrate 4 times → +6 exactly
#   set lastInteractionDay and decayChargedThroughDay 10 days back → −14 on load; reload same day → no change; never below 0
#   corrupt bond.json → panel "Unavailable", no write on hide, file unchanged (sha256sum before/after)
#   Reset bond → confirm dialog names the file; zeros written; tier Wary
#   two monitors (headless): only the terminal's instance writes (inotifywait on the directory)
#   Savage at bond 10 → every Savage line from 2.2 still plays; at peakTier 2 → extra lines appear
#   let bond decay from 60 to 40 → extra lines still play (peakTier), bravery drops
#   two outputs (headless): pet on A, summon on B within 2 s, pet again → bond +2, revision +2 or +1, never +1 with a lost increment

# structural
bash tests/run.sh
qmltestrunner -input tests/qml/tst_pet_encounter.qml
qmltestrunner -input tests/qml/tst_pet_voice.qml
```

Multi-output and fractional-scale checks reuse the Phase 3 procedure on a
headless output and record whether they were physical or headless (PD4).

## Acceptance criteria

- Villains appear only after precise qualifying failures with command tracking
  installed, never for a failure the user did not see, at most one at a time,
  at most one encounter per 90 s.
- Every encounter path ends within 14 s by construction, and the deadline
  timer ends anything that does not; every interrupt leaves no timer, no
  villain, and no stale callback, verified through the controller and not only
  the pure resolver.
- The villain rectangle is pet-layer input only while a villain is visible and
  never covers the terminal or its resize ring; keyboard focus never moves.
- The bond persists across logins, obeys the daily caps and decay bounds,
  shows word, number, and shape in the panel, and reads `Unavailable` rather
  than overwriting a document it could not parse.
- No tone loses a line it had in 2.2; unlocked lines are keyed to `peakTier`
  and survive decay. With `petVillains` off and no bond document present,
  2.2 behavior is unchanged (A11).
- Outside encounters the Phase 6 voice limit of one bubble per 8 s is
  unchanged; inside one, at most one line per stage and three per encounter.
- Moving the terminal to another output between a bond increment and its
  flush loses no increment.
- `reduceMotion` removes villains entirely; sound and voice budgets from
  Phase 6 are unchanged.
- Both villain packs pass the validator and the hostile fixtures fail; a
  villain manifest is never accepted as a pet.

## Out of scope

Nothing from the Phase 5 list. A third villain for cancellations was offered
and declined on 2026-09-09; the contract supports adding one without code.

## Resolved implementation choices

1. Villains are their own pack kind with a smaller contract, rendered by the
   same sprite component and motion model as pets, inside the existing pet
   surface. No second layer-shell surface.
2. The bond lives in `XDG_STATE_HOME` with the Phase 6 single-writer rule and
   is never written over a document that failed to parse.
3. `petVillains` defaults on; it reaches only users who enabled the pet and
   installed command tracking.
4. Two bundled villains keyed on exit-status class; the ordinary `failure`
   reaction covers every failure that does not become an encounter.
5. Friendship unlocks extra lines keyed to the never-decreasing `peakTier`;
   no tone is ever gated, so 2.2 users lose nothing and a break from the
   terminal costs bravery, not lines.
6. Encounters run on the floor only, so 2.3 needs no wall or ledge variants
   of the pet's reaction art; the villain contract's optional `climb` and
   `hang` are accepted for future use and unused.
7. Ownership hand-off and delta-merge writes are the answer to per-screen
   services: the bond is never written from a stale snapshot.
