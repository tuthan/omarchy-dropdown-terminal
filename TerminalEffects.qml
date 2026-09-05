import QtQuick
import QtQuick.Particles
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons

// Decorative entrance treatment for the terminal. This component is loaded
// once per bar/output by BarWidget, but only the output named by the live
// terminal monitor ever maps its surface.
//
// The surface is intentionally full-screen and has an empty input region.
// Its children paint only the terminal's gutter, so clicks and keystrokes
// continue to belong to the terminal throughout the effect.
Item {
  id: root

  property var service: null
  property var hostScreen: null

  property bool playing: false
  property bool waitingForSettle: false
  property bool lastTerminalVisible: false
  property bool observationInitialized: false
  property string lastTerminalMonitorName: ""
  property bool emitterArmed: false
  property int generation: 0
  property int pendingGeneration: 0
  property int stableSamples: 0
  property double settleDeadline: 0
  property rect lastSettledRect: Qt.rect(0, 0, 0, 0)
  property real progress: 0
  property real hyprlandRounding: Style.cornerRadius
  property bool roundingLoaded: false

  readonly property rect terminalRect: service ? service.terminalRect : Qt.rect(0, 0, 0, 0)
  readonly property var terminalMonitor: service ? service.terminalMonitor : null
  readonly property bool terminalGeometryValid: terminalRect.width > 0 && terminalRect.height > 0
  readonly property bool hostMatchesTerminal: !!hostScreen && !!terminalMonitor
    && String(hostScreen.name || "") === String(terminalMonitor.name || "")
  readonly property real intensity: service ? Math.max(0, Math.min(100, service.effectIntensity)) / 100 : 0.5
  readonly property int effectDuration: 760
  readonly property int gutter: Math.max(Style.space(12), Math.round(Style.space(18) * (0.75 + intensity * 0.5)))
  readonly property real localTerminalX: hostScreen ? terminalRect.x - hostScreen.x : 0
  readonly property real localTerminalY: hostScreen ? terminalRect.y - hostScreen.y : 0
  readonly property real finalLocalY: Math.max(24, (hostScreen ? hostScreen.height : 0) * 0.04)
  readonly property real cornerRadius: {
    var queried = Number(hyprlandRounding)
    if (isFinite(queried) && queried >= 0) return queried
    var fallback = Number(Style.cornerRadius)
    return isFinite(fallback) && fallback >= 0 ? fallback : 0
  }
  readonly property real fadeProgress: {
    if (progress <= 0) return 0
    if (progress < 0.16) return progress / 0.16
    return Math.max(0, 1 - (progress - 0.16) / 0.84)
  }
  readonly property real coreOpacity: fadeProgress * intensity * (0.45 + intensity * 0.55)
  readonly property real haloOpacity: fadeProgress * intensity * (0.08 + intensity * 0.24)
  readonly property int sparkCount: Math.min(12, Math.max(0, Math.round(intensity * 12)))
  readonly property real sparkRate: sparkCount > 0 ? sparkCount * 8 : 0
  readonly property int sparkLifeSpan: 360 + Math.round(intensity * 180)
  readonly property int sparkWindowMs: 120 + Math.round((1 - intensity) * 50)
  readonly property real sparkSize: Math.max(Style.space(2), Style.space(3) + intensity * Style.space(2))
  readonly property real sparkSpeed: Style.space(28) + intensity * Style.space(34)

  // Hyprland accepts rgb(rrggbb) / rgba(rrggbbaa) for the existing terminal
  // border setting. Theme remains the authority when the setting is "theme".
  function configuredColor(raw) {
    var value = String(raw || "theme")
    var match = value.match(/^(rgb|rgba)\(([0-9a-fA-F]{6}|[0-9a-fA-F]{8})\)$/)
    if (!match) return Color.accent
    var hex = match[2]
    var channel = function(offset) { return parseInt(hex.substring(offset, offset + 2), 16) / 255 }
    return hex.length === 8
      ? Qt.rgba(channel(0), channel(2), channel(4), channel(6))
      : Qt.rgba(channel(0), channel(2), channel(4), 1)
  }

  readonly property color effectColor: configuredColor(service ? service.borderColor : "theme")

  function parseRounding(raw) {
    var fallbackValue = Number(Style.cornerRadius)
    var fallback = isFinite(fallbackValue) && fallbackValue >= 0 ? fallbackValue : 0
    try {
      var parsed = JSON.parse(String(raw || ""))
      var candidate = parsed && parsed.int !== undefined ? parsed.int
        : (parsed && parsed.value !== undefined ? parsed.value : (parsed ? parsed.str : undefined))
      var value = Number(candidate)
      return isFinite(value) && value >= 0 ? value : fallback
    } catch (e) {
      return fallback
    }
  }

  function loadRounding() {
    if (root.roundingLoaded || roundingProcess.running) return
    roundingProcess.running = true
  }

  function sameRect(left, right) {
    return Math.abs(left.x - right.x) <= 1 && Math.abs(left.y - right.y) <= 1
      && Math.abs(left.width - right.width) <= 1 && Math.abs(left.height - right.height) <= 1
  }

  function beginSettleWait() {
    if (!root.service || !root.service.terminalVisible || !root.hostMatchesTerminal) {
      root.cancelEffect()
      return
    }
    if (root.playing) root.cancelEffect()
    root.generation++
    root.pendingGeneration = root.generation
    root.waitingForSettle = true
    root.stableSamples = 0
    root.lastSettledRect = Qt.rect(0, 0, 0, 0)
    root.settleDeadline = Date.now() + 1400
    settleTimer.restart()
  }

  function observeTerminalVisibility() {
    if (!root.service) return
    var visible = root.service.terminalVisible === true
    if (!visible) {
      root.lastTerminalVisible = false
      if (root.waitingForSettle || root.playing) root.cancelEffect()
      return
    }
    if (!root.lastTerminalVisible)
      root.beginSettleWait()
    root.lastTerminalVisible = true
  }

  function observeTerminalMonitor() {
    if (!root.service || !root.observationInitialized) return
    var monitor = root.service.terminalMonitor
    var monitorName = monitor ? String(monitor.name || "") : ""
    var changed = monitorName !== root.lastTerminalMonitorName
    root.lastTerminalMonitorName = monitorName
    if (!changed) return
    if (root.service.terminalVisible === true)
      root.beginSettleWait()
    else if (root.waitingForSettle || root.playing)
      root.cancelEffect()
  }

  function checkSettlement(token) {
    if (token !== root.generation || !root.waitingForSettle || !root.service) return
    if (!root.service.terminalVisible || !root.hostScreen) {
      root.cancelEffect()
      return
    }

    // This is a bounded, in-process model refresh. It is used only while a
    // newly visible terminal is being claimed by a potential visual effect;
    // the continuous 4 Hz refresh is armed only after the effect maps.
    root.service.refreshToplevels()
    var current = root.terminalRect
    if (!root.terminalGeometryValid) {
      if (Date.now() >= root.settleDeadline) root.cancelEffect()
      else settleTimer.restart()
      return
    }

    if (sameRect(current, root.lastSettledRect)) root.stableSamples++
    else root.stableSamples = 0
    root.lastSettledRect = current

    var atFinalPosition = Math.abs((current.y - root.hostScreen.y) - root.finalLocalY) <= 3
    var stable = root.stableSamples >= 1
    var slideFromTop = root.service.slideFromTop === true
    if (stable && (!slideFromTop || atFinalPosition)) {
      root.startEffect(token)
      return
    }

    // If a compositor configuration makes the planned top margin slightly
    // different, a stable live rectangle is still safer than losing the
    // decorative transition entirely. This remains bounded to one summon.
    if (stable && Date.now() >= root.settleDeadline) {
      root.startEffect(token)
      return
    }
    if (Date.now() >= root.settleDeadline) {
      root.cancelEffect()
      return
    }
    settleTimer.restart()
  }

  function startEffect(token) {
    if (token !== root.generation || !root.waitingForSettle || !root.terminalGeometryValid
        || !root.hostMatchesTerminal || !root.service.terminalVisible) return
    root.waitingForSettle = false
    settleTimer.stop()
    root.progress = 0
    root.playing = true
    root.emitterArmed = root.sparkCount > 0
    root.loadRounding()
    particleSystem.reset()
    particleSystem.start()
    if (root.sparkCount > 0) sparkStopTimer.restart()
    progressAnimation.restart()
  }

  function finishEffect(token) {
    if (token !== root.generation) return
    progressAnimation.stop()
    root.playing = false
    root.emitterArmed = false
    sparkStopTimer.stop()
    particleSystem.stop()
    particleSystem.reset()
    root.progress = 1
  }

  function cancelEffect() {
    root.generation++
    root.pendingGeneration = root.generation
    root.waitingForSettle = false
    root.playing = false
    root.emitterArmed = false
    settleTimer.stop()
    sparkStopTimer.stop()
    progressAnimation.stop()
    particleSystem.stop()
    particleSystem.reset()
    root.progress = 0
  }

  Component.onCompleted: {
    root.lastTerminalVisible = root.service ? root.service.terminalVisible === true : false
    root.lastTerminalMonitorName = root.service && root.service.terminalMonitor
      ? String(root.service.terminalMonitor.name || "") : ""
    root.observationInitialized = true
  }

  Connections {
    target: root.service
    function onTerminalVisibleChanged() { root.observeTerminalVisibility() }
    function onTerminalMonitorChanged() { root.observeTerminalMonitor() }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && String(event.name || "") === "configreloaded") {
        root.roundingLoaded = false
        if (root.playing) root.loadRounding()
      }
    }
  }

  Timer {
    id: settleTimer
    interval: 250
    repeat: false
    onTriggered: root.checkSettlement(root.pendingGeneration)
  }

  Timer {
    id: geometryTimer
    interval: 250
    repeat: true
    running: root.playing
    onTriggered: {
      if (!root.service || !root.service.terminalVisible || !root.hostMatchesTerminal) {
        root.cancelEffect()
        return
      }
      root.service.refreshToplevels()
    }
  }

  Timer {
    id: sparkStopTimer
    interval: root.sparkWindowMs
    repeat: false
    onTriggered: root.emitterArmed = false
  }

  NumberAnimation {
    id: progressAnimation
    target: root
    property: "progress"
    from: 0
    to: 1
    duration: root.effectDuration
    easing.type: Easing.OutCubic
    onFinished: root.finishEffect(root.generation)
  }

  Process {
    id: roundingProcess
    command: ["hyprctl", "-j", "getoption", "decoration:rounding"]
    stdout: StdioCollector { id: roundingOutput; waitForEnd: true }
    onExited: {
      root.hyprlandRounding = root.parseRounding(roundingOutput.text)
      root.roundingLoaded = true
    }
  }

  PanelWindow {
    id: panel
    screen: root.hostScreen
    visible: root.playing && root.hostMatchesTerminal && root.terminalGeometryValid
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    updatesEnabled: root.playing

    WlrLayershell.namespace: "io.github.tuthan.dropdown-terminal.entrance-effect"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // The overlay is decorative. An empty region is what makes transparent
    // pixels and the visible outline click-through to the terminal below.
    mask: Region {}

    Item {
      id: effectBounds
      x: root.localTerminalX - root.gutter
      y: root.localTerminalY - root.gutter
      width: root.terminalRect.width + root.gutter * 2
      height: root.terminalRect.height + root.gutter * 2
      visible: root.terminalGeometryValid

      // Multiple flat rings provide a soft additive halo without a per-frame
      // blur FBO. All dimensions and opacity remain bounded by host tokens and
      // the user's intensity setting.
      Rectangle {
        anchors.fill: parent
        radius: root.cornerRadius + root.gutter
        color: "transparent"
        border.width: Math.max(1, Style.space(2))
        border.color: root.effectColor
        opacity: root.haloOpacity * 0.55
      }

      Rectangle {
        anchors.fill: parent
        anchors.margins: Math.max(1, Math.round(root.gutter * 0.36))
        radius: root.cornerRadius + Math.max(0, Math.round(root.gutter * 0.64))
        color: "transparent"
        border.width: Math.max(1, Style.space(2))
        border.color: root.effectColor
        opacity: root.haloOpacity
      }

      Rectangle {
        x: root.gutter
        y: root.gutter
        width: root.terminalRect.width
        height: root.terminalRect.height
        radius: root.cornerRadius
        color: "transparent"
        border.width: Math.max(1, Style.space(2))
        border.color: root.effectColor
        opacity: root.coreOpacity
      }

      ParticleSystem {
        id: particleSystem
        anchors.fill: parent
        running: root.playing
        visible: root.playing

        Emitter {
          id: emitter
          // Emit only in the upper gutter so particles never cover terminal
          // text. maximumEmitted and the stop timer make the burst finite.
          x: 0
          y: 0
          width: parent.width
          height: root.gutter
          enabled: root.emitterArmed
          emitRate: root.sparkRate
          maximumEmitted: root.sparkCount
          lifeSpan: root.sparkLifeSpan
          lifeSpanVariation: Math.round(root.sparkLifeSpan * 0.2)
          size: root.sparkSize
          endSize: 0
          sizeVariation: root.sparkSize * 0.5
          velocity: AngleDirection {
            angle: 90
            angleVariation: 180
            magnitude: root.sparkSpeed
            magnitudeVariation: root.sparkSpeed * 0.35
          }
        }

        ItemParticle {
          system: particleSystem
          fade: true
          delegate: Component {
            Rectangle {
              width: root.sparkSize
              height: width
              radius: width / 2
              color: root.effectColor
              opacity: root.coreOpacity
            }
          }
        }
      }
    }
  }
}
