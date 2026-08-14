import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Item {
  id: root
  visible: false

  readonly property string helperPath: Qt.resolvedUrl("bin/omarchy-dropdown-terminal").toString().replace(/^file:\/\//, "")
  readonly property string bindPath: Qt.resolvedUrl("bin/omarchy-dropdown-terminal-bind").toString().replace(/^file:\/\//, "")
  readonly property bool busy: toggleProcess.running

  // This registers an action with Hyprland. The physical key is normally
  // configured by the user; the optional right-click installer is explicit.
  GlobalShortcut {
    appid: "hvo.dropdown-terminal"
    name: "toggle"
    description: "Toggle the dropdown terminal"
    onPressed: root.toggle()
  }

  Process {
    id: toggleProcess
    command: ["bash", root.helperPath]
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

  function installHotkey() {
    if (!bindProcess.running) bindProcess.running = true
  }
}
