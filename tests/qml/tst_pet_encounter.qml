import QtQuick
import QtTest
import "../../PetEncounter.js" as Encounter

TestCase {
  name: "PetEncounter"

  function test_deterministic_resolution_and_reroll() {
    compare(Encounter.resolve(0, 0.14, false), "brave")
    compare(Encounter.resolve(0, 0.15, false), "cower")
    compare(Encounter.resolve(0, 0.39, true), "brave")
    compare(Encounter.resolve(100, 0.84, false), "brave")
    compare(Encounter.resolve(100, 0.85, false), "cower")
    verify(!Encounter.rerollAllowed(2499))
    verify(Encounter.rerollAllowed(2500))
  }

  function test_spawn_distance_is_room_and_speed_bounded() {
    compare(Encounter.spawnDistance(12, 100), 0)
    compare(Encounter.spawnDistance(12, 300), 120)
    compare(Encounter.spawnDistance(60, 300), 274)
    compare(Encounter.spawnDistance(60, 1000), 274)
  }

  function test_every_named_path_meets_deadline() {
    verify(Encounter.allPathsWithinDeadline())
    for (var name in Encounter.pathBudgets)
      verify(Encounter.budgetFor(name) <= Encounter.MAX_ENCOUNTER_MS, name)
    compare(Encounter.budgetFor("lastMomentReroll"), 14000)
  }
}
