import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.tuthan.dropdown-terminal"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var pendingSettings: null
  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string borderSetting: String(root.setting("borderColor", "theme"))
  readonly property color pickerColor: {
    var match = root.borderSetting.match(/^rgb\(([0-9a-fA-F]{6})\)$/)
    return match ? Qt.color("#" + match[1]) : Color.accent
  }

  function savePendingSettings() {
    if (!root.pendingSettings) return
    var entry = root.pendingSettings
    root.pendingSettings = null
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function close() {
    root.controller.hide()
    Qt.callLater(root.savePendingSettings)
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    root.pendingSettings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
  }

  function setWidth(value) { persistSettings({ widthPercent: Math.round(value) }) }
  function setHeight(value) { persistSettings({ heightPercent: Math.round(value) }) }
  function setAutoHide(value) { persistSettings({ autoHideOnFocusLoss: value }) }
  function setSpecialFallthrough(value) {
    persistSettings({ allowSpecialFallthrough: value })
    if (root.hostWidget && typeof root.hostWidget.setSpecialFallthrough === "function")
      root.hostWidget.setSpecialFallthrough(value)
  }
  function setDelay(value) { persistSettings({ autoHideDelayMs: Math.round(value) }) }

  function colorToHypr(color) {
    function channel(value) {
      var hex = Math.round(Math.max(0, Math.min(1, value)) * 255).toString(16)
      return hex.length === 1 ? "0" + hex : hex
    }
    return "rgb(" + channel(color.r) + channel(color.g) + channel(color.b) + ")"
  }

  function setCustomColor(color) {
    persistSettings({ borderColor: root.colorToHypr(color) })
  }

  ColorDialog {
    id: colorDialog
    title: "Choose terminal border color"
    selectedColor: root.pickerColor
    onAccepted: root.setCustomColor(selectedColor)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
    }

    Column {
      id: content
      width: panel.contentWidth - panel.padding * 2
      spacing: Style.space(10)

      Text {
        width: parent.width
        text: "DROPDOWN TERMINAL"
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }

      Text {
        width: parent.width
        text: "Middle-click opened settings"
        color: Util.alpha(root.contentForeground, 0.64)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
      }

      PanelSeparator { width: parent.width }

      Text {
        text: "Bar icon"
        color: Util.alpha(root.contentForeground, 0.64)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        text: "Paste a Nerd Font glyph or short label"
        color: Util.alpha(root.contentForeground, 0.5)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
      }

      Row {
        width: parent.width
        spacing: Style.space(8)
        TextField {
          id: iconField
          width: parent.width - applyIcon.width - iconPreview.width - parent.spacing * 2
          text: String(root.setting("icon", "\uF120"))
          foreground: root.contentForeground
          font.family: root.contentFontFamily
          onAccepted: root.persistSettings({ icon: text || "\uF120" })
        }
        Button {
          id: applyIcon
          text: "Apply"
          tooltipText: "Apply this glyph to the bar button."
          focusable: true
          bordered: true
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onClicked: root.persistSettings({ icon: iconField.text || "\uF120" })
        }
        Text {
          id: iconPreview
          width: Style.space(28)
          text: iconField.text || "\uF120"
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.title
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(8)
        NumberField {
          label: "Width (%)"
          value: Number(root.setting("widthPercent", 90))
          from: 20
          to: 100
          fieldWidth: Style.space(120)
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onModified: function(value) { root.setWidth(value) }
        }
        Button {
          text: "?"
          tooltipText: "Width of the terminal relative to the focused monitor."
          focusable: true
          bordered: true
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onClicked: {}
        }
        NumberField {
          label: "Height (%)"
          value: Number(root.setting("heightPercent", 45))
          from: 20
          to: 100
          fieldWidth: Style.space(120)
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onModified: function(value) { root.setHeight(value) }
        }
        Button {
          text: "?"
          tooltipText: "Height of the terminal relative to the focused monitor."
          focusable: true
          bordered: true
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onClicked: {}
        }
      }

      Text {
        text: "Border color"
        color: Util.alpha(root.contentForeground, 0.64)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        text: "theme or rgb(...) / rgba(...)"
        color: Util.alpha(root.contentForeground, 0.5)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
      }

      Row {
        width: parent.width
        spacing: Style.space(8)
        Button {
          text: "Theme"
          selected: root.borderSetting === "theme"
          tooltipText: "Follow the current Omarchy/Hyprland active border theme."
          focusable: true
          bordered: true
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onClicked: root.persistSettings({ borderColor: "theme" })
        }
        Button {
          text: "Custom"
          tooltipText: "Choose a custom border color."
          focusable: true
          bordered: true
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onClicked: colorDialog.open()
        }
        Rectangle {
          width: Style.space(26)
          height: Style.space(26)
          radius: Style.cornerRadius
          color: root.borderSetting === "theme" ? Color.accent : root.pickerColor
          border.color: root.contentForeground
          border.width: 1
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(8)
        Button {
          text: root.setting("autoHideOnFocusLoss", false) === true ? "Auto-hide: on" : "Auto-hide: off"
          tooltipText: "Automatically hide the terminal when another window takes focus."
          focusable: true
          bordered: true
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onClicked: root.setAutoHide(!(root.setting("autoHideOnFocusLoss", false) === true))
        }
        Button {
          text: root.setting("allowSpecialFallthrough", false) === true ? "Focus through: on" : "Focus through: off"
          focusable: true
          bordered: true
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onClicked: root.setSpecialFallthrough(!(root.setting("allowSpecialFallthrough", false) === true))
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(8)
        Button {
          text: root.setting("showIcon", true) === true ? "Icon: shown" : "Icon: hidden"
          tooltipText: "Show or hide the terminal button in the bar. The hotkey still works when hidden."
          focusable: true
          bordered: true
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onClicked: root.persistSettings({ showIcon: !(root.setting("showIcon", true) === true) })
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(8)
        NumberField {
          label: "Delay (ms)"
          value: Number(root.setting("autoHideDelayMs", 500))
          from: 0
          to: 2000
          fieldWidth: Style.space(120)
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onModified: function(value) { root.setDelay(value) }
        }
        Button {
          text: "?"
          tooltipText: "How long to wait after focus changes before auto-hide runs. This prevents hiding during brief focus transitions."
          focusable: true
          bordered: true
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onClicked: {}
        }
      }
    }
  }
}
