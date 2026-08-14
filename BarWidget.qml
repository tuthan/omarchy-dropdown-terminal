import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "hvo.dropdown-terminal"

  Service { id: service }

  visible: !vertical
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

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
