#!/usr/bin/env bash

set -u

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_dir="$root_dir/tests/fixtures/hyprland"
runtime_dir="$(mktemp -d)"
chmod 700 "$runtime_dir"
trap 'rm -rf "$runtime_dir"' EXIT

pass=0
fail=0

ok() {
  pass=$((pass + 1))
}

not_ok() {
  fail=$((fail + 1))
  printf 'FAIL: %s\n' "$1" >&2
}

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    ok
  else
    not_ok "$name (expected '$expected', got '$actual')"
  fi
}

assert_status() {
  local name="$1"
  shift
  if "$@" >/dev/null; then ok; else not_ok "$name"; fi
}

assert_false() {
  local name="$1"
  shift
  if "$@"; then not_ok "$name"; else ok; fi
}

fixture_clients="$fixture_dir/clients-single.json"
fixture_monitors="$fixture_dir/monitors-dual-scaled.json"

hyprctl() {
  case "$*" in
    'clients -j') cat "$fixture_clients" ;;
    'monitors -j') cat "$fixture_monitors" ;;
    '-j animations') cat "$fixture_dir/animations-omarchy.json" ;;
    'activewindow -j') printf '%s\n' '{"address":"0x1000"}' ;;
    reload) return 0 ;;
    'configerrors -j') printf '%s\n' '[]' ;;
    *) return 1 ;;
  esac
}
notify-send() { :; }
export -f hyprctl
export -f notify-send

YADTM_LIB_ONLY=1 XDG_RUNTIME_DIR="$runtime_dir" source "$root_dir/bin/omarchy-dropdown-terminal"
export fixture_clients fixture_monitors
export -f client_exists client_monitor window_on_screen wait_window_y lua_string

window_width_percent=90
window_height_percent=45
compute_geometry_on 1
assert_eq "fractional logical width" "1382" "$window_width"
assert_eq "fractional logical height" "388" "$window_height"
assert_eq "monitor-origin x" "3517" "$window_x"
assert_eq "monitor-origin y" "34" "$top_margin"
assert_eq "parked y" "-448" "$parked_y"

assert_eq "workspace numeric" "3" "$(workspace_selector 3)"
assert_eq "workspace named" "name:web" "$(workspace_selector web)"
assert_eq "lua quote escaping" '"a\\b\"c"' "$(lua_string 'a\b"c')"
assert_false "lua rejects control character" lua_string $'bad\nvalue'

assert_status "QML iterates toplevel object-model values" grep -Fq 'Hyprland.toplevels.values' "$root_dir/Service.qml"
assert_status "QML iterates monitor object-model values" grep -Fq 'Hyprland.monitors.values' "$root_dir/Service.qml"
assert_status "QML returns the toplevel monitor object" grep -Fq 'return toplevel && toplevel.monitor ? toplevel.monitor : null' "$root_dir/Service.qml"
assert_status "QML normalizes raw closewindow addresses" grep -Fq 'root.normalizedAddress(closed) === root.normalizedAddress(root.trackedAddress)' "$root_dir/Service.qml"
assert_status "QML normalizes model toplevel addresses" grep -Fq 'root.normalizedAddress(toplevels[i].address) === address' "$root_dir/Service.qml"
assert_status "QML reconciles tracked closewindow events" grep -Fq 'root.requestCloseReconcile()' "$root_dir/Service.qml"
assert_status "QML resolves the helper state root" grep -Fq '"state-root"' "$root_dir/Service.qml"
assert_status "binding preflight waits for fresh status" grep -Fq 'readonly property bool bindingStatusReady' "$root_dir/BarWidget.qml"
assert_status "phase 1 overlay is lazy on Off" grep -Fq 'active: service.entranceEffect !== "Off"' "$root_dir/BarWidget.qml"
assert_status "phase 1 overlay is click-through" grep -Fq 'mask: Region {}' "$root_dir/TerminalEffects.qml"
assert_status "phase 1 overlay has no keyboard focus" grep -Fq 'WlrLayershell.keyboardFocus: WlrKeyboardFocus.None' "$root_dir/TerminalEffects.qml"
assert_status "phase 1 overlay follows the terminal monitor" grep -Fq 'hostMatchesTerminal' "$root_dir/TerminalEffects.qml"
assert_status "phase 1 geometry refresh is bounded" grep -Fq 'interval: 250' "$root_dir/TerminalEffects.qml"
assert_status "phase 1 uses the host logical screen geometry" grep -Fq 'terminalRect.x - hostScreen.x' "$root_dir/TerminalEffects.qml"
assert_status "phase 1 caches Hyprland rounding" grep -Fq 'getoption", "decoration:rounding' "$root_dir/TerminalEffects.qml"
assert_status "phase 1 glow has a finite particle cap" grep -Fq 'maximumEmitted: root.sparkCount' "$root_dir/TerminalEffects.qml"
assert_status "phase 1 has both manifest settings" jq -e '.barWidget.schema | any(.[]; .key == "entranceEffect" and .defaultValue == "Glow") and any(.[]; .key == "effectIntensity" and .min == 0 and .max == 100 and .step == 10)' "$root_dir/manifest.json"
assert_status "phase 1 exposes all entrance effects" jq -e '.barWidget.schema[] | select(.key == "entranceEffect") | .options == ["Off","Glow","Fire","Firework","Thunder","Snow","Rain"]' "$root_dir/manifest.json"
assert_status "phase 1 implements fire and weather finishes" grep -Fq 'root.isFirework' "$root_dir/TerminalEffects.qml"
assert_status "phase 1 implements thunder finish" grep -Fq 'root.isThunder' "$root_dir/TerminalEffects.qml"
assert_false "phase 1 overlay does not write compositor state" grep -Fq 'hyprctl", "eval' "$root_dir/TerminalEffects.qml"
assert_status "phase 1 re-arms on terminal monitor transitions" grep -Fq 'function observeTerminalMonitor()' "$root_dir/TerminalEffects.qml"
assert_status "phase 1 settle waits require output ownership" grep -Fq '!root.hostMatchesTerminal' "$root_dir/TerminalEffects.qml"
assert_status "phase 1 preserves zero corner radius" grep -Fq 'isFinite(queried) && queried >= 0' "$root_dir/TerminalEffects.qml"
assert_status "phase 1 scales core opacity by intensity" grep -Fq 'fadeProgress * intensity *' "$root_dir/TerminalEffects.qml"
assert_status "phase 1 scales halo opacity by intensity" grep -Fq 'readonly property real haloOpacity: fadeProgress * intensity *' "$root_dir/TerminalEffects.qml"
assert_status "phase 1 allows zero emitted sparks" grep -Fq 'Math.round(intensity * 12)' "$root_dir/TerminalEffects.qml"
assert_status "phase 3 has a pet controller" test -f "$root_dir/PetController.qml"
assert_status "phase 3 has perimeter motion model" grep -Fq 'readonly property real perimeter' "$root_dir/PetMotion.qml"
assert_status "phase 3 rounds only final sprite origin" grep -Fq 'Math.round(root.unroundedSpriteX)' "$root_dir/PetMotion.qml"
assert_status "phase 3 keeps normalized progress on resize" grep -Fq 'setNormalizedProgress' "$root_dir/PetMotion.qml"
assert_status "phase 3 has generation cancellation" grep -Fq 'root.generation++' "$root_dir/PetController.qml"
assert_status "phase 3 has hidden cleanup" grep -Fq 'function invalidate()' "$root_dir/PetController.qml"
assert_status "phase 3 finite actions restore idle sprite" grep -Fq 'root.spriteItem.actionName = "idle"' "$root_dir/PetController.qml"
assert_false "phase 3 uses lexical child ids directly" grep -Eq 'root\.(motion|sprite|effects)([^A-Za-z]|$)' "$root_dir/PetController.qml"
assert_status "phase 3 movement follows edge boundaries" grep -Fq 'function edgeEndU(edge)' "$root_dir/PetController.qml"
assert_status "phase 3 corners select the following edge" grep -Fq 'function nextEdge(edge)' "$root_dir/PetController.qml"
assert_status "phase 3 has a single variable-duration frame timer" grep -Fq 'id: frameTimer' "$root_dir/PetSprite.qml"
assert_status "phase 3 waits for atlas decode" grep -Fq 'onStatusChanged: root.observeAtlasStatus()' "$root_dir/PetSprite.qml"
assert_status "phase 3 checks decoded atlas dimensions" grep -Fq 'atlasProbe.sourceSize.width' "$root_dir/PetSprite.qml"
assert_status "phase 3 keeps render clipping separate from validation" grep -Fq 'sourceClipRect intentionally makes the renderer report one frame' "$root_dir/PetSprite.qml"
assert_status "phase 3 exposes asset diagnostics" grep -Fq 'property string petDiagnostic' "$root_dir/TerminalEffects.qml"
assert_status "phase 3 passes the outer service into visual effects" grep -Fq 'service: terminalService' "$root_dir/BarWidget.qml"
assert_status "phase 3 does not use mouse input" grep -Fq 'mask: Region {}' "$root_dir/TerminalEffects.qml"
assert_status "phase 3 disables infinite motion" grep -Fq 'root.playbackRequested && !root.reducedMotion' "$root_dir/PetSprite.qml"
assert_status "phase 3 maps precise result names to pet actions" grep -Fq 'reactionForResult' "$root_dir/PetController.qml"
assert_status "phase 3 accepts only qualifying precise events" grep -Fq 'commandLatestQualifies !== true' "$root_dir/PetController.qml"
assert_status "phase 3 ignores replayed completion events" grep -Fq 'eventReplayReady !== true' "$root_dir/PetController.qml"
assert_status "phase 3 service publishes completion qualification" grep -Fq 'commandLatestQualifies = qualifies' "$root_dir/Service.qml"
assert_status "phase 3 cancels finite pet effects on reduced motion" grep -Fq 'root.effectsItem.cancel()' "$root_dir/PetController.qml"
assert_status "phase 3 shares reduceMotion with bar status" grep -Fq 'service.reduceMotion' "$root_dir/BarWidget.qml"
assert_status "phase 3 coordinator updates while pet is active" grep -Fq 'running: root.surfaceActive' "$root_dir/TerminalEffects.qml"
assert_status "phase 3 manifest settings" jq -e '.barWidget.schema as $schema | ["petEnabled","petSpecies","petActivity","reduceMotion"] | all(.[]; . as $key | any($schema[]; .key == $key))' "$root_dir/manifest.json"
assert_status "phase 3 exposes all pet species" jq -e '.barWidget.schema[] | select(.key == "petSpecies") | .options == ["Penguin","Cat","Corgi"]' "$root_dir/manifest.json"
assert_status "phase 3 pack provenance exists" test -s "$root_dir/assets/pets/penguin/LICENSE" -a -s "$root_dir/assets/pets/penguin/SOURCE"
assert_status "phase 3 atlas is exact size" identify -format '%wx%h' "$root_dir/assets/pets/penguin/pet.png" | grep -Fxq '256x256'
assert_status "phase 3 bar icon is exact size" identify -format '%wx%h' "$root_dir/assets/pets/penguin/bar.png" | grep -Fxq '20x20'
assert_status "phase 3 bundled pack validates" "$root_dir/bin/omarchy-dropdown-terminal-pet-validate" validate "$root_dir/assets/pets/penguin"
assert_status "phase 3 cat pack validates" "$root_dir/bin/omarchy-dropdown-terminal-pet-validate" validate "$root_dir/assets/pets/cat"
assert_status "phase 3 corgi pack validates" "$root_dir/bin/omarchy-dropdown-terminal-pet-validate" validate "$root_dir/assets/pets/corgi"
assert_status "phase 3 renderer resolves selected species" grep -Fq 'root.assetRoot + root.pack.atlas.path' "$root_dir/PetSprite.qml"
assert_status "phase 3 pack contract lists every action" jq -e '.actions as $actions | ["peek","enter","land","idle","walk","corner","climb","dance","success","failure","exit","sleep"] | all(.[]; . as $name | $actions | has($name))' "$root_dir/assets/pets/penguin/pet.json"

pet_bad="$runtime_dir/pet-bad"
cp -a "$root_dir/assets/pets/penguin" "$pet_bad"
jq '.atlas.path = "../pet.png"' "$pet_bad/pet.json" > "$runtime_dir/pet-bad-path.json"
mv "$runtime_dir/pet-bad-path.json" "$pet_bad/pet.json"
assert_false "pet validator rejects traversal path" "$root_dir/bin/omarchy-dropdown-terminal-pet-validate" validate "$pet_bad"
rm -rf "$pet_bad"
cp -a "$root_dir/assets/pets/penguin" "$pet_bad"
rm "$pet_bad/bar.png"
ln -s pet.png "$pet_bad/bar.png"
assert_false "pet validator rejects symlink" "$root_dir/bin/omarchy-dropdown-terminal-pet-validate" validate "$pet_bad"
rm -rf "$pet_bad"
cp -a "$root_dir/assets/pets/penguin" "$pet_bad"
rm "$pet_bad/bar.png"
cp "$root_dir/assets/pets/penguin/pet.png" "$pet_bad/bar.png"
chmod +x "$pet_bad/bar.png"
assert_false "pet validator rejects executable content" "$root_dir/bin/omarchy-dropdown-terminal-pet-validate" validate "$pet_bad"
rm -rf "$pet_bad"
cp -a "$root_dir/assets/pets/penguin" "$pet_bad"
cp "$root_dir/assets/pets/penguin/bar.png" "$pet_bad/bar.png"
truncate -s 8 "$pet_bad/bar.png"
assert_false "pet validator rejects truncated PNG" "$root_dir/bin/omarchy-dropdown-terminal-pet-validate" validate "$pet_bad"
pet_bad_dim="$runtime_dir/pet-bad-dim"
cp -a "$root_dir/assets/pets/penguin" "$pet_bad_dim"
jq '.bar.width = 19' "$pet_bad_dim/pet.json" > "$runtime_dir/pet-bad-dim.json"
mv "$runtime_dir/pet-bad-dim.json" "$pet_bad_dim/pet.json"
assert_false "pet validator rejects manifest dimension mismatch" "$root_dir/bin/omarchy-dropdown-terminal-pet-validate" validate "$pet_bad_dim"
pet_bad_full="$runtime_dir/pet-bad-full"
cp -a "$root_dir/assets/pets/penguin" "$pet_bad_full"
truncate -s 32 "$pet_bad_full/pet.png"
assert_false "pet validator rejects truncated atlas" "$root_dir/bin/omarchy-dropdown-terminal-pet-validate" validate "$pet_bad_full"
assert_status "phase 2 has the urgency property" grep -Fq 'toplevel.urgent === true' "$root_dir/Service.qml"
assert_status "phase 2 parses the append-only journal" grep -Fq 'eventIncompleteTail' "$root_dir/Service.qml"
assert_status "phase 2 re-probes only while running" grep -Fq 'interval: 1000' "$root_dir/Service.qml"
assert_status "phase 2 classifies from lifecycle order" grep -Fq 'root.eventTerminalState === "hidden"' "$root_dir/Service.qml"
assert_status "phase 2 does not use current visibility for finish history" grep -Fq 'Historical hidden-at-finish' "$root_dir/Service.qml"
assert_status "phase 2 uses distinct indicator states" grep -Eq 'return "(running|attention|succeeded|failed)"' "$root_dir/Service.qml"
assert_status "phase 2 has all manifest settings" jq -e '.barWidget.schema as $schema | ["urgencyIndicator","commandTracking","commandNotifyAfterMs","commandFailureIndicator","commandCancelIsFailure"] | all(.[]; . as $key | any($schema[]; .key == $key))' "$root_dir/manifest.json"
assert_status "phase 2 has the shell installer" test -x "$root_dir/bin/omarchy-dropdown-terminal-shell"
assert_status "phase 2 has all shell adapters" test -f "$root_dir/shell/bash.yadtm" -a -f "$root_dir/shell/zsh.yadtm" -a -f "$root_dir/shell/fish.yadtm"
assert_status "shell install opens confirmation from a ready snapshot" grep -Fq 'root.beginConfirmation("shell-install")' "$root_dir/Panel.qml"
assert_status "shell install confirms only after source status is ready" grep -Fq '&& root.shellStatusReport.sourceReadable === true' "$root_dir/Panel.qml"
assert_status "settings panel scrolls content within its card" grep -Fq 'id: contentScroll' "$root_dir/Panel.qml"
assert_status "effect choices wrap inside the card" test -f "$root_dir/WrappedButtonGroup.qml" -a -s "$root_dir/WrappedButtonGroup.qml"
assert_status "shell confirmation keeps its action row reachable" grep -Fq 'Guarded source: add only the marked Dropdown Terminal block.' "$root_dir/Panel.qml"
assert_false "bash adapter does not capture command text" grep -Fq 'BASH_COMMAND' "$root_dir/shell/bash.yadtm"
assert_false "bash adapter has no prompt-path external date" grep -Fq 'date ' "$root_dir/shell/bash.yadtm"
assert_false "fish adapter has no prompt-path external date" grep -Fq 'date ' "$root_dir/shell/fish.yadtm"
assert_status "installer captures Bash DEBUG trap before sourcing" grep -Fq 'YADTM_EXISTING_DEBUG_TRAP="$(trap -p DEBUG' "$root_dir/bin/omarchy-dropdown-terminal-shell"
assert_status "Bash adapter requires the rc-level trap capture" grep -Fq 'YADTM_EXISTING_DEBUG_TRAP_CAPTURED' "$root_dir/shell/bash.yadtm"
assert_status "Bash session includes its shell PID" grep -Fq 'YADTM_TERMINAL_SESSION:-bash}-bash-${BASHPID:-$$}' "$root_dir/shell/bash.yadtm"
assert_status "Zsh session includes its shell PID" grep -Fq 'YADTM_TERMINAL_SESSION:-zsh}-zsh-$$' "$root_dir/shell/zsh.yadtm"
assert_status "all adapters include their shell PID in sessions" grep -Fq 'YADTM_TERMINAL_SESSION-fish-$fish_pid' "$root_dir/shell/fish.yadtm"
assert_status "helper has scoped terminal environment" grep -Fq 'YADTM_COMMAND_EVENTS="$event_file"' "$root_dir/bin/omarchy-dropdown-terminal"
assert_status "helper records lifecycle only through a short schema" grep -Fq "v1\\t%s\\thelper" "$root_dir/bin/omarchy-dropdown-terminal"

rm -f "$state_file" "$legacy_address_file"
write_state 0x1000 0x1000
assert_status "state is valid JSON" jq -e '.version == 1 and .clients == ["0x1000"] and .active == "0x1000"' "$state_file"
read_state
assert_eq "state active round trip" "0x1000" "$state_active"
assert_eq "state clients round trip" "0x1000" "${state_clients[0]}"

rm -f "$state_file"
printf '0x1000\n' > "$legacy_address_file"
read_state
assert_eq "legacy address migration read" "1" "$legacy_migration"
choose_terminal_address
write_state "$terminal_address" "$terminal_address"
rm -f "$legacy_address_file"
assert_status "migrated state exists" jq -e '.version == 1 and .active == "0x1000"' "$state_file"

printf '%s\n' '{"version":99,"clients":["0x1000"],"active":"0x1000"}' > "$state_file"
read_state
choose_terminal_address
assert_eq "future state recovers from compositor" "0x1000" "$terminal_address"

printf '%s\n' 'not json' > "$state_file"
read_state
choose_terminal_address
assert_eq "invalid state recovers from compositor" "0x1000" "$terminal_address"

assert_eq "animation tuple fixture" $'3\teaseOutQuint\tslidevert' "$(read_special_animation)"

rm -f "$animation_file" "$legacy_animation_file"
printf '%s\n' $'3\teaseOutQuint\tslidevert' > "$animation_file"
repair_special_animation
assert_false "fresh animation marker is repaired after lock acquisition" test -e "$animation_file"

concurrent_clients="$(<"$fixture_dir/clients-concurrent.json")"
assert_eq "launch adopts the matching process lineage" "0x3000" \
  "$(new_client_from_json "$concurrent_clients" "0x1000" $'4242')"
assert_eq "launch rejects unrelated concurrent window" "" \
  "$(new_client_from_json "$concurrent_clients" "0x1000" $'7777')"
rm -f "$launch_file"
write_launch_marker "0x1000" 4242 $'4242\n7777'
assert_status "launch marker stores process lineage" jq -e '.launcherPid == 4242 and .launcherPids == ["4242", "7777"] and .before == ["0x1000"]' "$launch_file"
launch_now="$(date +%s)"
jq --argjson now "$launch_now" '.startedAt = $now' "$launch_file" > "$runtime_dir/fresh-launch.json"
mv "$runtime_dir/fresh-launch.json" "$launch_file"
pending_launch_before
assert_false "fresh launch marker is not stale" launch_marker_stale
assert_eq "fresh launch marker remains adoptable" "0x1000" "$pending_before"
assert_eq "fresh marker restores launcher PID" "4242" "$launch_pid"
assert_eq "fresh marker restores observed PIDs" $'4242\n7777' "$launch_pids"
jq '.startedAt = 0' "$launch_file" > "$runtime_dir/old-launch.json"
mv "$runtime_dir/old-launch.json" "$launch_file"
pending_launch_before
assert_status "expired launch marker is recognized" launch_marker_stale

fixture_clients="$fixture_dir/clients-stacked-parked.json"
fixture_monitors="$fixture_dir/monitors-stacked.json"
assert_false "stacked parked window is not on owner output" window_on_screen 0x1000

fixture_clients="$fixture_dir/clients-group.json"
recover_clients
assert_eq "recovery keeps every special client" "2" "${#recovery_clients[@]}"

fixture_clients="$fixture_dir/clients-hidden.json"
assert_false "missing client ends wait" wait_window_y 0xdead 100 1

fixture_clients="$fixture_dir/clients-single.json"
fixture_monitors="$fixture_dir/monitors-dual-scaled.json"
rm -f "$state_file"
status_output="$(YADTM_LIB_ONLY=0 XDG_RUNTIME_DIR="$runtime_dir" bash "$root_dir/bin/omarchy-dropdown-terminal" status)"
assert_status "status emits one JSON document" jq -e '.version == 1 and (.clients | length) == 1 and .active == "0x1000" and .visible == true and .focused == true' <<<"$status_output"

lock_fd=8
exec {lock_fd}>"$runtime_dir/io.github.tuthan.dropdown-terminal.lock"
flock -n "$lock_fd"
assert_status "status does not wait on the mutation lock" timeout 1 bash "$root_dir/bin/omarchy-dropdown-terminal" status
exec {lock_fd}>&-

mutation_config_home="$runtime_dir/config"
XDG_CONFIG_HOME="$mutation_config_home" bash "$root_dir/bin/omarchy-dropdown-terminal-bind" install
assert_status "binding helper read-back installed" bash -c 'XDG_CONFIG_HOME="$1" bash "$2" status | jq -e ".installed == true"' _ "$mutation_config_home" "$root_dir/bin/omarchy-dropdown-terminal-bind"
XDG_CONFIG_HOME="$mutation_config_home" bash "$root_dir/bin/omarchy-dropdown-terminal-bind" remove
assert_status "binding helper removal is idempotent" env XDG_CONFIG_HOME="$mutation_config_home" bash "$root_dir/bin/omarchy-dropdown-terminal-bind" remove
XDG_CONFIG_HOME="$mutation_config_home" bash "$root_dir/bin/omarchy-dropdown-terminal-special-fallthrough" enable
assert_status "fallthrough helper read-back installed" bash -c 'XDG_CONFIG_HOME="$1" bash "$2" status | jq -e ".installed == true"' _ "$mutation_config_home" "$root_dir/bin/omarchy-dropdown-terminal-special-fallthrough"
fallthrough_file="$mutation_config_home/hypr/input.lua"
fallthrough_digest_before="$(sha256sum "$fallthrough_file")"
fallthrough_backups_before="$(find "$mutation_config_home/hypr" -maxdepth 1 -type f -name 'input.lua.bak.*' | wc -l)"
XDG_CONFIG_HOME="$mutation_config_home" bash "$root_dir/bin/omarchy-dropdown-terminal-special-fallthrough" enable
assert_eq "fallthrough enable is content-idempotent" "$fallthrough_digest_before" "$(sha256sum "$fallthrough_file")"
assert_eq "fallthrough enable does not create another backup" "$fallthrough_backups_before" "$(find "$mutation_config_home/hypr" -maxdepth 1 -type f -name 'input.lua.bak.*' | wc -l)"
XDG_CONFIG_HOME="$mutation_config_home" bash "$root_dir/bin/omarchy-dropdown-terminal-special-fallthrough" disable
assert_status "fallthrough removal is idempotent" env XDG_CONFIG_HOME="$mutation_config_home" bash "$root_dir/bin/omarchy-dropdown-terminal-special-fallthrough" disable

conflict_config_home="$runtime_dir/conflict-config"
mkdir -p "$conflict_config_home/hypr"
printf '%s\n' \
  'bind = CTRL, Grave, exec, some-other-action' \
  'hl.bind("CTRL + code:41", hl.dsp.global("another-action"))' \
  > "$conflict_config_home/hypr/bindings.lua"
conflict_status="$(XDG_CONFIG_HOME="$conflict_config_home" bash "$root_dir/bin/omarchy-dropdown-terminal-bind" status)"
assert_status "binding status reports Ctrl + Grave conflicts" jq -e '.installed == false and .conflictCount == 2 and .conflicts[0].lineNumber == 1 and .conflicts[1].lineNumber == 2' <<<"$conflict_status"
assert_false "binding install refuses silent conflict" env XDG_CONFIG_HOME="$conflict_config_home" bash "$root_dir/bin/omarchy-dropdown-terminal-bind" install
assert_false "conflict install does not append duplicate" grep -Fqx -- 'hl.bind("CTRL + GRAVE", hl.dsp.global("io.github.tuthan.dropdown-terminal:toggle"))' "$conflict_config_home/hypr/bindings.lua"
XDG_CONFIG_HOME="$conflict_config_home" bash "$root_dir/bin/omarchy-dropdown-terminal-bind" install-force
assert_status "explicit conflict confirmation can install" bash -c 'XDG_CONFIG_HOME="$1" bash "$2" status | jq -e ".installed == true and .conflictCount == 2"' _ "$conflict_config_home" "$root_dir/bin/omarchy-dropdown-terminal-bind"

malformed_binding_home="$runtime_dir/malformed-binding"
mkdir -p "$malformed_binding_home/hypr"
printf '%s\n' \
  '-- BEGIN Dropdown Terminal binding' \
  'user_setting=kept' \
  > "$malformed_binding_home/hypr/bindings.lua"
malformed_binding_digest="$(sha256sum "$malformed_binding_home/hypr/bindings.lua")"
assert_false "binding helper refuses malformed managed block" env XDG_CONFIG_HOME="$malformed_binding_home" bash "$root_dir/bin/omarchy-dropdown-terminal-bind" install
assert_eq "malformed binding remains untouched" "$malformed_binding_digest" "$(sha256sum "$malformed_binding_home/hypr/bindings.lua")"

malformed_fallthrough_home="$runtime_dir/malformed-fallthrough"
mkdir -p "$malformed_fallthrough_home/hypr"
printf '%s\n' \
  '-- BEGIN Dropdown Terminal special fallthrough' \
  'user_setting=kept' \
  > "$malformed_fallthrough_home/hypr/input.lua"
malformed_fallthrough_digest="$(sha256sum "$malformed_fallthrough_home/hypr/input.lua")"
assert_false "fallthrough helper refuses malformed managed block" env XDG_CONFIG_HOME="$malformed_fallthrough_home" bash "$root_dir/bin/omarchy-dropdown-terminal-special-fallthrough" enable
assert_eq "malformed fallthrough remains untouched" "$malformed_fallthrough_digest" "$(sha256sum "$malformed_fallthrough_home/hypr/input.lua")"

# Phase 2 shell integration installer: use a private fake HOME and an installed
# plugin copy so the guarded source path is real, just as it is after Omarchy
# installs this plugin.
shell_home="$runtime_dir/shell-home"
shell_plugin="$shell_home/.config/omarchy/plugins/io.github.tuthan.dropdown-terminal"
mkdir -p "$shell_plugin/shell"
cp "$root_dir"/shell/*.yadtm "$shell_plugin/shell/"
printf '%s\n' 'user_setting=kept' > "$shell_home/.bashrc"
shell_status="$(HOME="$shell_home" SHELL=/usr/bin/bash bash "$root_dir/bin/omarchy-dropdown-terminal-shell" status)"
assert_status "shell status reports target and source" jq -e '.shell == "bash" and .installed == false and .sourceReadable == true' <<<"$shell_status"
HOME="$shell_home" SHELL=/usr/bin/bash bash "$root_dir/bin/omarchy-dropdown-terminal-shell" install >/dev/null
assert_status "shell install read-back" bash -c 'HOME="$1" SHELL=/usr/bin/bash bash "$2" status | jq -e ".installed == true"' _ "$shell_home" "$root_dir/bin/omarchy-dropdown-terminal-shell"
assert_status "shell block is exact" grep -Fqx -- '# END Dropdown Terminal shell integration' "$shell_home/.bashrc"
shell_backup_count="$(find "$shell_home" -maxdepth 1 -type f -name '.bashrc.bak.*' | wc -l)"
shell_digest="$(sha256sum "$shell_home/.bashrc")"
HOME="$shell_home" SHELL=/usr/bin/bash bash "$root_dir/bin/omarchy-dropdown-terminal-shell" install >/dev/null
assert_eq "shell install is content-idempotent" "$shell_digest" "$(sha256sum "$shell_home/.bashrc")"
assert_eq "shell install does not create another backup" "$shell_backup_count" "$(find "$shell_home" -maxdepth 1 -type f -name '.bashrc.bak.*' | wc -l)"
printf '%s\n' 'unrelated=preserved' > "$shell_home/.zshrc"
HOME="$shell_home" SHELL=/usr/bin/zsh bash "$root_dir/bin/omarchy-dropdown-terminal-shell" install zsh >/dev/null
assert_status "zsh shell target" bash -c 'HOME="$1" SHELL=/usr/bin/zsh bash "$2" status zsh | jq -e ".shell == \"zsh\" and .installed == true"' _ "$shell_home" "$root_dir/bin/omarchy-dropdown-terminal-shell"
fish_config_home="$shell_home/fish-config"
mkdir -p "$fish_config_home/fish"
HOME="$shell_home" XDG_CONFIG_HOME="$fish_config_home" SHELL=/usr/bin/fish bash "$root_dir/bin/omarchy-dropdown-terminal-shell" install fish >/dev/null
assert_status "fish shell target" bash -c 'HOME="$1" XDG_CONFIG_HOME="$2" SHELL=/usr/bin/fish bash "$3" status fish | jq -e ".shell == \"fish\" and .installed == true"' _ "$shell_home" "$fish_config_home" "$root_dir/bin/omarchy-dropdown-terminal-shell"
HOME="$shell_home" SHELL=/usr/bin/bash bash "$root_dir/bin/omarchy-dropdown-terminal-shell" remove >/dev/null
assert_status "shell removal read-back" bash -c 'HOME="$1" SHELL=/usr/bin/bash bash "$2" status | jq -e ".installed == false"' _ "$shell_home" "$root_dir/bin/omarchy-dropdown-terminal-shell"
assert_status "shell removal preserves unrelated content" grep -Fqx -- 'user_setting=kept' "$shell_home/.bashrc"
assert_status "missing plugin source is silent" bash -c 'output="$(HOME="$1" bash --noprofile --rcfile "$1/.bashrc" -c true 2>&1)"; ! grep -Fq "No such file" <<<"$output"' _ "$shell_home"
printf '%s\n' '# BEGIN Dropdown Terminal shell integration' 'user_content_after_unclosed_marker' >"$shell_home/.bashrc"
malformed_digest="$(sha256sum "$shell_home/.bashrc")"
assert_false "shell installer refuses unclosed marker" env HOME="$shell_home" SHELL=/usr/bin/bash bash "$root_dir/bin/omarchy-dropdown-terminal-shell" remove
assert_eq "malformed marker is not destructively rewritten" "$malformed_digest" "$(sha256sum "$shell_home/.bashrc")"

# Bash prompt-path contract: one start/end pair per foreground command, no
# command text, and the status remains nonzero when a later prompt helper runs.
hook_events="$runtime_dir/bash-events"
hook_rc="$runtime_dir/bash-hook.rc"
hook_output="$runtime_dir/bash-hook.out"
cat > "$hook_rc" <<EOF
PROMPT_COMMAND=(user_precmd)
user_precmd() { :; }
YADTM_EXISTING_DEBUG_TRAP="\$(trap -p DEBUG 2>/dev/null || true)"
YADTM_EXISTING_DEBUG_TRAP_CAPTURED=1
source "$root_dir/shell/bash.yadtm"
unset YADTM_EXISTING_DEBUG_TRAP YADTM_EXISTING_DEBUG_TRAP_CAPTURED
EOF
printf 'sleep 0.02\nfalse\nexit\n' | HOME="$shell_home" YADTM_TERMINAL=1 YADTM_COMMAND_EVENTS="$hook_events" YADTM_TERMINAL_SESSION=phase2-test PS1=prompt SHELL=/usr/bin/bash bash --noprofile --rcfile "$hook_rc" -i >"$hook_output" 2>"$runtime_dir/bash-hook.err" || true
assert_status "bash hook emits start and finish" test "$(awk -F '\t' '$2 == "start" { starts++ } $2 == "finish" { finishes++ } END { print starts ":" finishes }' "$hook_events")" = "3:2"
assert_eq "bash hook preserves false status" "1" "$(awk -F '\t' '$2 == "finish" { print $6 }' "$hook_events" | tail -n 1)"
assert_false "bash hook never writes command text" grep -Eq 'sleep|false' "$hook_events"
assert_false "bash hook writes no prompt output" grep -Fq 'Dropdown Terminal' "$hook_output"

debug_events="$runtime_dir/bash-debug-events"
debug_rc="$runtime_dir/bash-debug.rc"
debug_marker="$runtime_dir/bash-debug.marker"
cat > "$debug_rc" <<EOF
user_debug() { printf x >>"$debug_marker"; }
trap 'user_debug' DEBUG
YADTM_EXISTING_DEBUG_TRAP="\$(trap -p DEBUG 2>/dev/null || true)"
YADTM_EXISTING_DEBUG_TRAP_CAPTURED=1
source "$root_dir/shell/bash.yadtm"
unset YADTM_EXISTING_DEBUG_TRAP YADTM_EXISTING_DEBUG_TRAP_CAPTURED
: >"$debug_marker"
printf 'after-source\n' >/dev/null
EOF
printf 'true\nexit\n' | HOME="$shell_home" YADTM_TERMINAL=1 YADTM_COMMAND_EVENTS="$debug_events" YADTM_TERMINAL_SESSION=debug-test PS1=prompt SHELL=/usr/bin/bash bash --noprofile --rcfile "$debug_rc" -i >"$runtime_dir/bash-debug.out" 2>"$runtime_dir/bash-debug.err" || true
assert_status "bash hook preserves an existing DEBUG trap" test -s "$debug_marker"

concurrent_events="$runtime_dir/concurrent-events"
for concurrent_session in one two; do
  (printf 'true\nexit\n' | env HOME="$shell_home" YADTM_TERMINAL=1 YADTM_COMMAND_EVENTS="$concurrent_events" YADTM_TERMINAL_SESSION=shared-launch PS1=prompt SHELL=/usr/bin/bash bash --noprofile --rcfile "$hook_rc" -i >/dev/null 2>"$runtime_dir/$concurrent_session.err" || true) &
done
wait
assert_status "concurrent shell events remain complete lines" awk -F '\t' 'NF != 0 && NF != 5 && NF != 6 { bad=1 } END { exit bad }' "$concurrent_events"
assert_eq "concurrent shell events are not lost" "4:2" "$(awk -F '\t' '$2 == "start" { starts++ } $2 == "finish" { finishes++ } END { print starts ":" finishes }' "$concurrent_events")"
assert_eq "shared launch sessions include distinct shell PIDs" "2" "$(awk -F '\t' '$2 == "start" && !seen[$3]++ { sessions++ } END { print sessions }' "$concurrent_events")"

if (( fail > 0 )); then
  printf '%d passed, %d failed\n' "$pass" "$fail" >&2
  exit 1
fi
printf '%d checks passed\n' "$pass"
