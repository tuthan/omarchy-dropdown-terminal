import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Item {
  id: root
  visible: false

  property var settings: ({})
  readonly property bool autoHideOnFocusLoss: setting("autoHideOnFocusLoss", false) === true
  readonly property int autoHideDelayMs: Math.max(0, Number(setting("autoHideDelayMs", 500)))

  readonly property string helperPath: Qt.resolvedUrl("bin/omarchy-dropdown-terminal").toString().replace(/^file:\/\//, "")
  readonly property string bindPath: Qt.resolvedUrl("bin/omarchy-dropdown-terminal-bind").toString().replace(/^file:\/\//, "")
  readonly property bool busy: toggleProcess.running

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
      if (root.autoHideOnFocusLoss) hideTimer.restart()
      else hideTimer.stop()
    }
  }

  Timer {
    id: hideTimer
    interval: root.autoHideDelayMs
    repeat: false
    onTriggered: root.hide()
  }

  Process {
    id: toggleProcess
    command: ["bash", root.helperPath]
    running: false
  }

  Process {
    id: hideProcess
    command: ["bash", root.helperPath, "hide"]
    running: false
  }

  Process {
    id: bindProcess
    command: ["bash", root.bindPath]
    running: false
  }

  function toggle() {
    if (!toggleProcess.running) toggleProcess.running = true
  }

  function hide() {
    if (!hideProcess.running) hideProcess.running = true
  }

  function installHotkey() {
    if (!bindProcess.running) bindProcess.running = true
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }
}
