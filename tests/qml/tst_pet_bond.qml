import QtQuick
import QtTest
import "../../PetBond.js" as PetBond

TestCase {
  name: "PetBond"

  function test_daily_caps_and_events() {
    var record = PetBond.emptySpecies(10)
    for (var i = 0; i < 12; i++) record = PetBond.applyDelta(record, "petting", 10)
    compare(record.bond, 10)
    compare(record.pets, 10)
    compare(record.dayPets, 10)

    for (var j = 0; j < 4; j++) record = PetBond.applyDelta(record, "celebration", 10)
    compare(record.bond, 16)
    compare(record.dayCelebrations, 6)
  }

  function test_tier_boundaries_and_bravery() {
    compare(PetBond.tierWord(24), "Wary")
    compare(PetBond.tierWord(25), "Warming up")
    compare(PetBond.tierWord(49), "Warming up")
    compare(PetBond.tierWord(50), "Friends")
    compare(PetBond.tierWord(74), "Friends")
    compare(PetBond.tierWord(75), "Inseparable")
    compare(PetBond.braveryChance(0), 0.15)
    compare(PetBond.braveryChance(50), 0.5)
    compare(PetBond.braveryChance(100), 0.85)
  }

  function test_decay_is_bounded_and_idempotent() {
    var record = PetBond.emptySpecies(1)
    record.bond = 60
    record.peakTier = 2
    record.lastInteractionDay = -10
    record.decayChargedThroughDay = 1
    var decayed = PetBond.applyDecay(record, 20)
    compare(decayed.bond, 40)
    compare(decayed.decayChargedThroughDay, 20)
    compare(decayed.peakTier, 2)
    var sameDay = PetBond.applyDecay(decayed, 20)
    compare(sameDay.bond, 40)
    compare(sameDay.decayChargedThroughDay, 20)
  }

  function test_grace_and_markers() {
    var record = PetBond.emptySpecies(1)
    record.bond = 20
    record.lastInteractionDay = 1
    record.decayChargedThroughDay = 1
    var grace = PetBond.applyDecay(record, 5)
    compare(grace.bond, 18)
    var interaction = PetBond.applyDelta(grace, "petting", 10)
    compare(interaction.lastInteractionDay, 10)
    compare(interaction.decayChargedThroughDay, 5)
  }

  function test_delta_merge_is_order_independent() {
    var base = PetBond.emptyDocument(10)
    var first = [
      { species: "Penguin", kind: "win" },
      { species: "Penguin", kind: "petting" },
      { species: "Penguin", kind: "celebration" }
    ]
    var second = first.slice().reverse()
    var left = PetBond.applyDeltas(base, first, 10)
    var right = PetBond.applyDeltas(base, second, 10)
    compare(JSON.stringify(left.species.Penguin), JSON.stringify(right.species.Penguin))
  }

  function test_invalid_document_is_not_valid() {
    verify(!PetBond.validDocument({ version: 99, species: {} }))
    var document = PetBond.emptyDocument(10)
    document.species.Penguin.bond = 101
    verify(!PetBond.validDocument(document))

    var legacy = {
      bond: 0, peakTier: 0, pets: 0, wins: 0, assists: 0, losses: 0,
      dayPets: 0, dayCelebrations: 0
    }
    document.species.Penguin = legacy
    verify(PetBond.validDocument(document))
    var migrated = PetBond.applyDocumentDecay(document, 10).document.species.Penguin
    compare(migrated.lastInteractionDay, 10)
    compare(migrated.decayChargedThroughDay, 10)
    compare(migrated.countersDay, 10)
  }
}
