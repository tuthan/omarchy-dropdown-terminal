import QtQuick
import Quickshell.Io

// Data-driven atlas renderer. It deliberately uses one Timer because each
// action can have authored, non-uniform frame durations without a per-frame
// JavaScript loop or a second animation layer writing position.
Item {
  id: root

  property string actionName: "idle"
  property string species: "Penguin"
  property bool playbackRequested: false
  property bool reducedMotion: false
  property int frameCursor: 0
  property bool sequenceComplete: false
  property var pack: ({})
  property bool manifestReady: false
  property bool assetReady: false
  property string assetDiagnostic: ""
  property bool mirrorFrame: false

  signal sequenceFinished()

  readonly property string speciesKey: root.species === "Cat" ? "cat"
    : (root.species === "Corgi" ? "corgi" : "penguin")
  readonly property string assetRoot: "assets/pets/" + root.speciesKey + "/"
  readonly property string manifestPath: Qt.resolvedUrl(root.assetRoot + "pet.json").toString().replace(/^file:\/\//, "")
  readonly property var actions: root.pack && root.pack.actions ? root.pack.actions : ({})
  readonly property var fallbacks: root.pack && root.pack.fallbacks ? root.pack.fallbacks : ({})
  readonly property var activeSequence: root.sequenceFor(root.actionName)
  readonly property int frameWidth: root.pack && root.pack.atlas ? Number(root.pack.atlas.frameWidth) : 32
  readonly property int frameHeight: root.pack && root.pack.atlas ? Number(root.pack.atlas.frameHeight) : 32
  readonly property int columns: root.pack && root.pack.atlas ? Number(root.pack.atlas.columns) : 8
  readonly property int rows: root.pack && root.pack.atlas ? Number(root.pack.atlas.rows) : 8
  readonly property int renderScale: root.pack && root.pack.atlas ? Number(root.pack.atlas.renderScale) : 1
  readonly property int walkStride: root.actions.walk && root.actions.walk.stride
    ? Number(root.actions.walk.stride) : 10
  readonly property int climbStride: root.actions.climb && root.actions.climb.stride
    ? Number(root.actions.climb.stride) : root.walkStride
  readonly property bool wallSafeClimb: !!(root.actions.climb && root.actions.climb.mirrorSafe
    && root.actions.climb.anchors && root.actions.climb.anchors.length > 0)
  readonly property bool wallSafeClimbDown: !!(root.actions.climbDown && root.actions.climbDown.mirrorSafe
    && root.actions.climbDown.anchors && root.actions.climbDown.anchors.length > 0)
  readonly property bool bottomHangAvailable: !!(root.actions.hang && root.actions.hang.mirrorSafe)
  readonly property bool petReactionAvailable: !!root.actions.happy
    || (!!root.fallbacks.happy && root.fallbacks.happy !== "idle"
      && !!root.actions[root.fallbacks.happy])
  readonly property int atlasWidth: root.frameWidth * root.columns
  readonly property int atlasHeight: root.frameHeight * root.rows
  readonly property int frameIndex: root.activeSequence && root.activeSequence.frames
    && root.activeSequence.frames.length > 0
    ? Number(root.activeSequence.frames[Math.min(root.frameCursor, root.activeSequence.frames.length - 1)]) : 0
  readonly property int frameDuration: root.activeSequence && root.activeSequence.durations
    && root.activeSequence.durations.length > 0
    ? Number(root.activeSequence.durations[Math.min(root.frameCursor, root.activeSequence.durations.length - 1)]) : 100
  readonly property real anchorX: root.activeSequence && root.activeSequence.anchors
    && root.activeSequence.anchors.length > 0
    ? Number((root.activeSequence.anchors[Math.min(root.frameCursor, root.activeSequence.anchors.length - 1)] || {}).x) : 16
  readonly property real anchorY: root.activeSequence && root.activeSequence.anchors
    && root.activeSequence.anchors.length > 0
    ? Number((root.activeSequence.anchors[Math.min(root.frameCursor, root.activeSequence.anchors.length - 1)] || {}).y) : 30
  readonly property real projectedAnchorX: root.mirrorFrame && !!(root.activeSequence && root.activeSequence.mirrorSafe)
    ? root.frameWidth - root.anchorX : root.anchorX
  readonly property bool loop: !!(root.activeSequence && root.activeSequence.loop)
  readonly property bool playbackActive: root.playbackRequested && !root.reducedMotion
    && !root.sequenceComplete && root.assetReady
  readonly property string atlasPath: root.manifestReady && root.pack.atlas
    ? Qt.resolvedUrl(root.assetRoot + root.pack.atlas.path).toString() : ""
  readonly property rect frameRect: Qt.rect((root.frameIndex % root.columns) * root.frameWidth,
    Math.floor(root.frameIndex / root.columns) * root.frameHeight, root.frameWidth, root.frameHeight)

  function boundedInteger(value, low, high) {
    return Number.isInteger(Number(value)) && Number(value) >= low && Number(value) <= high
  }

  function safeRelativePath(value) {
    var path = String(value || "")
    return path.length > 0 && path.length <= 128 && path.charAt(0) !== "/"
      && path.indexOf("..") < 0 && !/[\\\x00-\x1f]/.test(path)
  }

  function validAnchor(anchor) {
    return !!anchor && isFinite(Number(anchor.x)) && isFinite(Number(anchor.y))
      && Number(anchor.x) >= 0 && Number(anchor.x) <= root.frameWidth
      && Number(anchor.y) >= 0 && Number(anchor.y) <= root.frameHeight
  }

  function validSequence(sequence, cellCount, minimumFrames, maximumFrames, durationLow, durationHigh) {
    minimumFrames = minimumFrames === undefined ? 1 : minimumFrames
    maximumFrames = maximumFrames === undefined ? 16 : maximumFrames
    durationLow = durationLow === undefined ? 16 : durationLow
    durationHigh = durationHigh === undefined ? 4000 : durationHigh
    if (!sequence || !Array.isArray(sequence.frames) || !Array.isArray(sequence.durations)
        || !Array.isArray(sequence.anchors) || sequence.frames.length === 0
        || sequence.frames.length < minimumFrames || sequence.frames.length > maximumFrames
        || sequence.frames.length !== sequence.durations.length
        || sequence.frames.length !== sequence.anchors.length || typeof sequence.loop !== "boolean"
        || typeof sequence.mirrorSafe !== "boolean")
      return false
    for (var i = 0; i < sequence.frames.length; i++) {
      if (!boundedInteger(sequence.frames[i], 0, cellCount - 1)
          || !boundedInteger(sequence.durations[i], durationLow, durationHigh)
          || !validAnchor(sequence.anchors[i])) return false
    }
    var totalDuration = sequence.durations.reduce(function(total, duration) { return total + Number(duration) }, 0)
    if (!sequence.loop && totalDuration > 12000) return false
    return true
  }

  function validPack(candidate) {
    if (!candidate || [1, 2, 3].indexOf(Number(candidate.version)) < 0
        || !candidate.atlas || !candidate.actions)
      return false
    var version = Number(candidate.version)
    var atlas = candidate.atlas
    if (!safeRelativePath(atlas.path) || !boundedInteger(atlas.frameWidth, 32, 32)
        || !boundedInteger(atlas.frameHeight, 32, 32) || !boundedInteger(atlas.columns, 1, 8)
        || !boundedInteger(atlas.rows, 1, 8) || !boundedInteger(atlas.renderScale, 1, 4)) return false
    if (atlas.columns * atlas.rows > 64) return false
    var required = ["peek", "enter", "land", "idle", "walk", "corner", "climb",
      "dance", "success", "failure", "exit", "sleep"]
    var cellCount = atlas.columns * atlas.rows
    for (var i = 0; i < required.length; i++) {
      var sequence = candidate.actions[required[i]]
      var low = (version === 2 && (required[i] === "walk" || required[i] === "climb")) ? 41 : 16
      var high = (version === 2 && (required[i] === "walk" || required[i] === "climb")) ? 250 : 4000
      if (!validSequence(sequence, cellCount, 1, 16, low, high)) return false
    }
    if (version === 3) {
      if (candidate.kind !== undefined && candidate.kind !== "pet") return false
      var requiredWorld = ["climbDown", "hang"]
      for (var w = 0; w < requiredWorld.length; w++) {
        var worldSequence = candidate.actions[requiredWorld[w]]
        if (!validSequence(worldSequence, cellCount, 1, 16, 16, 4000)) return false
      }
      var v3Fallbacks = {
        climbDown: "climb", hang: "idle", notice: "idle", alert: "idle",
        brave: "dance", cower: "failure", victory: "success", carried: "idle",
        cornerBottom: "hang", wallIdle: "climb", wallHappy: "climb",
        ledgeIdle: "hang", ledgeHappy: "hang"
      }
      for (var fallbackName in v3Fallbacks)
        if (candidate.actions[fallbackName]
            && (!candidate.fallbacks || candidate.fallbacks[fallbackName] !== v3Fallbacks[fallbackName])) return false
      if (!candidate.actions.climb.mirrorSafe || !candidate.actions.climbDown.mirrorSafe
          || !candidate.actions.hang.mirrorSafe) return false
      var wallActions = ["climb", "climbDown", "wallIdle", "wallHappy"]
      for (var wi = 0; wi < wallActions.length; wi++) {
        var wall = candidate.actions[wallActions[wi]]
        if (!wall) continue
        if (!wall.mirrorSafe || !validSequence(wall, cellCount, 1, 16, 16, 4000)) return false
        for (var wa = 0; wa < wall.anchors.length; wa++)
          if (Number(wall.anchors[wa].x) < 0 || Number(wall.anchors[wa].x) > 6
              || Number(wall.anchors[wa].y) < 12 || Number(wall.anchors[wa].y) > 20) return false
      }
      var ledgeActions = ["hang", "ledgeIdle", "ledgeHappy"]
      for (var li = 0; li < ledgeActions.length; li++) {
        var ledge = candidate.actions[ledgeActions[li]]
        if (!ledge) continue
        if (!ledge.mirrorSafe || !validSequence(ledge, cellCount, 1, 16, 16, 4000)) return false
        for (var la = 0; la < ledge.anchors.length; la++)
          if (Number(ledge.anchors[la].x) !== 16 || Number(ledge.anchors[la].y) < 0
              || Number(ledge.anchors[la].y) > 4) return false
      }
      var floorActions = ["peek", "enter", "land", "idle", "walk", "corner", "turn",
        "happy", "sleep", "dance", "success", "failure", "exit", "notice", "alert",
        "brave", "cower", "victory", "carried"]
      for (var fi = 0; fi < floorActions.length; fi++) {
        var floor = candidate.actions[floorActions[fi]]
        if (!floor) continue
        for (var fa = 0; fa < floor.anchors.length; fa++)
          if (Number(floor.anchors[fa].x) !== 16 || Number(floor.anchors[fa].y) < 24
              || Number(floor.anchors[fa].y) > 32) return false
      }
      var optionalNames = ["notice", "alert", "brave", "cower", "victory", "carried",
        "cornerBottom", "wallIdle", "wallHappy", "ledgeIdle", "ledgeHappy"]
      for (var oi = 0; oi < optionalNames.length; oi++) {
        var optional = candidate.actions[optionalNames[oi]]
        if (optional && !validSequence(optional, cellCount, 1, 16, 16, 4000)) return false
      }
      if (candidate.actions.walk.stride < 4 || candidate.actions.walk.stride > 32
          || candidate.actions.climb.stride < 4 || candidate.actions.climb.stride > 32
          || candidate.actions.climbDown.stride < 4 || candidate.actions.climbDown.stride > 32
          || candidate.actions.hang.stride < 4 || candidate.actions.hang.stride > 32) return false
      var speedActions = ["walk", "climb", "climbDown", "hang"]
      for (var si = 0; si < speedActions.length; si++) {
        var speedAction = candidate.actions[speedActions[si]]
        var cycle = speedAction.durations.reduce(function(total, value) { return total + Number(value) }, 0)
        var speed = Number(speedAction.stride) * Number(atlas.renderScale) / cycle * 1000
        if (!isFinite(speed) || speed < 12 || speed > 80) return false
      }
    }
    if (version === 2) {
      if (!boundedInteger(candidate.actions.walk.stride, 4, 32)
          || !boundedInteger(candidate.actions.climb.stride, 4, 32)) return false
      var walkSpeed = Number(candidate.actions.walk.stride) * Number(atlas.renderScale) /
        candidate.actions.walk.durations.reduce(function(total, value) { return total + Number(value) }, 0) * 1000
      var climbSpeed = Number(candidate.actions.climb.stride) * Number(atlas.renderScale) /
        candidate.actions.climb.durations.reduce(function(total, value) { return total + Number(value) }, 0) * 1000
      if (!isFinite(walkSpeed) || walkSpeed < 12 || walkSpeed > 80
          || !isFinite(climbSpeed) || climbSpeed < 12 || climbSpeed > 80) return false
      if (candidate.actions.happy
          && !validSequence(candidate.actions.happy, cellCount, 2, 6, 16, 4000)) return false
      if (candidate.actions.turn
          && !validSequence(candidate.actions.turn, cellCount, 2, 4, 16, 4000)) return false
      if (candidate.actions.climbDown
          && !validSequence(candidate.actions.climbDown, cellCount, 1, 16, 41, 250)) return false
      if (candidate.actions.happy && candidate.actions.happy.loop !== true) return false
      if (candidate.actions.turn && candidate.actions.turn.loop !== false) return false
      var standing = ["idle", "walk", "turn", "happy", "sleep", "dance", "success", "failure", "land"]
      for (var s = 0; s < standing.length; s++) {
        var standingSequence = candidate.actions[standing[s]]
        if (standingSequence) {
          for (var a = 0; a < standingSequence.anchors.length; a++)
            if (Number(standingSequence.anchors[a].x) !== 16) return false
        }
      }
      var transitions = [
        ["land", "idle"], ["idle", "walk"], ["walk", "idle"],
        ["walk", "turn"], ["turn", "idle"], ["idle", "happy"],
        ["happy", "idle"], ["walk", "happy"], ["idle", "sleep"],
        ["sleep", "idle"], ["idle", "dance"], ["idle", "success"],
        ["idle", "failure"], ["walk", "corner"], ["corner", "climb"],
        ["climb", "corner"], ["corner", "walk"]
      ]
      for (var t = 0; t < transitions.length; t++) {
        var from = candidate.actions[transitions[t][0]]
        var to = candidate.actions[transitions[t][1]]
        if (!from || !to) continue
        var fromAnchor = from.anchors[from.anchors.length - 1]
        var toAnchor = to.anchors[0]
        for (var mirrored = 0; mirrored < 2; mirrored++) {
          var fromX = mirrored && from.mirrorSafe ? Number(atlas.frameWidth) - Number(fromAnchor.x) : Number(fromAnchor.x)
          var toX = mirrored && to.mirrorSafe ? Number(atlas.frameWidth) - Number(toAnchor.x) : Number(toAnchor.x)
          if (Math.abs(fromX - toX) * Number(atlas.renderScale) > 1
              || Math.abs(Number(fromAnchor.y) - Number(toAnchor.y)) * Number(atlas.renderScale) > 1)
            return false
        }
      }
    }
    if (!candidate.fallbacks || typeof candidate.fallbacks !== "object") return false
    for (var name in candidate.fallbacks) {
      var fallback = String(candidate.fallbacks[name])
      if (!candidate.actions[fallback] || fallback === name) return false
    }
    if (version === 2) {
      if (!candidate.actions.happy && ["dance", "success"].indexOf(String(candidate.fallbacks.happy || "")) < 0)
        return false
      if (!candidate.actions.turn && String(candidate.fallbacks.turn || "") !== "idle") return false
    }
    return safeRelativePath(candidate.bar && candidate.bar.path)
  }

  function sequenceFor(name) {
    if (root.actions[name]) return root.actions[name]
    var fallback = root.fallbacks[name]
    return fallback && root.actions[fallback] ? root.actions[fallback] : root.actions.idle
  }

  function loadManifest(raw) {
    root.manifestReady = false
    root.assetReady = false
    try {
      var candidate = JSON.parse(String(raw || ""))
      if (!root.validPack(candidate)) {
        root.pack = ({})
        root.assetReady = false
        root.assetDiagnostic = root.species + " pack unavailable: invalid manifest"
        return
      }
      root.pack = candidate
      root.assetDiagnostic = ""
      root.frameCursor = 0
      root.sequenceComplete = false
      root.manifestReady = true
      Qt.callLater(root.observeAtlasStatus)
    } catch (e) {
      root.pack = ({})
      root.assetReady = false
      root.assetDiagnostic = root.species + " pack unavailable: unreadable manifest"
    }
  }

  function observeAtlasStatus() {
    if (!root.manifestReady) return
    if (atlas.status === Image.Ready) {
      var expectedWidth = root.frameWidth * root.columns
      var expectedHeight = root.frameHeight * root.rows
      var actualWidth = Number(atlas.sourceSize.width)
      var actualHeight = Number(atlas.sourceSize.height)
      if (actualWidth !== expectedWidth || actualHeight !== expectedHeight) {
        root.assetReady = false
        root.assetDiagnostic = root.species + " pack unavailable: atlas dimensions do not match (got "
          + actualWidth + "x" + actualHeight + ", expected "
          + expectedWidth + "x" + expectedHeight + ")"
      } else if (atlas.status === Image.Error) {
        root.assetReady = false
        root.assetDiagnostic = root.species + " pack unavailable: atlas could not be rendered"
      } else {
        root.assetReady = true
        root.assetDiagnostic = ""
      }
    } else if (atlas.status === Image.Error) {
      root.assetReady = false
      root.assetDiagnostic = root.species + " pack unavailable: atlas could not be loaded"
    } else {
      root.assetReady = false
    }
  }

  function restartSequence() {
    root.frameCursor = 0
    root.sequenceComplete = false
    if (root.playbackActive) frameTimer.restart()
  }

  function advanceFrame() {
    var frames = root.activeSequence && root.activeSequence.frames ? root.activeSequence.frames : []
    if (frames.length === 0) return
    if (root.frameCursor + 1 >= frames.length) {
      if (root.loop) {
        root.frameCursor = 0
        frameTimer.restart()
      } else {
        root.frameCursor = frames.length - 1
        root.sequenceComplete = true
        root.sequenceFinished()
      }
      return
    }
    root.frameCursor++
    frameTimer.restart()
  }

  FileView {
    id: manifestFile
    path: root.manifestPath
    watchChanges: false
    printErrors: false
    onTextChanged: root.loadManifest(text())
  }

  Timer {
    id: frameTimer
    interval: Math.max(16, Math.min(4000, root.frameDuration))
    repeat: false
    running: root.playbackActive
    onTriggered: root.advanceFrame()
  }

  // Decode the atlas once, then move the full texture behind this clipped
  // viewport. Changing the source clip on every frame makes Qt reload and
  // potentially decode the PNG repeatedly.
  Item {
    id: frameViewport
    width: root.frameWidth * root.renderScale
    height: root.frameHeight * root.renderScale
    clip: true

    Image {
      id: atlas
      width: root.atlasWidth * root.renderScale
      height: root.atlasHeight * root.renderScale
      x: root.mirrorFrame && !!(root.activeSequence && root.activeSequence.mirrorSafe)
        ? -(root.atlasWidth - root.frameRect.x - root.frameWidth) * root.renderScale
        : -root.frameRect.x * root.renderScale
      y: -root.frameRect.y * root.renderScale
      visible: root.assetReady
      source: root.atlasPath
      fillMode: Image.Stretch
      mirror: root.mirrorFrame && !!(root.activeSequence && root.activeSequence.mirrorSafe)
      smooth: false
      mipmap: false
      asynchronous: true
      onStatusChanged: root.observeAtlasStatus()
      onSourceSizeChanged: root.observeAtlasStatus()
    }
  }

  onActionNameChanged: root.restartSequence()
  onSpeciesChanged: {
    root.manifestReady = false
    root.assetReady = false
    root.pack = ({})
    root.assetDiagnostic = ""
    root.frameCursor = 0
    root.sequenceComplete = false
    manifestFile.reload()
  }
  onReducedMotionChanged: root.restartSequence()
  onPlaybackRequestedChanged: {
    if (root.playbackRequested) root.restartSequence()
    else frameTimer.stop()
  }
}
