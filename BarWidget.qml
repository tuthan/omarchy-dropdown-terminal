import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.tuthan.dropdown-terminal"

  Service {
    id: terminalService
    settings: root.settings
    moduleName: root.moduleName
  }

  readonly property var service: terminalService
  readonly property bool opened: settingsLoader.item && settingsLoader.item.opened === true

  readonly property bool showIcon: setting("showIcon", true) === true
  readonly property string icon: String(setting("icon", "\uF120"))
  readonly property string keybinding: service.keybinding
  readonly property string indicatorGlyph: {
    if (service.reduceMotion && service.indicatorState !== "idle") return "•"
    if (service.indicatorState === "running") return "◌"
    if (service.indicatorState === "attention") return "!"
    if (service.indicatorState === "succeeded") return "✓"
    if (service.indicatorState === "failed") return "×"
    return root.icon
  }
  readonly property color indicatorColor: {
    if (service.indicatorState === "attention" || service.indicatorState === "failed")
      return root.bar ? root.bar.urgent : Color.urgent
    if (service.indicatorState === "running")
      return Color.muted
    if (service.indicatorState === "succeeded")
      return Color.accent
    return root.bar ? root.bar.barForeground : Color.foreground
  }
  readonly property string indicatorTooltip: {
    if (service.indicatorState === "running") return "running · Dropdown Terminal command in progress"
    if (service.indicatorState === "attention")
      return "attention · Terminal needs attention (generic urgency; command status unavailable)"
    if (service.indicatorState === "succeeded")
      return "succeeded · command finished while hidden"
        + (service.commandUnreadCount > 1 ? " (" + service.commandUnreadCount + " unread)" : "")
    if (service.indicatorState === "failed")
      return "failed · command finished with a nonzero status while hidden"
        + (service.commandUnreadCount > 1 ? " (" + service.commandUnreadCount + " unread)" : "")
    if (service.commandTracking && !service.commandIntegrationInstalled)
      return "Dropdown Terminal · command tracking not configured; urgency remains available"
    if (service.bindingStatus === "installed")
      return "Left-click: terminal · Middle-click: settings · Right-click: review binding " + root.keybinding
    return "Left-click: terminal · Middle-click: settings · Right-click: bind " + root.keybinding
  }

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

  function requestBindingInstall() {
    if (!settingsLoader.item) {
      pendingBindingRequest = true
      return
    }
    pendingBindingRequest = false
    root.open()
    Qt.callLater(function() {
      if (settingsLoader.item && typeof settingsLoader.item.requestBindingInstall === "function")
        settingsLoader.item.requestBindingInstall()
    })
  }

  property bool pendingBindingRequest: false

  function setSpecialFallthrough(enabled) {
    service.applySpecialFallthrough(enabled)
  }

  function installHotkey(allowConflict) {
    service.installHotkey(allowConflict === true)
  }

  function refreshMutationStatus() {
    service.refreshMutationStatus()
  }

  function refreshShellIntegrationStatus() {
    service.refreshShellIntegrationStatus()
  }

  function installShellIntegration() {
    service.mutateShellIntegration("install")
  }

  function removeShellIntegration() {
    service.mutateShellIntegration("remove")
  }

  readonly property string bindingStatus: service.bindingStatus
  readonly property var bindingConflicts: service.bindingConflicts
  readonly property bool bindingStatusReady: service.bindingStatusReady
  readonly property string fallthroughStatus: service.fallthroughStatus
  readonly property string shellStatus: service.shellStatus
  readonly property var shellStatusReport: service.shellStatusReport
  readonly property bool shellStatusReady: service.shellStatusReady
  readonly property string shellActionMessage: service.shellActionMessage
  readonly property bool effectsEnabled: service.entranceEffect !== "Off"
    && service.effectIntensity > 0 && !service.reduceMotion
  readonly property string petDiagnostic: petLoader.item && petLoader.item.petDiagnostic
    ? String(petLoader.item.petDiagnostic) : ""

  // BarWidget is instantiated once per output by Omarchy. Separate loaders keep
  // each optional visual stack genuinely absent when it is not selected: an
  // effect never creates pet state or atlas decoders, and a pet never creates
  // the Qt particle system.
  Loader {
    id: effectsLoader
    active: root.effectsEnabled
    sourceComponent: Component {
      TerminalEffects {
        service: terminalService
        hostScreen: root.QsWindow.window ? root.QsWindow.window.screen : null
      }
    }
  }

  Loader {
    id: petLoader
    active: service.petEnabled
    sourceComponent: Component {
      PetLayer {
        service: terminalService
        hostScreen: root.QsWindow.window ? root.QsWindow.window.screen : null
      }
    }
  }

  Loader {
    id: settingsLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectSettingsPanel()
      Qt.callLater(root.injectSettingsPanel)
      if (root.pendingBindingRequest) Qt.callLater(root.requestBindingInstall)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    slotSize: Style.bar.statusSlot
    iconComponent: Component {
      Item {
        OpticalGlyph {
          anchors.fill: parent
          text: root.indicatorGlyph
          color: root.indicatorColor
          fontFamily: button.fontFamily
          fontSize: button.fontSize
        }

        Rectangle {
          visible: service.commandUnreadCount > 0
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          width: Style.space(9)
          height: Style.space(9)
          radius: width / 2
          color: root.indicatorColor
          border.color: root.bar ? root.bar.background : Color.background
          border.width: 1

          Text {
            anchors.centerIn: parent
            visible: service.commandUnreadCount > 1
            text: service.commandUnreadCount > 9 ? "9" : String(service.commandUnreadCount)
            color: root.bar ? root.bar.background : Color.background
            font.family: button.fontFamily
            font.pixelSize: Math.max(Style.font.bodySmall, Style.space(6))
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
          }
        }
      }
    }
    tooltipText: service.launching ? "Opening terminal…" : root.indicatorTooltip
    onPressed: function(button) {
      if (button === Qt.RightButton) root.requestBindingInstall()
      else if (button === Qt.MiddleButton) root.toggleSettings()
      else if (button === Qt.LeftButton) service.toggle()
    }
  }

  onBarChanged: injectSettingsPanel()
  onSettingsChanged: injectSettingsPanel()
}
