import QtQuick

// The motion model is the single source of truth for edge/u geometry. The
// controller may move travelU in either direction; projection never guesses
// facing from the animation that happens to be playing.
Item {
  id: root

  property var service: null
  property var hostScreen: null
  property real travelU: 0
  property int direction: 1
  property real reactionX: 0
  property real reactionY: 0
  property real frameWidth: 32
  property real frameHeight: 32
  property real renderScale: 1
  property real anchorX: 16
  property real anchorY: 30
  property rect previousTerminalRect: Qt.rect(0, 0, 0, 0)
  property bool geometrySnapshotReady: false

  signal geometryRemapped(string edge, real fraction)

  readonly property rect terminalRect: service ? service.terminalRect : Qt.rect(0, 0, 0, 0)
  readonly property bool geometryValid: !!hostScreen && terminalRect.width > 0 && terminalRect.height > 0
  readonly property real localTerminalX: hostScreen ? terminalRect.x - hostScreen.x : 0
  readonly property real localTerminalY: hostScreen ? terminalRect.y - hostScreen.y : 0
  readonly property real trackWidth: Math.max(1, terminalRect.width)
  readonly property real trackHeight: Math.max(1, terminalRect.height)
  readonly property real perimeter: Math.max(1, 2 * (trackWidth + trackHeight))
  readonly property real screenWidth: hostScreen ? Number(hostScreen.width) : width
  readonly property real screenHeight: hostScreen ? Number(hostScreen.height) : height
  readonly property real wallAnchorInset: 2 * Math.max(1, root.renderScale)
  readonly property real ledgeAnchorInset: 2 * Math.max(1, root.renderScale)
  // Room is measured for the bundled wall/ledge posture rather than for the
  // floor sprite. A side is unavailable when the complete outward-facing
  // frame cannot fit between the output edge and the terminal.
  readonly property real roomLeft: root.localTerminalX - (root.frameWidth - root.wallAnchorInset)
  readonly property real roomRight: root.screenWidth - (root.localTerminalX + root.trackWidth)
    - (root.frameWidth - root.wallAnchorInset)
  readonly property real roomBottom: root.screenHeight - (root.localTerminalY + root.trackHeight)
    - (root.frameHeight - root.ledgeAnchorInset)
  readonly property real roomTop: root.localTerminalY
  readonly property real topEdgeStartU: 0
  readonly property real topEdgeEndU: root.trackWidth / root.perimeter
  readonly property real normalizedU: root.wrap(root.travelU)
  readonly property var projection: root.project(root.normalizedU)
  readonly property string edge: root.projection.edge
  readonly property string facing: root.projection.facing
  readonly property string wallSide: root.projection.wallSide
  readonly property real contactX: root.projection.x
  readonly property real contactY: root.projection.y
  readonly property real unroundedSpriteX: root.contactX + root.reactionX - root.anchorX
  readonly property real unroundedSpriteY: root.contactY + root.reactionY - root.anchorY
  readonly property real spriteX: root.clamp(Math.round(root.unroundedSpriteX), 0,
    Math.max(0, root.screenWidth - root.frameWidth))
  readonly property real spriteY: root.clamp(Math.round(root.unroundedSpriteY), 0,
    Math.max(0, root.screenHeight - root.frameHeight))

  function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value))
  }

  function wrap(value) {
    var result = Number(value) % 1
    return result < 0 ? result + 1 : result
  }

  function edgeStartU(edge, width, height) {
    var total = Math.max(1, 2 * (width + height))
    if (edge === "top") return 0
    if (edge === "right") return width / total
    if (edge === "bottom") return (width + height) / total
    return (2 * width + height) / total
  }

  function edgeEndU(edge, width, height) {
    var total = Math.max(1, 2 * (width + height))
    if (edge === "top") return width / total
    if (edge === "right") return (width + height) / total
    if (edge === "bottom") return (2 * width + height) / total
    return 1
  }

  function project(value) {
    var distance = root.wrap(value) * root.perimeter
    var x = root.localTerminalX
    var y = root.localTerminalY
    var edgeName = "top"
    var facingName = root.direction >= 0 ? "right" : "left"
    var side = ""

    if (distance <= root.trackWidth) {
      x += distance
      edgeName = "top"
      facingName = root.direction >= 0 ? "right" : "left"
    } else if (distance <= root.trackWidth + root.trackHeight) {
      x += root.trackWidth
      y += distance - root.trackWidth
      edgeName = "right"
      facingName = root.direction >= 0 ? "down" : "up"
      side = "right"
    } else if (distance <= 2 * root.trackWidth + root.trackHeight) {
      x += root.trackWidth - (distance - root.trackWidth - root.trackHeight)
      y += root.trackHeight
      edgeName = "bottom"
      facingName = root.direction >= 0 ? "left" : "right"
    } else {
      x += 0
      y += root.trackHeight - (distance - 2 * root.trackWidth - root.trackHeight)
      edgeName = "left"
      facingName = root.direction >= 0 ? "up" : "down"
      side = "left"
    }

    return { x: x, y: y, edge: edgeName, facing: facingName, wallSide: side }
  }

  function fractionForProjection(value, edge, width, height) {
    var total = Math.max(1, 2 * (width + height))
    var start = root.edgeStartU(edge, width, height)
    var end = root.edgeEndU(edge, width, height)
    if (end <= start) return 0
    return root.clamp((root.wrap(value) - start) / (end - start), 0, 1)
  }

  function remapForGeometryChange() {
    var old = root.previousTerminalRect
    if (!root.geometrySnapshotReady || old.width <= 0 || old.height <= 0
        || root.terminalRect.width <= 0 || root.terminalRect.height <= 0) return
    var oldProjection = root.projectForRect(root.travelU, old)
    var edgeName = oldProjection.edge
    var fraction = root.fractionForProjection(root.travelU, edgeName, old.width, old.height)
    var start = root.edgeStartU(edgeName, root.terminalRect.width, root.terminalRect.height)
    var end = root.edgeEndU(edgeName, root.terminalRect.width, root.terminalRect.height)
    root.travelU = root.wrap(start + (end - start) * fraction)
    root.geometryRemapped(edgeName, fraction)
  }

  function projectForRect(value, rect) {
    var width = Math.max(1, Number(rect.width))
    var height = Math.max(1, Number(rect.height))
    var total = Math.max(1, 2 * (width + height))
    var distance = root.wrap(value) * total
    var edgeName = "top"
    if (distance <= width) edgeName = "top"
    else if (distance <= width + height) edgeName = "right"
    else if (distance <= 2 * width + height) edgeName = "bottom"
    else edgeName = "left"
    return { edge: edgeName }
  }

  function setNormalizedProgress(value) {
    root.travelU = root.wrap(value)
  }

  onTerminalRectChanged: {
    if (root.geometrySnapshotReady) root.remapForGeometryChange()
    root.previousTerminalRect = root.terminalRect
    root.geometrySnapshotReady = root.terminalRect.width > 0 && root.terminalRect.height > 0
  }

  Component.onCompleted: {
    root.previousTerminalRect = root.terminalRect
    root.geometrySnapshotReady = root.terminalRect.width > 0 && root.terminalRect.height > 0
  }
}
