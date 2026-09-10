.pragma library
.import "PetBond.js" as PetBond

// Pure encounter decisions and budgets. PetEncounter.qml owns timers and
// sprites; keeping these calculations here makes the 14-second bound easy to
// audit without a compositor or a running shell.

var MAX_ENCOUNTER_MS = 14000
var MIN_REROLL_REMAINING_MS = 2500

var stages = ["appear", "approach", "standoff", "resolve", "cleanup"]

var budgetTable = {
  appear: 500,
  approach: 4000,
  standoff: 2000,
  brave: 2000,
  cower: 5000,
  assisted: 1500,
  defeat: 1000,
  vanish: 500,
  cleanup: 500
}

// Named paths are data rather than hidden timing arithmetic in QML. The
// largest legal path includes the last-moment pet reroll and lands exactly on
// the hard deadline; the deadline timer remains the safety guard.
var pathBudgets = {
  skip: ["appear", "cleanup"],
  approachTimeoutStandoff: ["appear", "approach", "standoff", "cower"],
  approachTimeoutVanish: ["appear", "approach", "vanish"],
  brave: ["appear", "approach", "standoff", "brave", "vanish"],
  assisted: ["appear", "approach", "standoff", "cower", "assisted"],
  success: ["appear", "approach", "standoff", "cower", "vanish"],
  cowerTimeout: ["appear", "approach", "standoff", "cower", "defeat"],
  lastMomentReroll: ["appear", "approach", "standoff", "cower", "brave", "vanish"]
}

function finite(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

function clamp(value, low, high) {
  return Math.max(low, Math.min(high, value))
}

function randomValue(random) {
  var value = typeof random === "function" ? random() : random
  return clamp(finite(value, Math.random()), 0, 0.999999)
}

function resolve(bond, random, assistedReroll) {
  var chance = PetBond.braveryChance(bond) + (assistedReroll === true ? 0.25 : 0)
  chance = clamp(chance, 0, 1)
  return randomValue(random) < chance ? "brave" : "cower"
}

function spawnDistance(speed, room) {
  var roomValue = Math.max(0, finite(room, 0))
  // The caller treats zero as the explicit "not enough room" result. A
  // villain never spawns in the terminal's resize ring just to satisfy the
  // lower clamp when a corner is closer than 120 px.
  if (roomValue < 120) return 0
  return Math.min(roomValue, Math.max(120, finite(speed, 30) * 3.5 + 64))
}

function rerollAllowed(remainingMs) {
  return finite(remainingMs, 0) >= MIN_REROLL_REMAINING_MS
}

function sumBudget(path) {
  var names = Array.isArray(path) ? path : []
  var total = 0
  for (var i = 0; i < names.length; i++) total += Number(budgetTable[names[i]] || 0)
  return total
}

function allPathsWithinDeadline() {
  for (var path in pathBudgets)
    if (sumBudget(pathBudgets[path]) > MAX_ENCOUNTER_MS) return false
  return true
}

function budgetFor(path) {
  return sumBudget(pathBudgets[path] || [])
}
