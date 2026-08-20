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
  readonly property string icon: String(setting("icon", "\uF120"))

  visible: !vertical && showIcon
  implicitWidth: showIcon ? button.implicitWidth : 0
  implicitHeight: showIcon ? button.implicitHeight : 0

  function injectSettingsPanel() {
    if (!settingsLoader.item) return
    settingsLoader.item.bar = root.bar
    settingsLoader.item.anchorItem = button
    settingsLoader.item.hostWidget = root
    settingsLoader.item.settings = root.settings
  }

  // KeyboardPanel dismissal resolves close() on the host widget; without these
  // it writes to a bound property directly and the panel can never reopen.
  function open() {
    if (settingsLoader.item && typeof settingsLoader.item.open === "function")
      settingsLoader.item.open()
  }

  function close() {
    if (settingsLoader.item && typeof settingsLoader.item.close === "function")
      settingsLoader.item.close()
  }

  function closeForPopoutSwitch() {
    if (settingsLoader.item && typeof settingsLoader.item.closeForPopoutSwitch === "function")
      settingsLoader.item.closeForPopoutSwitch()
  }

  function toggleSettings() {
    if (settingsLoader.item && typeof settingsLoader.item.toggle === "function")
      settingsLoader.item.toggle()
  }

  function setSpecialFallthrough(enabled) {
    service.applySpecialFallthrough(enabled)
  }

  Loader {
    id: settingsLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectSettingsPanel()
      Qt.callLater(root.injectSettingsPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    slotSize: Style.bar.statusSlot
    tooltipText: service.busy
      ? "Opening terminal…"
      : "Left-click: terminal · Middle-click: settings · Right-click: bind Ctrl + Grave"
    onPressed: function(button) {
      if (button === Qt.RightButton) service.installHotkey()
      else if (button === Qt.MiddleButton) root.toggleSettings()
      else if (button === Qt.LeftButton) service.toggle()
    }
  }

  onBarChanged: injectSettingsPanel()
  onSettingsChanged: injectSettingsPanel()
}
