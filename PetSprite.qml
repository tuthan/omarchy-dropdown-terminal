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

  function validSequence(sequence, cellCount) {
    if (!sequence || !Array.isArray(sequence.frames) || !Array.isArray(sequence.durations)
        || !Array.isArray(sequence.anchors) || sequence.frames.length === 0
        || sequence.frames.length > 16 || sequence.frames.length !== sequence.durations.length
        || sequence.frames.length !== sequence.anchors.length || typeof sequence.loop !== "boolean"
        || typeof sequence.mirrorSafe !== "boolean")
      return false
    for (var i = 0; i < sequence.frames.length; i++) {
      if (!boundedInteger(sequence.frames[i], 0, cellCount - 1)
          || !boundedInteger(sequence.durations[i], 16, 4000)
          || !validAnchor(sequence.anchors[i])) return false
    }
    var totalDuration = sequence.durations.reduce(function(total, duration) { return total + Number(duration) }, 0)
    if (!sequence.loop && totalDuration > 12000) return false
    return true
  }

  function validPack(candidate) {
    if (!candidate || candidate.version !== 1 || !candidate.atlas || !candidate.actions)
      return false
    var atlas = candidate.atlas
    if (!safeRelativePath(atlas.path) || !boundedInteger(atlas.frameWidth, 32, 32)
        || !boundedInteger(atlas.frameHeight, 32, 32) || !boundedInteger(atlas.columns, 1, 8)
        || !boundedInteger(atlas.rows, 1, 8) || !boundedInteger(atlas.renderScale, 1, 4)) return false
    if (atlas.columns * atlas.rows > 64) return false
    var required = ["peek", "enter", "land", "idle", "walk", "corner", "climb",
      "dance", "success", "failure", "exit", "sleep"]
    var cellCount = atlas.columns * atlas.rows
    for (var i = 0; i < required.length; i++) {
      if (!validSequence(candidate.actions[required[i]], cellCount)) return false
    }
    if (!candidate.fallbacks || typeof candidate.fallbacks !== "object") return false
    for (var name in candidate.fallbacks) {
      var fallback = String(candidate.fallbacks[name])
      if (!candidate.actions[fallback] || fallback === name) return false
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
