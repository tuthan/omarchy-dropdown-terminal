import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Item {
  id: root
  visible: false

  property var settings: ({})
  // The shell instantiates this Service once per bar, i.e. per monitor, and
  // each instance receives its own copy of `settings`. A change saved through
  // one panel does not reach the sibling instances, so hotkey-spawned helpers
  // could run with stale geometry. All instances therefore read the canonical
  // values from the shared shell.json instead.
  property string moduleName: ""
  property int configRevision: 0
  property int stateRevision: 0
  property int observationRevision: 0
  property string clearedTrackedAddress: ""
  readonly property bool debugEnabled: Quickshell.env("YADTM_DEBUG") === "1"

  FileView {
    id: shellConfigFile
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    onFileChanged: {
      reload()
      // Omarchy can coalesce a burst of atomic settings writes. A short,
      // bounded settle catches the final value without turning this into a
      // permanent poll.
      if (configSettleReloads <= 0) {
        configSettleReloads = 3
        configSettleTimer.restart()
      }
    }
    onTextChanged: {
      root.configRevision++
      root.logDebug("shell config reloaded")
    }
  }

  readonly property string runtimeStateRoot: {
    var dir = Quickshell.env("XDG_RUNTIME_DIR")
    if (dir) return dir
    return "/tmp/omarchy-dropdown-terminal-" + (Quickshell.env("UID") || "0")
  }

  FileView {
    id: stateFile
    path: root.runtimeStateRoot + "/io.github.tuthan.dropdown-terminal.state.json"
    watchChanges: true
    onFileChanged: reload()
    onTextChanged: {
      root.stateRevision++
      root.clearedTrackedAddress = ""
      root.logDebug("runtime state reloaded")
    }
  }

  property int configSettleReloads: 0
  Timer {
    id: configSettleTimer
    interval: 1000
    repeat: false
    onTriggered: {
      if (root.configSettleReloads <= 0) return
      shellConfigFile.reload()
      root.configSettleReloads--
      if (root.configSettleReloads > 0) restart()
    }
  }

  function logDebug(message) {
    if (root.debugEnabled) console.log("Dropdown Terminal [debug]: " + message)
  }

  function persistedSetting(name) {
    try {
      var txt = shellConfigFile.text()
      if (!txt) return undefined
      var cfg = JSON.parse(txt)
      var candidates = []
      if (cfg.bar && cfg.bar.layout) {
        candidates = [].concat(cfg.bar.layout.left || [], cfg.bar.layout.center || [], cfg.bar.layout.right || [])
      }
      if (cfg.plugins) candidates = candidates.concat(cfg.plugins)
      for (var i = 0; i < candidates.length; i++) {
        var entry = candidates[i]
        if (entry && entry.id === root.moduleName && entry[name] !== undefined && entry[name] !== null)
          return entry[name]
      }
    } catch (e) { /* unparsable or not yet loaded */ }
    return undefined
  }

  readonly property bool autoHideOnFocusLoss: { configRevision; return setting("autoHideOnFocusLoss", false) === true }
  readonly property bool allowSpecialFallthrough: { configRevision; return setting("allowSpecialFallthrough", false) === true }
  readonly property int autoHideDelayMs: { configRevision; return Math.max(0, Number(setting("autoHideDelayMs", 500))) }
  readonly property int widthPercent: { configRevision; return Math.max(20, Math.min(100, Number(setting("widthPercent", 90)))) }
  readonly property int heightPercent: { configRevision; return Math.max(20, Math.min(100, Number(setting("heightPercent", 45)))) }
  readonly property string borderColor: { configRevision; return String(setting("borderColor", "theme")) }
  readonly property bool slideFromTop: { configRevision; return setting("slideFromTop", true) !== false }
  // Manifest enum values are display strings and therefore part of the
  // persisted contract. Keep the runtime contract closed: an unknown value
  // falls back to the shipped Glow preset instead of creating an unsupported
  // surface or silently disabling the feature.
  readonly property string entranceEffect: {
    configRevision
    var value = String(setting("entranceEffect", "Glow")).toLowerCase()
    return value === "off" ? "Off" : "Glow"
  }
  readonly property int effectIntensity: {
    configRevision
    var value = Number(setting("effectIntensity", 50))
    if (!isFinite(value)) value = 50
    return Math.max(0, Math.min(100, Math.round(value / 10) * 10))
  }

  function parsedState() {
    stateRevision
    try {
      var parsed = JSON.parse(stateFile.text() || "")
      if (!parsed || parsed.version !== 1 || !Array.isArray(parsed.clients)) return null
      var clients = parsed.clients.filter(function(address) { return typeof address === "string" && /^0x[0-9a-f]+$/i.test(address) })
      if (clients.length === 0) return null
      var active = typeof parsed.active === "string" && clients.indexOf(parsed.active) >= 0
        ? parsed.active : clients[0]
      return { clients: clients, active: active }
    } catch (e) {
      return null
    }
  }

  readonly property string trackedAddress: {
    var state = parsedState()
    return state && state.active !== root.clearedTrackedAddress ? state.active : ""
  }

  function normalizedAddress(value) {
    var text = String(value === undefined || value === null ? "" : value).trim()
    if (!text) return ""
    // closewindow's raw payload is normally just the hexadecimal handle, while
    // the Hyprland model and persisted state use the 0x-prefixed form.
    text = text.split(/[,\s]/)[0]
    if (text.substring(0, 2).toLowerCase() !== "0x") text = "0x" + text
    return text.toLowerCase()
  }

  readonly property var trackedToplevel: {
    observationRevision
    var address = root.trackedAddress
    if (!address || !Hyprland.toplevels) return null
    var toplevels = Hyprland.toplevels.values || []
    for (var i = 0; i < toplevels.length; i++) {
      if (toplevels[i] && toplevels[i].address === address)
        return toplevels[i]
    }
    return null
  }

  readonly property bool terminalVisible: {
    observationRevision
    var monitors = Hyprland.monitors ? (Hyprland.monitors.values || []) : []
    for (var i = 0; i < monitors.length; i++) {
      var ipc = monitors[i] ? monitors[i].lastIpcObject : null
      var special = ipc ? ipc.specialWorkspace : null
      if (special && special.name === "special:dropdown-terminal") return true
    }
    return false
  }

  readonly property bool terminalFocused: {
    observationRevision
    var active = Hyprland.activeToplevel
    return !!root.trackedAddress && !!active && active.address === root.trackedAddress
  }

  readonly property rect terminalRect: {
    observationRevision
    var ipc = root.trackedToplevel ? root.trackedToplevel.lastIpcObject : null
    if (!ipc || !ipc.at || !ipc.size) return Qt.rect(0, 0, 0, 0)
    return Qt.rect(Number(ipc.at[0]) || 0, Number(ipc.at[1]) || 0,
      Number(ipc.size[0]) || 0, Number(ipc.size[1]) || 0)
  }

  readonly property var terminalMonitor: {
    observationRevision
    var toplevel = root.trackedToplevel
    // HyprlandToplevel.monitor is already the HyprlandMonitor object. Treating
    // it as an integer id leaves the monitor null on every normal model update.
    return toplevel && toplevel.monitor ? toplevel.monitor : null
  }

  function refreshToplevels() {
    if (typeof Hyprland.refreshToplevels === "function") Hyprland.refreshToplevels()
    observationRevision++
  }

  function refreshMonitors() {
    if (typeof Hyprland.refreshMonitors === "function") Hyprland.refreshMonitors()
    observationRevision++
  }

  function refreshObservedState() {
    refreshToplevels()
    refreshMonitors()
    observationRevision++
  }

  readonly property string helperPath: Qt.resolvedUrl("bin/omarchy-dropdown-terminal").toString().replace(/^file:\/\//, "")
  readonly property string bindPath: Qt.resolvedUrl("bin/omarchy-dropdown-terminal-bind").toString().replace(/^file:\/\//, "")
  readonly property string fallthroughPath: Qt.resolvedUrl("bin/omarchy-dropdown-terminal-special-fallthrough").toString().replace(/^file:\/\//, "")
  // Every helper action mutates the same window, workspace, and compositor
  // animation state, so they must never overlap; the helper's own flock is a
  // second line of defense for direct invocations.
  readonly property bool busy: toggleProcess.running || hideProcess.running || reconcileProcess.running
  // User-facing subset: only actions that actually summon the terminal.
  readonly property bool launching: toggleProcess.running || hideProcess.running
  // Timestamp of the last toggle start; focus events within this window belong
  // to the summon itself and must not arm the auto-hide timer.
  property double lastToggleStart: 0
  property bool settingsReady: false
  property bool desiredSpecialFallthrough: false
  property string bindingStatus: "unknown"
  property var bindingConflicts: []
  property bool bindingStatusReady: false
  property string fallthroughStatus: "unknown"

  onAllowSpecialFallthroughChanged: {
    if (settingsReady) applySpecialFallthrough(allowSpecialFallthrough)
  }

  Component.onCompleted: {
    root.refreshObservedState()
    settingsReady = true
    if (allowSpecialFallthrough) applySpecialFallthrough(true)
    refreshMutationStatus()
    root.logDebug("service ready address=" + root.trackedAddress)
  }

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
      root.reconcileSpecialWorkspace()
      if (!root.autoHideOnFocusLoss) return
      // On a dual-monitor setup the summon itself can bounce focus; ignore
      // those events instead of instantly hiding the freshly shown terminal.
      if (Date.now() - root.lastToggleStart < 1200) {
        hideTimer.stop()
        return
      }
      hideTimer.restart()
    }

    function onRawEvent(event) {
      if (!event || !event.name) return
      var name = String(event.name)
      root.logDebug("hypr event=" + name)
      if (name === "activespecial" || name === "activespecialv2"
          || name === "focusedmon" || name === "focusedmonv2") {
        root.refreshMonitors()
      } else if (name === "openwindow") {
        if (!root.trackedAddress) root.refreshToplevels()
      } else if (name === "closewindow") {
        var closed = event.address || event.data || ""
        if (root.trackedAddress && root.normalizedAddress(closed) === root.normalizedAddress(root.trackedAddress))
          root.clearedTrackedAddress = root.trackedAddress
        root.refreshToplevels()
      } else if (name === "movewindow" || name === "movewindowv2") {
        root.refreshToplevels()
      } else if (name === "configreloaded") {
        root.refreshObservedState()
      }
      // activewindow/activewindowv2 intentionally do not refresh: the host's
      // activeToplevel binding already carries focus changes.
    }
  }

  Timer {
    id: hideTimer
    interval: root.autoHideDelayMs
    repeat: false
    onTriggered: if (root.autoHideOnFocusLoss) root.hide()
  }

  // Every action needs the geometry: hiding slides the window off the top edge
  // before the workspace is toggled away.
  function helperArgs(action) {
    return ["bash", root.helperPath, action, String(root.widthPercent),
      String(root.heightPercent), root.borderColor, root.slideFromTop ? "1" : "0"]
  }

  Process {
    id: toggleProcess
    command: root.helperArgs("toggle")
    running: false
  }

  Process {
    id: hideProcess
    command: root.helperArgs("hide")
    running: false
  }

  Process {
    id: reconcileProcess
    command: root.helperArgs("cleanup")
    running: false
  }

  Process {
    id: fallthroughProcess
    property bool enabled: false
    command: ["bash", root.fallthroughPath, enabled ? "enable" : "disable"]
    running: false
    onExited: {
      if (root.desiredSpecialFallthrough !== enabled) {
        enabled = root.desiredSpecialFallthrough
        running = true
      } else {
        fallthroughStatusProcess.running = true
      }
    }
  }

  Process {
    id: bindProcess
    property bool allowConflict: false
    command: ["bash", root.bindPath, allowConflict ? "install-force" : "install"]
    running: false
    onExited: {
      root.bindingStatusReady = false
      allowConflict = false
      bindStatusProcess.running = true
    }
  }

  Process {
    id: bindStatusProcess
    command: ["bash", root.bindPath, "status"]
    stdout: StdioCollector { id: bindStatusOutput; waitForEnd: true }
    onExited: {
      var report = root.parseMutationStatus(bindStatusOutput.text)
      root.bindingConflicts = Array.isArray(report.conflicts) ? report.conflicts : []
      root.bindingStatus = report.available !== true ? "unavailable" : (report.supported === false ? "unsupported" : (report.installed === true ? "installed" : "not installed"))
      root.bindingStatusReady = true
    }
  }

  Process {
    id: fallthroughStatusProcess
    command: ["bash", root.fallthroughPath, "status"]
    stdout: StdioCollector { id: fallthroughStatusOutput; waitForEnd: true }
    onExited: {
      var report = root.parseMutationStatus(fallthroughStatusOutput.text)
      root.fallthroughStatus = report.available !== true ? "unavailable" : (report.supported === false ? "unsupported" : (report.installed === true ? "installed" : "not installed"))
    }
  }

  function toggle() {
    var now = Date.now()
    // Debounce: duplicate keybindings or key repeat must not queue a second
    // toggle behind the first, which would show and then instantly hide.
    if (root.busy || now - root.lastToggleStart < 150) {
      root.logDebug("toggle rejected busy-or-debounce")
      return
    }
    root.lastToggleStart = now
    root.logDebug("toggle start address=" + root.trackedAddress)
    toggleProcess.running = true
  }

  function hide() {
    if (!root.busy) {
      root.logDebug("hide start address=" + root.trackedAddress)
      hideProcess.running = true
    }
  }

  function reconcileSpecialWorkspace() {
    if (!root.busy) reconcileProcess.running = true
  }

  function applySpecialFallthrough(enabled) {
    desiredSpecialFallthrough = enabled
    root.logDebug("special fallthrough requested enabled=" + enabled)
    if (fallthroughProcess.running) return
    fallthroughProcess.enabled = enabled
    fallthroughProcess.running = true
  }

  function installHotkey(allowConflict) {
    if (!bindProcess.running) {
      root.logDebug("binding install requested")
      bindProcess.allowConflict = allowConflict === true
      bindProcess.running = true
    }
  }

  function parseMutationStatus(raw) {
    try {
      var report = JSON.parse(String(raw || ""))
      return report && typeof report === "object" ? report : ({ available: false })
    } catch (e) {
      return { available: false }
    }
  }

  function refreshMutationStatus() {
    root.bindingStatusReady = false
    if (!bindStatusProcess.running) bindStatusProcess.running = true
    if (!fallthroughStatusProcess.running) fallthroughStatusProcess.running = true
  }

  function setting(name, fallback) {
    var persisted = persistedSetting(name)
    if (persisted !== undefined) return persisted
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }
}
