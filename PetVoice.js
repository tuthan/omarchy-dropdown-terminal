.pragma library

// Pure speech selection. This module deliberately never evaluates a template
// or executes a string; the only substitutions are the two documented facts.

var knownEvents = ["failed", "succeeded", "petting", "idle", "villainAppear",
  "victory", "assisted", "defeat"]
var knownTiers = ["Kind", "Sassy", "Savage"]

function finite(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

function asLine(value) {
  if (typeof value === "string") return { text: value, minPeakTier: 0 }
  if (value && typeof value === "object" && typeof value.text === "string")
    return { text: value.text, minPeakTier: Number(value.minPeakTier || 0) }
  return null
}

function fill(text, facts) {
  facts = facts || {}
  return String(text).replace(/\{status\}/g, String(facts.status === undefined ? "?" : facts.status))
    .replace(/\{duration\}/g, String(facts.duration === undefined ? "unknown duration" : facts.duration))
}

function mergeLines(lines, tier, event, species) {
  var result = []
  var overrides = lines && lines.species && species && lines.species[species]
    ? lines.species[species][tier] : null
  var base = lines && lines.tiers && lines.tiers[tier] ? lines.tiers[tier][event] : null
  var overrideEvent = overrides && overrides[event]
  var source = Array.isArray(overrideEvent) ? overrideEvent : []
  // Overrides are intentionally in front of the base list. They add flavour
  // without making a species lose the stable fallback lines.
  for (var i = 0; i < source.length; i++) if (asLine(source[i])) result.push(source[i])
  if (Array.isArray(base)) for (var j = 0; j < base.length; j++) if (asLine(base[j])) result.push(base[j])
  return result
}

function randomValue(random) {
  if (typeof random === "function") return Math.max(0, Math.min(0.999999, finite(random(), 0)))
  return Math.max(0, Math.min(0.999999, finite(random, Math.random())))
}

function pickLine(lines, tier, event, species, recent, random, unlocks) {
  if (!lines || knownTiers.indexOf(String(tier)) < 0 || knownEvents.indexOf(String(event)) < 0)
    return ""
  var peak = unlocks === undefined || unlocks === null ? 3 : Math.max(0, Math.min(3, Number(unlocks)))
  var candidates = []
  var merged = mergeLines(lines, String(tier), String(event), String(species || ""))
  var recentList = Array.isArray(recent) ? recent.slice(-5) : []
  for (var i = 0; i < merged.length; i++) {
    var line = asLine(merged[i])
    if (!line || !isFinite(line.minPeakTier) || line.minPeakTier < 0 || line.minPeakTier > peak)
      continue
    var filled = fill(line.text, lines.facts)
    if (recentList.indexOf(filled) < 0) candidates.push(filled)
  }
  if (candidates.length === 0) {
    for (var j = 0; j < merged.length; j++) {
      var fallback = asLine(merged[j])
      if (fallback && isFinite(fallback.minPeakTier) && fallback.minPeakTier <= peak)
        candidates.push(fill(fallback.text, lines.facts))
    }
  }
  if (candidates.length === 0) return ""
  return candidates[Math.floor(randomValue(random) * candidates.length)]
}

function encounterLineAllowed(event, usedEvents, count) {
  var name = String(event || "")
  var used = Array.isArray(usedEvents) ? usedEvents : []
  // Encounter events are stage names, so uniqueness is the one-line-per-stage
  // gate. The count check is still explicit because a future stage may share
  // an event name without being allowed to extend the encounter budget.
  return ["villainAppear", "victory", "assisted", "defeat"].indexOf(name) >= 0
    && used.indexOf(name) < 0
    && Number(count || 0) < 3
}

function lineAvailability(lines, tier, species, unlocks) {
  if (!lines || knownTiers.indexOf(String(tier)) < 0) return { available: 0, total: 0 }
  var peak = unlocks === undefined || unlocks === null ? 3
    : Math.max(0, Math.min(3, Number(unlocks)))
  var total = 0
  var available = 0
  for (var i = 0; i < knownEvents.length; i++) {
    var merged = mergeLines(lines, String(tier), knownEvents[i], String(species || ""))
    for (var j = 0; j < merged.length; j++) {
      var line = asLine(merged[j])
      if (!line || !isFinite(line.minPeakTier) || line.minPeakTier < 0 || line.minPeakTier > 3)
        continue
      total++
      if (line.minPeakTier <= peak) available++
    }
  }
  return { available: available, total: total }
}

function validText(text) {
  return typeof text === "string" && text.length > 0 && text.length <= 72
    && !/[\x00-\x1f\x7f]/.test(text)
    && text.indexOf("$") < 0 && text.indexOf("`") < 0
    && text.replace(/\{status\}|\{duration\}/g, "").indexOf("{") < 0
    && text.replace(/\{status\}|\{duration\}/g, "").indexOf("}") < 0
}

function validateArray(value, path, errors) {
  if (!Array.isArray(value) || value.length < 6 || value.length > 40) {
    errors.push(path + " must contain 6-40 lines")
    return
  }
  for (var i = 0; i < value.length; i++) {
    var line = asLine(value[i])
    if (!line || !validText(line.text) || !isFinite(line.minPeakTier)
        || line.minPeakTier < 0 || line.minPeakTier > 3 || Math.floor(line.minPeakTier) !== line.minPeakTier)
      errors.push(path + "[" + i + "] is invalid")
  }
}

function validateEventMap(value, path, errors) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    errors.push(path + " must be an object")
    return
  }
  for (var event in value)
    if (knownEvents.indexOf(event) < 0) errors.push(path + "." + event + " is unknown")
}

function validateDocument(document) {
  var errors = []
  if (!document || document.version !== 1) errors.push("version must be 1")
  if (!document || !document.tiers || typeof document.tiers !== "object") {
    errors.push("tiers is required")
  } else {
    for (var t = 0; t < knownTiers.length; t++) {
      var tier = knownTiers[t]
      if (!document.tiers[tier]) { errors.push("missing tier " + tier); continue }
      validateEventMap(document.tiers[tier], "tiers." + tier, errors)
      for (var e = 0; e < knownEvents.length; e++) {
        var event = knownEvents[e]
        if (!document.tiers[tier][event]) errors.push("missing " + tier + "." + event)
        else validateArray(document.tiers[tier][event], "tiers." + tier + "." + event, errors)
      }
    }
  }
  if (document && document.species && typeof document.species === "object") {
    for (var species in document.species) {
      var speciesTiers = document.species[species]
      if (!speciesTiers || typeof speciesTiers !== "object") { errors.push("species." + species + " invalid"); continue }
      for (var speciesTier in speciesTiers) {
        if (knownTiers.indexOf(speciesTier) < 0) { errors.push("unknown tier " + speciesTier); continue }
        var speciesEvents = speciesTiers[speciesTier]
        validateEventMap(speciesEvents, "species." + species + "." + speciesTier, errors)
        if (!speciesEvents || typeof speciesEvents !== "object" || Array.isArray(speciesEvents)) continue
        for (var speciesEvent in speciesEvents) {
          if (knownEvents.indexOf(speciesEvent) < 0) errors.push("unknown event " + speciesEvent)
          else validateArray(speciesEvents[speciesEvent], "species." + species + "." + speciesTier + "." + speciesEvent, errors)
        }
      }
    }
  }
  return { valid: errors.length === 0, errors: errors }
}
