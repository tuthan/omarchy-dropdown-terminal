.pragma library

// Pure bond arithmetic. Service owns persistence and writer election; this
// module only transforms a validated species record or document. Keeping the
// caps and decay here makes the values deterministic in QML tests and keeps a
// stale reader from becoming a second authority.

var MIN_BOND = 0
var MAX_BOND = 100
var MAX_DAY_PETS = 10
var MAX_DAY_CELEBRATIONS = 6
var DECAY_GRACE_DAYS = 3
var DECAY_PER_DAY = 2
var MAX_DECAY_DAYS_PER_LOAD = 10

var TIER_NAMES = ["Wary", "Warming up", "Friends", "Inseparable"]
var SPECIES = ["Penguin", "Cat", "Corgi"]

function finite(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

function integer(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? Math.floor(number) : fallback
}

function clamp(value, low, high) {
  return Math.max(low, Math.min(high, value))
}

function clampBond(value) {
  return clamp(Math.round(finite(value, 0)), MIN_BOND, MAX_BOND)
}

function tierForBond(value) {
  var bond = clampBond(value)
  if (bond >= 75) return 3
  if (bond >= 50) return 2
  if (bond >= 25) return 1
  return 0
}

function tierName(value) {
  var tier = Number(value)
  if (tier >= 0 && tier < TIER_NAMES.length) return TIER_NAMES[Math.floor(tier)]
  return TIER_NAMES[0]
}

function tierWord(value) {
  return tierName(tierForBond(value))
}

function braveryChance(value) {
  var bond = value && typeof value === "object" ? value.bond : value
  return 0.15 + 0.70 * clampBond(bond) / 100
}

function dayValue(value, today) {
  var fallback = integer(today, 0)
  var number = Number(value)
  return isFinite(number) ? Math.floor(number) : fallback
}

function emptySpecies(today) {
  var day = dayValue(today, 0)
  return {
    bond: 0,
    peakTier: 0,
    pets: 0,
    wins: 0,
    assists: 0,
    losses: 0,
    lastInteractionDay: day,
    decayChargedThroughDay: day,
    countersDay: day,
    dayPets: 0,
    dayCelebrations: 0
  }
}

function copyRecord(record) {
  var result = {}
  record = record && typeof record === "object" ? record : {}
  for (var key in record) result[key] = record[key]
  return result
}

function normalizeSpecies(record, today) {
  var day = dayValue(today, 0)
  var source = record && typeof record === "object" ? record : {}
  var result = emptySpecies(day)
  result.bond = clampBond(source.bond)
  result.peakTier = clamp(integer(source.peakTier, tierForBond(result.bond)), 0, 3)
  result.peakTier = Math.max(result.peakTier, tierForBond(result.bond))
  result.pets = Math.max(0, integer(source.pets, 0))
  result.wins = Math.max(0, integer(source.wins, 0))
  result.assists = Math.max(0, integer(source.assists, 0))
  result.losses = Math.max(0, integer(source.losses, 0))

  // Missing markers are intentionally treated as today. There is no safe way
  // to infer how long an old document was absent, so a defensive reader never
  // charges retroactive decay for an incomplete record.
  result.lastInteractionDay = source.lastInteractionDay === undefined
    ? day : dayValue(source.lastInteractionDay, day)
  result.decayChargedThroughDay = source.decayChargedThroughDay === undefined
    ? day : dayValue(source.decayChargedThroughDay, day)
  result.countersDay = source.countersDay === undefined
    ? day : dayValue(source.countersDay, day)
  result.dayPets = Math.max(0, integer(source.dayPets, 0))
  result.dayCelebrations = Math.max(0, integer(source.dayCelebrations, 0))
  if (result.countersDay !== day) {
    result.countersDay = day
    result.dayPets = 0
    result.dayCelebrations = 0
  }
  return result
}

function emptyDocument(today, writer) {
  var result = {
    version: 1,
    revision: 0,
    writer: String(writer || ""),
    updatedAt: 0,
    species: {}
  }
  var day = dayValue(today, 0)
  for (var i = 0; i < SPECIES.length; i++) result.species[SPECIES[i]] = emptySpecies(day)
  return result
}

function normalizeDocument(document, today, writer) {
  var source = document && typeof document === "object" ? document : {}
  var result = {
    version: 1,
    revision: Math.max(0, integer(source.revision, 0)),
    writer: String(writer === undefined ? (source.writer || "") : writer),
    updatedAt: Math.max(0, integer(source.updatedAt, 0)),
    species: {}
  }
  var sourceSpecies = source.species && typeof source.species === "object"
    ? source.species : {}
  for (var i = 0; i < SPECIES.length; i++) {
    var name = SPECIES[i]
    result.species[name] = normalizeSpecies(sourceSpecies[name], today)
  }
  return result
}

function resetDayCounters(record, today) {
  var day = dayValue(today, 0)
  if (record.countersDay !== day) {
    record.countersDay = day
    record.dayPets = 0
    record.dayCelebrations = 0
  }
}

function updatePeak(record) {
  record.bond = clampBond(record.bond)
  record.peakTier = Math.max(clamp(integer(record.peakTier, 0), 0, 3), tierForBond(record.bond))
}

function eventKind(value) {
  var kind = String(value || "").toLowerCase()
  var aliases = {
    pet: "petting",
    petting: "petting",
    release: "petting",
    celebration: "celebration",
    celebrate: "celebration",
    success: "celebration",
    succeeded: "celebration",
    win: "win",
    alone: "win",
    encounterwin: "win",
    victory: "win",
    assist: "assist",
    assisted: "assist",
    encounterassist: "assist",
    loss: "loss",
    defeated: "loss",
    failure: "loss",
    encounterloss: "loss",
    decay: "decay",
    reset: "reset"
  }
  return aliases[kind] || kind
}

function applyDelta(record, kind, today) {
  var result = normalizeSpecies(record, today)
  var day = dayValue(today, 0)
  var event = eventKind(kind)

  if (event === "reset") {
    var reset = emptySpecies(day)
    // Reset is intentionally a complete data reset, including peakTier.
    return reset
  }
  if (event === "decay") return applyDecay(result, day)

  var change = 0
  if (event === "petting") {
    if (result.dayPets >= MAX_DAY_PETS) return result
    result.dayPets++
    result.pets++
    change = 1
  } else if (event === "celebration") {
    if (result.dayCelebrations >= MAX_DAY_CELEBRATIONS) return result
    change = Math.min(2, MAX_DAY_CELEBRATIONS - result.dayCelebrations)
    result.dayCelebrations += change
  } else if (event === "win") {
    result.wins++
    change = 5
  } else if (event === "assist") {
    result.assists++
    change = 3
  } else if (event === "loss") {
    result.losses++
    change = -1
  } else {
    return result
  }

  result.bond = clampBond(result.bond + change)
  // A bond mutation is an interaction even when the outcome lowered the
  // score. This prevents a witnessed encounter from immediately being read
  // as an unattended day.
  result.lastInteractionDay = day
  updatePeak(result)
  return result
}

function applyEvent(record, kind, today) {
  return applyDelta(record, kind, today)
}

function applyDecay(record, today) {
  var day = dayValue(today, 0)
  var result = normalizeSpecies(record, day)
  var charged = result.decayChargedThroughDay
  if (charged > day) charged = day
  var first = charged + 1
  var end = Math.min(day, first + MAX_DECAY_DAYS_PER_LOAD - 1)
  for (var d = first; d <= end; d++) {
    if (d > result.lastInteractionDay + DECAY_GRACE_DAYS)
      result.bond = Math.max(MIN_BOND, result.bond - DECAY_PER_DAY)
  }
  result.decayChargedThroughDay = day
  updatePeak(result)
  return result
}

function applyDocumentDecay(document, today) {
  var result = normalizeDocument(document, today)
  var changed = false
  for (var i = 0; i < SPECIES.length; i++) {
    var name = SPECIES[i]
    var before = JSON.stringify(result.species[name])
    result.species[name] = applyDecay(result.species[name], today)
    if (before !== JSON.stringify(result.species[name])) changed = true
  }
  return { document: result, changed: changed }
}

function deltaSort(left, right) {
  var speciesLeft = SPECIES.indexOf(String(left && left.species || ""))
  var speciesRight = SPECIES.indexOf(String(right && right.species || ""))
  if (speciesLeft !== speciesRight) return speciesLeft - speciesRight
  var order = { reset: 0, decay: 1, loss: 2, assist: 3, win: 4,
    celebration: 5, petting: 6 }
  var leftKind = eventKind(left && left.kind)
  var rightKind = eventKind(right && right.kind)
  return (order[leftKind] === undefined ? 99 : order[leftKind])
    - (order[rightKind] === undefined ? 99 : order[rightKind])
}

function applyDeltas(document, deltas, today, writer) {
  var result = normalizeDocument(document, today, writer)
  var list = Array.isArray(deltas) ? deltas.slice() : []
  list.sort(deltaSort)
  for (var i = 0; i < list.length; i++) {
    var delta = list[i]
    if (!delta || SPECIES.indexOf(String(delta.species || "")) < 0) continue
    var name = String(delta.species)
    result.species[name] = applyDelta(result.species[name], delta.kind, today)
  }
  return result
}

function validSpeciesRecord(record) {
  if (!record || typeof record !== "object" || Array.isArray(record)) return false
  var required = ["bond", "peakTier", "pets", "wins", "assists", "losses",
    "dayPets", "dayCelebrations"]
  var optionalMarkers = ["lastInteractionDay", "decayChargedThroughDay", "countersDay"]
  for (var i = 0; i < required.length; i++) {
    if (typeof record[required[i]] !== "number" || !isFinite(record[required[i]])
        || record[required[i]] !== Math.floor(record[required[i]])) return false
  }
  // Marker fields were deliberately made defensive for the first release:
  // an older bond document can omit them and normalizeSpecies will seed them
  // with today rather than charging an unknowable period retroactively.
  for (var j = 0; j < optionalMarkers.length; j++) {
    var marker = optionalMarkers[j]
    if (record[marker] !== undefined
        && (typeof record[marker] !== "number" || !isFinite(record[marker])
          || record[marker] !== Math.floor(record[marker]))) return false
  }
  return Number(record.bond) >= 0 && Number(record.bond) <= 100
    && Number(record.peakTier) >= 0 && Number(record.peakTier) <= 3
    && Number(record.peakTier) === Math.floor(Number(record.peakTier))
    && Number(record.pets) >= 0 && Number(record.wins) >= 0
    && Number(record.assists) >= 0 && Number(record.losses) >= 0
    && (record.lastInteractionDay === undefined || Number(record.lastInteractionDay) >= 0)
    && (record.decayChargedThroughDay === undefined || Number(record.decayChargedThroughDay) >= 0)
    && (record.countersDay === undefined || Number(record.countersDay) >= 0)
    && Number(record.dayPets) >= 0 && Number(record.dayCelebrations) >= 0
}

function validDocument(document) {
  if (!document || typeof document !== "object" || Array.isArray(document)
      || document.version !== 1 || !document.species
      || typeof document.species !== "object" || Array.isArray(document.species)) return false
  for (var i = 0; i < SPECIES.length; i++) {
    var record = document.species[SPECIES[i]]
    if (record !== undefined && !validSpeciesRecord(record)) return false
  }
  return true
}
