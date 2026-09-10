import QtQuick
import "PetRoute.js" as PetRoute
import "PetEncounter.js" as EncounterMath

// One encounter lives inside the existing PetLayer surface. It owns the
// villain sprite, its bounded timers, and the hand-off callbacks to the pet
// controller; it deliberately creates no PanelWindow of its own.
Item {
  id: root

  property var controller: null
  property var service: null
  property var hostScreen: null
  property bool running: false
  property string stage: "idle"
  property string villainKind: "bug"
  property string villainStatus: ""
  property int token: -1
  property string outcome: ""
  property bool rerollUsed: false
  property double deadlineAt: 0
  property double lastVillainTauntAt: 0
  property real spawnU: 0
  property real standoffU: 0
  property int spawnSide: -1
  property real spawnDistancePx: 0
  property var approachPlan: null

  readonly property var villainSpriteItem: villainSprite
  readonly property bool inputEnabled: root.running && root.controller
    && root.controller.interactionEnabled === true && villainSprite.visible
    && villainSprite.assetReady && root.stage !== "loading"
  readonly property string diagnostic: root.running && root.stage !== "idle"
    ? "Encounter: " + root.stage : ""

  function logDebug(message) {
    if (root.service && root.service.debugEnabled)
      console.log("Dropdown Terminal [debug]: encounter " + message)
  }

  function validToken(value) {
    return root.running && root.controller && Number(value) === Number(root.token)
      && Number(root.controller.generation) === Number(root.token)
  }

  function clamp(value, low, high) {
    return Math.max(low, Math.min(high, Number(value)))
  }

  function nextRandom() {
    return root.controller && typeof root.controller.nextRandom === "function"
      ? root.controller.nextRandom() : Math.random()
  }

  function petContactX() {
    if (!root.controller || !root.controller.motionItem) return 0
    return Number(root.controller.motionItem.contactX - root.controller.motionItem.localTerminalX)
  }

  function topUForX(localX) {
    var width = Math.max(1, Number(villainMotion.trackWidth))
    return villainMotion.topEdgeStartU + clamp(localX / width, 0, 1)
      * (villainMotion.topEdgeEndU - villainMotion.topEdgeStartU)
  }

  function villainSpeed() {
    var action = villainSprite.actions && villainSprite.actions.walk
    if (!action || !Array.isArray(action.durations) || action.durations.length === 0) return 20
    var cycle = action.durations.reduce(function(total, value) { return total + Number(value) }, 0)
    var speed = Number(action.stride || 10) * Number(villainSprite.renderScale || 1) * 1000 / cycle
    return isFinite(speed) && speed > 0 ? speed : 20
  }

  function chooseSpawn() {
    var petX = petContactX()
    var width = Math.max(1, Number(villainMotion.trackWidth))
    var leftRoom = petX
    var rightRoom = width - petX
    var preferred = root.controller && root.controller.motionItem
      && Number(root.controller.motionItem.direction) >= 0 ? -1 : 1
    var preferredRoom = preferred < 0 ? leftRoom : rightRoom
    var otherRoom = preferred < 0 ? rightRoom : leftRoom
    var side = preferred
    var room = preferredRoom
    if (room < 120 && otherRoom >= 120) {
      side = -preferred
      room = otherRoom
    }
    var distance = EncounterMath.spawnDistance(villainSpeed(), room)
    if (distance <= 0) return null
    return { side: side, room: room, distance: distance, petX: petX,
      startX: petX + side * distance, targetX: petX + side * 64 }
  }

  function setAction(sprite, action, playback) {
    if (!sprite) return
    sprite.actionName = action
    sprite.playbackRequested = playback !== false
    sprite.restartSequence()
  }

  function begin(kind, status, encounterToken) {
    if (root.running || !root.controller || Number(encounterToken) !== Number(root.controller.generation)) return false
    root.villainKind = ["bug", "ghost"].indexOf(String(kind)) >= 0 ? String(kind) : "bug"
    root.villainStatus = String(status || "")
    root.token = Number(encounterToken)
    root.outcome = ""
    root.rerollUsed = false
    root.lastVillainTauntAt = 0
    root.approachPlan = null
    root.deadlineAt = Date.now() + EncounterMath.MAX_ENCOUNTER_MS
    root.running = true
    root.stage = "loading"
    deadlineTimer.restart()
    loadingTimer.restart()
    if (villainSprite.assetReady) root.startLoadedEncounter()
    else root.logDebug("waiting for " + root.villainKind + " asset")
    return true
  }

  function startLoadedEncounter() {
    if (!root.validToken(root.token) || root.stage !== "loading" || !villainSprite.assetReady) return
    loadingTimer.stop()
    var spawn = root.chooseSpawn()
    if (!spawn) {
      root.stopAll()
      root.running = false
      root.stage = "idle"
      if (root.controller && typeof root.controller.finishEncounter === "function")
        root.controller.finishEncounter("no-room", root.token)
      return
    }
    root.spawnSide = spawn.side
    root.spawnDistancePx = spawn.distance
    root.spawnU = root.topUForX(spawn.startX)
    root.standoffU = root.topUForX(spawn.targetX)
    root.stage = "appear"
    villainMotion.direction = spawn.side < 0 ? 1 : -1
    villainMotion.setNormalizedProgress(root.spawnU)
    villainSprite.mirrorFrame = villainMotion.direction < 0
    root.setAction(villainSprite, "appear", true)
    if (root.controller && typeof root.controller.showEncounterVoice === "function")
      root.controller.showEncounterVoice("villainAppear", root.villainKind)
    if (root.controller && typeof root.controller.playEncounterSound === "function")
      root.controller.playEncounterSound("villain")
    stageTimer.interval = EncounterMath.budgetTable.appear
    stageTimer.restart()
    root.logDebug("begin kind=" + root.villainKind + " distance=" + root.spawnDistancePx)
  }

  function startApproach() {
    if (!root.validToken(root.token) || root.stage !== "appear") return
    stageTimer.stop()
    root.stage = "approach"
    root.setAction(villainSprite, "walk", true)
    var action = villainSprite.actions.walk || {}
    var plan = PetRoute.planStep({
      edge: "top", u: root.spawnU, direction: villainMotion.direction,
      roamingMode: "Top edge", allowedEdges: ["top"],
      terminalRect: villainMotion.terminalRect, stride: Number(action.stride || 10),
      renderScale: villainSprite.renderScale, durations: action.durations || [125, 125],
      towardU: root.standoffU, maxDistance: Math.max(0, root.spawnDistancePx - 64),
      towardDirection: villainMotion.direction,
      random: { step: 0.5, turn: 0.99 }
    })
    root.approachPlan = plan
    approachAnimation.from = root.spawnU
    approachAnimation.to = plan.targetU
    approachAnimation.duration = Math.min(EncounterMath.budgetTable.approach,
      Math.max(1, Number(plan.durationMs || 1)))
    approachTimeout.restart()
    if (approachAnimation.duration <= 1) root.finishApproach("arrived")
    else approachAnimation.restart()
  }

  function finishApproach(reason) {
    if (!root.validToken(root.token) || root.stage !== "approach") return
    approachAnimation.stop()
    approachTimeout.stop()
    if (reason === "timeout") {
      var petX = root.controller && root.controller.motionItem
        ? Number(root.controller.motionItem.contactX) : 0
      var separation = Math.abs(Number(villainMotion.contactX) - petX)
      if (separation < 32) {
        root.startVanishWithoutRecord()
        return
      }
    }
    villainMotion.setNormalizedProgress(root.approachPlan ? root.approachPlan.targetU : root.standoffU)
    root.startStandoff()
  }

  function startStandoff() {
    if (!root.validToken(root.token)) return
    root.stage = "standoff"
    root.setAction(villainSprite, "taunt", true)
    if (root.controller && typeof root.controller.beginEncounterSequence === "function")
      root.controller.beginEncounterSequence("alert", root.token)
    stageTimer.interval = 1200 + Math.floor(root.nextRandom() * 801)
    stageTimer.restart()
  }

  function startResolve() {
    if (!root.validToken(root.token) || root.stage !== "standoff") return
    stageTimer.stop()
    var bond = root.controller && typeof root.controller.currentBond === "function"
      ? root.controller.currentBond() : 0
    var branch = EncounterMath.resolve(bond, root.nextRandom(), false)
    if (branch === "brave") root.startBrave()
    else root.startCower()
  }

  function startBrave() {
    if (!root.validToken(root.token)) return
    stageTimer.stop()
    root.stage = "brave"
    root.setAction(villainSprite, "taunt", true)
    if (root.controller && typeof root.controller.beginEncounterSequence === "function")
      root.controller.beginEncounterSequence("brave", root.token)
    resolutionTimer.interval = EncounterMath.budgetTable.brave
    resolutionTimer.restart()
  }

  function startCower() {
    if (!root.validToken(root.token)) return
    root.stage = "cower"
    root.setAction(villainSprite, "taunt", true)
    if (root.controller && typeof root.controller.beginEncounterSequence === "function")
      root.controller.beginEncounterSequence("cower", root.token)
    stageTimer.interval = EncounterMath.budgetTable.cower
    stageTimer.restart()
  }

  function startVictory(assisted, brave) {
    if (!root.validToken(root.token) || root.outcome !== "") return
    // A precise success can arrive during appear, approach, or cower. Stop
    // every pending stage callback before the victory cleanup timer takes
    // ownership, otherwise a late timeout could turn a win into a loss.
    stageTimer.stop()
    approachAnimation.stop()
    approachTimeout.stop()
    root.outcome = assisted ? "assisted" : "won"
    root.stage = "victory"
    var villainAction = brave ? "defeated" : "flee"
    root.setAction(villainSprite, villainAction, true)
    if (root.controller && typeof root.controller.beginEncounterSequence === "function")
      root.controller.beginEncounterSequence("victory", root.token)
    if (root.controller && typeof root.controller.showEncounterVoice === "function")
      root.controller.showEncounterVoice(assisted ? "assisted" : "victory", root.villainKind)
    if (root.controller && typeof root.controller.playEncounterSound === "function")
      root.controller.playEncounterSound("victory")
    // Leave enough time for the bundled pet victory sequence to emit its
    // success burst before cleanup, while keeping the success path well under
    // the encounter deadline.
    resolutionTimer.interval = assisted ? EncounterMath.budgetTable.assisted
      : EncounterMath.budgetTable.vanish
    resolutionTimer.restart()
  }

  function startDefeat() {
    if (!root.validToken(root.token) || root.outcome !== "") return
    root.outcome = "lost"
    root.stage = "defeat"
    root.setAction(villainSprite, "vanish", true)
    if (root.controller && typeof root.controller.beginEncounterSequence === "function")
      root.controller.beginEncounterSequence("failure", root.token)
    if (root.controller && typeof root.controller.showEncounterVoice === "function")
      root.controller.showEncounterVoice("defeat", root.villainKind)
    resolutionTimer.interval = EncounterMath.budgetTable.defeat
    resolutionTimer.restart()
  }

  function startVanishWithoutRecord() {
    if (!root.validToken(root.token)) return
    root.outcome = "skip"
    root.stage = "vanish"
    root.setAction(villainSprite, "vanish", true)
    resolutionTimer.interval = EncounterMath.budgetTable.vanish
    resolutionTimer.restart()
  }

  function deadlineReached() {
    if (!root.validToken(root.token)) return
    var result = root.stage === "loading" ? "unavailable" : (root.outcome || "deadline")
    root.stopAll()
    root.running = false
    root.stage = "idle"
    if (root.controller && typeof root.controller.finishEncounter === "function")
      root.controller.finishEncounter(result, root.token)
  }

  function finishResolution() {
    if (!root.validToken(root.token)) return
    var result = root.outcome || "skip"
    root.stopAll()
    root.running = false
    root.stage = "idle"
    if (root.controller && typeof root.controller.finishEncounter === "function")
      root.controller.finishEncounter(result, root.token)
  }

  function stopAll() {
    deadlineTimer.stop()
    loadingTimer.stop()
    stageTimer.stop()
    approachTimeout.stop()
    resolutionTimer.stop()
    approachAnimation.stop()
    villainSprite.playbackRequested = false
  }

  function interrupt() {
    var wasRunning = root.running
    root.stopAll()
    root.running = false
    root.stage = "idle"
    root.outcome = "interrupt"
    if (wasRunning) root.logDebug("interrupted")
  }

  function petPressed() {
    if (!root.validToken(root.token) || root.stage !== "cower") return true
    if (root.rerollUsed || !EncounterMath.rerollAllowed(root.deadlineAt - Date.now())) return true
    root.rerollUsed = true
    var bond = root.controller && typeof root.controller.currentBond === "function"
      ? root.controller.currentBond() : 0
    var branch = EncounterMath.resolve(bond, root.nextRandom(), true)
    if (branch === "brave") root.startBrave()
    return true
  }

  function villainPressed() {
    if (!root.validToken(root.token)) return true
    if (root.stage === "cower") root.startVictory(true, false)
    return true
  }

  function successArrived() {
    if (!root.validToken(root.token) || root.outcome !== "") return true
    if (["loading", "appear", "approach", "standoff", "cower"].indexOf(root.stage) >= 0)
      root.startVictory(false, false)
    return true
  }

  function villainHovered() {
    if (!root.validToken(root.token)) return
    if (Date.now() - root.lastVillainTauntAt < 3000) return
    root.lastVillainTauntAt = Date.now()
    if (root.stage === "standoff" || root.stage === "cower")
      root.setAction(villainSprite, "taunt", true)
  }

  function petSequenceFinished(action, sequenceToken) {
    if (!root.validToken(sequenceToken)) return
    if (root.stage === "brave" && action === "brave") root.startVictory(false, true)
  }

  Timer {
    id: deadlineTimer
    interval: EncounterMath.MAX_ENCOUNTER_MS
    repeat: false
    onTriggered: root.deadlineReached()
  }

  Timer {
    id: loadingTimer
    interval: 1000
    repeat: false
    onTriggered: {
      if (!root.validToken(root.token) || root.stage !== "loading") return
      root.stopAll()
      root.running = false
      root.stage = "idle"
      if (root.controller && typeof root.controller.finishEncounter === "function")
        root.controller.finishEncounter("unavailable", root.token)
    }
  }

  Timer {
    id: stageTimer
    repeat: false
    onTriggered: {
      if (root.stage === "appear") root.startApproach()
      else if (root.stage === "standoff") root.startResolve()
      else if (root.stage === "cower") root.startDefeat()
    }
  }

  Timer {
    id: approachTimeout
    interval: EncounterMath.budgetTable.approach
    repeat: false
    onTriggered: root.finishApproach("timeout")
  }

  Timer {
    id: resolutionTimer
    repeat: false
    onTriggered: {
      if (root.stage === "brave") root.startVictory(false, true)
      else root.finishResolution()
    }
  }

  NumberAnimation {
    id: approachAnimation
    target: villainMotion
    property: "travelU"
    easing.type: Easing.Linear
    onFinished: root.finishApproach("arrived")
  }

  Connections {
    target: villainSprite
    function onAssetReadyChanged() {
      if (root.running && root.stage === "loading" && villainSprite.assetReady)
        root.startLoadedEncounter()
    }
  }

  PetMotion {
    id: villainMotion
    anchors.fill: parent
    service: root.service
    hostScreen: root.hostScreen
    frameWidth: villainSprite.width > 0 ? villainSprite.width / Math.max(1, villainSprite.renderScale) : 32
    frameHeight: villainSprite.height > 0 ? villainSprite.height / Math.max(1, villainSprite.renderScale) : 32
    renderScale: villainSprite.renderScale
    anchorX: villainSprite.projectedAnchorX * villainSprite.renderScale
    anchorY: villainSprite.anchorY * villainSprite.renderScale
  }

  PetSprite {
    id: villainSprite
    kind: "villain"
    species: root.villainKind
    actionName: "idle"
    reducedMotion: root.controller ? root.controller.reduceMotion : false
    visible: root.running
    width: frameWidth * renderScale
    height: frameHeight * renderScale
    x: villainMotion.spriteX
    y: villainMotion.spriteY
    mirrorFrame: villainMotion.direction < 0
  }

  MouseArea {
    id: villainMouseArea
    z: 4
    x: villainSprite.x
    y: villainSprite.y
    width: villainSprite.width
    height: villainSprite.height
    enabled: root.inputEnabled
    acceptedButtons: Qt.LeftButton
    hoverEnabled: true
    preventStealing: true
    cursorShape: Qt.PointingHandCursor
    onEntered: root.villainHovered()
    onPressed: root.villainPressed()
  }
}
