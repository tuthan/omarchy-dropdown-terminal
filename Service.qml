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
  readonly property bool slideFromTop: setting("slideFromTop", true) !== false

  readonly property string helperPath: Qt.resolvedUrl("bin/omarchy-dropdown-terminal").toString().replace(/^file:\/\//, "")
  readonly property string bindPath: Qt.resolvedUrl("bin/omarchy-dropdown-terminal-bind").toString().replace(/^file:\/\//, "")
  readonly property string fallthroughPath: Qt.resolvedUrl("bin/omarchy-dropdown-terminal-special-fallthrough").toString().replace(/^file:\/\//, "")
  // Every helper action mutates the same window, workspace, and compositor
  // animation state, so they must never overlap; the helper's own flock is a
  // second line of defense for direct invocations.
  readonly property bool busy: toggleProcess.running || hideProcess.running || reconcileProcess.running
  // User-facing subset: only actions that actually summon the terminal.
  readonly property bool launching: toggleProcess.running || hideProcess.running
  // Timestamp of the last toggle start; focus events within this window belong
  // to the summon itself and must not arm the auto-hide timer.
  property double lastToggleStart: 0
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
      if (!root.autoHideOnFocusLoss) return
      // On a dual-monitor setup the summon itself can bounce focus; ignore
      // those events instead of instantly hiding the freshly shown terminal.
      if (Date.now() - root.lastToggleStart < 1200) {
        hideTimer.stop()
        return
      }
      hideTimer.restart()
    }
  }

  Timer {
    id: hideTimer
    interval: root.autoHideDelayMs
    repeat: false
    onTriggered: if (root.autoHideOnFocusLoss) root.hide()
  }

  // Every action needs the geometry: hiding slides the window off the top edge
  // before the workspace is toggled away.
  function helperArgs(action) {
    return ["bash", root.helperPath, action, String(root.widthPercent),
      String(root.heightPercent), root.borderColor, root.slideFromTop ? "1" : "0"]
  }

  Process {
    id: toggleProcess
    command: root.helperArgs("toggle")
    running: false
  }

  Process {
    id: hideProcess
    command: root.helperArgs("hide")
    running: false
  }

  Process {
    id: reconcileProcess
    command: root.helperArgs("cleanup")
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
    var now = Date.now()
    // Debounce: duplicate keybindings or key repeat must not queue a second
    // toggle behind the first, which would show and then instantly hide.
    if (root.busy || now - root.lastToggleStart < 150) return
    root.lastToggleStart = now
    toggleProcess.running = true
  }

  function hide() {
    if (!root.busy) hideProcess.running = true
  }

  function reconcileSpecialWorkspace() {
    if (!root.busy) reconcileProcess.running = true
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
