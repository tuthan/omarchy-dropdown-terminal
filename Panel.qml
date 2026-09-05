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
  readonly property string entranceEffect: {
    var value = String(root.setting("entranceEffect", "Glow")).toLowerCase()
    var effects = {
      "off": "Off",
      "glow": "Glow",
      "fire": "Fire",
      "firework": "Firework",
      "thunder": "Thunder",
      "snow": "Snow",
      "rain": "Rain"
    }
    return effects[value] || "Glow"
  }
  readonly property int effectIntensity: {
    var value = Number(root.setting("effectIntensity", 50))
    if (!isFinite(value)) value = 50
    return Math.max(0, Math.min(100, Math.round(value / 10) * 10))
  }
  readonly property bool petEnabled: root.setting("petEnabled", false) === true
  readonly property string petSpecies: {
    var value = String(root.setting("petSpecies", "Penguin"))
    return ["Penguin", "Cat", "Corgi"].indexOf(value) >= 0 ? value : "Penguin"
  }
  readonly property string petActivity: {
    var value = String(root.setting("petActivity", "On focus"))
    return ["On focus", "Always while visible", "Celebrations only"].indexOf(value) >= 0
      ? value : "On focus"
  }
  readonly property bool reduceMotion: root.setting("reduceMotion", false) === true
  readonly property bool urgencyIndicator: root.setting("urgencyIndicator", true) !== false
  readonly property bool commandTracking: root.setting("commandTracking", false) === true
  readonly property int commandNotifyAfterMs: {
    var value = Number(root.setting("commandNotifyAfterMs", 5000))
    if (!isFinite(value)) value = 5000
    return Math.max(0, Math.min(60000, Math.round(value / 500) * 500))
  }
  readonly property bool commandFailureIndicator: root.setting("commandFailureIndicator", true) !== false
  readonly property bool commandCancelIsFailure: root.setting("commandCancelIsFailure", false) === true
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
  readonly property var shellStatusReport: root.hostWidget && root.hostWidget.shellStatusReport
    ? root.hostWidget.shellStatusReport : ({})
  readonly property string integrationShell: String(root.shellStatusReport.shell || "bash")
  readonly property string shellConfigPath: String(root.shellStatusReport.config ||
    ((Quickshell.env("HOME") || "") + "/.bashrc"))
  readonly property string petDiagnostic: root.hostWidget
    ? String(root.hostWidget.petDiagnostic || "") : ""
  readonly property string shellBlock: String(root.shellStatusReport.block ||
    '# BEGIN Dropdown Terminal shell integration\nYADTM_EXISTING_DEBUG_TRAP="$(trap -p DEBUG 2>/dev/null || true)"\nYADTM_EXISTING_DEBUG_TRAP_CAPTURED=1\n[[ -r "$HOME/.config/omarchy/plugins/io.github.tuthan.dropdown-terminal/shell/bash.yadtm" ]] \\\n  && source "$HOME/.config/omarchy/plugins/io.github.tuthan.dropdown-terminal/shell/bash.yadtm"\nunset YADTM_EXISTING_DEBUG_TRAP YADTM_EXISTING_DEBUG_TRAP_CAPTURED\n# END Dropdown Terminal shell integration')
  readonly property bool shellStatusReady: root.hostWidget && root.hostWidget.shellStatusReady === true
  readonly property bool shellInstalled: root.hostWidget && root.hostWidget.shellStatus === "installed"
  property bool shellPreflightWaiting: false
  property bool shellPreflightInstall: true
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
    if (root.confirmKind === "shell-install")
      return "Install command tracking for " + root.integrationShell + "?\n\nTarget: " + root.shellConfigPath
        + "\nGuarded block:\n" + root.shellBlock
        + "\nFields written: v1 start/finish, session, sequence, timestamp, and exit status.\nPrivacy: command text and terminal output are never written.\nBackup: timestamped cp -p copy before atomic replacement.\nRemoval: deletes only the marked integration block."
    if (root.confirmKind === "shell-remove")
      return "Remove command tracking for " + root.integrationShell + "?\n\nTarget: " + root.shellConfigPath
        + "\nRemoval: deletes only the marked integration block; unrelated rc content stays unchanged.\nBackup: timestamped cp -p copy before atomic replacement."
    return ""
  }

  readonly property string confirmAction: root.confirmKind === "binding"
    ? (root.bindingConflictCount > 0 ? "Add anyway" : "Add binding")
    : (root.confirmKind === "fallthrough-enable" ? "Enable"
      : (root.confirmKind === "shell-install" ? "Install" : "Remove"))

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
    root.shellPreflightWaiting = false
    bindingPreflightTimer.stop()
    shellPreflightTimer.stop()
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

  function requestShellIntegrationChange(install) {
    root.shellPreflightInstall = install
    // The action buttons are gated by the last completed status read. Open
    // the confirmation from that stable snapshot immediately; refreshing
    // first used to clear shellStatusReady and leave the dialog waiting on a
    // status process that could already be in flight.
    if (install && !root.shellInstalled
        && root.shellStatusReport.sourceReadable === true) {
      root.beginConfirmation("shell-install")
      return
    }
    if (!install && root.shellInstalled) {
      root.beginConfirmation("shell-remove")
      return
    }
    if (root.hostWidget && typeof root.hostWidget.refreshShellIntegrationStatus === "function")
      root.hostWidget.refreshShellIntegrationStatus()
    root.shellPreflightWaiting = true
    shellPreflightTimer.restart()
  }

  Timer {
    id: shellPreflightTimer
    interval: 50
    repeat: true
    onTriggered: {
      if (!root.shellPreflightWaiting) {
        stop()
        return
      }
      if (!root.hostWidget || root.hostWidget.shellStatusReady !== false) {
        stop()
        root.shellPreflightWaiting = false
        var installed = root.hostWidget && root.hostWidget.shellStatus === "installed"
        if ((root.shellPreflightInstall && !installed) || (!root.shellPreflightInstall && installed))
          root.beginConfirmation(root.shellPreflightInstall ? "shell-install" : "shell-remove")
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
    } else if (kind === "shell-install") {
      if (root.hostWidget && typeof root.hostWidget.installShellIntegration === "function")
        root.hostWidget.installShellIntegration()
    } else if (kind === "shell-remove") {
      if (root.hostWidget && typeof root.hostWidget.removeShellIntegration === "function")
        root.hostWidget.removeShellIntegration()
    }
  }
  function setDelay(value) { persistSettings({ autoHideDelayMs: Math.round(value) }) }
  function setSlideFromTop(value) { persistSettings({ slideFromTop: value }) }
  function setEntranceEffect(value) { persistSettings({ entranceEffect: value }) }
  function setEffectIntensity(value) {
    persistSettings({ effectIntensity: Math.max(0, Math.min(100, Math.round(value / 10) * 10)) })
  }
  function setPetEnabled(value) { persistSettings({ petEnabled: value }) }
  function setPetActivity(value) { persistSettings({ petActivity: value }) }
  function setReduceMotion(value) { persistSettings({ reduceMotion: value }) }
  function setUrgencyIndicator(value) { persistSettings({ urgencyIndicator: value }) }
  function setCommandTracking(value) { persistSettings({ commandTracking: value }) }
  function setCommandNotifyAfter(value) { persistSettings({ commandNotifyAfterMs: Math.round(value / 500) * 500 }) }
  function setCommandFailureIndicator(value) { persistSettings({ commandFailureIndicator: value }) }
  function setCommandCancelIsFailure(value) { persistSettings({ commandCancelIsFailure: value }) }

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
      blocked: root.confirming || root.bindingPreflightWaiting || root.shellPreflightWaiting
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

      Text {
        text: "Entrance effect"
        color: Util.alpha(root.contentForeground, 0.64)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width
        text: "A decorative finish when the terminal enters; it never reports command status."
        color: Util.alpha(root.contentForeground, 0.5)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      ButtonGroup {
        width: parent.width
        options: [
          { value: "Off", label: "Off", tooltip: "Do not create an entrance-effect surface." },
          { value: "Glow", label: "Glow", tooltip: "Show a brief decorative glow after the terminal settles." },
          { value: "Fire", label: "Fire / burn", tooltip: "Show a warm flame-like burn around the terminal edge." },
          { value: "Firework", label: "Firework", tooltip: "Show a short celebratory burst above the terminal." },
          { value: "Thunder", label: "Thunder", tooltip: "Show a brief cool lightning flash." },
          { value: "Snow", label: "Snow", tooltip: "Show a short snowfall across the terminal gutter." },
          { value: "Rain", label: "Rain", tooltip: "Show a short rain streak effect across the terminal gutter." }
        ]
        value: root.entranceEffect
        foreground: root.contentForeground
        accent: Color.accent
        fontFamily: root.contentFontFamily
        onChanged: function(value) { root.setEntranceEffect(value) }
      }

      NumberField {
        label: "Effect intensity (%)"
        value: root.effectIntensity
        from: 0
        to: 100
        stepSize: 10
        fieldWidth: Style.space(120)
        foreground: root.contentForeground
        fontFamily: root.contentFontFamily
        onModified: function(value) { root.setEffectIntensity(value) }
      }

      PanelSeparator { width: parent.width }

      Text {
        text: "Pet"
        color: Util.alpha(root.contentForeground, 0.64)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width
        text: "A decorative, click-through pet lives on the terminal edge. It never changes the meaning of the command indicator."
        color: Util.alpha(root.contentForeground, 0.5)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        visible: root.petDiagnostic !== ""
        text: root.petDiagnostic
        color: Color.urgent
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Row {
        width: parent.width
        spacing: Style.space(8)
        Button {
          property bool on: root.petEnabled
          text: (on ? "✓ " : "") + "Pet"
          selected: on
          tooltipText: on
            ? "On: show the click-through pet while the terminal is visible."
            : "Off: do not create the pet layer."
          focusable: true
          bordered: true
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onClicked: root.setPetEnabled(!on)
        }
        Button {
          property bool on: root.reduceMotion
          text: (on ? "✓ " : "") + "Reduce motion"
          selected: on
          tooltipText: on
            ? "On: use static decorative states and stop all infinite animation."
            : "Off: allow the authored pet and entrance motion."
          focusable: true
          bordered: true
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onClicked: root.setReduceMotion(!on)
        }
      }

      Text {
        text: "Pet species"
        color: Util.alpha(root.contentForeground, 0.64)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
      }

      ButtonGroup {
        width: parent.width
        options: [
          { value: "Penguin", label: "Penguin", tooltip: "The bundled, validated penguin pack." },
          { value: "Cat", label: "Fluffy cat", tooltip: "A bundled, validated fluffy cat pack." },
          { value: "Corgi", label: "Corgi", tooltip: "A bundled, validated corgi pack." }
        ]
        value: root.petSpecies
        foreground: root.contentForeground
        accent: Color.accent
        fontFamily: root.contentFontFamily
        onChanged: function(value) { root.persistSettings({ petSpecies: value }) }
      }

      Text {
        text: "Activity"
        color: Util.alpha(root.contentForeground, 0.64)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
      }

      ButtonGroup {
        width: parent.width
        options: [
          { value: "On focus", label: "On focus", tooltip: "React to focus; otherwise remain quietly idle." },
          { value: "Always while visible", label: "Always visible", tooltip: "Allow infrequent walking and sleep while visible." },
          { value: "Celebrations only", label: "Celebrations", tooltip: "Only react to precise success and failure results." }
        ]
        value: root.petActivity
        foreground: root.contentForeground
        accent: Color.accent
        fontFamily: root.contentFontFamily
        onChanged: function(value) { root.setPetActivity(value) }
      }

      PanelSeparator { width: parent.width }

      Text {
        text: "Command indicator"
        color: Util.alpha(root.contentForeground, 0.64)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width
        text: "Urgency is a generic terminal-needs-attention signal. Precise running, succeeded, and failed states require the explicit shell integration below. No command text is recorded."
        color: Util.alpha(root.contentForeground, 0.5)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Row {
        width: parent.width
        spacing: Style.space(8)
        Button {
          property bool on: root.urgencyIndicator
          text: (on ? "✓ " : "") + "Urgency"
          selected: on
          tooltipText: "Show a generic attention badge when the managed terminal raises compositor urgency."
          focusable: true
          bordered: true
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onClicked: root.setUrgencyIndicator(!on)
        }
        Button {
          property bool on: root.commandTracking
          text: (on ? "✓ " : "") + "Command tracking"
          selected: on
          tooltipText: on
            ? "Read precise shell completion events; installation remains a separate explicit action."
            : "Keep precise shell completion tracking disabled."
          focusable: true
          bordered: true
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onClicked: root.setCommandTracking(!on)
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(8)
        visible: root.commandTracking

        Text {
          width: parent.width
          text: "Shell integration: " + (root.hostWidget ? root.hostWidget.shellStatus : "unavailable")
            + " · target: " + root.integrationShell + " · " + root.shellConfigPath
          color: Util.alpha(root.contentForeground, 0.6)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Row {
          width: parent.width
          spacing: Style.space(8)
          NumberField {
            label: "Notify after (ms)"
            value: root.commandNotifyAfterMs
            from: 0
            to: 60000
            stepSize: 500
            fieldWidth: Style.space(150)
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onModified: function(value) { root.setCommandNotifyAfter(value) }
          }
          Button {
            property bool on: root.commandFailureIndicator
            text: (on ? "✓ " : "") + "Failures"
            selected: on
            tooltipText: on ? "Show nonzero command exits as failed." : "Do not show nonzero command exits."
            focusable: true
            bordered: true
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: root.setCommandFailureIndicator(!on)
          }
          Button {
            property bool on: root.commandCancelIsFailure
            text: (on ? "✓ " : "") + "C-c fails"
            selected: on
            tooltipText: on ? "Treat exit status 130 as failed." : "Ignore exit status 130 from Ctrl-C."
            focusable: true
            bordered: true
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: root.setCommandCancelIsFailure(!on)
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)
          Button {
            visible: root.shellInstalled
            text: "Remove shell integration"
            tooltipText: "Remove only the marked command-tracking block from the selected shell rc file."
            focusable: true
            bordered: true
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: root.requestShellIntegrationChange(false)
          }
          Button {
            visible: !root.shellInstalled
            enabled: root.shellStatusReady && root.shellStatusReport.sourceReadable === true
            text: "Install shell integration"
            tooltipText: "Add the guarded command-tracking block after confirmation."
            focusable: true
            bordered: true
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: root.requestShellIntegrationChange(true)
          }
        }

        Text {
          width: parent.width
          visible: root.hostWidget && (!root.shellStatusReady || root.shellStatusReport.sourceReadable !== true
            || root.hostWidget.shellActionMessage !== "")
          text: root.hostWidget && root.hostWidget.shellActionMessage !== ""
            ? root.hostWidget.shellActionMessage
            : (!root.shellStatusReady ? "Checking the selected shell…"
              : (root.shellStatusReport.sourceReadable !== true
                ? "Command tracking is unavailable: the adapter file is not readable."
                : ""))
          color: Util.alpha(root.contentForeground, 0.58)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
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
