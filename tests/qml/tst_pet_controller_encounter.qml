import QtQuick
import QtTest

TestCase {
  name: "PetControllerEncounter"

  QtObject {
    id: screen
    property string name: "test-output"
    property real x: 0
    property real y: 0
    property real width: 1200
    property real height: 800
  }

  QtObject {
    id: service
    property bool petEnabled: true
    property string petSpecies: "Penguin"
    property string petActivity: "Always while visible"
    property bool reduceMotion: false
    property bool petInteraction: true
    property string petRoaming: "Top edge"
    property bool petDrag: true
    property string petHoverHalo: "Off"
    property string petVoice: "Off"
    property string petSound: "Off"
    property bool petRememberPosition: false
    property bool petVillains: true
    property bool terminalVisible: true
    property var terminalMonitor: screen
    property rect terminalRect: Qt.rect(300, 80, 600, 400)
    property bool grabMarginReady: true
    property bool commandTracking: true
    property bool commandIntegrationInstalled: true
    property bool eventReplayReady: true
    property string commandLatestFinishKey: "seed"
    property string commandLatestResult: ""
    property bool commandLatestQualifies: true
    property int commandLatestStatus: 1
    property int commandLatestDurationMs: 6000
    property var bondEvents: []
    function bondValue(species) { return 0 }
    function bondPeakTier(species) { return 0 }
    function queueBondDelta(species, kind) {
      bondEvents = bondEvents.concat([{ species: species, kind: kind }])
      return true
    }
    function savePetState(snapshot, owner, immediate) {}
  }

  QtObject {
    id: encounterStub
    property bool running: false
    property string stage: "idle"
    property string diagnostic: ""
    property int beginCount: 0
    property int successCount: 0
    function begin(kind, status, token) {
      beginCount++
      stage = "appear"
      running = true
      return true
    }
    function interrupt() {
      running = false
      stage = "idle"
    }
    function successArrived() { successCount++ }
  }

  property var controllerObject: null

  function initTestCase() {
    var component = Qt.createComponent(Qt.resolvedUrl("../../PetController.qml"),
      Component.PreferSynchronous)
    if (component.status === Component.Error) return
    controllerObject = component.createObject(null, {
      width: screen.width,
      height: screen.height,
      service: service,
      hostScreen: screen,
      surfaceReady: true,
      encounterItem: encounterStub
    })
    if (!controllerObject) return
    tryCompare(controllerObject.spriteItem, "assetReady", true, 1500)
    controllerObject.petState = "idle"
    controllerObject.actionGeneration = controllerObject.generation
    controllerObject.lastObservedFinishKey = service.commandLatestFinishKey
  }

  function test_failure_routes_to_encounter_and_success_is_consumed() {
    if (!controllerObject) {
      skip("PetController requires the Quickshell runtime plugin")
      return
    }
    service.commandLatestResult = "failed"
    service.commandLatestStatus = 1
    service.commandLatestFinishKey = "failure-1"
    tryCompare(encounterStub, "running", true, 200)
    compare(encounterStub.beginCount, 1)
    compare(controllerObject.petState, "encounter")
    compare(controllerObject.pendingReaction, "")

    encounterStub.stage = "cower"
    service.commandLatestResult = "succeeded"
    service.commandLatestStatus = 0
    service.commandLatestFinishKey = "success-1"
    tryCompare(encounterStub, "successCount", 1, 200)
    compare(service.bondEvents.length, 1)
    compare(service.bondEvents[0].kind, "celebration")
    compare(controllerObject.pendingReaction, "")

    controllerObject.invalidate()
    compare(encounterStub.running, false)
    compare(controllerObject.petState, "hidden")
  }

  function cleanupTestCase() {
    if (controllerObject) controllerObject.destroy()
  }
}
