# Floating Terminal Delight Features — Research and Implementation Plan

Research date: 2026-09-03

Revised: 2026-09-04 after repository, machine, and live Quickshell behavior review

Design rule: this research and its implementation phases adopt the reusable [`General Omarchy plugin design rules`](../../plugin-docs/rules/omarchy-plugin-design.md) through the project-specific [`Dropdown Terminal design-rule profile`](design-rules.md). The profile is binding where a purely functional design would otherwise conflict with truthful status, native host UI, theme ownership, explicit external mutations, reduced motion, or input safety.

## Executive recommendation

All four ideas are feasible, but they should not be built as one large feature. The lowest-risk sequence is:

1. establish one versioned shared-state model and its migration/recovery rules;
2. prototype a Quickshell-owned glow/burning border overlay;
3. add fork-free shell completion events and a hidden-terminal badge;
4. add an optional pet using the overlay's proven positioning path;
5. prototype native Hyprland groups as terminal tabs, behind a feature flag.

The most important constraints are:

- Omarchy confirms that a plugin widget appearing once in the layout is still instantiated once per screen. Core state must therefore use canonical files; a plugin entry point cannot place a single `IpcHandler` above Omarchy's screen `Variants` or use the shell's internal `manageIpc` escape hatch.
- Prompt hooks are latency-sensitive. They must use shell builtins only—no `omarchy-shell`, `hyprctl`, `jq`, `flock`, or other subprocess per command.
- Quickshell 0.3.1 already exposes the complete read path required for live geometry: `Hyprland.toplevels`, monitors, workspaces, active toplevel, raw events, `refreshToplevels()`, and each toplevel's raw IPC object. QML uses that path directly; a shell command on an animation/poll tick is unacceptable.
- `FileView.watchChanges` is only a notification mechanism: `onFileChanged` must call asynchronous `reload()`, and rapid writes can make a watch stop delivering. State readers need explicit reload handling; the command reader also needs a bounded 1 Hz re-probe while a command is running.
- Hyprland's global `borderangle` animation is disabled and overridden on this machine. Lossless restoration and per-window gradient support are unproven, so changing it is not the initial border plan.
- The current machine has only one physical output at scale 1.0. Fractional-scale coverage needs a temporary headless output; physical multi-monitor acceptance still needs another machine.

## Current architecture and reusable patterns

### Floating-terminal plugin

The existing plugin is small and intentionally stateful:

- `bin/omarchy-dropdown-terminal` serializes mutations with `flock`, stores one runtime Hyprland window address, launches the configured terminal, configures it through Hyprland dispatches, and moves it through `special:dropdown-terminal`.
- `Service.qml` registers the global shortcut, invokes toggle/hide/cleanup actions, watches focus, and reconciles persisted settings across per-output instances.
- `BarWidget.qml` owns the bar icon and settings-panel host; `Panel.qml` persists layout/behavior preferences through Omarchy's shell plugin registry.
- `bin/omarchy-dropdown-terminal-bind` optionally installs the direct binding, while `bin/omarchy-dropdown-terminal-special-fallthrough` manages its marked Hyprland input override.

Useful properties already present:

- exact-address targeting instead of title matching;
- a private per-login runtime directory with a UID-scoped `/tmp` fallback;
- atomic-ish mutation through one locked helper;
- special-workspace parking;
- per-window opacity, position, size, focus, and close dispatches;
- `hyprctl --batch` for logically grouped compositor mutations;
- config-editing helpers that preserve a user override when updating a setting.

### Omarchy and Hyprland patterns worth reusing

The local Omarchy installation also provides patterns the design should follow:

- a direct `bindd` line for a user-facing hotkey;
- `special_fallthrough` and `special_scale_factor` as explicit special-workspace behavior;
- `omarchy-hyprland-migrate` / config helper patterns for idempotent edits rather than blind appends;
- QML services that read small canonical files with `FileView`, `watchChanges`, and `onFileChanged: reload()`;
- Quickshell `PanelWindow` and `QsWindow` surfaces for bar and free-positioned overlays;
- Lua-backed Hyprland config writes through `hyprctl eval`. Eval cannot return query values (`return 1+1` still prints `ok`), so every new read/query path must use the appropriate `hyprctl -j` endpoint or Quickshell's raw IPC objects.

One immediate prerequisite is a live settings bug in `Service.qml`: its `shellConfigFile` watches changes but never reloads. `text()` therefore remains the load-time value, and `persistedSetting()` shadows the freshly injected panel setting with stale data. Phase 0 begins by adding the standard reload handler and a regression test before building any new setting on top of it.

Settings also have verified host constraints: manifest enums use a flat array of display strings that double as persisted values; the schema has no conditional-visibility field; and the installed shell/bin code does not consume third-party `minimumVersion` or `package` fields. Because this plugin's `Panel.qml` is hand-built, every setting must be added to both the manifest and the panel, with conditional presentation implemented in the panel.

## Shared state and ownership

This should be completed before visual or shell-hook features.

### Canonical state schema

Replace the single plaintext address with one versioned JSON file from the start. Even the one-window implementation uses a `clients` array, so tab support extends the schema instead of replacing it.

Illustrative shape:

```json
{
  "version": 1,
  "activeClient": "0x123",
  "visibility": "hidden",
  "clients": [
    {
      "address": "0x123",
      "session": "launch-token",
      "createdAt": 1788430000
    }
  ]
}
```

Rules:

- The helper is the only writer of membership and active-client state.
- The helper also records the current `visible`, `hidden`, or `closed` lifecycle state.
- Mutations run under the helper lock and publish by writing a temporary file followed by an atomic rename.
- Every Quickshell service instance watches the same JSON file with `FileView`, calls `reload()` when notified, and consumes the result only after that asynchronous reload completes.
- Live visual geometry comes directly from the matching `HyprlandToplevel.lastIpcObject`; the helper remains authoritative for lifecycle/membership, not rendering geometry.
- Do not create a separate per-monitor source of truth.

### Migration and recovery

On the first run after upgrade:

1. Read the legacy plaintext `address` file, if present.
2. Confirm that the address still names a live managed terminal client.
3. If valid, seed `state.json`; otherwise inspect `special:dropdown-terminal` for a recoverable managed client.
4. Atomically publish valid versioned JSON.
5. Retire the legacy file only after the JSON write succeeds.

Normal recovery should:

- prune addresses that no longer exist;
- recover a known managed window from the named special workspace when state was lost;
- avoid adopting arbitrary user windows in that workspace—prefer an exact launch token, app identity, or tracked address;
- select a deterministic active client if the recorded active client disappeared;
- rewrite repaired state atomically.

The group/tab prototype must define stronger identity before permitting multiple recovered windows.

## 1. Hidden command-completion indicator

### Three delivery tiers

| Tier | Signal | What it provides | User setup |
|---|---|---|---|
| 0 — compositor urgency | `HyprlandToplevel.urgent` for the managed client | Immediate generic “terminal needs attention” badge while hidden | None; works when the terminal/application raises urgency |
| 1 — precise Bash events | append-only start/finish journal | Running state, duration, success/failure, reliable hidden-at-finish semantics for the current default shell | Explicit Bash integration |
| 2 — complete adapters | Bash, Zsh, and Fish plus lifecycle replay/concurrency hardening | The full cross-shell contract and phase exit gate | Explicit per-shell integration |

Tier 0 is useful on day one and is roughly a small QML change, but it is not falsely labeled as universal command completion: urgency depends on terminal/application behavior and does not carry exit status or duration. Focusing/showing the managed terminal lets the compositor clear its urgency. Tiers 1–2 provide the exact semantics described below.

### User experience

The bar icon should have four restrained states:

| State | Indicator |
|---|---|
| Terminal idle or closed | normal icon |
| A command is running | slow, low-amplitude pulse |
| A qualifying command finished while hidden | one brief success or failure animation, then a persistent badge |
| Terminal shown again | badge clears and icon returns to normal |

Suggested details:

- success: mint/green ring or check pulse;
- failure: coral/red shake or small error dot;
- multiple completions: one badge with a capped count such as `9+`;
- reduce-motion mode: color and badge changes only;
- debounce very short commands with a configurable threshold, initially 2 seconds;
- never store command text or terminal output.

### Event transport: append-only journal

At terminal launch, export a per-login journal path and a random terminal-session token, for example:

```text
YADTM_COMMAND_EVENTS=$XDG_RUNTIME_DIR/io.github.tuthan.dropdown-terminal.events
YADTM_TERMINAL_SESSION=<random launch token>
```

Shell hooks append short, newline-terminated ASCII records using a single shell-builtin `printf`. A conceptual record is:

```text
v1<TAB>finish<TAB>session-token<TAB>sequence<TAB>duration-ms<TAB>exit-status<NL>
```

Required properties:

- one `printf >> "$YADTM_COMMAND_EVENTS"` call per event;
- no subprocess in `preexec`, `precmd`, or prompt-command paths;
- no command text;
- each record is short enough for the shell builtin to emit as one append write; concurrent-write behavior is a required stress test rather than an assumption based on pipe semantics;
- each shell keeps its own integer sequence counter;
- the file lives in a private `XDG_RUNTIME_DIR` directory and naturally expires at logout/reboot.

Every Quickshell service instance uses `FileView.watchChanges` on the same journal. `onFileChanged` calls `reload()` but does not parse immediately because reload is asynchronous; parsing happens from the post-reload data. The reader parses only complete newline-terminated records and remembers its processed character count plus any incomplete trailing record. While any replayed command is running, a 1 Hz timer explicitly reloads the journal because Omarchy documents that rapid successive changes can permanently silence a `FileView` watch. The timer stops when no command is running. Coalesced notifications and a stalled watch therefore do not lose a finish event.

Do not truncate or compact the journal in the MVP. Append/truncate races are easy to get wrong. The expected per-login file is small; if future measurements justify compaction, first design a generation/rotation handoff protocol. QML restart can safely replay the whole journal to reconstruct state.

The terminal helper should append lifecycle records such as `shown`, `hidden`, and `closed` outside the prompt hot path. During replay, each instance tracks visibility in journal order: a qualifying `finish` creates unread state only while the replayed terminal state is hidden, and a later `shown` clears it. The current value in `state.json` resolves startup state. This makes clearing deterministic for every monitor instance and after QML reload.

### Shell integration

The integration activates only when both the YADTM marker and a writable journal path are present. Regular terminal sessions remain untouched.

#### Bash

`bash-preexec` 0.6.0 is available in the Arch `extra` repository and is a better candidate than an untested hand-rolled DEBUG/PROMPT_COMMAND framework. It should not be adopted blindly:

- its documented import must be last in the shell startup file;
- this machine initializes Starship before the user's appended `~/.bashrc` content;
- Starship and bash-preexec both manage prompt/preexec hooks;
- the exact load order must be tested in interactive Bash before choosing system-package use or a pinned, MIT-licensed vendored copy.

The PoC must verify that existing Starship, mise, zoxide, and user `PROMPT_COMMAND` behavior still works, and that hooks are registered once across repeated shell startup.

#### Zsh and Fish

- Zsh: register `preexec` and `precmd` functions once.
- Fish: use event handlers appropriate to interactive command execution.
- Both paths use builtin `printf` only and share the same journal schema.

### Installation and uninstall resilience

The installer should add one clearly marked, idempotent block at the end of each supported shell rc file. The source must be guarded because the plugin directory can disappear or be renamed during removal:

```bash
if [[ -n ${YADTM_TERMINAL:-} && -r /resolved/plugin/path/shell/yadtm.bash ]]; then
  source /resolved/plugin/path/shell/yadtm.bash
fi
```

Provide an explicit integration-uninstall command that removes the marked rc blocks before plugin removal. A generic Omarchy plugin removal cannot be assumed to run plugin cleanup; if cleanup is skipped, the readability guard leaves a harmless no-op instead of a broken shell startup.

### Acceptance criteria

- No child process is created by a command start/finish hook.
- A long command finishing while the terminal is hidden creates exactly one unread state.
- Showing the terminal clears unread state on all monitors.
- Fast commands below the threshold do not animate.
- Exit status 0 and nonzero produce distinct states.
- Concurrent shells cannot interleave or lose complete journal records in a stress test.
- A partial final record is ignored until completed.
- QML reload and missed/coalesced file notifications reconstruct the correct state.
- Bash startup preserves Starship and existing prompt hooks.
- Ordinary non-YADTM shells are unaffected.
- Removing the plugin without cleanup does not emit shell startup errors.

## 2. Glow or burning border overlay

### Recommended implementation

Build the first version as a transparent Quickshell overlay positioned around the terminal window. It can provide:

- animated gradient stroke;
- glow halo or bloom;
- optional sparks/embers;
- appear, focus, success, and failure variants;
- clean clipping and a reduced-motion fallback.

The overlay should be click-through, should not accept keyboard focus, should never cover terminal text, and should disappear immediately when the terminal hides or closes.

### Geometry without shell polling

The Quickshell Hyprland module exposes `Hyprland.toplevels`. A `HyprlandToplevel` includes address, workspace, monitor, activation state, and `lastIpcObject`; the last IPC object contains the compositor JSON fields such as `at` and `size` after a refresh.

Prototype algorithm:

1. Watch canonical `state.json` for the active address.
2. Find the matching `HyprlandToplevel`.
3. Read workspace, monitor, activation, and `lastIpcObject.at` / `size`.
4. Trigger `Hyprland.refreshToplevels()` after state changes and while a visual effect is visible.
5. Elect only the service instance whose screen matches the terminal monitor to own any refresh timer and visible overlay.
6. Prefer compositor raw events plus an immediate refresh; use only a modest refresh rate during movement or a short animation.

`lastIpcObject` is the raw `hyprctl clients`/monitor record and is fully sufficient for the required fields; it is refreshed rather than replaced by a helper query path. Measure refresh timing and drive it from raw events plus a bounded active-animation refresh. Do not run `bash + hyprctl + jq` once per poll per monitor.

### Compositor border animation: experimental only

Hyprland supports gradients and border animation globally, but this machine reports `borderangle` as disabled and overridden. The current helper also avoids touching disabled/inherited animation nodes because it cannot restore them losslessly. It is additionally unverified whether per-window `set_prop active_border_color` accepts a gradient or only a single color.

Therefore compositor-owned rotation is not a small initial change. It can be considered only after a live, reversible PoC proves all of the following:

1. a gradient can be applied to only the managed terminal window;
2. the exact prior disabled/overridden state is restored after normal completion, interruption, and process death;
3. other windows never change;
4. no persistent global config edit is required.

If any condition fails, reject this path and keep animation entirely in the overlay. The helper's existing single `rgb(...)` / `rgba(...)` validation must not be represented as gradient support.

### Acceptance criteria

- Overlay tracks terminal position and size without visible lag during move/resize.
- Only the correct monitor instance displays it.
- It remains aligned under scaling, bar offsets, and special-workspace transitions.
- It is click-through and never steals focus.
- It stops when hidden or closed and consumes negligible idle CPU.
- Reduced-motion mode eliminates continuous motion.
- Compositor configuration and other windows are unchanged by the default implementation.

## 3. Optional edge pet

### Scope

Treat the pet as an optional theme layered on the border overlay, not as a separate window-tracking system. A penguin, fluffy cat, or corgi can idle, walk, climb, jump, land, and occasionally dance on the terminal perimeter.

The pet's world ends at the active floating-terminal rectangle. It must not wander across unrelated windows or the whole desktop, even if the implementation uses a transparent full-output surface.

### Reference plugins studied

The following Omarchy plugins demonstrate three useful but different approaches. Source was inspected at exact commits because marketplace install commands clone mutable upstream HEAD; marketplace verification does not necessarily cover later changes.

| Example | Rendering and behavior | Strong ideas to reuse | Limits for this project |
|---|---|---|---|
| [Bitmochi](https://plugins.omarchy.org/plugin.html?id=io.github.gsirawan.bitmochi), source [`36d0e42`](https://github.com/Gsirawan/Bitmochi/tree/36d0e42f9e8a1cc2de00ac954a8a04f774d5ac92) | Individual pixel-art PNG frames, normalized room coordinates, timer-driven frame swaps, and `NumberAnimation`/`Behavior` for motion. It authors a separate 20 px bar sprite rather than shrinking room art. | Integer scaling, `smooth: false`, distinct bar art, latched facing direction, immediate click reactions, long quiet pauses, and closed-form persistent state. | It lives inside a panel rather than tracking an external window edge. Its simulation and care mechanics are unnecessary here. |
| [Omagotchi](https://plugins.omarchy.org/plugin.html?id=slcode777.omagotchi), source [`c04d94a`](https://github.com/SLcode777/omagotchi/tree/c04d94aa4b0d17fe9ea906928325c4eaa5166bbb) | Two-frame 16×16 monochrome sprites tinted with `MultiEffect`; a static, full-output transparent `PanelWindow`; an input mask around the pet; explicit walk/climb/fall states; Hyprland toplevels treated as platforms. | The closest technical reference: output-local world model, rideable window geometry, event-debounced `Hyprland.refreshToplevels()`, sprite fallbacks, and separate sprite/body/effect animation layers. | Its movement uses a 40 ms JavaScript physics timer and the source explicitly marks fractional scaling as a TODO. Its sounds have mixed licenses, including non-commercial terms. |
| [Omarchy Pets](https://plugins.omarchy.org/plugin.html?id=raiden-meixelysia.omarchy-pets), source [`ae7aa3e`](https://github.com/ZacharyZhang-NY/omarchy-pets/tree/ae7aa3e4cdec6b83d8eedef5fefc050f2abdaa64) | Crops cells from Codex Pets atlases, uses one non-repeating timer with per-frame durations, chooses random actions every 8–20 seconds, provides 16-direction pointer look frames, and can pin a draggable pet in a full-output masked window. | Data-driven pose timing, idle-action randomization without repeating the last action, explicit animation-off behavior, deterministic unit tests, and strict validation of imported images/JSON. | Standard Codex Pets sheets do not include terminal-edge climb/turn/contact metadata. Third-party pet artwork has unclear licensing and must not be bundled automatically. |

Across all three examples, the reusable pattern is a small decision engine controlling three independent visual layers:

1. **Sprite pose** — which authored frame is visible.
2. **Body transform** — position, facing, rotation, scale, and jump arc.
3. **Effect layer** — heart, stars, emote bubble, glow, dust, or tiny sparks.

This separation creates more expression from little artwork. Omagotchi, for example, makes orbiting stun stars from one star asset, while Bitmochi adds a heart rise/fade and an egg squash without needing those motions baked into every body frame.

### Recommended state machine

Use one explicit action state with a priority rule. Do not let multiple unrelated animations fight over the same position or scale property.

```text
disabled/hidden
      |
      v
    enter -> idle <-> walk -> turn-corner -> climb
               |        \-> jump -> land --/
               +----------> dance ----------/
               +----------> working --------/
               +----------> success/failure reaction -> idle
```

Priority from highest to lowest:

1. terminal closed/hidden or reduced-motion shutdown;
2. direct user interaction;
3. success/failure reaction;
4. enter/focus reaction;
5. walking/climbing transition already in progress;
6. autonomous idle choice.

Each action gets an incrementing generation token. Completion callbacks check that token before changing state, so a stale jump cannot return the pet to idle after the terminal has already hidden.

Event mapping:

| Input | Pet behavior |
|---|---|
| Terminal shown, no unread result | enter from the nearest top corner and settle |
| Terminal focused | brief look-up, ear perk, or tail wag; apply an 8-second cooldown |
| Command runs past the long-command threshold | switch from idle to a quiet `working` loop |
| Command succeeds while visible | play one celebration immediately |
| Command fails while visible | stop, react, then recover to idle |
| Command finishes while hidden | show only the bar badge; replay one summarized greeting/reaction on the next reveal |
| Terminal moved or resized | preserve edge and normalized progress, then reproject the contact point |
| Terminal hidden or closed | cancel actions, stop timers, and hide immediately or play a sub-200 ms exit if geometry remains valid |

### Overlay surface and input model

The strongest initial candidate is one static transparent `PanelWindow` for the owning monitor, shared by the glow and pet layers:

- anchor it to the full output and keep `exclusionMode: Ignore`;
- create it once and toggle `visible` instead of repeatedly constructing layer surfaces;
- draw only around the terminal rectangle;
- set keyboard focus to none;
- use a `Region` mask containing only the optional pet hitbox; the glow and the rest of the output remain click-through;
- if pet interaction is disabled, use an empty input region;
- keep only the monitor instance matching the active terminal visible.

This follows the stable-surface and narrow-input patterns demonstrated by Omagotchi and Omarchy Pets. It also avoids resizing a Wayland surface for every pet step. A terminal-sized overlay remains a viable lower-fill-rate alternative, but it must first prove that compositor surface movement and resize do not create lag or competing animations.

The pet should normally fade when the terminal loses focus, because a top-layer surface would otherwise draw it above a different window that overlaps the terminal. A setting may allow persistent display when the terminal remains unobstructed, but occlusion detection is not part of the MVP.

### Terminal-edge coordinate model

Store position as `{ edge, u }`, not raw screen pixels:

- `edge` is `top`, `right`, `bottom`, or `left`;
- `u` is progress from 0 to 1 along that edge;
- each animation defines a contact anchor, such as feet for walking or hands for climbing;
- world position is derived from the current terminal rectangle plus a small outward offset.

For a terminal rectangle `{ x, y, width, height }` and corner clearance `r`:

```text
top:    contact = (x + r + u × (width  - 2r), y)
right:  contact = (x + width,  y + r + u × (height - 2r))
bottom: contact = (x + width - r - u × (width  - 2r), y + height)
left:   contact = (x,          y + height - r - u × (height - 2r))
```

The reverse direction on bottom/left keeps a clockwise perimeter. On resize, retain `edge` and `u`; on a dimension becoming too short, clamp to the nearest safe contact point. At a corner, enter `turn-corner` and switch edge only after its frames finish, preventing a visible teleport.

Do not copy Omagotchi's scale-1 coordinate assumption. Convert compositor coordinates into the overlay window's output-local logical coordinates in one tested function using the selected screen origin and device-pixel ratio. The fractional headless-output test is a gate for this function.

### Sprite format and asset pipeline

Use a small data-driven atlas format for YADTM pets. A recommended first format is:

- 32×32 source-pixel cells;
- at most 8 frames per row;
- integer display scales, normally 2× for a 64 px pet;
- nearest-neighbor rendering with `smooth: false` and `mipmap: false`;
- transparent PNG or lossless WebP;
- one separately authored 20 px bar icon, following Bitmochi's legibility lesson;
- metadata that supplies frame count, per-frame durations, looping, fallback pose, and contact anchor.

Example manifest:

```json
{
  "version": 1,
  "id": "penguin",
  "name": "Penguin",
  "cell": { "width": 32, "height": 32 },
  "scale": 2,
  "palette": "native",
  "atlas": "pet.png",
  "barIcon": "bar.png",
  "actions": {
    "idle":      { "row": 0, "frames": 4, "durations": [420, 140, 140, 700], "loop": true,  "contact": [16, 30] },
    "walk":      { "row": 1, "frames": 6, "durations": [120, 120, 140, 120, 120, 180], "loop": true,  "contact": [16, 30] },
    "climb":     { "row": 2, "frames": 4, "durations": [160, 160, 160, 200], "loop": true,  "contact": [16, 17] },
    "jump":      { "row": 3, "frames": 4, "durations": [90, 140, 120, 180],  "loop": false, "contact": [16, 30] },
    "land":      { "row": 4, "frames": 3, "durations": [80, 100, 180],       "loop": false, "contact": [16, 30] },
    "celebrate": { "row": 5, "frames": 6, "durations": [100, 100, 120, 120, 160, 260], "loop": false, "contact": [16, 30] },
    "failure":   { "row": 6, "frames": 4, "durations": [160, 220, 300, 500], "loop": false, "contact": [16, 30] },
    "dance":     { "row": 7, "frames": 8, "durations": [120, 120, 120, 120, 120, 120, 120, 240], "loop": false, "contact": [16, 30] }
  }
}
```

The numbers are starting values for an art prototype, not a compatibility standard. The renderer should accept missing actions and fall back in this order: requested action → `walk` for climb-like motion → `idle`. Mirroring can supply left/right walking for symmetric art; a dedicated climb pose is preferred over rotating walking frames 90 degrees.

Keep every frame on the same canvas and make its contact anchor stable. Otherwise changing frames makes feet skate along the border. Store editable source files and a reproducible export/check script, but ship only optimized runtime images and attribution.

Two visual modes are useful:

- **Native palette:** appropriate for a recognizable penguin, cat, or corgi.
- **Theme tint:** one-bit or grayscale art colored through `MultiEffect`, like Omagotchi.

### How to make the motion feel cute

The reference plugins consistently use unequal timing, immediate feedback, and controlled randomness. Apply these principles:

- **Readable silhouette:** ears, flippers, tail, and short legs must remain recognizable at 48–64 px.
- **Anticipation:** compress or lean for 70–100 ms before a jump.
- **Squash and stretch:** keep it subtle—roughly 8–14%—and restore the exact scale when interrupted.
- **Unequal holds:** fast middle frames and a longer final pose feel intentional; evenly timed frames feel mechanical.
- **Secondary motion:** add a tail follow-through, ear bounce, heart, dust puff, or three orbiting stars as a separate layer.
- **Quiet time:** choose a new autonomous action every 8–20 seconds, never immediately repeat the last one, and allow “do nothing” as an outcome.
- **Latched direction:** decide facing when choosing a destination and keep it through the whole walk; deriving direction from an interpolating position creates flip jitter.
- **Immediate click response:** start the visual reaction before persistence or business logic completes.
- **One strong beat:** completion should be a brief reaction, not an endless celebration beside the user's terminal.

Concrete success animation, approximately 620 ms:

1. squash to `scaleX 1.10 / scaleY 0.90` for 90 ms;
2. launch 12–16 logical pixels outward from the border over 160 ms with `OutQuad` easing;
3. hold the apex for 70 ms while emitting one heart or sparkle;
4. return over 180 ms with `InQuad` easing;
5. land at `scaleX 1.12 / scaleY 0.88` for 70 ms, then settle to 1.0 over 120 ms.

Concrete appear animation, approximately 500 ms:

1. show only eyes/ears/flippers behind the nearest top corner for 120 ms;
2. rise to the contact point over 180 ms;
3. overshoot by 3–4 logical pixels for 80 ms;
4. settle over 120 ms and blink once.

Failure should be gentler: stop walking, lower the head/ears for 350–500 ms, show one small concern bubble, then recover. Avoid red flashing; the persistent terminal badge already carries failure status.

### Character-specific animation ideas

| Pet | Idle signature | Travel/climb | Success | Rare dance |
|---|---|---|---|---|
| Penguin | slow blink and tiny side sway | waddle on top; alternating flippers on a side | short hop with two flaps | belly slide across a safe portion of the top edge |
| Fluffy cat | tail-tip flick, loaf, ear twitch | soft paw steps; peek and pull-up at a corner | pounce upward, heart, proud sit | two-step paw knead with tail follow-through |
| Corgi | pant, ear bounce, butt wiggle | quick short steps; determined scramble | hop, spin a quarter turn, rapid wag | compact side-to-side “tippy taps” |

Build the penguin first: its strong silhouette and waddling two-beat walk can validate the system with the fewest frames. Add the cat next to validate secondary tail motion, then the wider corgi to validate contact anchors and clipping for non-square poses.

### QML implementation guidance

Split the implementation into four responsibilities:

- `PetController.qml`: action priority, cooldowns, random choices, and command-event mapping;
- `PetSprite.qml`: atlas validation/cropping, frame timer, fallback actions, tinting, and mirroring;
- `PetMotion.qml`: `{ edge, u }`, terminal geometry projection, corner transitions, and transform offsets;
- `PetEffects.qml`: bounded hearts, dust, stars, emote bubble, and appear/success/failure sequences.

Implementation rules:

- Use one non-repeating timer armed from the current frame's duration, as Omarchy Pets does.
- Use `NumberAnimation`, `SequentialAnimation`, and `ParallelAnimation` for deterministic transforms.
- Keep autonomous decisions on a slow timer; do not use a 40 ms JavaScript physics loop for ordinary walking.
- A jump can be a parallel linear tangential movement plus `OutQuad`/`InQuad` normal movement; it does not need a general physics engine.
- Use separate `pathOffset`, `reactionOffset`, and `effectOffset` properties so a `Behavior` and an explicit animation never own the same property.
- Reset rotation, scale, opacity, and offsets explicitly when an animation stops; Qt animations may otherwise leave the last value applied.
- Gate every animation and timer on owner, visibility, feature enablement, and reduced-motion state.
- Keep the overlay object statically instantiated and change visibility; Omagotchi's source documents stale layer-surface problems after dynamically recreating its roam window during hot reload.
- Render the bar icon and overlay pet as separate QML items sharing a read-only controller model. Do not move one visual item between different windows.

### Asset safety and licensing

Bundled pets should be original work or carry an explicit redistribution-compatible license. Do not copy artwork or sounds merely because a reference plugin's code is MIT:

- Bitmochi states that its code and included art are MIT.
- Omagotchi's code and sprites are MIT, but its sound files retain separate Creative Commons licenses and some are non-commercial.
- Omarchy Pets does not bundle Codex Pets art and warns that third-party upload licenses may be unclear.

Optional imported pet packs must be data only—JSON and images, never QML or executable scripts. Validate them before loading:

- reject symlinks and non-regular files;
- cap JSON and image byte sizes;
- verify PNG/WebP signatures and dimensions before decode;
- cap row/frame counts and reject paths outside the pet directory;
- sanitize strings and ignore unknown manifest fields;
- show a static fallback pet when validation fails.

### Performance budget

- No shell process or Hyprland query for a sprite frame or animation tick.
- Frame timers run only while the pet is visible; typical authored frame holds are 90–700 ms.
- Autonomous decisions occur at most once every few seconds.
- Continuous 60 fps JavaScript loops are out of scope.
- Limit burst effects to a handful of items with lifetimes below one second; avoid a general particle system in the MVP.
- When hidden, stop timers and set the overlay's render updates off if the installed Quickshell version behaves correctly with `updatesEnabled`.
- Measure total `omarchy-shell` CPU/GPU and wakeups against a no-pet baseline; the acceptance criterion is no measurable sustained hidden-state increase.

### Animation tests

- Validate atlas dimensions, frame bounds, duration bounds, action fallbacks, and contact anchors.
- Inject deterministic random values to test action selection and no-immediate-repeat behavior.
- Verify interruption from every action to hidden/closed restores transforms and stops callbacks.
- Verify success/failure priority over idle, but direct hide/close priority over reactions.
- Confirm the frame timer is stopped with animation disabled or reduced motion enabled.
- Confirm only the owning monitor has a visible pet or active timers.
- Confirm the input region follows the pet and the glow remains click-through.
- Move and resize the terminal during walk, corner turn, climb, and jump.
- Test very small terminal sizes and every screen edge for clipping.
- Test scale 1.0 and the temporary fractional headless output before approving coordinate conversion.
- Hot-reload the plugin repeatedly and inspect for stale layer surfaces or duplicate timers.

### Settings

Suggested options:

```text
pet.enabled = false
pet.character = penguin | cat | corgi
pet.scale = 1 | 2 | 3
pet.interactive = false
pet.autonomous = true
pet.showWhenUnfocused = false
pet.reduceMotion = true | false
```

The default remains disabled. Enabling reduced motion holds one stable idle frame and permits only an instantaneous pose/badge change—no walking, pulsing, particles, or automatic timers. Add a `follow-system` mode only if the host later exposes a reliable system-wide preference.

### Acceptance criteria

- The selected pet has a distinct, readable personality at normal terminal size.
- Pet remains attached to the correct terminal contact point during move/resize.
- Its feet/hands do not jitter when sprite frames change.
- It does not overlap terminal content or become trapped off-screen.
- Exactly one pet is visible across monitors.
- Focus/completion reactions occur once, not once per monitor service.
- Hidden completion produces a badge without rendering an off-screen pet reaction.
- Overlay input is click-through outside the optional pet hitbox and never takes keyboard focus.
- CPU/GPU usage returns to the measured no-pet baseline when hidden.
- Disabling the pet removes all pet-related timers and rendering work.
- Invalid or unlicensed third-party assets are not executed or bundled.

## 4. Tabs in the floating terminal

### Preferred direction: native Hyprland groups

The first serious prototype should test Hyprland window groups. Each terminal tab remains a real terminal window, while the compositor provides membership, active-window switching, and optionally a group bar.

The state schema already supports multiple clients. Phase 4 extends behavior around that array; it does not introduce a second state format.

Proposed commands:

```text
omarchy-dropdown-terminal new-tab
omarchy-dropdown-terminal next-tab
omarchy-dropdown-terminal previous-tab
omarchy-dropdown-terminal close-tab
omarchy-dropdown-terminal list-tabs --json
```

### Duplicate invocation policy

Because one hotkey may reach N per-monitor integration instances, every user-triggered mutating action must use a nonblocking lock and drop duplicates:

- `toggle`, `new-tab`, `next-tab`, `prev-tab`, and `close-tab`: `flock -n` semantics;
- no `flock -w 3` queue for hotkey actions;
- internal recovery/cleanup work may queue only when it is idempotent and cannot create extra windows.

The losing invocation exits successfully without doing the action again.

### Group behavior that must be proven

Before committing to native groups, test these questions explicitly:

- Does moving/resizing the floating group move one stable box or only the active member?
- Does group switching preserve exact geometry, opacity, and special-workspace membership?
- Does `reveal_parked` need to mutate only the active member or all group members?
- Are opacity, `no_anim`, position, and workspace changes applied atomically enough when targeting all members?
- Is the group bar geometry included in client bounds, and can it be themed or hidden?
- What happens when the active tab exits, the final tab exits, or a member crashes?
- Do hide/show and focus operations preserve group membership?

For the prototype, treat the group as one visual box but apply safety-critical park/reveal properties to every member in one synchronous batch unless compositor behavior proves that active-member-only mutation is sufficient.

### Fallbacks

- tmux is the simplest mature fallback, but changes the interaction model.
- Foot server/client mode reduces process overhead but does not create GUI tabs by itself.
- A custom tab bar with independent terminal windows gives maximum control and maximum synchronization risk.
- Switching the project to a different terminal emulator purely for tabs is not recommended.

### Acceptance criteria

- `new-tab` creates exactly one tab under concurrent per-monitor invocation.
- Next/previous navigation is deterministic.
- Closing the active tab selects a sensible successor.
- The last tab closes or hides the floating terminal cleanly.
- Group move/resize, hide/show, opacity, and special-workspace behavior are correct for every member.
- Existing one-window users migrate without losing the current terminal.
- A helper restart reconstructs membership without adopting unrelated windows.

## Testing prerequisites and matrix

### Local limitation

The reviewed machine currently exposes one physical monitor, `DP-1`, at 3440×1440 and scale 1.0. Physical multi-monitor and fractional-DPI acceptance cannot be claimed from that setup.

Before overlay work, create a temporary Hyprland headless output using the documented output command, discover its actual generated name, configure a fractional scale such as 1.25 through the existing Lua/config mechanism, run the positioning tests, and remove the headless output afterward. Do not hardcode a guessed output name.

This covers logical multi-output and fractional-scale geometry. A real second display remains a release prerequisite for hardware behavior such as hotplug, mixed refresh rates, and physical focus transitions.

### Test matrix

- hidden vs visible terminal;
- active vs inactive terminal;
- command success, failure, signal termination, nested shell, shell exit;
- two concurrent terminal shells writing events;
- QML reload during start/finish activity;
- journal partial line and coalesced notifications;
- move/resize during overlay and pet animation;
- headless second output at fractional scale;
- physical second display on another test machine;
- repeated hotkey delivery from N service instances;
- group create/switch/close/crash/recovery;
- plugin install, reinstall, integration uninstall, and removal without cleanup;
- reduce-motion and all visual features disabled.

## Delivery phases

The executable, file-level plan is split by execution phase in [`docs/plan/README.md`](plan/README.md). That index maps execution numbering back to the numbered research sections. Each phase document includes work packages, verification, constraints, and an exit gate.

### Phase 0 — shared state and observability

Detailed plan: [`phase-0-foundation.md`](plan/phase-0-foundation.md)

- Fix `Service.qml`'s stale `shell.json` `FileView` by reloading on change and consuming the asynchronous result.
- Introduce versioned `state.json` with a `clients` array.
- Implement plaintext-address migration, workspace recovery, pruning, and atomic writes.
- Make every Quickshell service instance watch the same canonical file.
- Prove nonblocking duplicate suppression for all user actions.
- Instrument timings during development without adding prompt-path subprocesses.
- Establish the temporary headless/fractional-output test procedure.
- Reproduce the vertically stacked-output case where the lower monitor's parked rectangle intersects the upper monitor, then stop using any-monitor intersection as the sole parked-state test.

Exit gate: existing toggle behavior and crash recovery remain correct, including simultaneous service invocations.

### Phase 1 — border overlay

Detailed plan: [`phase-1-entrance-effects.md`](plan/phase-1-entrance-effects.md)

- Implement the verified address-to-`HyprlandToplevel` lookup and refreshed raw IPC geometry path.
- Elect one monitor owner for refresh and rendering.
- Build appear/focus/success/failure overlay states.
- Verify click-through behavior, alignment, reduced motion, and idle cost.
- Run the compositor-border experiment only as an optional rejection/feasibility test.

Exit gate: stable overlay on the physical monitor and temporary fractional headless output; physical multi-monitor remains separately tracked.

### Phase 2 — command completion

Detailed plan: [`phase-2-command-indicator.md`](plan/phase-2-command-indicator.md)

- Ship Tier 0 first using the managed `HyprlandToplevel.urgent` property: generic attention badge, no rc changes, and no false claim of exit-status knowledge.
- Define and stress-test the append-only journal.
- Integrate Bash after the Starship/bash-preexec load-order PoC.
- Add Zsh and Fish hook adapters.
- Add helper lifecycle journal records and the persistent icon badge.
- Add a 1 Hz explicit journal reload only while a replayed command is running, so a stalled `FileView` watch cannot lose completion.
- Add guarded rc-file install blocks and explicit integration cleanup.

Exit gate: zero prompt-path child processes, no lost concurrent events, and no regressions to existing prompt tooling.

### Phase 3 — pet

Detailed plan: [`phase-3-pet.md`](plan/phase-3-pet.md)

- Reuse the proven overlay geometry and ownership path.
- Compare the static full-output and terminal-sized overlay surfaces, with the static surface preferred unless measurement disproves it.
- Implement the pet manifest validator, atlas renderer, contact-anchor projection, and prioritized action controller.
- Build the penguin first, including idle, walk, climb, enter, success, failure, and dance actions.
- Add deterministic animation/controller tests and interruption cleanup.
- Add reduced-motion/disable controls and measure visible, idle, and hidden render cost.
- Add the cat and corgi only after the penguin proves the asset and geometry contracts.

Exit gate: one distinctive, correctly positioned optional pet with stable frame anchors, bounded input, and no hidden-state resource use.

### Phase 4 — tabs

Detailed plan: [`phase-4-tabs.md`](plan/phase-4-tabs.md)

- Prototype group creation and active-member tracking.
- Answer the group/reveal/geometry questions above with recorded tests.
- Implement new/next/previous/close actions with drop-duplicate locks.
- Extend recovery and cleanup for multiple clients.
- Keep the feature behind a flag until group behavior passes the full matrix.

Exit gate: one action per hotkey, reliable recovery, and correct group movement/parking on all tested output configurations.

## Suggested file layout

```text
BarWidget.qml                         # existing bar icon; add badge and overlay host
Service.qml                           # existing service; add shared state/event readers
Panel.qml                             # existing settings panel; add feature controls
FloatingTerminalOverlay.qml          # border/glow/pet surface and ownership
OverlayGeometry.js                   # pure coordinate/validation helpers
PetController.qml                    # event priority, cooldowns, random decisions
PetSprite.qml                        # atlas frames, timing, fallback, mirroring
PetMotion.qml                        # edge/u projection and corner transitions
PetEffects.qml                       # hearts, dust, stars, short reactions
manifest.json                        # existing plugin settings schema
bin/
  omarchy-dropdown-terminal           # existing lifecycle/actions; canonical state writer
  omarchy-dropdown-terminal-bind      # existing optional direct binding installer
  omarchy-dropdown-terminal-shell-integration
  omarchy-dropdown-terminal-special-fallthrough
shell/
  yadtm.bash                          # Bash adapter; optional pinned bash-preexec
  yadtm.zsh                           # Zsh adapter
  yadtm.fish                          # Fish adapter
assets/pets/<character>/
  pet.json                           # bounded animation/contact metadata
  pet.png                            # licensed sprite atlas
  bar.png                            # separately authored 20 px icon
docs/
  feature-research-and-plan.md
  design-rules.md                     # project adoption, authorities, exceptions, gates
  plan/                              # phase-by-phase executable plans and testing guide
```

Runtime files:

```text
$state_root/io.github.tuthan.dropdown-terminal.state.json
$state_root/io.github.tuthan.dropdown-terminal.events
$state_root/io.github.tuthan.dropdown-terminal.lock
```

`$state_root` is the private `XDG_RUNTIME_DIR` when valid, or the helper's UID-scoped private `/tmp` fallback. The prefix is required because a valid `XDG_RUNTIME_DIR` is shared with other applications.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Prompt hooks feel slow | builtin-only journal writes; benchmark interactively; no Omarchy helper call per command |
| File notifications coalesce | append journal, parse by offset, ignore incomplete tail, never truncate in MVP |
| `FileView` returns stale data or its watch stalls | call asynchronous `reload()` on change, parse only refreshed content, nudge state reads after known events, and re-probe the journal at 1 Hz only while a command runs |
| N per-monitor services diverge | all watch the same state and event files; one monitor owns the active overlay/refresh timer |
| Duplicate new tab/toggle | nonblocking lock and drop duplicate user actions |
| Geometry updates are stale | refresh Quickshell toplevels on compositor events and only while needed; measure before fallback |
| Overlay steals input | transparent, non-focusable, click-through surface; explicit pointer tests |
| Global border state is corrupted | do not use global rotation by default; require lossless PoC or reject it |
| Plugin removal breaks shells | readable-path guard plus explicit integration-uninstall command |
| Group behavior surprises | feature flag and dedicated group/reveal prototype tests |
| Fractional/multi-monitor bugs are missed | temporary fractional headless output plus required real-hardware pass |
| A parked window intersects a vertically stacked neighbour | classify against the owner monitor plus workspace/park target, and keep a dedicated stacked-output regression |
| Pet wastes resources | one instance, bounded frames, no hidden timers, asset size limits |
| Pet animation properties fight each other | explicit action priority and separate path/reaction/effect offsets |
| Frames visibly skate on the border | fixed canvas plus validated contact anchors for every action |
| Imported pet pack is hostile or huge | data-only packs, regular-file checks, signature/dimension/size bounds, no QML loading |
| Reference art has incompatible terms | original assets by default and per-file license/attribution review |
| State file is corrupt or stale | schema version, atomic rename, validation, pruning, deterministic workspace recovery |

## Sources

### Local evidence

- `/home/hvo/Projects/omasafe-plugin/docs/design/02-design-principles.md` as the source for the generalized plugin design rule and YADTM adoption profile.
- `bin/omarchy-dropdown-terminal`, `bin/omarchy-dropdown-terminal-bind`, and `bin/omarchy-dropdown-terminal-special-fallthrough` in this repository.
- `Service.qml`, `BarWidget.qml`, `Panel.qml`, and `manifest.json` in this repository.
- Live `FileView` probe confirming that `watchChanges` needs asynchronous `reload()`, plus the eight installed Omarchy reload call sites and `plugins/bar/Bar.qml:950-953` stalled-watch repair comment.
- `/usr/share/omarchy/shell/plugins/bar/Bar.qml` and `/usr/share/omarchy/shell/Ui/Panel.qml` for per-screen `Variants`, single IPC ownership, and `manageIpc` behavior.
- Installed plugin manifests and shell schema readers for enum, conditional-visibility, `minimumVersion`, and `package` behavior.
- `~/.bashrc` and `/usr/share/omarchy/default/bash/init` for the current Starship initialization order.
- `/usr/lib/qt6/qml/Quickshell/Hyprland/_Ipc/quickshell-hyprland-ipc.qmltypes` for locally installed `HyprlandToplevel` and monitor properties.
- Live `hyprctl eval 'return 1+1'` probe confirming eval prints `ok` rather than returning query data.
- `/usr/share/omarchy/default/hypr/looknfeel.lua` for current gradient and animation defaults.
- Local package metadata: `bash-preexec` 0.6.0 is available from Arch `extra`; Starship 1.26.0 is installed.
- Current compositor review: one `DP-1` output at 3440×1440 scale 1.0, and `borderangle` disabled/overridden.

### Pet reference implementations

- [Bitmochi marketplace entry](https://plugins.omarchy.org/plugin.html?id=io.github.gsirawan.bitmochi) and reviewed [`BarWidget.qml`](https://github.com/Gsirawan/Bitmochi/blob/36d0e42f9e8a1cc2de00ac954a8a04f774d5ac92/BarWidget.qml), [`Room.qml`](https://github.com/Gsirawan/Bitmochi/blob/36d0e42f9e8a1cc2de00ac954a8a04f774d5ac92/Room.qml), and [`Panel.qml`](https://github.com/Gsirawan/Bitmochi/blob/36d0e42f9e8a1cc2de00ac954a8a04f774d5ac92/Panel.qml).
- [Omagotchi marketplace entry](https://plugins.omarchy.org/plugin.html?id=slcode777.omagotchi) and reviewed [`PetSprite.qml`](https://github.com/SLcode777/omagotchi/blob/c04d94aa4b0d17fe9ea906928325c4eaa5166bbb/PetSprite.qml), [`RoamWindow.qml`](https://github.com/SLcode777/omagotchi/blob/c04d94aa4b0d17fe9ea906928325c4eaa5166bbb/RoamWindow.qml), and [`Service.qml`](https://github.com/SLcode777/omagotchi/blob/c04d94aa4b0d17fe9ea906928325c4eaa5166bbb/Service.qml).
- [Omarchy Pets marketplace entry](https://plugins.omarchy.org/plugin.html?id=raiden-meixelysia.omarchy-pets) and reviewed [`PetSprite.qml`](https://github.com/ZacharyZhang-NY/omarchy-pets/blob/ae7aa3e4cdec6b83d8eedef5fefc050f2abdaa64/PetSprite.qml), [`Sprite.js`](https://github.com/ZacharyZhang-NY/omarchy-pets/blob/ae7aa3e4cdec6b83d8eedef5fefc050f2abdaa64/Sprite.js), and [`Panel.qml`](https://github.com/ZacharyZhang-NY/omarchy-pets/blob/ae7aa3e4cdec6b83d8eedef5fefc050f2abdaa64/Panel.qml).
- [Omarchy shell plugin manual](https://github.com/basecamp/omarchy/blob/quattro/manual/32-shell-plugins.md).

### Upstream documentation

- [Quickshell `FileView`](https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/FileView/)
- [Quickshell `Hyprland`](https://quickshell.org/docs/v0.3.1/types/Quickshell.Hyprland/Hyprland/)
- [Quickshell `HyprlandToplevel`](https://quickshell.org/docs/v0.3.1/types/Quickshell.Hyprland/HyprlandToplevel/)
- [Quickshell `PanelWindow`](https://quickshell.org/docs/v0.3.1/types/Quickshell/PanelWindow/)
- [Quickshell `QsWindow`](https://quickshell.org/docs/v0.3.1/types/Quickshell/QsWindow/)
- [Quickshell `Region`](https://quickshell.org/docs/v0.3.1/types/Quickshell/Region/)
- [Hyprland using `hyprctl`: Lua eval/dispatch and headless outputs](https://wiki.hypr.land/Configuring/Advanced-and-Cool/Using-hyprctl/)
- [Hyprland dispatcher catalog](https://wiki.hypr.land/Configuring/Dispatchers/)
- [Hyprland IPC](https://wiki.hypr.land/IPC/)
- [Hyprland animations](https://wiki.hypr.land/Configuring/Animations/)
- [Hyprland window rules](https://wiki.hypr.land/Configuring/Window-Rules/)
- [bash-preexec](https://github.com/rcaloras/bash-preexec)
- [Starship Bash initialization](https://github.com/starship/starship/blob/main/src/init/starship.bash)
- [Bash startup and prompt variables](https://www.gnu.org/software/bash/manual/html_node/Bash-Startup-Files.html)
- [Zsh hook functions](https://zsh.sourceforge.io/Doc/Release/Functions.html#Hook-Functions)
- [Fish event handlers](https://fishshell.com/docs/current/cmds/function.html)
- [Qt Quick `SpriteSequence`](https://doc.qt.io/qt-6/qml-qtquick-spritesequence.html)
- [Qt Quick Particles](https://doc.qt.io/qt-6/qtquick-particles-qmlmodule.html)
- [Foot server mode](https://codeberg.org/dnkl/foot/src/branch/master/foot.ini)
- [tmux manual](https://man7.org/linux/man-pages/man1/tmux.1.html)

## Final decision

Proceed with the shared state and Quickshell overlay first. Ship the zero-integration urgency indicator, then add the append-only completion journal after proving shell-hook compatibility. The pet is a safe extension of the overlay. Tabs remain feasible but should stay experimental until native group behavior, duplicate hotkey suppression, and multi-output recovery are demonstrated.
