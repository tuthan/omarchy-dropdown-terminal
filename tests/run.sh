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
assert_status "binding preflight waits for fresh status" grep -Fq 'readonly property bool bindingStatusReady' "$root_dir/BarWidget.qml"

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
jq '.startedAt = 0' "$launch_file" > "$runtime_dir/old-launch.json"
mv "$runtime_dir/old-launch.json" "$launch_file"
pending_launch_before
assert_eq "late launch marker remains adoptable" "0x1000" "$pending_before"
assert_eq "late marker restores launcher PID" "4242" "$launch_pid"
assert_eq "late marker restores observed PIDs" $'4242\n7777' "$launch_pids"

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

if (( fail > 0 )); then
  printf '%d passed, %d failed\n' "$pass" "$fail" >&2
  exit 1
fi
printf '%d checks passed\n' "$pass"
