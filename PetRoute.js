.pragma library

// Pure pixel-space route planning. The controller owns timers, generation
// tokens, and reactions; this file only turns geometry and pack metadata into
// one bounded route step.

function finite(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

function clamp(value, low, high) {
  return Math.max(low, Math.min(high, value))
}

function perimeter(rect) {
  return Math.max(1, 2 * (Math.max(1, finite(rect && rect.width, 1))
    + Math.max(1, finite(rect && rect.height, 1))))
}

function edgeLength(edge, rect) {
  return edge === "top" || edge === "bottom"
    ? Math.max(1, finite(rect && rect.width, 1))
    : Math.max(1, finite(rect && rect.height, 1))
}

function edgeStartU(edge, rect) {
  var width = Math.max(1, finite(rect && rect.width, 1))
  var height = Math.max(1, finite(rect && rect.height, 1))
  var total = perimeter(rect)
  if (edge === "top") return 0
  if (edge === "right") return width / total
  if (edge === "bottom") return (width + height) / total
  return (2 * width + height) / total
}

function edgeEndU(edge, rect) {
  var width = Math.max(1, finite(rect && rect.width, 1))
  var height = Math.max(1, finite(rect && rect.height, 1))
  var total = perimeter(rect)
  if (edge === "top") return width / total
  if (edge === "right") return (width + height) / total
  if (edge === "bottom") return (2 * width + height) / total
  return 1
}

function wrap(value) {
  var result = finite(value, 0) % 1
  return result < 0 ? result + 1 : result
}

function nextEdge(edge, direction) {
  if (direction >= 0) {
    if (edge === "top") return "right"
    if (edge === "right") return "bottom"
    if (edge === "bottom") return "left"
    return "top"
  }
  if (edge === "top") return "left"
  if (edge === "left") return "bottom"
  if (edge === "bottom") return "right"
  return "top"
}

function randomValue(random, key, fallback) {
  if (Array.isArray(random)) {
    var index = key === "step" ? 0 : 1
    if (index < random.length && isFinite(Number(random[index])))
      return clamp(Number(random[index]), 0, 0.999999)
  }
  if (random && isFinite(Number(random[key])))
    return clamp(Number(random[key]), 0, 0.999999)
  return clamp(finite(fallback, Math.random()), 0, 0.999999)
}

function durationTotal(durations, fallback) {
  if (!Array.isArray(durations) || durations.length === 0) return fallback
  var total = 0
  for (var i = 0; i < durations.length; i++) total += Math.max(1, finite(durations[i], 1))
  return total > 0 ? total : fallback
}

function edgeNames(value, mode) {
  var names = ["top", "right", "bottom", "left"]
  if (Array.isArray(value)) {
    var selected = []
    for (var i = 0; i < names.length; i++)
      if (value.indexOf(names[i]) >= 0) selected.push(names[i])
    if (selected.length > 0) return selected
  }
  return String(mode || "Top edge") === "Whole border" ? names : ["top"]
}

function pointForU(value, rect) {
  var width = Math.max(1, finite(rect && rect.width, 1))
  var height = Math.max(1, finite(rect && rect.height, 1))
  var total = perimeter(rect)
  var distance = wrap(value) * total
  if (distance <= width) return { x: distance, y: 0 }
  if (distance <= width + height) return { x: width, y: distance - width }
  if (distance <= 2 * width + height)
    return { x: width - (distance - width - height), y: height }
  return { x: 0, y: height - (distance - 2 * width - height) }
}

function nearestEdgePoint(rect, allowedEdges, x, y) {
  rect = rect || { width: 1, height: 1 }
  var width = Math.max(1, finite(rect.width, 1))
  var height = Math.max(1, finite(rect.height, 1))
  var edges = edgeNames(allowedEdges, "Whole border")
  var px = finite(x, 0)
  var py = finite(y, 0)
  var best = null
  for (var i = 0; i < edges.length; i++) {
    var edge = edges[i]
    var ex = 0
    var ey = 0
    var distance = 0
    var start = edgeStartU(edge, { width: width, height: height })
    var end = edgeEndU(edge, { width: width, height: height })
    if (edge === "top") {
      ex = clamp(px, 0, width)
      ey = 0
    } else if (edge === "right") {
      ex = width
      ey = clamp(py, 0, height)
    } else if (edge === "bottom") {
      ex = clamp(px, 0, width)
      ey = height
    } else {
      ex = 0
      ey = clamp(py, 0, height)
    }
    distance = Math.sqrt(Math.pow(px - ex, 2) + Math.pow(py - ey, 2))
    var candidate = {
      edge: edge,
      u: start + (end - start) * (edge === "top" || edge === "bottom"
        ? ex / width : ey / height),
      x: ex,
      y: ey,
      distancePx: distance
    }
    if (!best || candidate.distancePx < best.distancePx - 0.000001)
      best = candidate
  }
  return best || { edge: "top", u: 0, x: 0, y: 0, distancePx: Infinity }
}

function planStep(input) {
  input = input || {}
  var rect = input.terminalRect || input.rect || { width: 1, height: 1 }
  var edge = ["top", "right", "bottom", "left"].indexOf(String(input.edge)) >= 0
    ? String(input.edge) : "top"
  var direction = Number(input.direction) < 0 ? -1 : 1
  var mode = String(input.roamingMode || input.mode || "Top edge")
  var allowedEdges = edgeNames(input.allowedEdges, mode)
  if (allowedEdges.indexOf(edge) < 0) edge = allowedEdges[0]
  var total = perimeter(rect)
  var startU = edgeStartU(edge, rect)
  var endU = edgeEndU(edge, rect)
  var rawU = finite(input.u, startU)
  // Keep both representations of the left edge's top endpoint unwrapped.
  // Motion projection commonly normalizes that point to u=0, while saved
  // positions and edge arithmetic may use u=1. Treating both as the edge end
  // prevents a zero-duration step or an accidental wrap to the top edge.
  var wrappedU = wrap(rawU)
  var currentU = edge === "left"
    && (Math.abs(rawU - 1) <= 0.000001 || Math.abs(wrappedU) <= 0.000001)
    ? 1 : wrappedU
  var edgeStartDistance = startU * total
  var edgeEndDistance = endU * total
  var currentDistance = clamp(currentU * total, edgeStartDistance, edgeEndDistance)
  var distanceToBoundary = direction > 0
    ? edgeEndDistance - currentDistance : currentDistance - edgeStartDistance
  var stride = clamp(finite(input.stride, 10), 4, 32)
  var renderScale = Math.max(1, finite(input.renderScale, 1))
  var cycleMs = durationTotal(input.durations || input.walkDurations, 440)
  var speed = stride * renderScale / cycleMs * 1000
  var approach = input.towardU !== undefined && isFinite(Number(input.towardU))
  var stepScale = clamp(finite(input.stepScale, 1), 0.5, 4)
  var requestedDistance = 0
  var travelDirection = direction
  if (approach) {
    var towardDistance = clamp(Number(input.towardU), 0, 0.999999) * total
    // A remembered position is a directed perimeter destination. Unwrap the
    // destination relative to the current point so the first leg can choose
    // the adjacent corner, then retain that direction on subsequent edges.
    if (input.towardDirection !== undefined && isFinite(Number(input.towardDirection))) {
      var preferredDirection = Number(input.towardDirection) < 0 ? -1 : 1
      if (preferredDirection < 0 && towardDistance > currentDistance)
        towardDistance -= total
      else if (preferredDirection > 0 && towardDistance < currentDistance)
        towardDistance += total
    }
    travelDirection = towardDistance >= currentDistance ? 1 : -1
    requestedDistance = Math.abs(towardDistance - currentDistance)
    var maxApproach = Math.max(stride, finite(input.maxDistance, requestedDistance))
    requestedDistance = Math.min(requestedDistance, maxApproach)
    distanceToBoundary = travelDirection > 0
      ? edgeEndDistance - currentDistance : currentDistance - edgeStartDistance
  } else {
    var stepCount = 3 + Math.floor(randomValue(input.random, "step", 0.5) * 10)
    requestedDistance = stepCount * stride * stepScale
    // A wall/ledge step is deliberately one authored step to the corner. This
    // keeps a side from pausing on a floor frame before changing posture.
    if ((edge === "right" || edge === "left") && allowedEdges.length > 1 && input.wallStep === true)
      requestedDistance = Math.max(requestedDistance, distanceToBoundary)
  }
  var travelDistance = Math.max(0, Math.min(requestedDistance, distanceToBoundary))
  var atBoundary = distanceToBoundary <= stride || travelDistance >= distanceToBoundary - 0.0001
  if (distanceToBoundary <= stride) travelDistance = Math.max(0, distanceToBoundary)

  var targetDistance = currentDistance + travelDirection * travelDistance
  var targetU = edge === "left" && targetDistance >= edgeEndDistance - 0.0001
    ? 1 : wrap(targetDistance / total)
  var approachNeedsCorner = approach && atBoundary
    && (requestedDistance > distanceToBoundary + 0.0001
      || (String(input.towardEdge || "") !== "" && String(input.towardEdge) !== edge))
  var turn = (!approach && (atBoundary || randomValue(input.random, "turn", 1) < 0.25))
    || approachNeedsCorner
  var actions = ["walk"]
  var targetEdge = edge
  var nextDirection = travelDirection
  if (turn) {
    var candidateEdge = nextEdge(edge, travelDirection)
    if (atBoundary && mode === "Whole border" && allowedEdges.indexOf(candidateEdge) >= 0) {
      actions.push("corner")
      targetEdge = candidateEdge
    } else {
      nextDirection = -travelDirection
      actions.push("turn")
    }
  }

  return {
    edge: edge,
    targetEdge: targetEdge,
    fromU: currentU,
    targetU: targetU,
    direction: travelDirection,
    nextDirection: nextDirection,
    distancePx: travelDistance,
    distanceToBoundaryPx: distanceToBoundary,
    stride: stride,
    stepScale: stepScale,
    cycleMs: cycleMs,
    speedPxPerSecond: speed,
    durationMs: Math.max(0, Math.round(travelDistance / speed * 1000)),
    atBoundary: atBoundary,
    turnaround: turn,
    actions: actions,
    allowedEdges: allowedEdges,
    approaching: approach
  }
}
