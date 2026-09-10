import QtQuick
import Quickshell.Io
import "PetRoute.js" as PetRoute
import "PetVoice.js" as PetVoice

// Decorative pet state machine. It owns priority, cooldowns, generation
// cancellation, and pointer reactions; PetMotion owns geometry and PetSprite
// owns authored frame timing.
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
  property real routeTargetU: 0
  property string routeEdge: "top"
  property string routeNextEdge: "top"
  property int routeDirection: 1
  property int routeNextDirection: 1
  property var routePlan: null
  property var randomValues: []
  property int randomValueIndex: 0
  property var motionItem: null
  property var spriteItem: null
  property var effectsItem: null
  property bool petPressActive: false
  property int petPressGeneration: -1
  property double petPressedAt: 0
  property double lastHeartsAt: 0
  property bool turning: false
  property bool pendingTurnMirror: false
  property bool renderMirror: false
  property bool dragging: false
  property int dragGeneration: -1
  property real dragPressX: 0
  property real dragPressY: 0
  property real dragOffsetX: 0
  property real dragOffsetY: 0
  property real dragPointerX: 0
  property real dragPointerY: 0
  property real dragBaseContactX: 0
  property real dragBaseContactY: 0
  property bool pointerInside: false
  property int pointerZone: 1
  property real pointerX: 0
  property real pointerY: 0
  property double lastNoticeAt: 0
  property double lastFollowAt: 0
  property string pendingVoiceEvent: ""
  property double lastVoiceAt: 0
  property var rememberedPosition: null
  property real returnTargetU: -1
  property bool returningToRemembered: false
  property int returnDirection: 1
  property bool voiceReady: false
  property var voiceLines: null
  property var soundItem: null

  readonly property var priorityOrder: ["hidden/closed", "invalid geometry", "enter/exit",
    "failure", "success", "petting/carried", "first-focus dance", "corner/climb",
    "walking", "idle/sleep"]
  readonly property bool petEnabledActive: service ? service.petEnabled === true : false
  readonly property string species: service ? service.petSpecies : "Penguin"
  readonly property string activity: service ? service.petActivity : "On focus"
  readonly property bool reduceMotion: service ? service.reduceMotion === true : false
  readonly property bool petInteraction: service ? service.petInteraction !== false : true
  readonly property string petRoaming: service ? service.petRoaming : "Top edge"
  readonly property bool petDrag: service ? service.petDrag !== false : true
  readonly property string petHoverHalo: service ? service.petHoverHalo : "Off"
  readonly property int hoverHaloExtent: root.petHoverHalo === "Large" ? 48
    : (root.petHoverHalo === "Small" ? 24 : 0)
  readonly property string petVoice: service ? service.petVoice : "Off"
  readonly property string petSound: service ? service.petSound : "Off"
  readonly property bool petRememberPosition: service ? service.petRememberPosition !== false : true
  readonly property bool positionReadReady: !root.petRememberPosition
    || (!!root.service && root.service.petStateReadReady === true)
  readonly property bool hostMatchesTerminal: !!hostScreen && !!service && !!service.terminalMonitor
    && String(hostScreen.name || "") === String(service.terminalMonitor.name || "")
  readonly property bool geometryValid: !!service && service.terminalRect.width > 0
    && service.terminalRect.height > 0
  readonly property bool assetReady: !!root.spriteItem && root.spriteItem.assetReady
    && ["Penguin", "Cat", "Corgi"].indexOf(species) >= 0
  readonly property bool active: petEnabledActive && surfaceReady && hostMatchesTerminal
    && geometryValid && assetReady
  readonly property var allowedEdges: root.computeAllowedEdges()
  readonly property string effectiveRoaming: root.allowedEdges.length > 1 ? "Whole border" : "Top edge"
  readonly property bool idle: root.petState === "idle"
  readonly property string assetDiagnostic: root.spriteItem ? root.spriteItem.assetDiagnostic : ""
  readonly property bool wholeBorderAvailable: !!root.spriteItem
    && root.spriteItem.wallSafeClimb && root.spriteItem.wallSafeClimbDown
  readonly property string roamingDiagnostic: root.petRoaming === "Whole border"
    && !root.wholeBorderAvailable
    ? "Pack has no wall-safe descending climb (climbDown); roaming limited to top edge" : ""
  readonly property string roomDiagnostic: root.petRoaming !== "Whole border" ? ""
    : ((root.allowedEdges.indexOf("left") < 0 && root.allowedEdges.indexOf("right") < 0)
      ? "No room beside the terminal at this width; the sides are unavailable"
      : (root.allowedEdges.indexOf("bottom") < 0 && root.spriteItem && root.spriteItem.bottomHangAvailable
        ? "No room below the terminal at this height; the bottom is unavailable" : ""))
  readonly property string voiceDiagnostic: root.petVoice !== "Off" && !root.voiceReady
    ? "Voice unavailable: bundled lines could not be read" : ""
  readonly property string soundDiagnostic: root.petSound !== "Off" && root.soundItem
    && root.soundItem.diagnostic !== "" ? root.soundItem.diagnostic : ""
  readonly property real clickableExtent: {
    if (!root.motionItem || !root.spriteItem) return 0
    var margin = service ? Number(service.grabMargin) : 17
    var edge = root.motionItem.edge
    if (edge === "top") return root.spriteItem.anchorY * root.spriteItem.renderScale - margin
    if (edge === "bottom")
      return root.spriteItem.height - root.spriteItem.anchorY * root.spriteItem.renderScale - margin
    // Use the authored wall anchor, not the frame midpoint. The anchor is the
    // terminal-facing point, so the remaining outward footprint is the actual
    // area that remains after Hyprland's resize/grab region is subtracted.
    var projectedAnchor = root.spriteItem.projectedAnchorX * root.spriteItem.renderScale
    var outwardExtent = edge === "left"
      ? projectedAnchor : root.spriteItem.width - projectedAnchor
    return outwardExtent - margin
  }
  readonly property string interactionDiagnostic: root.active && root.petInteraction
    && !root.spriteItem.petReactionAvailable ? "Pack has no petting reaction" :
    (root.active && root.petInteraction && root.clickableExtent < 8
      ? "Pet too small to click at this scale" : "")
  readonly property bool interactionEnabled: root.active && root.petInteraction
    && root.positionReadReady && root.petState !== "hidden"
    && root.service && root.service.grabMarginReady === true
    && root.spriteItem && root.spriteItem.visible && root.spriteItem.petReactionAvailable
    && root.clickableExtent >= 8

  function logDebug(message) {
    if (service && service.debugEnabled) console.log("Dropdown Terminal [debug]: pet " + message)
  }

  function computeAllowedEdges() {
    if (!root.motionItem || !root.spriteItem || root.petRoaming !== "Whole border"
        || !root.wholeBorderAvailable) return ["top"]
    var allowed = ["top"]
    if (root.motionItem.roomRight >= 0) allowed.push("right")
    if (root.spriteItem.bottomHangAvailable && root.motionItem.roomBottom >= 0) allowed.push("bottom")
    if (root.motionItem.roomLeft >= 0) allowed.push("left")
    return allowed
  }

  function savePosition(immediate) {
    if (!root.petRememberPosition || !root.motionItem || !root.service
        || typeof root.service.savePetState !== "function") return
    root.service.savePetState({
      species: root.species,
      edge: root.motionItem.edge,
      fraction: root.motionItem.fractionForProjection(root.motionItem.normalizedU,
        root.motionItem.edge, root.motionItem.trackWidth, root.motionItem.trackHeight),
      direction: root.motionItem.direction
    }, root.hostScreen ? root.hostScreen.name : "", immediate === true)
  }

  function loadRememberedPosition() {
    if (!root.petRememberPosition || !root.service || typeof root.service.readPetState !== "function") return
    var saved = root.service.readPetState(root.species, root.allowedEdges)
    if (!saved) { root.rememberedPosition = null; return }
    root.rememberedPosition = saved
  }

  function stopAnimations() {
    if (root.spriteItem) root.spriteItem.playbackRequested = false
    walkAnimation.stop()
    cornerCompensation.stop()
    dropAnimation.stop()
    hopAnimation.stop()
    pettingTimeout.stop()
    turnFallbackTimer.stop()
    sleepTimeout.stop()
    randomDecisionTimer.stop()
    offFloorReactionTimer.stop()
    noticeHoldTimer.stop()
    hoverExitTimer.stop()
    hoverDwellTimer.stop()
  }

  function invalidate() {
    root.generation++
    root.actionGeneration = root.generation
    root.nextState = "hidden"
    root.stopAnimations()
    root.petPressActive = false
    root.petPressGeneration = -1
    root.dragging = false
    root.dragGeneration = -1
    if (root.motionItem) {
      root.motionItem.reactionX = 0
      root.motionItem.reactionY = 0
    }
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

  function durationBucket(durationMs) {
    var value = Number(durationMs)
    if (!isFinite(value) || value < 10000) return "under 10 s"
    if (value < 60000) return "10–60 s"
    if (value < 600000) return "1–10 min"
    return "over 10 min"
  }

  function showVoice(event) {
    if (root.petVoice === "Off" || !root.voiceReady || !root.voiceLines
        || Date.now() - root.lastVoiceAt < 8000 || !root.effectsItem) return
    var facts = {
      status: root.service ? root.service.commandLatestStatus : "?",
      duration: root.service ? root.durationBucket(root.service.commandLatestDurationMs) : "unknown duration"
    }
    root.voiceLines.facts = facts
    var line = PetVoice.pickLine(root.voiceLines, root.petVoice, event, root.species,
      root.effectsItem.recentVoiceLines || [], root.nextRandom(), 3)
    if (!line) return
    root.lastVoiceAt = Date.now()
    root.effectsItem.recentVoiceLines = (root.effectsItem.recentVoiceLines || []).concat([line]).slice(-5)
    root.effectsItem.showBubble(line, root.motionItem ? root.motionItem.edge : "top")
  }

  function actionFamily(edge) {
    return edge === "left" || edge === "right" ? "wall" : (edge === "bottom" ? "ledge" : "floor")
  }

  function actionForFamily(edge, preferred, fallback) {
    if (!root.spriteItem) return fallback || "idle"
    if (root.spriteItem.actions[preferred]) return preferred
    if (fallback && root.spriteItem.actions[fallback]) return fallback
    return edge === "left" || edge === "right" ? "climb" : (edge === "bottom" ? "hang" : "idle")
  }

  function holdFamilyFrame(edge, preferred) {
    var action = root.actionForFamily(edge, preferred, edge === "bottom" ? "hang" : "climb")
    root.spriteItem.actionName = action
    root.spriteItem.playbackRequested = false
    root.spriteItem.frameCursor = 0
    root.spriteItem.sequenceComplete = false
  }

  function enterIdle() {
    if (!root.active || !root.spriteItem) return
    root.turning = false
    root.petState = "idle"
    root.nextState = "idle"
    var family = root.actionFamily(root.motionItem ? root.motionItem.edge : "top")
    if (family === "wall") root.holdFamilyFrame(root.motionItem.edge, "wallIdle")
    else if (family === "ledge") root.holdFamilyFrame(root.motionItem.edge, "ledgeIdle")
    else {
      root.spriteItem.actionName = "idle"
      root.spriteItem.playbackRequested = !root.reduceMotion
    }
    root.spriteItem.restartSequence()
    root.maybeCelebrateQueued()
    if (root.petState !== "idle") return
    if (root.returningToRemembered && root.returnTargetU >= 0
        && Math.abs(root.motionItem.normalizedU - root.returnTargetU) < 0.0001) {
      root.returningToRemembered = false
      root.returnTargetU = -1
      root.savePosition()
    }
    if (root.returningToRemembered && root.returnTargetU >= 0) {
      root.startRouteToward(root.returnTargetU)
    }
    root.armDecisionTimer()
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
    if (token !== root.generation || !root.active || !root.spriteItem) return
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
    if (root.petState === "petting") {
      if (root.petPressActive) root.spriteItem.restartSequence()
      else root.endPetting(token)
      return
    }
    root.spriteItem.playbackRequested = false
    if (root.petState === "land") {
      root.effectsItem.burst("land")
      if (root.soundItem) root.soundItem.play("land")
      // The top landing is only staging while a remembered side/bottom
      // position is being restored. Save after the destination is reached.
      if (!root.returningToRemembered) root.savePosition()
    }
    if (root.petState === "success") {
      root.effectsItem.burst("success")
      if (root.soundItem) root.soundItem.play("success")
    }
    if (root.petState === "failure") {
      root.effectsItem.burst("failure")
      if (root.soundItem) root.soundItem.play("failure")
    }
    if (root.petState === "turn") {
      root.turning = false
      root.renderMirror = root.pendingTurnMirror
      root.motionItem.direction = root.routeNextDirection
    }
    if (root.nextState === "idle") {
      root.enterIdle()
    } else if (root.nextState === "enter") {
      root.beginSequence("enter", "land", token)
      hopAnimation.restart()
    } else if (root.nextState === "route") {
      var exitingCorner = root.petState === "corner"
      if (exitingCorner) root.prepareCornerExitCompensation(root.routePlan)
      root.startRouteAction(root.routeNextEdge, root.routeNextDirection, token)
      if (exitingCorner && !root.reduceMotion) cornerCompensation.restart()
    } else if (root.nextState === "reenter") {
      root.motionItem.setNormalizedProgress(root.motionItem.topEdgeStartU
        + (root.returningToRemembered ? 0 : 0.12)
        * (root.motionItem.topEdgeEndU - root.motionItem.topEdgeStartU))
      root.beginSequence("peek", "enter", token)
    } else {
      root.beginSequence(root.nextState, "idle", token)
    }
  }

  function reveal() {
    if (!root.active || !root.positionReadReady) return
    root.generation++
    var token = root.generation
    root.randomValueIndex = 0
    root.stopAnimations()
    root.petPressActive = false
    root.effectsItem.cancel()
    root.motionItem.reactionX = 0
    root.motionItem.reactionY = 0
    root.loadRememberedPosition()
    root.motionItem.direction = root.rememberedPosition
      ? root.rememberedPosition.direction : 1
    root.renderMirror = root.mirrorFor("top", root.motionItem.direction)
    root.returningToRemembered = !!root.rememberedPosition
      && root.rememberedPosition.edge !== "top"
    root.returnDirection = 1
    root.returnTargetU = -1
    if (root.returningToRemembered) {
      var savedStart = root.motionItem.edgeStartU(root.rememberedPosition.edge,
        root.motionItem.trackWidth, root.motionItem.trackHeight)
      var savedEnd = root.motionItem.edgeEndU(root.rememberedPosition.edge,
        root.motionItem.trackWidth, root.motionItem.trackHeight)
      root.returnTargetU = savedStart + root.rememberedPosition.fraction * (savedEnd - savedStart)
      root.returnDirection = root.rememberedPosition.edge === "right"
        || (root.rememberedPosition.edge === "bottom" && root.rememberedPosition.fraction <= 0.5)
        ? 1 : -1
    }
    if (root.rememberedPosition && root.rememberedPosition.edge === "top") {
      root.motionItem.setNormalizedProgress(root.motionItem.topEdgeStartU
        + root.rememberedPosition.fraction
        * (root.motionItem.topEdgeEndU - root.motionItem.topEdgeStartU))
    } else if (root.returningToRemembered) {
      var cornerEdge = root.rememberedPosition.edge === "right"
        || (root.rememberedPosition.edge === "bottom" && root.rememberedPosition.fraction <= 0.5)
        ? "right" : "left"
      root.motionItem.setNormalizedProgress(cornerEdge === "right"
        ? root.motionItem.topEdgeEndU : root.motionItem.topEdgeStartU)
    } else {
      root.motionItem.setNormalizedProgress(root.motionItem.topEdgeStartU
        + (root.returningToRemembered ? 0 : 0.12)
        * (root.motionItem.topEdgeEndU - root.motionItem.topEdgeStartU))
    }
    if (service && root.petInteraction && typeof service.refreshGrabMargin === "function")
      service.refreshGrabMargin()
    if (root.reduceMotion) {
      root.settleRememberedPositionForReducedMotion()
      root.enterIdle()
      return
    }
    root.beginSequence("peek", "enter", token)
  }

  function hide() {
    // Hide is a settle boundary: persist immediately so a shell/plugin reload
    // cannot race the normal two-second coalescing timer. A remembered route
    // still in transit must retain its original destination.
    if (root.positionReadReady && root.petState !== "hidden"
        && !root.returningToRemembered) root.savePosition(true)
    if (root.effectsItem) root.effectsItem.dismissBubble()
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
    if (!root.active || !root.validReaction(reaction)) return
    root.generation++
    var token = root.generation
    root.stopAnimations()
    root.petPressActive = false
    root.petPressGeneration = -1
    root.effectsItem.cancel()
    if (root.motionItem && root.motionItem.edge !== "top") {
      root.petState = reaction
      root.actionGeneration = token
      root.holdFamilyFrame(root.motionItem.edge, root.motionItem.edge === "bottom" ? "hang" : "climb")
      root.effectsItem.burst(reaction)
      if (root.soundItem) root.soundItem.play(reaction)
      offFloorReactionTimer.interval = root.reduceMotion ? 0 : 420
      offFloorReactionTimer.restart()
      return
    }
    root.beginSequence(reaction, "idle", token)
    if (!root.reduceMotion) hopAnimation.restart()
  }

  function observeFocus() {
    if (!service || !service.terminalFocused) return
    if (service.terminalVisible && !root.hostMatchesTerminal) return
    root.focusSeen = true
    if (root.petState !== "idle") {
      root.focusQueued = true
      return
    }
    if (root.reduceMotion || root.activity === "Celebrations only") return
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
    root.showVoice(reaction === "success" ? "succeeded" : "failed")
    if (root.dragging) {
      root.pendingReaction = reaction
      root.pendingReactionHidden = false
    } else if ((root.petState === "idle" || root.petState === "petting") && root.active)
      root.startCelebration(reaction)
    else {
      root.pendingReaction = reaction
      root.pendingReactionHidden = !service.terminalVisible
    }
  }

  function armDecisionTimer() {
    randomDecisionTimer.stop()
    if (root.active && !root.reduceMotion && root.activity === "Always while visible"
        && root.petState === "idle") {
      randomDecisionTimer.interval = 3000 + Math.floor(root.nextRandom() * 6001)
      randomDecisionTimer.restart()
    }
  }

  function decideIdleAction() {
    if (!root.active || root.reduceMotion || root.petState !== "idle") return
    var behaviorRoll = root.nextRandom()
    if (behaviorRoll < 0.08) {
      // Idle voice is deliberately rare and carries no command/result facts.
      root.showVoice("idle")
      root.armDecisionTimer()
      return
    }
    if (behaviorRoll < 0.22) {
      if (root.motionItem.edge !== "top") { root.startRouteStep(); return }
      root.petState = "sleep"
      root.spriteItem.actionName = "sleep"
      root.spriteItem.playbackRequested = true
      root.spriteItem.restartSequence()
      sleepTimeout.restart()
      root.savePosition()
      return
    }
    root.startRouteStep()
  }

  function edgeStartU(edge) {
    if (edge === "top") return 0
    if (edge === "right") return root.motionItem.trackWidth / root.motionItem.perimeter
    if (edge === "bottom") return (root.motionItem.trackWidth + root.motionItem.trackHeight)
      / root.motionItem.perimeter
    return (2 * root.motionItem.trackWidth + root.motionItem.trackHeight)
      / root.motionItem.perimeter
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
    return edge === "top" ? "right" : (edge === "right" ? "bottom"
      : (edge === "bottom" ? "left" : "top"))
  }

  function actionForEdge(edge, direction) {
    if (edge === "top") return "walk"
    if (edge === "bottom") return "hang"
    var movingDown = edge === "right" ? direction >= 0 : direction < 0
    return movingDown ? "climbDown" : "climb"
  }

  function mirrorFor(edge, direction) {
    if (edge === "top") return direction < 0
    if (edge === "bottom") return direction > 0
    // Wall art is authored with the wall at the left of the frame. Mirror it
    // only on the left edge so the body always faces away from the terminal.
    if (edge === "left") return true
    return false
  }

  function startRouteAction(edge, direction, token, towardU) {
    if (!root.active || root.reduceMotion || token !== root.generation) return
    var approachTarget = towardU
    if (approachTarget === undefined && root.returningToRemembered)
      approachTarget = root.returnTargetU
    var action = root.actionForEdge(edge, direction)
    if (!root.spriteItem.actions[action]) action = edge === "top" || edge === "bottom" ? "walk" : "climb"
    var actionData = root.spriteItem.actions[action] || root.spriteItem.actions.walk
    var stride = Number(actionData.stride || root.spriteItem.walkStride || 10)
    var durations = actionData.durations || root.spriteItem.actions.walk.durations
    var plan = PetRoute.planStep({
      edge: edge,
      u: root.motionItem.normalizedU,
      direction: direction,
      roamingMode: root.effectiveRoaming,
      allowedEdges: root.allowedEdges,
      terminalRect: root.motionItem.terminalRect,
      stride: stride,
      renderScale: root.spriteItem.renderScale,
      durations: durations,
      random: { step: root.nextRandom(), turn: root.nextRandom() },
      towardU: approachTarget,
      towardDirection: root.returningToRemembered ? root.returnDirection : undefined,
      towardEdge: root.returningToRemembered && root.rememberedPosition
        ? root.rememberedPosition.edge : "",
      wallStep: edge === "left" || edge === "right"
    })
    root.routePlan = plan
    root.routeEdge = edge
    root.routeNextEdge = plan.targetEdge
    root.routeDirection = plan.direction
    root.routeNextDirection = plan.nextDirection
    root.routeTargetU = plan.targetU
    root.actionGeneration = token
    if (plan.durationMs <= 0) {
      root.startTurnOrCorner(plan, token)
      return
    }
    root.turning = false
    root.motionItem.direction = plan.direction
    root.renderMirror = root.mirrorFor(edge, plan.direction)
    root.petState = action
    root.nextState = "idle"
    root.spriteItem.actionName = action
    root.spriteItem.playbackRequested = true
    root.spriteItem.restartSequence()
    walkAnimation.from = plan.fromU
    walkAnimation.to = plan.targetU
    walkAnimation.duration = Math.max(1, plan.durationMs)
    walkAnimation.restart()
  }

  function startRouteStep() {
    if (!root.active || root.reduceMotion || root.petState !== "idle") return
    var edge = root.effectiveRoaming === "Top edge" ? "top" : root.motionItem.edge
    var direction = root.motionItem.direction >= 0 ? 1 : -1
    if (root.allowedEdges.indexOf(edge) < 0 || (root.effectiveRoaming === "Top edge"
        && root.motionItem.edge !== "top")) {
      root.startReentry()
      return
    }
    var token = ++root.generation
    root.stopAnimations()
    root.startRouteAction(edge, direction, token)
  }

  function startRouteToward(targetU) {
    if (!root.active || root.reduceMotion || root.petState !== "idle") return
    var edge = root.motionItem.edge
    var target = Number(targetU)
    if (root.allowedEdges.indexOf(edge) < 0 || !isFinite(target)) return
    var token = ++root.generation
    root.stopAnimations()
    root.startRouteAction(edge, root.motionItem.direction >= 0 ? 1 : -1, token, target)
  }

  function startTurnOrCorner(plan, token) {
    if (token !== root.generation || !root.active) return
    root.routeNextEdge = plan.targetEdge
    root.routeNextDirection = plan.nextDirection
    root.pendingTurnMirror = root.mirrorFor(plan.targetEdge, plan.nextDirection)
    root.turning = true
    root.nextState = "route"
    root.petState = plan.actions.indexOf("corner") >= 0 ? "corner" : "turn"
    if (root.petState === "corner") {
      root.applyAnchorCompensation(plan)
      root.beginSequence("corner", "route", token)
      if (!root.reduceMotion) cornerCompensation.restart()
      return
    }
    root.stopAnimations()
    root.actionGeneration = token
    if (root.spriteItem.actions.turn) {
      root.beginSequence("turn", "route", token)
      return
    }
    root.spriteItem.actionName = "idle"
    root.spriteItem.playbackRequested = true
    root.spriteItem.restartSequence()
    turnFallbackTimer.interval = Math.max(41, Number(root.spriteItem.actions.idle.durations[0] || 100))
    turnFallbackTimer.restart()
  }

  function projectedAnchorFor(actionName, mirrored) {
    var action = root.spriteItem && root.spriteItem.actions[actionName]
    if (!action || !action.anchors || action.anchors.length === 0) return { x: 16, y: 30 }
    var anchor = action.anchors[0]
    return { x: mirrored && action.mirrorSafe ? root.spriteItem.frameWidth - Number(anchor.x) : Number(anchor.x),
      y: Number(anchor.y) }
  }

  function applyAnchorCompensation(plan) {
    if (!root.motionItem || !root.spriteItem || !plan) return
    var currentAnchor = { x: root.motionItem.anchorX, y: root.motionItem.anchorY }
    var oldOrigin = {
      x: root.motionItem.contactX + root.motionItem.reactionX - currentAnchor.x,
      y: root.motionItem.contactY + root.motionItem.reactionY - currentAnchor.y
    }
    // Corner frames use their own floor anchor. Compensating against the next
    // wall anchor here applies the same delta twice when the action changes at
    // the end of the corner sequence.
    var cornerAnchor = root.projectedAnchorFor("corner", false)
    var cornerContact = root.motionItem.project(plan.targetU)
    var cornerOrigin = { x: cornerContact.x - cornerAnchor.x * root.spriteItem.renderScale,
      y: cornerContact.y - cornerAnchor.y * root.spriteItem.renderScale }
    root.motionItem.reactionX = oldOrigin.x - cornerOrigin.x
    root.motionItem.reactionY = oldOrigin.y - cornerOrigin.y
    cornerCompensation.duration = Math.max(160, Number(root.spriteItem.actions.corner
      && root.spriteItem.actions.corner.durations
      ? root.spriteItem.actions.corner.durations.reduce(function(total, value) { return total + Number(value) }, 0)
      : 160))
  }

  function prepareCornerExitCompensation(plan) {
    if (!root.motionItem || !root.spriteItem || !plan) return
    cornerCompensation.stop()
    var scale = root.spriteItem.renderScale
    var cornerAnchor = root.projectedAnchorFor("corner", false)
    var currentOrigin = {
      x: root.motionItem.contactX + root.motionItem.reactionX - cornerAnchor.x * scale,
      y: root.motionItem.contactY + root.motionItem.reactionY - cornerAnchor.y * scale
    }
    var targetAction = root.actionForEdge(plan.targetEdge, plan.nextDirection)
    var targetMirror = root.mirrorFor(plan.targetEdge, plan.nextDirection)
    var targetAnchor = root.projectedAnchorFor(targetAction, targetMirror)
    root.motionItem.reactionX = currentOrigin.x
      - (root.motionItem.contactX - targetAnchor.x * scale)
    root.motionItem.reactionY = currentOrigin.y
      - (root.motionItem.contactY - targetAnchor.y * scale)
  }

  function finishWalk(token) {
    if (token !== root.generation || token !== root.actionGeneration
        || ["walk", "climb", "climbDown", "hang"].indexOf(root.petState) < 0) return
    walkAnimation.stop()
    root.spriteItem.playbackRequested = false
    root.motionItem.setNormalizedProgress(root.routeTargetU)
    if (root.pendingReaction) {
      root.enterIdle()
      return
    }
    if (root.routePlan && root.routePlan.turnaround) {
      root.startTurnOrCorner(root.routePlan, token)
      return
    }
    if (root.returningToRemembered && root.returnTargetU >= 0
        && Math.abs(root.motionItem.normalizedU - root.returnTargetU) < 0.0001) {
      root.returningToRemembered = false
      root.returnTargetU = -1
      root.savePosition()
    }
    root.enterIdle()
  }

  function returnFromSleep() {
    if (root.petState !== "sleep" || !root.active) return
    root.spriteItem.playbackRequested = false
    root.enterIdle()
  }

  function settleRememberedPositionForReducedMotion() {
    if (!root.returningToRemembered || root.returnTargetU < 0 || !root.motionItem) return
    root.motionItem.setNormalizedProgress(root.returnTargetU)
    root.returningToRemembered = false
    root.returnTargetU = -1
    root.savePosition()
  }

  function startReentry() {
    if (!root.active || !root.positionReadReady) return
    root.dragging = false
    root.dragGeneration = -1
    if (root.motionItem) {
      root.motionItem.reactionX = 0
      root.motionItem.reactionY = 0
    }
    root.generation++
    var token = root.generation
    root.stopAnimations()
    root.petPressActive = false
    root.nextState = "reenter"
    root.beginSequence("exit", "reenter", token)
  }

  function handleGeometryRemap(edgeName) {
    if (!root.active || !root.positionReadReady) return
    root.dragging = false
    root.dragGeneration = -1
    root.motionItem.reactionX = 0
    root.motionItem.reactionY = 0
    root.generation++
    var token = root.generation
    root.stopAnimations()
    root.routePlan = null
    root.petPressActive = false
    if (root.allowedEdges.indexOf(edgeName) < 0 || (root.effectiveRoaming === "Top edge" && edgeName !== "top")) {
      root.startReentry()
      return
    }
    root.savePosition()
    root.actionGeneration = token
    root.enterIdle()
  }

  function pointerIsOnSprite(x, y) {
    return root.spriteItem && x >= root.spriteItem.x && x <= root.spriteItem.x + root.spriteItem.width
      && y >= root.spriteItem.y && y <= root.spriteItem.y + root.spriteItem.height
  }

  function handlePetPress(pointerX, pointerY) {
    if (!root.interactionEnabled || !root.active) return
    if (!root.pointerIsOnSprite(pointerX, pointerY)) return
    if (root.petState === "sleep") {
      sleepTimeout.stop()
      root.enterIdle()
      return
    }
    if (["peek", "enter", "land", "exit", "success", "failure", "dance", "corner", "carried"].indexOf(root.petState) >= 0)
      return
    root.startPetting()
  }

  function startPetting() {
    root.generation++
    var token = root.generation
    root.stopAnimations()
    root.effectsItem.cancel()
    root.petPressActive = true
    root.petPressGeneration = token
    root.petPressedAt = Date.now()
    root.petState = "petting"
    root.actionGeneration = token
    root.nextState = "petting"
    var edge = root.motionItem ? root.motionItem.edge : "top"
    if (edge === "top") {
      root.spriteItem.actionName = root.actionForFamily(edge, "happy", "idle")
      root.spriteItem.playbackRequested = !root.reduceMotion
    } else {
      root.holdFamilyFrame(edge, edge === "bottom" ? "ledgeHappy" : "wallHappy")
    }
    root.spriteItem.restartSequence()
    pettingTimeout.interval = root.reduceMotion ? 600 : 6000
    pettingTimeout.restart()
  }

  function finishPettingTimeout() {
    if (root.petState !== "petting") return
    root.petPressActive = false
    root.enterIdle()
  }

  function endPetting(token) {
    if (token !== root.generation || !root.petPressActive || root.petState !== "petting") return
    root.petPressActive = false
    pettingTimeout.stop()
    root.spriteItem.playbackRequested = false
    if (!root.reduceMotion && Date.now() - root.lastHeartsAt >= 1500) {
      root.lastHeartsAt = Date.now()
      root.effectsItem.burst("hearts")
    }
    if (root.soundItem) root.soundItem.play("pet")
    root.showVoice("petting")
    root.savePosition()
    root.enterIdle()
  }

  function handlePetRelease() {
    if (root.dragging) { root.finishDrag(); return }
    if (!root.petPressActive || root.petPressGeneration !== root.generation) return
    root.endPetting(root.generation)
  }

  function beginDrag(pointerX, pointerY) {
    if (!root.petDrag || !root.petPressActive || root.dragging || !root.pointerIsOnSprite(pointerX, pointerY)) return
    root.generation++
    root.dragGeneration = root.generation
    root.petPressActive = false
    pettingTimeout.stop()
    root.dragging = true
    root.dragBaseContactX = root.motionItem.contactX
    root.dragBaseContactY = root.motionItem.contactY
    root.dragOffsetX = pointerX - root.spriteItem.x
    root.dragOffsetY = pointerY - root.spriteItem.y
    root.dragPointerX = pointerX
    root.dragPointerY = pointerY
    root.stopAnimations()
    root.petState = "carried"
    root.actionGeneration = root.generation
    root.spriteItem.actionName = "carried"
    root.spriteItem.playbackRequested = !root.reduceMotion
    root.spriteItem.restartSequence()
    root.updateDragReaction(pointerX, pointerY)
  }

  function updateDragReaction(pointerX, pointerY) {
    if (!root.dragging || !root.motionItem || !root.spriteItem) return
    root.dragPointerX = pointerX
    root.dragPointerY = pointerY
    var desiredX = pointerX - root.dragOffsetX
    var desiredY = pointerY - root.dragOffsetY
    root.motionItem.reactionX = desiredX - (root.motionItem.contactX - root.motionItem.anchorX)
    root.motionItem.reactionY = desiredY - (root.motionItem.contactY - root.motionItem.anchorY)
  }

  function finishDrag() {
    if (!root.dragging || !root.motionItem || !root.spriteItem) return
    var token = root.dragGeneration
    root.dragging = false
    root.spriteItem.playbackRequested = false
    var localX = root.dragPointerX - root.motionItem.localTerminalX
    var localY = root.dragPointerY - root.motionItem.localTerminalY
    var nearest = PetRoute.nearestEdgePoint(root.motionItem.terminalRect, root.allowedEdges, localX, localY)
    root.motionItem.setNormalizedProgress(nearest.u)
    var nearestStart = root.motionItem.edgeStartU(nearest.edge, root.motionItem.trackWidth,
      root.motionItem.trackHeight)
    var nearestEnd = root.motionItem.edgeEndU(nearest.edge, root.motionItem.trackWidth,
      root.motionItem.trackHeight)
    root.motionItem.direction = (nearest.u - nearestStart) / Math.max(0.000001, nearestEnd - nearestStart) < 0.5 ? 1 : -1
    var landingAction = root.actionFamily(nearest.edge) === "floor" ? "land"
      : (nearest.edge === "bottom" ? "hang" : "climb")
    root.holdFamilyFrame(nearest.edge, landingAction)
    root.updateDragReaction(root.dragPointerX, root.dragPointerY)
    root.dragGeneration = token
    var duration = nearest.distancePx > 160 ? 320 : 220
    if (root.reduceMotion) {
      root.motionItem.reactionX = 0
      root.motionItem.reactionY = 0
      root.finishDragLanding(token)
    } else {
      dropAnimation.duration = duration
      dropAnimation.restart()
    }
  }

  function finishDragLanding(token) {
    if (token !== root.dragGeneration || root.dragging || !root.active) return
    root.motionItem.reactionX = 0
    root.motionItem.reactionY = 0
    var edge = root.motionItem.edge
    root.savePosition()
    if (edge === "top") {
      root.beginSequence("land", "idle", token)
    } else {
      root.holdFamilyFrame(edge, edge === "bottom" ? "hang" : "climb")
      if (!root.reduceMotion) root.effectsItem.burst("land")
      if (root.soundItem) root.soundItem.play("land")
      root.enterIdle()
    }
  }

  function updatePointer(pointerX, pointerY) {
    root.pointerX = pointerX
    root.pointerY = pointerY
    if (root.dragging) {
      root.updateDragReaction(pointerX, pointerY)
      return
    }
    var delta = pointerX - (root.motionItem ? root.motionItem.contactX : pointerX)
    var zone = Math.abs(delta) < 10 ? 1 : (delta < 0 ? 0 : 2)
    if (zone !== root.pointerZone) {
      root.pointerZone = zone
      if (root.motionItem && root.motionItem.edge === "top" && zone !== 1) {
        root.motionItem.direction = zone === 2 ? 1 : -1
        root.renderMirror = root.mirrorFor("top", root.motionItem.direction)
      }
      hoverDwellTimer.restart()
    }
  }

  function noticeFromHover() {
    if (!root.interactionEnabled || !root.pointerInside || !root.active) return
    if (Date.now() - root.lastNoticeAt < 2000) return
    if (["idle", "walk", "sleep"].indexOf(root.petState) < 0) return
    root.lastNoticeAt = Date.now()
    sleepTimeout.stop()
    if (root.petState === "sleep") root.petState = "idle"
    var token = ++root.generation
    root.stopAnimations()
    if (root.reduceMotion) {
      root.petState = "notice"
      root.holdFamilyFrame(root.motionItem.edge, root.motionItem.edge === "top" ? "notice"
        : (root.motionItem.edge === "bottom" ? "hang" : "climb"))
      noticeHoldTimer.restart()
      return
    }
    if (root.motionItem.edge === "top") root.beginSequence("notice", "idle", token)
    else {
      root.petState = "notice"
      root.holdFamilyFrame(root.motionItem.edge, root.motionItem.edge === "bottom" ? "hang" : "climb")
      noticeHoldTimer.restart()
    }
  }

  function followPointerOnce() {
    if (root.petHoverHalo === "Off" || !root.pointerInside || root.reduceMotion
        || root.petState !== "idle" || Date.now() - root.lastFollowAt < 4000) return
    var localX = root.pointerX - root.motionItem.localTerminalX
    var localY = root.pointerY - root.motionItem.localTerminalY
    var nearest = PetRoute.nearestEdgePoint(root.motionItem.terminalRect, root.allowedEdges, localX, localY)
    if (!nearest || nearest.edge !== root.motionItem.edge
        || Math.abs(nearest.u - root.motionItem.normalizedU) < 0.0001) return
    root.lastFollowAt = Date.now()
    root.startRouteToward(nearest.u)
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
      } else if (root.surfaceReady) root.reveal()
    }
    function onPetActivityChanged() { root.armDecisionTimer() }
    function onPetInteractionChanged() {
      if (root.service && root.service.terminalVisible && root.service.petEnabled
          && root.service.petInteraction && typeof root.service.refreshGrabMargin === "function")
        root.service.refreshGrabMargin()
    }
    function onPetRoamingChanged() {
      if (root.active && root.petState !== "hidden"
          && root.effectiveRoaming === "Top edge" && root.motionItem.edge !== "top")
        root.startReentry()
    }
    function onPetSpeciesChanged() {
      root.invalidate()
      if (root.surfaceReady && root.active) root.reveal()
    }
    function onPetDragChanged() {
      if (!root.petDrag && root.dragging) {
        root.invalidate()
        if (root.surfaceReady && root.active) root.reveal()
      }
    }
    function onPetHoverHaloChanged() {
      hoverDwellTimer.stop()
    }
    function onPetRememberPositionChanged() {
      root.loadRememberedPosition()
      if (root.surfaceReady && root.active && root.petState === "hidden") root.reveal()
    }
    function onPetStateRevisionChanged() {
      if (root.petState === "hidden") {
        root.loadRememberedPosition()
        if (root.surfaceReady && root.active) root.reveal()
      }
    }
    function onReduceMotionChanged() {
      if (root.reduceMotion) {
        if (root.dragging) root.invalidate()
        else {
          root.stopAnimations()
          root.effectsItem.cancel()
        }
        if (root.active && root.positionReadReady) {
          root.settleRememberedPositionForReducedMotion()
          root.enterIdle()
        }
      } else if (root.surfaceReady) root.reveal()
    }
  }

  Connections {
    target: root.motionItem
    function onGeometryRemapped(edgeName) { root.handleGeometryRemap(edgeName) }
  }

  onSurfaceReadyChanged: {
    if (root.surfaceReady && root.active && root.petState === "hidden") root.reveal()
    else if (!root.surfaceReady) root.hide()
  }

  onActiveChanged: {
    if (!root.active) root.hide()
    else if (root.surfaceReady && root.petState === "hidden") root.reveal()
  }

  onAllowedEdgesChanged: {
    if (root.motionItem && root.allowedEdges.indexOf(root.motionItem.edge) < 0
        && root.active && root.petState !== "hidden") root.startReentry()
  }

  Timer {
    id: randomDecisionTimer
    interval: 3000
    repeat: false
    onTriggered: root.decideIdleAction()
  }

  Timer {
    id: sleepTimeout
    interval: 5000
    repeat: false
    onTriggered: root.returnFromSleep()
  }

  Timer {
    id: pettingTimeout
    interval: 6000
    repeat: false
    onTriggered: root.finishPettingTimeout()
  }

  Timer {
    id: turnFallbackTimer
    interval: 100
    repeat: false
    onTriggered: root.finishSequence(root.actionGeneration)
  }

  Timer {
    id: offFloorReactionTimer
    interval: 420
    repeat: false
    onTriggered: {
      if (root.petState === "success" || root.petState === "failure") root.enterIdle()
    }
  }

  Timer {
    id: noticeHoldTimer
    interval: 600
    repeat: false
    onTriggered: if (root.petState === "notice") root.enterIdle()
  }

  Timer {
    id: hoverExitTimer
    interval: 400
    repeat: false
    onTriggered: if (root.active && root.petState === "notice") root.enterIdle()
  }

  Timer {
    id: hoverDwellTimer
    interval: 600
    repeat: false
    onTriggered: root.followPointerOnce()
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
    duration: 1000
    easing.type: Easing.Linear
    onFinished: root.finishWalk(root.actionGeneration)
  }

  ParallelAnimation {
    id: cornerCompensation
    property int duration: 160
    NumberAnimation { target: root.motionItem; property: "reactionX"; to: 0; duration: cornerCompensation.duration; easing.type: Easing.Linear }
    NumberAnimation { target: root.motionItem; property: "reactionY"; to: 0; duration: cornerCompensation.duration; easing.type: Easing.Linear }
  }

  ParallelAnimation {
    id: dropAnimation
    property int duration: 220
    NumberAnimation { target: root.motionItem; property: "reactionX"; to: 0; duration: dropAnimation.duration; easing.type: Easing.OutQuad }
    NumberAnimation { target: root.motionItem; property: "reactionY"; to: 0; duration: dropAnimation.duration; easing.type: Easing.OutQuad }
    onFinished: root.finishDragLanding(root.dragGeneration)
  }

  PetMotion {
    id: petMotion
    anchors.fill: parent
    service: root.service
    hostScreen: root.hostScreen
    frameWidth: root.spriteItem ? root.spriteItem.width : 32
    frameHeight: root.spriteItem ? root.spriteItem.height : 32
    renderScale: root.spriteItem ? root.spriteItem.renderScale : 1
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
    visible: root.active && root.positionReadReady && root.petState !== "hidden"
    reducedMotion: root.reduceMotion
    mirrorFrame: root.renderMirror
  }

  Connections {
    target: root.spriteItem
    function onSequenceFinished() { root.finishSequence(root.actionGeneration) }
    function onFrameCursorChanged() {
      if (root.petState !== "turn" || !root.turning || !root.spriteItem.activeSequence) return
      var midpoint = Math.floor(root.spriteItem.activeSequence.frames.length / 2)
      if (root.spriteItem.frameCursor >= midpoint) root.renderMirror = root.pendingTurnMirror
    }
  }

  MouseArea {
    id: petMouseArea
    z: 3
    x: root.spriteItem ? root.spriteItem.x - root.hoverHaloExtent : 0
    y: root.spriteItem ? root.spriteItem.y - root.hoverHaloExtent : 0
    width: root.spriteItem ? root.spriteItem.width + 2 * root.hoverHaloExtent : 0
    height: root.spriteItem ? root.spriteItem.height + 2 * root.hoverHaloExtent : 0
    enabled: root.interactionEnabled
    acceptedButtons: Qt.LeftButton
    cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    hoverEnabled: true
    preventStealing: true
    onEntered: {
      root.pointerInside = true
      root.updatePointer(petMouseArea.x + mouseX, petMouseArea.y + mouseY)
      root.noticeFromHover()
    }
    onExited: {
      root.pointerInside = false
      hoverDwellTimer.stop()
      hoverExitTimer.restart()
    }
    onPositionChanged: {
      var pointerX = petMouseArea.x + mouse.x
      var pointerY = petMouseArea.y + mouse.y
      root.updatePointer(pointerX, pointerY)
      if (petMouseArea.pressed && !root.dragging && root.petPressActive
          && Math.sqrt(Math.pow(pointerX - root.dragPressX, 2)
            + Math.pow(pointerY - root.dragPressY, 2)) > 8)
        root.beginDrag(pointerX, pointerY)
    }
    onPressed: {
      var pointerX = petMouseArea.x + mouse.x
      var pointerY = petMouseArea.y + mouse.y
      root.dragPressX = pointerX
      root.dragPressY = pointerY
      root.handlePetPress(pointerX, pointerY)
    }
    onReleased: root.handlePetRelease()
  }

  PetEffects {
    id: petEffects
    anchors.fill: parent
    originX: root.motionItem ? root.motionItem.contactX : 0
    originY: root.motionItem ? root.motionItem.contactY : 0
    reducedMotion: root.reduceMotion
    spriteX: root.spriteItem ? root.spriteItem.x : 0
    spriteY: root.spriteItem ? root.spriteItem.y : 0
    spriteWidth: root.spriteItem ? root.spriteItem.width : 32
    spriteHeight: root.spriteItem ? root.spriteItem.height : 32
    z: 2
  }

  Loader {
    id: petSoundLoader
    active: root.active && root.petSound !== "Off"
    sourceComponent: Component {
      PetSound {
        level: root.petSound
        reducedMotion: root.reduceMotion
      }
    }
    onLoaded: root.soundItem = item
    onActiveChanged: if (!active) root.soundItem = null
  }

  FileView {
    id: voiceFile
    path: root.petVoice === "Off" ? "" : Qt.resolvedUrl("assets/voice/lines.json").toString().replace(/^file:\/\//, "")
    watchChanges: false
    printErrors: false
    onTextChanged: {
      try {
        var parsed = JSON.parse(text() || "")
        var report = PetVoice.validateDocument(parsed)
        root.voiceReady = report.valid
        root.voiceLines = report.valid ? parsed : null
      } catch (e) {
        root.voiceReady = false
        root.voiceLines = null
      }
    }
  }

  onPetVoiceChanged: {
    root.voiceReady = false
    root.voiceLines = null
    if (root.petVoice !== "Off") voiceFile.reload()
    else if (root.effectsItem) root.effectsItem.dismissBubble()
  }
}
