import QtQuick
import QtTest
import "../../PetRoute.js" as PetRoute

TestCase {
  name: "PetRoute"

  readonly property var rect: ({ width: 1000, height: 500 })

  function test_pixel_speed_is_size_independent() {
    var first = PetRoute.planStep({
      edge: "top", u: 0.05, direction: 1, roamingMode: "Top edge",
      terminalRect: { width: 1000, height: 500 }, stride: 10,
      renderScale: 1, durations: [110, 110, 110, 110],
      random: { step: 0.1, turn: 0.9 }
    })
    var second = PetRoute.planStep({
      edge: "top", u: 0.05, direction: 1, roamingMode: "Top edge",
      terminalRect: { width: 2000, height: 1000 }, stride: 10,
      renderScale: 1, durations: [110, 110, 110, 110],
      random: { step: 0.1, turn: 0.9 }
    })
    compare(first.distancePx, second.distancePx)
    compare(first.speedPxPerSecond, second.speedPxPerSecond)
    compare(first.durationMs, second.durationMs)
  }

  function test_step_stays_inside_top_edge() {
    var plan = PetRoute.planStep({
      edge: "top", u: 0.005, direction: -1, roamingMode: "Top edge",
      terminalRect: rect, stride: 10, renderScale: 1,
      durations: [110, 110, 110, 110],
      random: { step: 0.99, turn: 0.99 }
    })
    verify(plan.targetU >= 0)
    verify(plan.targetU <= PetRoute.edgeEndU("top", rect))
    compare(plan.targetEdge, "top")
  }

  function test_turnaround_is_inline_at_corner() {
    var edgeEnd = PetRoute.edgeEndU("top", rect)
    var plan = PetRoute.planStep({
      edge: "top", u: edgeEnd - 0.0001, direction: 1, roamingMode: "Top edge",
      terminalRect: rect, stride: 10, renderScale: 1,
      durations: [110, 110, 110, 110],
      random: { step: 0.1, turn: 0.99 }
    })
    verify(plan.atBoundary)
    verify(plan.turnaround)
    compare(plan.nextDirection, -1)
    compare(plan.actions[1], "turn")
  }

  function test_duration_matches_distance_and_speed() {
    var plan = PetRoute.planStep({
      edge: "top", u: 0.1, direction: 1, roamingMode: "Top edge",
      terminalRect: rect, stride: 12, renderScale: 2,
      durations: [80, 80, 80, 80],
      random: { step: 0.4, turn: 0.9 }
    })
    var expected = plan.distancePx / plan.speedPxPerSecond * 1000
    verify(Math.abs(plan.durationMs - expected) <= 1)
  }

  function test_whole_border_corner_keeps_direction() {
    var edgeEnd = PetRoute.edgeEndU("top", rect)
    var plan = PetRoute.planStep({
      edge: "top", u: edgeEnd - 0.0001, direction: 1, roamingMode: "Whole border",
      terminalRect: rect, stride: 10, renderScale: 1,
      durations: [110, 110, 110, 110],
      random: { step: 0.1, turn: 0.99 }
    })
    compare(plan.targetEdge, "right")
    compare(plan.nextDirection, 1)
    compare(plan.actions[1], "corner")
  }

  function test_left_edge_endpoint_does_not_wrap_to_top() {
    var plan = PetRoute.planStep({
      edge: "left", u: 1, direction: -1, roamingMode: "Whole border",
      terminalRect: rect, stride: 10, renderScale: 1,
      durations: [110, 110, 110, 110],
      random: { step: 0.1, turn: 0.99 }
    })
    compare(plan.fromU, 1)
    compare(plan.targetEdge, "left")
    verify(plan.distancePx > 0)
    verify(plan.targetU < 1 && plan.targetU > PetRoute.edgeStartU("left", rect))
  }

  function test_normalized_left_endpoint_is_also_the_edge_end() {
    var plan = PetRoute.planStep({
      edge: "left", u: 0, direction: -1, roamingMode: "Whole border",
      terminalRect: rect, stride: 10, renderScale: 1,
      durations: [110, 110, 110, 110],
      random: { step: 0.1, turn: 0.99 }
    })
    compare(plan.fromU, 1)
    verify(plan.distancePx > 0)
    compare(plan.targetEdge, "left")
  }

  function test_left_endpoint_target_keeps_u_one() {
    var plan = PetRoute.planStep({
      edge: "left", u: PetRoute.edgeStartU("left", rect) + 0.98
        * (PetRoute.edgeEndU("left", rect) - PetRoute.edgeStartU("left", rect)),
      direction: 1, roamingMode: "Whole border", terminalRect: rect,
      stride: 10, renderScale: 1, wallStep: true,
      durations: [110, 110, 110, 110], random: { step: 0.1, turn: 0.99 }
    })
    compare(plan.targetU, 1)
  }

  function test_remembered_left_route_chooses_adjacent_corner() {
    var plan = PetRoute.planStep({
      edge: "top", u: 0, direction: 1, towardU: 0.9,
      towardDirection: -1, towardEdge: "left", roamingMode: "Whole border",
      allowedEdges: ["top", "right", "bottom", "left"], terminalRect: rect,
      stride: 10, renderScale: 1, durations: [110, 110, 110, 110],
      random: { step: 0.1, turn: 0.99 }
    })
    compare(plan.targetEdge, "left")
    compare(plan.targetU, 0)
    verify(plan.turnaround)
  }

  function test_remembered_target_survives_left_corner_continuation() {
    var plan = PetRoute.planStep({
      edge: "left", u: 0, direction: -1, towardU: 0.9,
      towardDirection: -1, towardEdge: "left", roamingMode: "Whole border",
      allowedEdges: ["top", "right", "bottom", "left"], terminalRect: rect,
      stride: 10, renderScale: 1, durations: [110, 110, 110, 110],
      random: { step: 0.1, turn: 0.99 }
    })
    compare(plan.targetEdge, "left")
    compare(plan.targetU, 0.9)
    verify(!plan.turnaround)
  }

  function test_allowed_edges_turn_at_unavailable_corner() {
    var edgeEnd = PetRoute.edgeEndU("right", rect)
    var plan = PetRoute.planStep({
      edge: "right", u: edgeEnd - 0.0001, direction: 1,
      roamingMode: "Whole border", allowedEdges: ["top", "right"],
      terminalRect: rect, stride: 10, renderScale: 1,
      durations: [110, 110, 110, 110], random: { step: 0.1, turn: 0.99 }, wallStep: true
    })
    compare(plan.targetEdge, "right")
    verify(plan.turnaround)
    compare(plan.nextDirection, -1)
    compare(plan.allowedEdges.join(","), "top,right")
  }

  function test_wall_step_reaches_corner() {
    var start = PetRoute.edgeStartU("right", rect)
    var plan = PetRoute.planStep({
      edge: "right", u: start + 0.08, direction: 1,
      roamingMode: "Whole border", allowedEdges: ["top", "right", "bottom", "left"],
      terminalRect: rect, stride: 10, renderScale: 1,
      durations: [110, 110, 110, 110], random: { step: 0.1, turn: 0.99 }, wallStep: true
    })
    compare(plan.targetEdge, "bottom")
    verify(plan.atBoundary)
    verify(plan.actions.indexOf("corner") >= 0)
  }

  function test_toward_u_does_not_overshoot() {
    var plan = PetRoute.planStep({
      edge: "top", u: 0.08, direction: -1, towardU: 0.2,
      roamingMode: "Whole border", allowedEdges: ["top", "right", "bottom", "left"],
      terminalRect: rect, stride: 10, renderScale: 1,
      durations: [110, 110, 110, 110], random: { step: 0.99, turn: 0.99 }
    })
    compare(plan.targetU, 0.2)
    verify(plan.approaching)
    verify(!plan.turnaround)
  }

  function test_toward_u_can_cross_to_a_target_edge() {
    var rightStart = PetRoute.edgeStartU("right", rect)
    var plan = PetRoute.planStep({
      edge: "top", u: 0.05, direction: 1, towardU: rightStart,
      towardEdge: "right", roamingMode: "Whole border",
      allowedEdges: ["top", "right", "bottom", "left"], terminalRect: rect,
      stride: 10, renderScale: 1, durations: [110, 110, 110, 110],
      random: { step: 0.1, turn: 0.99 }
    })
    compare(plan.targetEdge, "right")
    verify(plan.turnaround)
    compare(plan.targetU, PetRoute.edgeEndU("top", rect))
  }

  function test_nearest_edge_point_respects_subset_and_corners() {
    var right = PetRoute.nearestEdgePoint(rect, ["top", "right"], 1030, 250)
    compare(right.edge, "right")
    compare(right.x, 1000)
    compare(right.y, 250)
    var topLeft = PetRoute.nearestEdgePoint(rect, ["top", "left"], -5, -5)
    compare(topLeft.edge, "top")
    compare(topLeft.u, 0)
    var bottom = PetRoute.nearestEdgePoint(rect, ["bottom"], 450, 600)
    compare(bottom.edge, "bottom")
    compare(bottom.u, PetRoute.edgeStartU("bottom", rect) + 450 / rect.width
      * (PetRoute.edgeEndU("bottom", rect) - PetRoute.edgeStartU("bottom", rect)))
  }
}
