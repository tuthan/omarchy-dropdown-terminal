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
  property bool observationCheckPending: false
  property bool observationCheckToplevels: false
  property bool observationCheckMonitors: false
  property int observationCheckAttempts: 0
  property string observationBeforeToplevels: ""
  property string observationBeforeMonitors: ""
  // The helper can animate a cross-output move for roughly 1.25 seconds.
  // Keep reconciling for a little longer than that so the model cannot stop
  // on the old owner while the compositor is still moving the client.
  readonly property int maxObservationCheckAttempts: 15
  property int commandRevision: 0
  property int eventProcessedOffset: 0
  property string eventIncompleteTail: ""
  property bool eventReplayReady: false
  property int eventRecordCount: 0
  property var commandSessions: Object.create(null)
  property string eventTerminalState: "closed"
  property int eventMalformedRecords: 0
  property int commandUnreadCount: 0
  property string commandUnreadResult: ""
  property string commandLatestFinishKey: ""
  property string commandLatestResult: ""
  property bool commandLatestQualifies: false
  property int commandLatestDurationMs: 0
  property int commandFlashUntil: 0
  property string commandFlashResult: ""
  property string commandDismissedFinishKey: ""
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

  // Resolve this through the helper so QML and the shell agree when
  // XDG_RUNTIME_DIR is unset or fails the helper's private-directory check.
  // Keep the FileViews detached until the answer arrives; guessing a path here
  // can make every bar instance read a different state journal.
  property string runtimeStateRoot: ""

  FileView {
    id: stateFile
    path: root.runtimeStateRoot ? root.runtimeStateRoot + "/io.github.tuthan.dropdown-terminal.state.json" : ""
    watchChanges: true
    onFileChanged: reload()
    onTextChanged: {
      root.stateRevision++
      root.clearedTrackedAddress = ""
      root.logDebug("runtime state reloaded")
    }
  }

  // The command journal is append-only and shared by every per-screen service
  // instance. FileView reloads asynchronously; parsing is therefore driven by
  // textChanged, never directly from onFileChanged.
  FileView {
    id: commandEventsFile
    path: root.runtimeStateRoot ? root.runtimeStateRoot + "/io.github.tuthan.dropdown-terminal.events" : ""
    watchChanges: root.commandTracking
    printErrors: false
    onFileChanged: if (root.commandTracking) reload()
    onTextChanged: if (root.commandTracking) root.consumeEventText(text(), true)
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

  // Hyprland's object models update asynchronously after a special-workspace
  // event. Re-probe once after the visibility property changes so the tracked
  // client geometry is available to the decorative layer without mutating the
  // dependency that is currently evaluating.
  Timer {
    id: terminalStateRefreshTimer
    interval: 100
    repeat: false
    onTriggered: if (root.terminalVisible) root.refreshObservedState()
  }

  // Hyprland.refreshToplevels()/refreshMonitors() complete through the IPC
  // event loop. Keep the cheap snapshot optimization, but check once after
  // the model has had time to publish the refreshed objects. Without this,
  // a cross-monitor summon can leave every per-screen service with the old
  // monitor/geometry and the visual layers either disappear or stay on the
  // previous output.
  Timer {
    id: observationRefreshTimer
    interval: 100
    repeat: false
    onTriggered: root.completeObservationCheck()
  }

  // Omarchy documents that a FileView watch can stop delivering notifications
  // after a burst of appends. Probe only while a command is running, so idle
  // bars create neither a timer wakeup nor a journal read.
  Timer {
    id: commandEventsReloadTimer
    interval: 1000
    repeat: true
    running: root.commandTracking && root.commandIntegrationInstalled && root.commandRunning
    onTriggered: commandEventsFile.reload()
  }

  Timer {
    id: commandFlashTimer
    interval: Math.max(1, root.commandFlashUntil - Date.now())
    repeat: false
    running: root.commandFlashUntil > 0
    onTriggered: {
      root.commandFlashUntil = 0
      root.commandFlashResult = ""
      root.commandRevision++
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
  readonly property string keybinding: {
    configRevision
    var value = String(setting("keybinding", "CTRL + GRAVE")).trim()
    return value || "CTRL + GRAVE"
  }
  readonly property bool slideFromTop: { configRevision; return setting("slideFromTop", true) !== false }
  // Manifest enum values are display strings and therefore part of the
  // persisted contract. Keep the runtime contract closed: an unknown value
  // falls back to the shipped Glow preset instead of creating an unsupported
  // surface or silently disabling the feature.
  readonly property string entranceEffect: {
    configRevision
    var value = String(setting("entranceEffect", "Glow")).toLowerCase()
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
    configRevision
    var value = Number(setting("effectIntensity", 50))
    if (!isFinite(value)) value = 50
    return Math.max(0, Math.min(100, Math.round(value / 10) * 10))
  }
  readonly property bool petEnabled: { configRevision; return setting("petEnabled", false) === true }
  readonly property string petSpecies: {
    configRevision
    var value = String(setting("petSpecies", "Penguin"))
    return ["Penguin", "Cat", "Corgi"].indexOf(value) >= 0 ? value : "Penguin"
  }
  readonly property string petActivity: {
    configRevision
    var value = String(setting("petActivity", "On focus"))
    return ["On focus", "Always while visible", "Celebrations only"].indexOf(value) >= 0
      ? value : "On focus"
  }
  readonly property bool reduceMotion: { configRevision; return setting("reduceMotion", false) === true }
  readonly property bool urgencyIndicator: { configRevision; return setting("urgencyIndicator", true) !== false }
  readonly property bool commandTracking: { configRevision; return setting("commandTracking", false) === true }
  readonly property int commandNotifyAfterMs: {
    configRevision
    var value = Number(setting("commandNotifyAfterMs", 5000))
    if (!isFinite(value)) value = 5000
    return Math.max(0, Math.min(60000, Math.round(value / 500) * 500))
  }
  readonly property bool commandFailureIndicator: { configRevision; return setting("commandFailureIndicator", true) !== false }
  readonly property bool commandCancelIsFailure: { configRevision; return setting("commandCancelIsFailure", false) === true }

  function resetCommandEvents() {
    root.eventProcessedOffset = 0
    root.eventIncompleteTail = ""
    root.eventReplayReady = false
    root.eventRecordCount = 0
    root.commandSessions = Object.create(null)
    root.eventTerminalState = "closed"
    root.eventMalformedRecords = 0
    root.commandUnreadCount = 0
    root.commandUnreadResult = ""
    root.commandLatestFinishKey = ""
    root.commandLatestResult = ""
    root.commandLatestQualifies = false
    root.commandLatestDurationMs = 0
    root.commandFlashUntil = 0
    root.commandFlashResult = ""
    root.commandDismissedFinishKey = ""
    root.commandRevision++
  }

  function newRecordMap() {
    return Object.create(null)
  }

  function pruneSession(sessionId, session) {
    if (!session || !session.starts || !session.commands) return

    var commandKeys = Object.keys(session.commands)
    while (commandKeys.length > root.maxSessionRecords) {
      var completedKey = commandKeys.shift()
      delete session.commands[completedKey]
      var completedFields = completedKey.split("\t")
      if (completedFields.length === 2) delete session.starts[completedFields[1]]
    }

    var startKeys = Object.keys(session.starts)
    while (startKeys.length > root.maxSessionRecords) {
      var oldestSequence = startKeys.shift()
      delete session.starts[oldestSequence]
      delete session.commands[sessionId + "\t" + oldestSequence]
    }
  }

  function pruneSessions() {
    var sessionIds = Object.keys(root.commandSessions)
    if (sessionIds.length <= root.maxCommandSessions) return

    // Completed sessions are disposable first. Active sessions are retained
    // until the hard cap is reached so commandRunning remains useful.
    for (var i = 0; i < sessionIds.length && sessionIds.length > root.maxCommandSessions; i++) {
      var candidate = root.commandSessions[sessionIds[i]]
      if (!candidate || !candidate.starts || Object.keys(candidate.starts).length === 0) {
        delete root.commandSessions[sessionIds[i]]
        sessionIds.splice(i, 1)
        i--
      }
    }
    while (sessionIds.length > root.maxCommandSessions)
      delete root.commandSessions[sessionIds.shift()]
  }

  function validEventSession(value) {
    return typeof value === "string" && value.length > 0 && value.length <= 128
      && !/[\t\r\n ]/.test(value)
  }

  function validEventSequence(value) {
    return typeof value === "string" && /^[0-9]+$/.test(value) && value.length <= 20
  }

  function eventTimestamp(value) {
    var timestamp = Number(value)
    return isFinite(timestamp) && timestamp >= 0 ? timestamp : NaN
  }

  function eventResultForStatus(status) {
    if (status === 130 && !root.commandCancelIsFailure) return "cancelled"
    return status === 0 ? "succeeded" : "failed"
  }

  function applyCommandFinish(fields, allowTransient) {
    if (fields.length !== 6 && fields.length !== 7) return false
    var sessionId = fields[2]
    var sequence = fields[3]
    var finishTimestamp = eventTimestamp(fields[4])
    var status = Number(fields[5])
    if (!root.validEventSession(sessionId) || !root.validEventSequence(sequence)
        || !isFinite(finishTimestamp) || !/^-?[0-9]+$/.test(fields[5])
        || !isFinite(status)) return false

    var session = root.commandSessions[sessionId]
    if (!session || !session.starts) return false
    var key = sessionId + "\t" + sequence
    var start = session.starts[sequence]
    if (!start || session.commands[key]) return false

    var durationMs = NaN
    if (fields.length === 7 && /^[0-9]+$/.test(fields[6]))
      durationMs = Number(fields[6])
    if (!isFinite(durationMs) && finishTimestamp >= start.timestamp && start.timestamp > 0)
      durationMs = Math.round((finishTimestamp - start.timestamp) * 1000)
    if (!isFinite(durationMs) || durationMs < 0 || durationMs > 2147483647) return false

    var result = root.eventResultForStatus(status)
    var cancelled = result === "cancelled"
    var qualifies = !cancelled && durationMs >= root.commandNotifyAfterMs
      && (result !== "failed" || root.commandFailureIndicator)
    session.commands[key] = {
      result: result, durationMs: durationMs, status: status, qualifies: qualifies,
      lifecycle: root.eventTerminalState
    }
    root.pruneSession(sessionId, session)
    root.pruneSessions()
    root.commandLatestResult = result
    root.commandLatestQualifies = qualifies
    root.commandLatestDurationMs = durationMs
    // Publish the key last: PetController observes this signal and must see
    // the complete result tuple, not the previous event's payload.
    root.commandLatestFinishKey = key
    if (qualifies && root.eventTerminalState === "hidden") {
      root.commandUnreadCount++
      root.commandUnreadResult = result
    } else if (qualifies && allowTransient === true && root.eventTerminalState === "shown") {
      root.commandFlashResult = result
      root.commandFlashUntil = Date.now() + 900
      commandFlashTimer.restart()
    }
    return true
  }

  function applyCommandStart(fields) {
    if (fields.length !== 5) return false
    var sessionId = fields[2]
    var sequence = fields[3]
    var timestamp = eventTimestamp(fields[4])
    if (!root.validEventSession(sessionId) || !root.validEventSequence(sequence)
        || !isFinite(timestamp)) return false
    var sessions = root.commandSessions
    var session = sessions[sessionId]
    if (!session) session = { starts: root.newRecordMap(), commands: root.newRecordMap() }
    session.starts[sequence] = { timestamp: timestamp }
    root.pruneSession(sessionId, session)
    sessions[sessionId] = session
    root.commandSessions = sessions
    root.pruneSessions()
    return true
  }

  function applyLifecycle(fields) {
    if (fields.length !== 6) return false
    var phase = fields[1]
    var timestamp = eventTimestamp(fields[4])
    var address = String(fields[5] || "")
    if (["shown", "hidden", "closed"].indexOf(phase) < 0
        || fields[2] !== "helper" || !validEventSession(fields[3])
        || !isFinite(timestamp) || !/^0x[0-9a-f]+$/i.test(address)) return false
    root.eventTerminalState = phase
    if (phase === "closed") {
      // A terminal close can race the shell's final prompt, so its active
      // commands may never emit a finish record. Discard those starts now;
      // otherwise a replay would keep the command indicator and reload timer
      // permanently in the running state after the terminal is reopened.
      var sessions = root.commandSessions
      var sessionIds = Object.keys(sessions)
      for (var i = 0; i < sessionIds.length; i++) {
        var sessionId = sessionIds[i]
        var session = sessions[sessionId]
        if (!session || !session.starts) continue
        var sequences = Object.keys(session.starts)
        for (var j = 0; j < sequences.length; j++) {
          var sequence = sequences[j]
          var key = sessionId + "\t" + sequence
          if (!session.commands || !session.commands[key]) delete session.starts[sequence]
        }
        root.pruneSession(sessionId, session)
      }
      root.commandSessions = sessions
      root.pruneSessions()
    }
    if (phase === "shown" || phase === "closed") {
      root.commandUnreadCount = 0
      root.commandUnreadResult = ""
      root.commandDismissedFinishKey = root.commandLatestFinishKey
    }
    return true
  }

  function applyEventLine(line, allowTransient) {
    if (!line) return true
    // A malformed record must not abort replay of the remaining journal. Keep
    // the line bounded as well: the shell contract has no field large enough
    // to justify allocating arbitrary input here.
    if (line.length > 512) return false
    try {
      var fields = line.split("\t")
      if (fields[0] !== "v1") return false
      if (fields[1] === "start") return root.applyCommandStart(fields)
      if (fields[1] === "finish") return root.applyCommandFinish(fields, allowTransient)
      if (fields[1] === "shown" || fields[1] === "hidden" || fields[1] === "closed")
        return root.applyLifecycle(fields)
      return false
    } catch (e) {
      root.logDebug("event record rejected")
      return false
    }
  }

  function consumeEventText(raw, fileLoadComplete) {
    var fullText = String(raw || "")
    var rebuilding = fullText.length < root.eventProcessedOffset || fullText.length > root.maxEventBytes
    var text = fullText
    if (rebuilding) {
      root.resetCommandEvents()
      if (fullText.length > root.maxEventBytes) {
        var cutoff = fullText.length - root.maxEventBytes
        var boundary = fullText.indexOf("\n", cutoff)
        text = boundary >= 0 ? fullText.substring(boundary + 1) : ""
      }
    }
    var allowTransient = root.eventReplayReady && !rebuilding
    var added = rebuilding ? text : text.substring(root.eventProcessedOffset)
    var combined = root.eventIncompleteTail + added
    var hasTrailingNewline = combined.endsWith("\n")
    var lines = combined.split("\n")
    if (hasTrailingNewline) {
      lines.pop()
      root.eventIncompleteTail = ""
    } else {
      root.eventIncompleteTail = lines.pop() || ""
    }
    if (lines.length > root.maxEventRecords) {
      root.resetCommandEvents()
      lines = lines.slice(-root.maxEventRecords)
      allowTransient = false
    }
    var malformed = 0
    for (var i = 0; i < lines.length; i++) {
      if (!root.applyEventLine(lines[i], allowTransient)) malformed++
    }
    root.eventMalformedRecords = Math.min(root.maxEventRecords,
      root.eventMalformedRecords + malformed)
    root.eventRecordCount = Math.min(root.maxEventRecords,
      root.eventRecordCount + lines.length)
    root.eventProcessedOffset = fullText.length
    // The first completed FileView load is the replay baseline. The fallback
    // nudge may see an empty stale value while reload() is still async, so it
    // only establishes the baseline once text is present.
    if (fileLoadComplete === true || text.length > 0) root.eventReplayReady = true
    root.commandRevision++
    // This is a presentational dismissal only. Historical hidden-at-finish
    // classification above always uses event order, never current visibility.
    if (root.terminalFocused || root.terminalVisible) root.clearCommandUnread()
    if (malformed > 0) root.logDebug("event journal malformed records=" + malformed)
  }

  function clearCommandUnread() {
    if (root.commandUnreadCount === 0) return
    root.commandUnreadCount = 0
    root.commandUnreadResult = ""
    root.commandDismissedFinishKey = root.commandLatestFinishKey
    root.commandRevision++
  }

  function reloadCommandEvents() {
    commandEventsFile.reload()
    // A reload may complete without changing FileView.text() when tracking is
    // toggled off and on. Re-read on the next event-loop turn so replay still
    // reconstructs the existing journal from offset zero.
    Qt.callLater(function() {
      if (root.commandTracking) root.consumeEventText(commandEventsFile.text(), false)
    })
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
      if (toplevels[i] && root.normalizedAddress(toplevels[i].address) === address)
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

  readonly property bool terminalUrgent: {
    observationRevision
    var toplevel = root.trackedToplevel
    return root.urgencyIndicator && !!toplevel && toplevel.urgent === true
  }

  readonly property bool commandRunning: {
    commandRevision
    for (var sessionId in root.commandSessions) {
      var session = root.commandSessions[sessionId]
      if (!session || !session.starts) continue
      for (var sequence in session.starts) {
        var key = sessionId + "\t" + sequence
        if (!session.commands || !session.commands[key]) return true
      }
    }
    return false
  }

  readonly property bool commandUnread: { commandRevision; return root.commandUnreadCount > 0 }
  readonly property bool commandFlashActive: {
    commandRevision
    return root.commandFlashUntil > Date.now() && root.commandFlashResult !== ""
  }

  readonly property string indicatorState: {
    commandRevision
    if (root.commandTracking && root.commandIntegrationInstalled) {
      if (root.commandFlashActive) return root.commandFlashResult
      if (root.commandRunning) return "running"
      if (root.commandUnread && (root.commandUnreadResult === "succeeded" || root.commandUnreadResult === "failed"))
        return root.commandUnreadResult
    }
    if (root.urgencyIndicator && !root.terminalVisible && !root.terminalFocused && root.terminalUrgent)
      return "attention"
    return "idle"
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
    return root.monitorFromClientPayload(toplevel)
  }

  function normalizedSnapshotNumber(value) {
    var number = Number(value)
    return isFinite(number) ? String(Math.round(number * 100) / 100) : "?"
  }

  function toplevelGeometrySnapshot() {
    var address = root.trackedAddress
    if (!address || !Hyprland.toplevels) return "none"
    var toplevels = Hyprland.toplevels.values || []
    for (var i = 0; i < toplevels.length; i++) {
      var toplevel = toplevels[i]
      if (!toplevel || root.normalizedAddress(toplevel.address) !== address) continue
      var ipc = toplevel.lastIpcObject
      if (!ipc || !ipc.at || !ipc.size) return address + "|missing"
      var monitor = root.monitorFromClientPayload(toplevel)
      var monitorName = monitor ? String(monitor.name || "") : ""
      return [address, monitorName, root.normalizedSnapshotNumber(ipc.at[0]),
        root.normalizedSnapshotNumber(ipc.at[1]), root.normalizedSnapshotNumber(ipc.size[0]),
        root.normalizedSnapshotNumber(ipc.size[1])].join("|")
    }
    return address + "|unresolved"
  }

  function monitorSnapshot() {
    var monitors = Hyprland.monitors ? (Hyprland.monitors.values || []) : []
    var values = []
    for (var i = 0; i < monitors.length; i++) {
      var monitor = monitors[i]
      if (!monitor) continue
      var ipc = monitor.lastIpcObject || {}
      var special = ipc.specialWorkspace || {}
      values.push([String(monitor.name || ""), String(special.name || ""),
        root.normalizedSnapshotNumber(monitor.x), root.normalizedSnapshotNumber(monitor.y),
        monitor.focused === true ? "1" : "0"].join("|"))
    }
    values.sort()
    return values.join(";")
  }

  // During a special-workspace transfer the HyprlandToplevel.monitor QObject
  // can lag behind the client payload. The payload is the same source used by
  // `hyprctl clients -j`, so resolve its monitor id/name against the refreshed
  // monitor model before falling back to the convenience property.
  function monitorFromClientPayload(toplevel) {
    if (!toplevel) return null
    var ipc = toplevel.lastIpcObject || {}
    var raw = ipc.monitor
    var monitors = Hyprland.monitors ? (Hyprland.monitors.values || []) : []
    var numericId = Number(raw)
    if (isFinite(numericId)) {
      for (var i = 0; i < monitors.length; i++) {
        if (monitors[i] && Number(monitors[i].id) === numericId) return monitors[i]
      }
    }
    var name = String(raw === undefined || raw === null ? "" : raw)
    if (name) {
      for (var j = 0; j < monitors.length; j++) {
        if (monitors[j] && String(monitors[j].name || "") === name) return monitors[j]
      }
    }
    return toplevel.monitor || null
  }

  function queueObservationCheck(toplevelSnapshot, monitorSnapshot) {
    var checkToplevels = toplevelSnapshot !== undefined && toplevelSnapshot !== null
    var checkMonitors = monitorSnapshot !== undefined && monitorSnapshot !== null
    if (!checkToplevels && !checkMonitors) return

    if (!root.observationCheckPending) root.observationCheckAttempts = 0

    if (checkToplevels && !root.observationCheckToplevels) {
      root.observationBeforeToplevels = String(toplevelSnapshot)
      root.observationCheckToplevels = true
    }
    if (checkMonitors && !root.observationCheckMonitors) {
      root.observationBeforeMonitors = String(monitorSnapshot)
      root.observationCheckMonitors = true
    }
    root.observationCheckPending = true
    observationRefreshTimer.restart()
  }

  function completeObservationCheck() {
    if (!root.observationCheckPending) return

    var changed = false
    if (root.observationCheckToplevels
        && root.observationBeforeToplevels !== root.toplevelGeometrySnapshot()) changed = true
    if (root.observationCheckMonitors
        && root.observationBeforeMonitors !== root.monitorSnapshot()) changed = true

    // A monitor transfer can take longer than one IPC turn while Hyprland is
    // finishing the window move. Re-issue the bounded refresh a few times so
    // the owner monitor cannot remain stale just because the first response
    // arrived before the compositor published the new toplevel.
    if (!changed && root.observationCheckAttempts < root.maxObservationCheckAttempts) {
      root.observationCheckAttempts++
      if (root.observationCheckToplevels && typeof Hyprland.refreshToplevels === "function")
        Hyprland.refreshToplevels()
      if (root.observationCheckMonitors && typeof Hyprland.refreshMonitors === "function")
        Hyprland.refreshMonitors()
      observationRefreshTimer.restart()
      return
    }

    root.observationCheckPending = false
    root.observationCheckToplevels = false
    root.observationCheckMonitors = false
    root.observationCheckAttempts = 0
    root.observationBeforeToplevels = ""
    root.observationBeforeMonitors = ""
    if (changed) root.observationRevision++
  }

  function refreshToplevels() {
    var before = root.toplevelGeometrySnapshot()
    if (typeof Hyprland.refreshToplevels !== "function") return
    Hyprland.refreshToplevels()
    if (before !== root.toplevelGeometrySnapshot()) root.observationRevision++
    else root.queueObservationCheck(before, null)
  }

  function refreshMonitors() {
    var before = root.monitorSnapshot()
    if (typeof Hyprland.refreshMonitors !== "function") return
    Hyprland.refreshMonitors()
    if (before !== root.monitorSnapshot()) root.observationRevision++
    else root.queueObservationCheck(null, before)
  }

  function refreshObservedState() {
    var beforeToplevels = root.toplevelGeometrySnapshot()
    var beforeMonitors = root.monitorSnapshot()
    var refreshedToplevels = typeof Hyprland.refreshToplevels === "function"
    var refreshedMonitors = typeof Hyprland.refreshMonitors === "function"
    if (refreshedToplevels) Hyprland.refreshToplevels()
    if (refreshedMonitors) Hyprland.refreshMonitors()
    var toplevelsChanged = beforeToplevels !== root.toplevelGeometrySnapshot()
    var monitorsChanged = beforeMonitors !== root.monitorSnapshot()
    if (toplevelsChanged || monitorsChanged) root.observationRevision++
    root.queueObservationCheck(
      refreshedToplevels && !toplevelsChanged ? beforeToplevels : null,
      refreshedMonitors && !monitorsChanged ? beforeMonitors : null)
  }

  readonly property string helperPath: Qt.resolvedUrl("bin/omarchy-dropdown-terminal").toString().replace(/^file:\/\//, "")
  readonly property string bindPath: Qt.resolvedUrl("bin/omarchy-dropdown-terminal-bind").toString().replace(/^file:\/\//, "")
  readonly property string fallthroughPath: Qt.resolvedUrl("bin/omarchy-dropdown-terminal-special-fallthrough").toString().replace(/^file:\/\//, "")
  readonly property string shellIntegrationPath: Qt.resolvedUrl("bin/omarchy-dropdown-terminal-shell").toString().replace(/^file:\/\//, "")

  Process {
    id: runtimeStateRootProcess
    command: ["bash", root.helperPath, "state-root"]
    stdout: StdioCollector { id: runtimeStateRootOutput; waitForEnd: true }
    running: false
    onExited: {
      var candidate = String(runtimeStateRootOutput.text || "").trim()
      if (candidate.charAt(0) === "/" && candidate.indexOf("\n") < 0 && candidate.indexOf("\r") < 0)
        root.runtimeStateRoot = candidate
    }
  }

  // Every helper action mutates the same window, workspace, and compositor
  // animation state, so they must never overlap; the helper's own flock is a
  // second line of defense for direct invocations.
  readonly property bool busy: toggleProcess.running || hideProcess.running || reconcileProcess.running
  property bool closeReconcilePending: false
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
  property string shellStatus: "unknown"
  property var shellStatusReport: ({})
  property bool shellStatusReady: false
  property string shellMutationAction: ""
  property string shellActionMessage: ""

  readonly property int maxEventBytes: 262144
  readonly property int maxEventRecords: 2048
  readonly property int maxCommandSessions: 64
  readonly property int maxSessionRecords: 128

  readonly property bool commandIntegrationInstalled: {
    shellStatusRevision
    return root.commandTracking && root.shellStatus === "installed"
      && root.shellStatusReport && root.shellStatusReport.sourceReadable === true
  }
  property int shellStatusRevision: 0

  onCommandTrackingChanged: {
    root.resetCommandEvents()
    if (root.commandTracking) root.reloadCommandEvents()
  }
  onTerminalVisibleChanged: {
    if (root.terminalVisible) {
      terminalStateRefreshTimer.restart()
      root.clearCommandUnread()
    }
  }
  onTerminalFocusedChanged: if (root.terminalFocused) root.clearCommandUnread()

  onAllowSpecialFallthroughChanged: {
    if (settingsReady) applySpecialFallthrough(allowSpecialFallthrough)
  }

  onKeybindingChanged: if (settingsReady) refreshMutationStatus()

  Component.onCompleted: {
    runtimeStateRootProcess.running = true
    root.refreshObservedState()
    settingsReady = true
    if (allowSpecialFallthrough) applySpecialFallthrough(true)
    refreshMutationStatus()
    refreshShellIntegrationStatus()
    if (commandTracking) reloadCommandEvents()
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
        root.refreshToplevels()
      } else if (name === "openwindow") {
        if (!root.trackedAddress) root.refreshToplevels()
      } else if (name === "closewindow") {
        var closed = event.address || event.data || ""
        var matchesTracked = root.trackedAddress && root.normalizedAddress(closed) === root.normalizedAddress(root.trackedAddress)
        if (matchesTracked) {
          root.clearedTrackedAddress = root.trackedAddress
          root.requestCloseReconcile()
        }
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
    command: ["bash", root.bindPath, allowConflict ? "install-force" : "install", root.keybinding]
    running: false
    onExited: {
      root.bindingStatusReady = false
      allowConflict = false
      bindStatusProcess.running = true
    }
  }

  Process {
    id: bindStatusProcess
    command: ["bash", root.bindPath, "status", root.keybinding]
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

  Process {
    id: shellStatusProcess
    command: ["bash", root.shellIntegrationPath, "status"]
    stdout: StdioCollector { id: shellStatusOutput; waitForEnd: true }
    onExited: {
      var report = root.parseMutationStatus(shellStatusOutput.text)
      root.shellStatusReport = report
      root.shellStatus = report.available !== true ? "unavailable"
        : (report.supported === false ? "unsupported"
          : (report.installed === true ? "installed" : "not installed"))
      root.shellStatusReady = true
      root.shellStatusRevision++
      root.finishShellMutationFromStatus(report)
    }
  }

  Process {
    id: shellMutationProcess
    property string requestedAction: ""
    command: ["bash", root.shellIntegrationPath, requestedAction]
    running: false
    onExited: {
      // Exit status alone is not a success signal. The exact managed block is
      // checked by a fresh status read-back before the panel reports success.
      root.shellStatusReady = false
      if (!shellStatusProcess.running) shellStatusProcess.running = true
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

  function requestCloseReconcile() {
    if (!root.busy) {
      reconcileProcess.running = true
    } else {
      root.closeReconcilePending = true
    }
  }

  onBusyChanged: {
    if (!root.busy && root.closeReconcilePending) {
      root.closeReconcilePending = false
      reconcileProcess.running = true
    }
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

  function finishShellMutationFromStatus(report) {
    if (root.shellMutationAction === "") return
    var action = root.shellMutationAction
    var exact = report && report.available === true && report.supported !== false
      && report.sourceReadable === true
    var installed = exact && report.installed === true
    if (action === "install") {
      root.shellActionMessage = installed
        ? "Installed command tracking for " + String(report.shell || "the login shell") + "."
        : "Install failed: the exact guarded block was not read back."
    } else {
      root.shellActionMessage = exact && !installed
        ? "Removed command tracking from " + String(report.shell || "the login shell") + "."
        : "Remove failed: the exact guarded block is still present."
    }
    root.shellMutationAction = ""
  }

  function refreshShellIntegrationStatus() {
    root.shellStatusReady = false
    if (!shellStatusProcess.running && !shellMutationProcess.running)
      shellStatusProcess.running = true
  }

  function mutateShellIntegration(action) {
    if (action !== "install" && action !== "remove") return
    if (shellMutationProcess.running || shellStatusProcess.running) return
    root.shellActionMessage = ""
    root.shellMutationAction = action
    shellMutationProcess.requestedAction = action
    shellMutationProcess.running = true
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
