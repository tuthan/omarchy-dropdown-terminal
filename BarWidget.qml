import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.tuthan.dropdown-terminal"

  Service { id: service }

  readonly property bool showIcon: setting("showIcon", true) === true

  visible: !vertical && showIcon
  implicitWidth: showIcon ? button.implicitWidth : 0
  implicitHeight: showIcon ? button.implicitHeight : 0

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uF120"
    slotSize: Style.bar.statusSlot
    tooltipText: service.busy ? "Opening terminal…" : "Left-click: terminal · Right-click: bind Ctrl + Grave"
    onPressed: function(button) {
      if (button === Qt.RightButton) service.installHotkey()
      else if (button === Qt.LeftButton) service.toggle()
    }
  }
}
