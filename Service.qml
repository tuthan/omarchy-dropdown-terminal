import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Item {
  id: root
  visible: false

  property var settings: ({})
  readonly property bool autoHideOnFocusLoss: setting("autoHideOnFocusLoss", false) === true
  readonly property bool allowSpecialFallthrough: setting("allowSpecialFallthrough", false) === true
  readonly property int autoHideDelayMs: Math.max(0, Number(setting("autoHideDelayMs", 500)))
  readonly property int widthPercent: Math.max(20, Math.min(100, Number(setting("widthPercent", 90))))
  readonly property int heightPercent: Math.max(20, Math.min(100, Number(setting("heightPercent", 45))))
  readonly property string borderColor: String(setting("borderColor", "theme"))

  readonly property string helperPath: Qt.resolvedUrl("bin/omarchy-dropdown-terminal").toString().replace(/^file:\/\//, "")
  readonly property string bindPath: Qt.resolvedUrl("bin/omarchy-dropdown-terminal-bind").toString().replace(/^file:\/\//, "")
  readonly property string fallthroughPath: Qt.resolvedUrl("bin/omarchy-dropdown-terminal-special-fallthrough").toString().replace(/^file:\/\//, "")
  readonly property bool busy: toggleProcess.running
  property bool settingsReady: false
  property bool desiredSpecialFallthrough: false

  onAllowSpecialFallthroughChanged: {
    if (settingsReady) applySpecialFallthrough(allowSpecialFallthrough)
  }

  Component.onCompleted: {
    settingsReady = true
    if (allowSpecialFallthrough) applySpecialFallthrough(true)
  }

  // This registers an action with Hyprland. The physical key is normally
  // configured by the user; the optional right-click installer is explicit.
  GlobalShortcut {
    appid: "io.github.tuthan.dropdown-terminal"
    name: "toggle"
    description: "Toggle the dropdown terminal"
    onPressed: root.toggle()
  }

  Connections {
    target: Hyprland
    function onActiveToplevelChanged() {
      root.reconcileSpecialWorkspace()
      if (root.autoHideOnFocusLoss) hideTimer.restart()
      else hideTimer.stop()
    }
  }

  Timer {
    id: hideTimer
    interval: root.autoHideDelayMs
    repeat: false
    onTriggered: if (root.autoHideOnFocusLoss) root.hide()
  }

  Process {
    id: toggleProcess
    command: ["bash", root.helperPath, "toggle", String(root.widthPercent),
      String(root.heightPercent), root.borderColor]
    running: false
  }

  Process {
    id: hideProcess
    command: ["bash", root.helperPath, "hide"]
    running: false
  }

  Process {
    id: reconcileProcess
    command: ["bash", root.helperPath, "cleanup"]
    running: false
  }

  Process {
    id: fallthroughProcess
    property bool enabled: false
    command: ["bash", root.fallthroughPath, enabled ? "enable" : "disable"]
    running: false
    onExited: {
      if (root.desiredSpecialFallthrough !== enabled) {
        enabled = root.desiredSpecialFallthrough
        running = true
      }
    }
  }

  Process {
    id: bindProcess
    command: ["bash", root.bindPath]
    running: false
  }

  function toggle() {
    if (!toggleProcess.running && !hideProcess.running) toggleProcess.running = true
  }

  function hide() {
    if (!toggleProcess.running && !hideProcess.running) hideProcess.running = true
  }

  function reconcileSpecialWorkspace() {
    if (!reconcileProcess.running) reconcileProcess.running = true
  }

  function applySpecialFallthrough(enabled) {
    desiredSpecialFallthrough = enabled
    if (fallthroughProcess.running) return
    fallthroughProcess.enabled = enabled
    fallthroughProcess.running = true
  }

  function installHotkey() {
    if (!bindProcess.running) bindProcess.running = true
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }
}
