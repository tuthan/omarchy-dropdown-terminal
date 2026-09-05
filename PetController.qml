import QtQuick

// Decorative pet state machine. It owns priority, cooldowns, and generation
// cancellation; PetMotion owns all base x/y projection and PetSprite owns
// frame timing. No action completion is allowed to revive a hidden pet.
Item {
  id: root

  property var service: null
  property var hostScreen: null
  property bool surfaceReady: false
  property bool focusSeen: false
  property bool focusQueued: false
  property string pendingReaction: ""
  property bool pendingReactionHidden: false
  property string lastObservedFinishKey: ""
  property string petState: "hidden"
  property int generation: 0
  property int actionGeneration: 0
  property string nextState: "idle"
  property double lastFocusAt: 0
  property real walkStartU: 0
  property real routeTargetU: 0
  property string routeEdge: "top"
  property string routeNextEdge: "top"
  property string routeNextAction: "walk"
  property bool routeAtCorner: false
  property var randomValues: []
  property int randomValueIndex: 0
  property var motionItem: null
  property var spriteItem: null
  property var effectsItem: null

  // Higher entries may interrupt lower entries. Hidden/closed and invalid
  // geometry are terminal conditions; reactions never outrank cleanup.
  readonly property var priorityOrder: ["hidden/closed", "invalid geometry", "enter/exit",
    "failure", "success", "first-focus dance", "corner/climb", "walking", "idle/sleep"]

  readonly property bool petEnabledActive: service ? service.petEnabled === true : false
  readonly property string species: service ? service.petSpecies : "Penguin"
  readonly property string activity: service ? service.petActivity : "On focus"
  readonly property bool reduceMotion: service ? service.reduceMotion === true : false
  readonly property bool hostMatchesTerminal: !!hostScreen && !!service && !!service.terminalMonitor
    && String(hostScreen.name || "") === String(service.terminalMonitor.name || "")
  readonly property bool geometryValid: !!service && service.terminalRect.width > 0 && service.terminalRect.height > 0
  readonly property bool assetReady: !!root.spriteItem && root.spriteItem.assetReady
    && ["Penguin", "Cat", "Corgi"].indexOf(species) >= 0
  readonly property bool active: petEnabledActive && surfaceReady && hostMatchesTerminal && geometryValid && assetReady
  readonly property bool idle: root.petState === "idle"
  readonly property string assetDiagnostic: root.spriteItem ? root.spriteItem.assetDiagnostic : ""

  function logDebug(message) {
    if (service && service.debugEnabled) console.log("Dropdown Terminal [debug]: pet " + message)
  }

  function stopAnimations() {
    if (root.spriteItem) root.spriteItem.playbackRequested = false
    walkAnimation.stop()
    hopAnimation.stop()
    sleepTimeout.stop()
    randomDecisionTimer.stop()
  }

  function invalidate() {
    root.generation++
    root.actionGeneration = root.generation
    root.nextState = "hidden"
    root.stopAnimations()
    if (root.effectsItem) root.effectsItem.cancel()
    if (service && service.terminalVisible && !root.hostMatchesTerminal) {
      root.pendingReaction = ""
      root.pendingReactionHidden = false
    }
    root.focusQueued = false
    root.petState = "hidden"
  }

  function validReaction(value) {
    return value === "success" || value === "failure"
  }

  function reactionForResult(value) {
    if (value === "succeeded" || value === "success") return "success"
    if (value === "failed" || value === "failure") return "failure"
    return ""
  }

  function enterIdle() {
    root.petState = "idle"
    root.nextState = "idle"
    root.spriteItem.actionName = "idle"
    root.spriteItem.playbackRequested = !root.reduceMotion
    root.spriteItem.restartSequence()
    root.armDecisionTimer()
    root.maybeCelebrateQueued()
    if (root.focusQueued && root.petState === "idle") {
      root.focusQueued = false
      root.observeFocus()
    }
  }

  function nextRandom() {
    if (Array.isArray(root.randomValues) && root.randomValueIndex < root.randomValues.length) {
      var value = Number(root.randomValues[root.randomValueIndex++])
      if (isFinite(value)) return Math.max(0, Math.min(0.999999, value))
    }
    return Math.random()
  }

  function beginSequence(action, after, token) {
    if (token !== root.generation || !root.active) return
    root.actionGeneration = token
    root.nextState = after || "idle"
    root.petState = action
    root.spriteItem.actionName = action
    root.spriteItem.playbackRequested = !root.reduceMotion
    root.spriteItem.restartSequence()
    if (root.reduceMotion) root.finishSequence(token)
  }

  function finishSequence(token) {
    if (token !== root.generation || token !== root.actionGeneration || !root.active) return
    root.spriteItem.playbackRequested = false
    if (root.petState === "land") root.effectsItem.burst("land")
    if (root.petState === "success") root.effectsItem.burst("success")
    if (root.petState === "failure") root.effectsItem.burst("failure")
    if (root.nextState === "idle") {
      root.enterIdle()
    } else if (root.nextState === "enter") {
      root.beginSequence("enter", "land", token)
      hopAnimation.restart()
    } else if (root.nextState === "route") {
      if (root.pendingReaction) root.enterIdle()
      else root.startRouteAction(root.routeNextAction, root.routeNextEdge, token)
    } else if (root.nextState === "idle-after-walk") {
      root.enterIdle()
    } else {
      root.beginSequence(root.nextState, "idle", token)
    }
  }

  function reveal() {
    if (!root.active) return
    root.generation++
    var token = root.generation
    root.randomValueIndex = 0
    root.stopAnimations()
    root.effectsItem.cancel()
    root.motionItem.reactionX = 0
    root.motionItem.reactionY = 0
    root.motionItem.setNormalizedProgress(0.12)
    if (root.reduceMotion) {
      root.enterIdle()
      return
    }
    root.beginSequence("peek", "enter", token)
  }

  function hide() {
    root.invalidate()
  }

  function maybeCelebrateQueued() {
    if (!root.pendingReaction || !root.active || root.petState !== "idle") return
    var reaction = root.pendingReaction
    root.pendingReaction = ""
    root.pendingReactionHidden = false
    root.startCelebration(reaction)
  }

  function startCelebration(reaction) {
    if (!root.active || !root.validReaction(reaction) || root.reduceMotion) return
    root.generation++
    var token = root.generation
    root.stopAnimations()
    root.effectsItem.cancel()
    root.beginSequence(reaction, "idle", token)
    hopAnimation.restart()
  }

  function observeFocus() {
    if (!service || !service.terminalFocused) return
    if (service.terminalVisible && !root.hostMatchesTerminal) return
    root.focusSeen = true
    if (root.petState !== "idle") {
      root.focusQueued = true
      return
    }
    if (root.reduceMotion) return
    if (root.activity === "Celebrations only") return
    if (Date.now() - root.lastFocusAt >= 8000) {
      root.focusQueued = false
      root.generation++
      var token = root.generation
      root.stopAnimations()
      root.lastFocusAt = Date.now()
      root.beginSequence("dance", "idle", token)
    }
  }

  function observeCommandCompletion() {
    if (!service || !service.commandLatestFinishKey
        || service.commandLatestFinishKey === root.lastObservedFinishKey) return
    root.lastObservedFinishKey = service.commandLatestFinishKey
    if (!service.commandTracking || !service.commandIntegrationInstalled
        || service.eventReplayReady !== true || service.commandLatestQualifies !== true) return
    if (service.terminalVisible && !root.hostMatchesTerminal) return
    var reaction = root.reactionForResult(String(service.commandLatestResult || ""))
    if (!root.validReaction(reaction)) return
    root.focusQueued = false
    if (root.petState === "idle" && root.active) root.startCelebration(reaction)
    else {
      root.pendingReaction = reaction
      root.pendingReactionHidden = !service.terminalVisible
    }
  }

  function armDecisionTimer() {
    randomDecisionTimer.stop()
    if (root.active && !root.reduceMotion && root.activity === "Always while visible"
        && root.petState === "idle") randomDecisionTimer.restart()
  }

  function decideIdleAction() {
    if (!root.active || root.reduceMotion || root.petState !== "idle") return
    if (root.nextRandom() < 0.22) {
      root.petState = "sleep"
      root.spriteItem.actionName = "sleep"
      root.spriteItem.playbackRequested = true
      root.spriteItem.restartSequence()
      sleepTimeout.restart()
      return
    }
    root.startRouteStep()
  }

  function edgeEndU(edge) {
    if (edge === "top") return root.motionItem.trackWidth / root.motionItem.perimeter
    if (edge === "right") return (root.motionItem.trackWidth + root.motionItem.trackHeight)
      / root.motionItem.perimeter
    if (edge === "bottom") return (2 * root.motionItem.trackWidth + root.motionItem.trackHeight)
      / root.motionItem.perimeter
    return 1
  }

  function nextEdge(edge) {
    if (edge === "top") return "right"
    if (edge === "right") return "bottom"
    if (edge === "bottom") return "left"
    return "top"
  }

  function actionForEdge(edge) {
    return edge === "top" || edge === "bottom" ? "walk" : "climb"
  }

  function startCornerTurn(nextAction, nextEdgeName) {
    if (!root.active || root.reduceMotion) return
    var token = ++root.generation
    root.actionGeneration = token
    root.stopAnimations()
    root.routeNextAction = nextAction
    root.routeNextEdge = nextEdgeName
    root.nextState = "route"
    root.beginSequence("corner", "route", token)
  }

  function startRouteAction(action, edge, token) {
    if (!root.active || root.reduceMotion || ["walk", "climb"].indexOf(action) < 0) return
    var start = root.motionItem.normalizedU
    var end = root.edgeEndU(edge)
    var remaining = end - start
    if (remaining <= 0.00001) {
      var followingEdge = root.nextEdge(edge)
      root.startCornerTurn(root.actionForEdge(followingEdge), followingEdge)
      return
    }
    var maximumStep = action === "walk" ? 0.22 : 0.08
    var target = Math.min(end, start + maximumStep)
    root.routeEdge = edge
    root.routeTargetU = target
    root.routeAtCorner = target >= end - 0.00001
    root.walkStartU = start
    root.actionGeneration = token
    root.nextState = "idle"
    root.petState = action
    root.spriteItem.actionName = action
    root.spriteItem.playbackRequested = true
    root.spriteItem.restartSequence()
    walkAnimation.from = start
    walkAnimation.to = target
    walkAnimation.duration = Math.max(260, Math.round((action === "walk" ? 2600 : 900)
      * (target - start) / maximumStep))
    walkAnimation.restart()
  }

  function startRouteStep() {
    if (!root.active || root.reduceMotion || root.petState !== "idle") return
    var edge = root.motionItem.edge
    var end = root.edgeEndU(edge)
    if (end - root.motionItem.normalizedU <= 0.00001) {
      root.startCornerTurn(root.actionForEdge(root.nextEdge(edge)), root.nextEdge(edge))
      return
    }
    var token = ++root.generation
    root.stopAnimations()
    root.startRouteAction(root.actionForEdge(edge), edge, token)
  }

  function finishWalk(token) {
    if (token !== root.generation || token !== root.actionGeneration || root.petState !== "walk") return
    walkAnimation.stop()
    root.spriteItem.playbackRequested = false
    root.motionItem.setNormalizedProgress(root.motionItem.travelU)
    if (root.pendingReaction) {
      root.enterIdle()
      return
    }
    if (root.routeAtCorner) {
      root.startCornerTurn(root.actionForEdge(root.nextEdge(root.routeEdge)), root.nextEdge(root.routeEdge))
      return
    }
    root.enterIdle()
  }

  function finishRouteMotion(token) {
    if (root.petState === "walk") root.finishWalk(token)
    else if (root.petState === "climb") root.finishClimb(token)
  }

  function finishClimb(token) {
    if (token !== root.generation || token !== root.actionGeneration || root.petState !== "climb") return
    walkAnimation.stop()
    root.spriteItem.playbackRequested = false
    root.motionItem.setNormalizedProgress(root.motionItem.travelU)
    if (root.pendingReaction) {
      root.enterIdle()
      return
    }
    if (root.routeAtCorner) {
      root.startCornerTurn(root.actionForEdge(root.nextEdge(root.routeEdge)), root.nextEdge(root.routeEdge))
      return
    }
    root.enterIdle()
  }

  function returnFromSleep() {
    if (root.petState !== "sleep" || !root.active) return
    root.spriteItem.playbackRequested = false
    root.enterIdle()
  }

  Component.onCompleted: {
    root.motionItem = petMotion
    root.spriteItem = petSprite
    root.effectsItem = petEffects
    root.lastObservedFinishKey = service ? service.commandLatestFinishKey : ""
    if (service && service.commandUnread && service.commandLatestQualifies === true) {
      var reaction = root.reactionForResult(String(service.commandUnreadResult || ""))
      if (root.validReaction(reaction)) {
        root.pendingReaction = reaction
        root.pendingReactionHidden = true
      }
    }
  }

  Connections {
    target: root.service
    function onTerminalVisibleChanged() {
      if (root.service && root.service.terminalVisible) {
        if (root.hostMatchesTerminal) root.reveal()
        else {
          root.pendingReaction = ""
          root.pendingReactionHidden = false
          root.focusQueued = false
        }
      } else {
        if (!root.pendingReactionHidden) root.pendingReaction = ""
        root.hide()
      }
    }
    function onTerminalFocusedChanged() { root.observeFocus() }
    function onCommandLatestFinishKeyChanged() { root.observeCommandCompletion() }
    function onPetEnabledChanged() {
      if (!root.petEnabledActive) {
        root.pendingReaction = ""
        root.pendingReactionHidden = false
        root.focusQueued = false
        root.hide()
      }
      else if (root.surfaceReady) root.reveal()
    }
    function onPetActivityChanged() { root.armDecisionTimer() }
    function onReduceMotionChanged() {
      if (root.reduceMotion) {
        root.stopAnimations()
        root.effectsItem.cancel()
        if (root.active) root.enterIdle()
      } else if (root.surfaceReady) root.reveal()
    }
  }

  onSurfaceReadyChanged: {
    if (root.surfaceReady && root.active && root.petState === "hidden") root.reveal()
    else if (!root.surfaceReady) root.hide()
  }

  onActiveChanged: {
    if (!root.active) root.hide()
    else if (root.surfaceReady && root.petState === "hidden") root.reveal()
  }

  Timer {
    id: randomDecisionTimer
    interval: 9000
    repeat: false
    onTriggered: root.decideIdleAction()
  }

  Timer {
    id: sleepTimeout
    interval: 5000
    repeat: false
    onTriggered: root.returnFromSleep()
  }

  SequentialAnimation {
    id: hopAnimation
    running: false
    NumberAnimation {
      target: root.motionItem
      property: "reactionY"
      to: -10
      duration: 210
      easing.type: Easing.OutQuad
    }
    NumberAnimation {
      target: root.motionItem
      property: "reactionY"
      to: 0
      duration: 210
      easing.type: Easing.InQuad
    }
  }

  NumberAnimation {
    id: walkAnimation
    target: root.motionItem
    property: "travelU"
    duration: 2600
    easing.type: Easing.InOutSine
    onFinished: root.finishRouteMotion(root.actionGeneration)
  }

  PetMotion {
    id: petMotion
    anchors.fill: parent
    service: root.service
    hostScreen: root.hostScreen
    frameWidth: root.spriteItem ? root.spriteItem.width : 32
    frameHeight: root.spriteItem ? root.spriteItem.height : 32
    anchorX: root.spriteItem ? root.spriteItem.projectedAnchorX * root.spriteItem.renderScale : 16
    anchorY: root.spriteItem ? root.spriteItem.anchorY * root.spriteItem.renderScale : 30
  }

  PetSprite {
    id: petSprite
    species: root.species
    width: frameWidth * renderScale
    height: frameHeight * renderScale
    x: root.motionItem ? root.motionItem.spriteX : 0
    y: root.motionItem ? root.motionItem.spriteY : 0
    visible: root.active
    reducedMotion: root.reduceMotion
    mirrorFrame: root.motionItem ? root.motionItem.facing === "left" : false
  }

  Connections {
    target: root.spriteItem
    function onSequenceFinished() { root.finishSequence(root.actionGeneration) }
  }

  PetEffects {
    id: petEffects
    anchors.fill: parent
    originX: root.motionItem ? root.motionItem.contactX : 0
    originY: root.motionItem ? root.motionItem.contactY : 0
    reducedMotion: root.reduceMotion
    z: 2
  }
}
