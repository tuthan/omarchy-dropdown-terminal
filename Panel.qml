import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.tuthan.dropdown-terminal"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var pendingSettings: null
  property string confirmKind: ""
  property double confirmOpenedAt: 0
  property bool bindingPreflightWaiting: false
  readonly property bool confirming: confirmKind !== ""
  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string borderSetting: String(root.setting("borderColor", "theme"))
  readonly property bool slideFromTop: root.setting("slideFromTop", true) !== false
  readonly property color pickerColor: {
    var match = root.borderSetting.match(/^rgb\(([0-9a-fA-F]{6})\)$/)
    return match ? Qt.color("#" + match[1]) : Color.accent
  }

  readonly property string hyprConfigRoot: (Quickshell.env("XDG_CONFIG_HOME") ||
    (Quickshell.env("HOME") + "/.config")) + "/hypr"
  readonly property string bindingConfigPath: root.hyprConfigRoot + "/bindings.lua"
  readonly property string inputConfigPath: root.hyprConfigRoot + "/input.lua"
  readonly property string bindingLine: 'hl.bind("CTRL + GRAVE", hl.dsp.global("io.github.tuthan.dropdown-terminal:toggle"))'
  readonly property string fallthroughBlock: '-- BEGIN Dropdown Terminal special fallthrough\nhl.config({\n  input = {\n    special_fallthrough = true,\n  },\n})\n-- END Dropdown Terminal special fallthrough'
  readonly property int bindingConflictCount: root.hostWidget && Array.isArray(root.hostWidget.bindingConflicts)
    ? root.hostWidget.bindingConflicts.length : 0
  readonly property string bindingConflictSummary: {
    var conflicts = root.hostWidget && Array.isArray(root.hostWidget.bindingConflicts)
      ? root.hostWidget.bindingConflicts : []
    if (conflicts.length === 0) return ""
    var lines = []
    var limit = Math.min(conflicts.length, 4)
    for (var i = 0; i < limit; i++) {
      var conflict = conflicts[i] || {}
      lines.push("Line " + String(conflict.lineNumber || "?") + ": " + String(conflict.text || ""))
    }
    if (conflicts.length > limit) lines.push("…and " + (conflicts.length - limit) + " more")
    return "\n\nExisting Ctrl + Grave conflict(s):\n" + lines.join("\n")
      + "\nThe helper will add the managed binding only after this explicit confirmation."
  }
  readonly property string confirmMessage: {
    if (root.confirmKind === "binding")
      return "Add the exact Ctrl + Grave binding?\n\nChord: CTRL + GRAVE\nTarget: " + root.bindingConfigPath
        + "\nEffect: invokes io.github.tuthan.dropdown-terminal:toggle\nBackup: timestamped copy before atomic replacement\nRemoval: remove only the managed binding block."
        + root.bindingConflictSummary
    if (root.confirmKind === "fallthrough-enable")
      return "Enable focus through the dropdown?\n\nTarget: " + root.inputConfigPath
        + "\nEffect: normal windows can receive pointer focus while the dropdown is visible.\nManaged block:\n" + root.fallthroughBlock
        + "\nBackup: timestamped copy before atomic replacement\nRemoval: disable removes only this managed block."
    if (root.confirmKind === "fallthrough-disable")
      return "Remove Dropdown Terminal's focus-through override?\n\nTarget: " + root.inputConfigPath
        + "\nRemoval: removes only the marked special_fallthrough block; unrelated input settings stay unchanged."
    return ""
  }

  readonly property string confirmAction: root.confirmKind === "binding"
    ? (root.bindingConflictCount > 0 ? "Add anyway" : "Add binding")
    : (root.confirmKind === "fallthrough-enable" ? "Enable" : "Remove")

  function savePendingSettings() {
    if (!root.pendingSettings) return
    var entry = root.pendingSettings
    root.pendingSettings = null
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  onOpenedChanged: if (!opened) root.cancelConfirmation()

  function close() {
    root.cancelConfirmation()
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
    // Write through immediately: with a bar on every monitor the widget has
    // one instance per screen, and helpers spawned via the global hotkey may
    // be served by an instance other than the one hosting this panel.
    Qt.callLater(root.savePendingSettings)
  }

  function setWidth(value) { persistSettings({ widthPercent: Math.round(value) }) }
  function setHeight(value) { persistSettings({ heightPercent: Math.round(value) }) }
  function setAutoHide(value) { persistSettings({ autoHideOnFocusLoss: value }) }
  function setSpecialFallthrough(value) {
    persistSettings({ allowSpecialFallthrough: value })
    if (root.hostWidget && typeof root.hostWidget.setSpecialFallthrough === "function")
      root.hostWidget.setSpecialFallthrough(value)
  }

  function beginConfirmation(kind) {
    if (root.confirming) return
    root.bindingPreflightWaiting = false
    root.confirmKind = kind
    root.confirmOpenedAt = Date.now()
    confirmDialog.selectedIndex = 0
    Qt.callLater(function() { if (root.confirming) confirmDialog.forceActiveFocus() })
  }

  function cancelConfirmation() {
    root.bindingPreflightWaiting = false
    bindingPreflightTimer.stop()
    root.confirmKind = ""
    root.confirmOpenedAt = 0
  }

  function requestBindingInstall() {
    if (root.hostWidget && typeof root.hostWidget.refreshMutationStatus === "function")
      root.hostWidget.refreshMutationStatus()
    if (root.hostWidget && root.hostWidget.bindingStatusReady === false) {
      root.bindingPreflightWaiting = true
      bindingPreflightTimer.restart()
      return
    }
    if (root.hostWidget && root.hostWidget.bindingStatus === "installed") return
    root.beginConfirmation("binding")
  }

  Timer {
    id: bindingPreflightTimer
    interval: 50
    repeat: true
    onTriggered: {
      if (!root.bindingPreflightWaiting) {
        stop()
        return
      }
      if (!root.hostWidget || root.hostWidget.bindingStatusReady !== false) {
        stop()
        root.bindingPreflightWaiting = false
        if (!root.hostWidget || root.hostWidget.bindingStatus !== "installed")
          root.beginConfirmation("binding")
      }
    }
  }

  function requestSpecialFallthrough(value) {
    if (value && root.hostWidget && root.hostWidget.fallthroughStatus === "installed") return
    root.beginConfirmation(value ? "fallthrough-enable" : "fallthrough-disable")
  }

  function acceptConfirmation() {
    var kind = root.confirmKind
    root.cancelConfirmation()
    if (kind === "binding") {
      if (root.hostWidget && typeof root.hostWidget.installHotkey === "function")
        root.hostWidget.installHotkey(root.bindingConflictCount > 0)
    } else if (kind === "fallthrough-enable") {
      root.setSpecialFallthrough(true)
    } else if (kind === "fallthrough-disable") {
      root.setSpecialFallthrough(false)
    }
  }
  function setDelay(value) { persistSettings({ autoHideDelayMs: Math.round(value) }) }
  function setSlideFromTop(value) { persistSettings({ slideFromTop: value }) }

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
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.confirming || root.bindingPreflightWaiting
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
        textFormat: Text.PlainText
        text: "Binding: " + (root.hostWidget ? root.hostWidget.bindingStatus : "unavailable")
          + (root.bindingConflictCount > 0 ? " (" + root.bindingConflictCount + " conflict(s))" : "")
          + " · Focus through: " + (root.hostWidget ? root.hostWidget.fallthroughStatus : "unavailable")
        color: Util.alpha(root.contentForeground, 0.55)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
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

      Row {
        width: parent.width
        spacing: Style.space(8)
        Button {
          text: root.borderSetting === "theme" ? "✓ Theme" : "Theme"
          selected: root.borderSetting === "theme"
          tooltipText: "Follow the current Omarchy/Hyprland active border theme."
          focusable: true
          bordered: true
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onClicked: root.persistSettings({ borderColor: "theme" })
        }
        Button {
          text: root.borderSetting !== "theme" ? "✓ Custom" : "Custom"
          selected: root.borderSetting !== "theme"
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
          property bool on: root.setting("autoHideOnFocusLoss", false) === true
          text: (on ? "✓ " : "") + "Auto-hide"
          tooltipText: on
            ? "On: the terminal hides automatically when another window takes focus, after the delay below."
            : "Off: the terminal stays open until you toggle it away."
          selected: on
          focusable: true
          bordered: true
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onClicked: root.setAutoHide(!on)
        }
        Text {
          text: "Delay (ms)"
          color: Util.alpha(root.contentForeground, 0.64)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }
        NumberField {
          label: ""
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

      Row {
        width: parent.width
        spacing: Style.space(8)
        Button {
          property bool on: root.slideFromTop
          text: (on ? "✓ " : "") + "Slide from top"
          tooltipText: on
            ? "On: the terminal drops in from the top edge. Click to use Hyprland's native upward slide instead."
            : "Off: Hyprland's native upward slide is used. Click to drop the terminal in from the top edge."
          focusable: true
          bordered: true
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onClicked: root.setSlideFromTop(!root.slideFromTop)
        }
        Button {
          property bool on: root.setting("allowSpecialFallthrough", false) === true
          text: (on ? "✓ " : "") + "Focus through"
          tooltipText: on
            ? "On: other windows receive mouse focus while the dropdown stays open."
            : "Off: the dropdown keeps exclusive mouse focus. Click to let clicks reach windows behind it."
          focusable: true
          bordered: true
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onClicked: root.requestSpecialFallthrough(!on)
        }
        Button {
          property bool on: root.setting("showIcon", true) === true
          text: (on ? "✓ " : "") + "Bar icon"
          tooltipText: on
            ? "On: the terminal button is shown in the bar."
            : "Off: no terminal button in the bar. The hotkey still works."
          focusable: true
          bordered: true
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onClicked: root.persistSettings({ showIcon: !on })
        }
      }

      ConfirmDialog {
        id: confirmDialog
        anchors.fill: parent
        z: 20
        opened: root.confirming
        focus: root.confirming
        selectedIndex: 0
        message: root.confirmMessage
        confirmText: root.confirmAction
        foreground: root.contentForeground
        fontFamily: root.contentFontFamily
        Keys.onPressed: function(event) {
          if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
              && event.isAutoRepeat) {
            event.accepted = true
            return
          }
          if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
              && Date.now() - root.confirmOpenedAt < 300) {
            event.accepted = true
            return
          }
          event.accepted = confirmDialog.handleKey(event)
        }
        onCanceled: root.cancelConfirmation()
        onConfirmed: root.acceptConfirmation()
      }
    }
  }
}
