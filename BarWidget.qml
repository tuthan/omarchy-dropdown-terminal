import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.tuthan.dropdown-terminal"

  Service {
    id: service
    settings: root.settings
  }

  readonly property bool showIcon: setting("showIcon", true) === true
  readonly property bool autoHideOnFocusLoss: service.autoHideOnFocusLoss

  visible: !vertical && showIcon
  implicitWidth: showIcon ? button.implicitWidth : 0
  implicitHeight: showIcon ? button.implicitHeight : 0

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uF120"
    slotSize: Style.bar.statusSlot
    tooltipText: service.busy
      ? "Opening terminal…"
      : "Left-click: terminal · Middle-click: auto-hide "
        + (root.autoHideOnFocusLoss ? "on" : "off")
        + " · Right-click: bind Ctrl + Grave"
    onPressed: function(button) {
      if (button === Qt.RightButton) service.installHotkey()
      else if (button === Qt.MiddleButton) root.toggleAutoHideOnFocusLoss()
      else if (button === Qt.LeftButton) service.toggle()
    }
  }

  function toggleAutoHideOnFocusLoss() {
    var entry = { id: moduleName }
    for (var key in settings) if (key !== "id") entry[key] = settings[key]
    entry.autoHideOnFocusLoss = !autoHideOnFocusLoss
    settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, entry)
  }
}
