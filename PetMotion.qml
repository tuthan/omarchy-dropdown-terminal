import QtQuick

// One source of truth for the pet's base position. The controller animates
// travelU and reaction offsets; this component alone turns those values into
// a clamped, pixel-aligned sprite origin.
Item {
  id: root

  property var service: null
  property var hostScreen: null
  property real travelU: 0
  property real reactionX: 0
  property real reactionY: 0
  property real frameWidth: 32
  property real frameHeight: 32
  property real anchorX: 16
  property real anchorY: 30

  readonly property rect terminalRect: service ? service.terminalRect : Qt.rect(0, 0, 0, 0)
  readonly property bool geometryValid: !!hostScreen && terminalRect.width > 0 && terminalRect.height > 0
  readonly property real localTerminalX: hostScreen ? terminalRect.x - hostScreen.x : 0
  readonly property real localTerminalY: hostScreen ? terminalRect.y - hostScreen.y : 0
  readonly property real trackWidth: Math.max(1, terminalRect.width)
  readonly property real trackHeight: Math.max(1, terminalRect.height)
  readonly property real perimeter: Math.max(1, 2 * (trackWidth + trackHeight))
  readonly property real normalizedU: root.wrap(root.travelU)
  readonly property var projection: root.project(root.normalizedU)
  readonly property string edge: root.projection.edge
  readonly property string facing: root.projection.facing
  readonly property real contactX: root.projection.x
  readonly property real contactY: root.projection.y
  readonly property real unroundedSpriteX: root.contactX + root.reactionX - root.anchorX
  readonly property real unroundedSpriteY: root.contactY + root.reactionY - root.anchorY
  readonly property real spriteX: root.clamp(Math.round(root.unroundedSpriteX), 0,
    Math.max(0, (hostScreen ? hostScreen.width : width) - root.frameWidth))
  readonly property real spriteY: root.clamp(Math.round(root.unroundedSpriteY), 0,
    Math.max(0, (hostScreen ? hostScreen.height : height) - root.frameHeight))

  function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value))
  }

  function wrap(value) {
    var result = Number(value) % 1
    return result < 0 ? result + 1 : result
  }

  function project(value) {
    var distance = root.wrap(value) * root.perimeter
    var x = root.localTerminalX
    var y = root.localTerminalY
    var edgeName = "top"
    var direction = "right"

    if (distance <= root.trackWidth) {
      x += distance
      y += 0
      edgeName = "top"
      direction = "right"
    } else if (distance <= root.trackWidth + root.trackHeight) {
      x += root.trackWidth
      y += distance - root.trackWidth
      edgeName = "right"
      direction = "down"
    } else if (distance <= 2 * root.trackWidth + root.trackHeight) {
      x += root.trackWidth - (distance - root.trackWidth - root.trackHeight)
      y += root.trackHeight
      edgeName = "bottom"
      direction = "left"
    } else {
      x += 0
      y += root.trackHeight - (distance - 2 * root.trackWidth - root.trackHeight)
      edgeName = "left"
      direction = "up"
    }

    return { x: x, y: y, edge: edgeName, facing: direction }
  }

  // The normalized progress survives a resize. Only the projection changes;
  // no action or progress is restarted just because the terminal moved.
  function setNormalizedProgress(value) {
    root.travelU = root.wrap(value)
  }
}
