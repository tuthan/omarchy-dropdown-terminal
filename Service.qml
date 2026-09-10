import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "PetBond.js" as PetBond

Item {
  id: root
  visible: false

  property var settings: ({})
  property var hostScreen: null
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
  // Cached once for each terminal reveal. The pet layer uses this margin to
  // leave Hyprland's active resize-sensitive grab ring to the terminal
  // surface. When resize_on_border is disabled, only the real border is
  // reserved; an inactive resize ring must not consume the pet's body.
  property real grabMargin: 17
  property bool grabMarginReady: false
  readonly property real fallbackGrabMargin: 64
  readonly property real maxGrabMarginComponent: 4096
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
  property int commandLatestStatus: 0
  property int commandFlashUntil: 0
  property string commandFlashResult: ""
  property string commandDismissedFinishKey: ""
  property string clearedTrackedAddress: ""
  // Bond state is intentionally separate from the runtime journal. It is a
  // durable, user-readable score and is written only by the service whose
  // terminal currently has an owning monitor.
  property int bondRevision: 0
  property bool bondReadReady: false
  property bool bondUnavailable: false
  property bool bondMissing: true
  property var bondDocument: null
  property var bondDeltas: []
  property var bondAppliedDeltas: []
  property string bondWriter: ""
  property int bondNextRevision: 0
  property bool bondWriteInFlight: false
  property bool bondFlushRetry: false
  property bool bondDirectoryReady: false
  property bool bondFlushWaitingForReload: false
  property string bondFlushOwner: ""
  property string bondExpectedText: ""
  readonly property string bondStateRoot: (Quickshell.env("XDG_STATE_HOME")
    || ((Quickshell.env("HOME") || "") + "/.local/state"))
    + "/io.github.tuthan.dropdown-terminal"
  readonly property string bondPath: root.bondStateRoot + "/bond.json"
  readonly property string bondOwnerName: root.terminalMonitor
    ? String(root.terminalMonitor.name || "") : ""
  readonly property bool bondOwner: !!root.hostScreen && root.bondOwnerName !== ""
    && String(root.hostScreen.name || "") === root.bondOwnerName
  readonly property string bondDiagnostic: root.bondUnavailable
    ? "Bond: Unavailable (" + root.bondPath + ")" : ""
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

  // Pet position is a separate, short-lived document. Only the Service whose
  // screen hosts the terminal may call savePetState; sibling services are
  // readers and never perform a read-modify-write of this file.
  property int petStateRevision: 0
  property bool petStateReadReady: false
  property var petStateDocument: null
  property var pendingPetState: null
  property string petStateWriter: ""
  property int petStateNextRevision: 0
  FileView {
    id: petStateFile
    path: root.runtimeStateRoot ? root.runtimeStateRoot + "/io.github.tuthan.dropdown-terminal.pet-state.json" : ""
    atomicWrites: true
    watchChanges: false
    printErrors: false
    onTextChanged: {
      petStateReadTimer.stop()
      root.petStateRevision++
      root.petStateReadReady = true
      try {
        var parsed = JSON.parse(text() || "")
        root.petStateDocument = parsed && typeof parsed === "object" ? parsed : null
        if (parsed && isFinite(Number(parsed.revision)))
          root.petStateNextRevision = Math.max(root.petStateNextRevision, Number(parsed.revision))
      } catch (e) {
        root.petStateDocument = null
        root.logDebug("pet position document ignored: invalid JSON")
      }
    }
    onSaveFailed: root.logDebug("pet position save failed")
  }

  Timer {
    id: petStateWriteTimer
    interval: 2000
    repeat: false
    onTriggered: root.flushPetState()
  }

  // FileView has no synchronous "missing file" result. Give a reload one
  // bounded second to publish its contents, then allow the pet to use the
  // Phase 5 default position rather than waiting forever on a first run.
  Timer {
    id: petStateReadTimer
    interval: 1000
    repeat: false
    onTriggered: {
      if (!root.petStateReadReady) {
        root.petStateReadReady = true
        root.petStateRevision++
        root.logDebug("pet position read timed out; using default")
      }
    }
  }

  // Bond is a durable document rather than a runtime cache. FileView changes
  // are the only external refresh trigger; all arithmetic is replayed through
  // PetBond so a sibling service never writes a stale snapshot.
  FileView {
    id: bondFile
    path: root.bondPath
    atomicWrites: true
    watchChanges: true
    printErrors: false
    onFileChanged: {
      if (root.bondWriteInFlight || root.bondFlushWaitingForReload)
        root.bondFlushRetry = true
      reload()
    }
    onLoaded: if (!root.bondWriteInFlight) root.consumeBondText(text())
    onTextChanged: {
      // setText() updates FileView.text before the asynchronous save signal.
      // Do not treat our own pending snapshot as a fresh disk read: the
      // queued deltas are already represented in that snapshot and replaying
      // them here would double-apply the bond change.
      if (root.bondWriteInFlight) return
      root.consumeBondText(text())
    }
    onLoadFailed: bondProbeProcess.running = true
    onSaved: root.finishBondSave()
    onSaveFailed: root.finishBondSaveFailed()
  }

  Process {
    id: bondProbeProcess
    command: ["bash", "-c", "if [ ! -e \"$1\" ]; then printf missing; elif [ ! -r \"$1\" ]; then printf unreadable; else printf present; fi", "bash", root.bondPath]
    running: false
    stdout: StdioCollector { id: bondProbeOutput; waitForEnd: true }
    onExited: {
      var state = String(bondProbeOutput.text || "").trim()
      if (state === "missing") {
        bondReadTimer.stop()
        root.bondReadReady = true
        root.bondMissing = true
        root.bondUnavailable = false
        root.bondDocument = PetBond.emptyDocument(root.localDay(), root.bondOwnerName)
        root.bondRevision++
      } else if (state === "unreadable") {
        root.markBondUnavailable("bond document could not be read")
      }
    }
  }

  Timer {
    id: bondReadTimer
    interval: 1000
    repeat: false
    onTriggered: {
      if (root.bondReadReady) return
      // FileView does not expose a useful synchronous missing-file result. An
      // empty first read is the documented missing-file path: all species are
      // Wary and the writer will create the directory only on first mutation.
      root.bondReadReady = true
      root.bondMissing = true
      root.bondUnavailable = false
      root.bondDocument = PetBond.emptyDocument(root.localDay(), root.bondOwnerName)
      root.bondRevision++
      root.logDebug("bond document missing; using Wary defaults")
    }
  }

  Timer {
    id: bondFlushTimer
    interval: 2000
    repeat: false
    onTriggered: root.flushBondState()
  }

  Timer {
    id: bondReloadTimer
    interval: 120
    repeat: false
    onTriggered: root.finishBondReload()
  }

  Timer {
    id: bondMidnightTimer
    interval: 3600000
    repeat: false
    onTriggered: {
      root.chargeBondDecay()
      root.scheduleBondMidnight()
    }
  }

  Process {
    id: bondDirectoryProcess
    command: ["bash", "-c", "mkdir -p -- \"$1\" && chmod 700 -- \"$1\"", "bash", root.bondStateRoot]
    running: false
    onExited: {
      root.bondDirectoryReady = true
      root.flushBondState(root.bondFlushOwner || undefined)
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

  function localDay() {
    var now = new Date()
    return Math.floor(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()) / 86400000)
  }

  function scheduleBondMidnight() {
    var now = new Date()
    var next = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 0, 0, 25)
    bondMidnightTimer.interval = Math.max(1000, Math.min(86400000, next.getTime() - now.getTime()))
    bondMidnightTimer.restart()
  }

  function bondSpeciesNames() {
    return PetBond.SPECIES.slice()
  }

  function bondRecord(species) {
    var name = String(species || "Penguin")
    var today = root.localDay()
    if (root.bondUnavailable || !root.bondDocument)
      return PetBond.emptySpecies(today)
    var record = root.bondDocument.species && root.bondDocument.species[name]
    return PetBond.normalizeSpecies(record, today)
  }

  function bondValue(species) {
    return root.bondRecord(species).bond
  }

  function bondPeakTier(species) {
    return root.bondRecord(species).peakTier
  }

  function validBondDocument(document) {
    return PetBond.validDocument(document)
  }

  function requestBondRead() {
    bondReadTimer.stop()
    root.bondReadReady = false
    root.bondUnavailable = false
    root.bondMissing = true
    root.bondDocument = null
    root.bondDirectoryReady = false
    bondReadTimer.restart()
    bondFile.reload()
  }

  function markBondUnavailable(reason) {
    bondReadTimer.stop()
    root.bondReadReady = true
    root.bondMissing = false
    root.bondUnavailable = true
    root.bondDocument = null
    root.bondDeltas = []
    root.bondAppliedDeltas = []
    root.bondFlushWaitingForReload = false
    root.bondWriteInFlight = false
    root.bondFlushRetry = false
    root.bondExpectedText = ""
    root.bondFlushOwner = ""
    root.logDebug(reason || "bond document unavailable")
    root.bondRevision++
  }

  function consumeBondText(raw) {
    var text = String(raw || "")
    if (text.trim() === "") {
      if (!root.bondReadReady || root.bondMissing) {
        bondReadTimer.stop()
        root.bondReadReady = true
        root.bondMissing = true
        root.bondUnavailable = false
        root.bondDocument = PetBond.emptyDocument(root.localDay(), root.bondOwnerName)
        root.bondRevision++
      }
      return
    }
    var parsed
    try {
      parsed = JSON.parse(text)
    } catch (e) {
      root.markBondUnavailable("bond document ignored: invalid JSON")
      return
    }
    if (!root.validBondDocument(parsed)) {
      root.markBondUnavailable("bond document ignored: unsupported or invalid version")
      return
    }
    bondReadTimer.stop()
    root.bondReadReady = true
    root.bondMissing = false
    root.bondUnavailable = false
    var decayed = PetBond.applyDocumentDecay(parsed, root.localDay())
    root.bondDocument = decayed.document
    root.bondNextRevision = Math.max(root.bondNextRevision,
      Number(decayed.document.revision) || 0)
    if (decayed.changed && root.bondOwner) {
      var decayDeltas = root.bondDeltas.slice()
      var today = root.localDay()
      for (var i = 0; i < 3; i++)
        decayDeltas.push({ species: root.bondSpeciesNames()[i], kind: "decay", today: today })
      root.bondDeltas = decayDeltas
      bondFlushTimer.restart()
    }
    // Preserve a locally queued delta on top of a fresh reader snapshot so a
    // monitor transfer or an external FileView notification cannot make the
    // panel jump backwards before the read-modify-write completes.
    if (root.bondDeltas.length > 0)
      root.bondDocument = PetBond.applyDeltas(root.bondDocument, root.bondDeltas, root.localDay())
    root.bondRevision++
  }

  function queueBondDelta(species, kind) {
    if (!root.bondReadReady || root.bondUnavailable || !root.bondOwner) return false
    var name = String(species || root.petSpecies)
    if (root.bondSpeciesNames().indexOf(name) < 0) return false
    if (!root.bondDocument)
      root.bondDocument = PetBond.emptyDocument(root.localDay(), root.bondOwnerName)
    var delta = { species: name, kind: String(kind || "") }
    var queued = root.bondDeltas.slice()
    // A reset is a user-confirmed boundary. Do not let mutations queued before
    // that boundary reappear when the delta log is merged into fresh disk data;
    // later mutations in the same coalescing window still apply after reset.
    if (String(delta.kind).toLowerCase() === "reset") {
      queued = queued.filter(function(previous) {
        return String(previous && previous.species || "") !== name
      })
    }
    root.bondDeltas = queued.concat([delta])
    root.bondDocument.species[name] = PetBond.applyDelta(root.bondDocument.species[name],
      delta.kind, root.localDay())
    root.bondRevision++
    bondFlushTimer.restart()
    return true
  }

  function resetBond(species) {
    return root.queueBondDelta(String(species || root.petSpecies), "reset")
  }

  function ensureBondDirectory() {
    if (root.bondDirectoryReady) return true
    if (!bondDirectoryProcess.running) bondDirectoryProcess.running = true
    return false
  }

  function flushBondState(ownerOverride) {
    if (!root.bondReadReady || root.bondUnavailable || root.bondDeltas.length === 0) return
    var currentOwner = root.bondOwnerName
    var hasOwnerOverride = ownerOverride !== undefined && ownerOverride !== null
      && String(ownerOverride) !== ""
    var writer = String(ownerOverride || currentOwner || "")
    if (!writer || (!hasOwnerOverride && !root.bondOwner)
        || (!hasOwnerOverride && writer !== currentOwner)
        || (root.bondWriter && root.bondWriter !== writer)) return
    if (root.bondWriteInFlight || root.bondFlushWaitingForReload) {
      root.bondFlushRetry = true
      return
    }
    root.bondFlushOwner = writer
    if (!root.ensureBondDirectory()) return
    root.bondWriter = writer
    root.bondAppliedDeltas = root.bondDeltas.slice()
    root.bondFlushWaitingForReload = true
    bondFile.reload()
    bondReloadTimer.restart()
  }

  function dropAppliedBondDeltas() {
    var pending = root.bondDeltas.slice()
    for (var i = 0; i < root.bondAppliedDeltas.length; i++) {
      var index = pending.indexOf(root.bondAppliedDeltas[i])
      if (index >= 0) pending.splice(index, 1)
    }
    root.bondDeltas = pending
  }

  function finishBondReload() {
    if (!root.bondFlushWaitingForReload || root.bondAppliedDeltas.length === 0) return
    root.bondFlushWaitingForReload = false
    if (root.bondFlushRetry) {
      // A sibling changed the file while this cycle was still reading it.
      // Keep the complete delta prefix queued and read the new base before
      // attempting a write; this is the bounded retry from the ownership
      // protocol, not a second writer.
      root.bondFlushRetry = false
      root.bondFlushWaitingForReload = true
      bondFile.reload()
      bondReloadTimer.restart()
      return
    }
    var text = String(bondFile.text() || "")
    var fresh
    if (text.trim() === "") {
      fresh = PetBond.emptyDocument(root.localDay(), root.bondWriter)
    } else {
      try { fresh = JSON.parse(text) } catch (e) {
        root.markBondUnavailable("bond save skipped: fresh document is invalid")
        return
      }
      if (!root.validBondDocument(fresh)) {
        root.markBondUnavailable("bond save skipped: fresh document is unsupported")
        return
      }
    }
    var updated = PetBond.applyDeltas(fresh, root.bondAppliedDeltas, root.localDay(), root.bondWriter)
    updated.revision = Math.max(Number(updated.revision) || 0, root.bondNextRevision) + 1
    updated.writer = root.bondWriter
    updated.updatedAt = Math.floor(Date.now() / 1000)
    root.bondNextRevision = updated.revision
    root.bondDocument = updated
    root.bondExpectedText = JSON.stringify(updated) + "\n"
    root.bondWriteInFlight = true
    bondFile.setText(root.bondExpectedText)
  }

  function finishBondSave() {
    if (!root.bondWriteInFlight) return
    var ownWrite = String(bondFile.text() || "").trim() === root.bondExpectedText.trim()
    if (!root.bondFlushRetry || ownWrite) root.dropAppliedBondDeltas()
    root.bondAppliedDeltas = []
    root.bondWriteInFlight = false
    root.bondFlushRetry = false
    root.bondExpectedText = ""
    root.bondFlushOwner = ""
    root.bondRevision++
    if (root.bondDeltas.length > 0) bondFlushTimer.restart()
  }

  function finishBondSaveFailed() {
    if (!root.bondWriteInFlight) return
    root.bondWriteInFlight = false
    root.bondAppliedDeltas = []
    root.bondFlushRetry = false
    root.bondExpectedText = ""
    root.bondFlushOwner = ""
    root.logDebug("bond save failed; deltas retained")
    if (root.bondDeltas.length > 0) bondFlushTimer.restart()
  }

  function chargeBondDecay() {
    if (!root.bondReadReady || root.bondUnavailable || !root.bondDocument) return
    var before = JSON.stringify(root.bondDocument)
    var decayed = PetBond.applyDocumentDecay(root.bondDocument, root.localDay())
    root.bondDocument = decayed.document
    if (before !== JSON.stringify(root.bondDocument) && root.bondOwner) {
      var deltas = root.bondDeltas.slice()
      var names = root.bondSpeciesNames()
      for (var i = 0; i < names.length; i++) deltas.push({ species: names[i], kind: "decay" })
      root.bondDeltas = deltas
      bondFlushTimer.restart()
      root.bondRevision++
    }
  }

  function requestPetStateRead() {
    if (!root.petRememberPosition || !root.runtimeStateRoot) return
    root.petStateReadReady = false
    root.petStateDocument = null
    petStateReadTimer.restart()
    petStateFile.reload()
  }

  function allowedPetEdge(value, allowedEdges) {
    return Array.isArray(allowedEdges) && allowedEdges.indexOf(String(value)) >= 0
  }

  function readPetState(species, allowedEdges) {
    if (!root.petRememberPosition || !root.petStateReadReady) return null
    var document = root.petStateDocument
    var now = Math.floor(Date.now() / 1000)
    if (!document || Number(document.version) !== 1
        || String(document.species || "") !== String(species || "")
        || !allowedPetEdge(document.edge, allowedEdges)
        || !isFinite(Number(document.fraction)) || Number(document.fraction) < 0
        || Number(document.fraction) > 1 || !isFinite(Number(document.savedAt))
        || now - Number(document.savedAt) > 12 * 60 * 60 || now < Number(document.savedAt) - 60) {
      if (document) root.logDebug("pet position document ignored")
      return null
    }
    return {
      edge: String(document.edge),
      fraction: Number(document.fraction),
      direction: Number(document.direction) < 0 ? -1 : 1,
      revision: Number(document.revision) || 0
    }
  }

  function savePetState(snapshot, ownerName, immediate) {
    if (!root.petRememberPosition || !root.petStateReadReady || !snapshot || !root.runtimeStateRoot) return
    var currentOwner = root.terminalMonitor ? String(root.terminalMonitor.name || "") : ""
    if (!currentOwner || String(ownerName || "") !== currentOwner) return
    root.pendingPetState = {
      edge: String(snapshot.edge || "top"),
      fraction: Math.max(0, Math.min(1, Number(snapshot.fraction) || 0)),
      direction: Number(snapshot.direction) < 0 ? -1 : 1,
      species: String(snapshot.species || root.petSpecies),
      writer: currentOwner
    }
    root.petStateWriter = currentOwner
    if (immediate === true) root.flushPetState()
    else petStateWriteTimer.restart()
  }

  function flushPetState(ownerOverride) {
    if (!root.pendingPetState || !root.petRememberPosition || !root.runtimeStateRoot) return
    var currentOwner = root.terminalMonitor ? String(root.terminalMonitor.name || "") : ""
    var writer = String(ownerOverride || currentOwner || "")
    if (!writer || root.petStateWriter !== writer || root.pendingPetState.writer !== writer) return
    var pending = root.pendingPetState
    root.pendingPetState = null
    var diskRevision = 0
    try {
      var current = JSON.parse(petStateFile.text() || "")
      diskRevision = isFinite(Number(current.revision)) ? Number(current.revision) : 0
    } catch (e) {}
    var revision = Math.max(root.petStateNextRevision, diskRevision) + 1
    root.petStateNextRevision = revision
    var document = {
      version: 1, revision: revision, writer: pending.writer, species: pending.species,
      edge: pending.edge, fraction: pending.fraction, direction: pending.direction,
      savedAt: Math.floor(Date.now() / 1000)
    }
    petStateFile.setText(JSON.stringify(document) + "\n")
  }

  function parseGrabOptions(raw) {
    var lines = String(raw || "").split(/\r?\n/)
    var values = []
    var resizeOnBorder
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].trim()) continue
      try {
        var parsed = JSON.parse(lines[i])
        if (parsed.bool !== undefined) {
          resizeOnBorder = parsed.bool === true
          continue
        }
        var value = Number(parsed.int !== undefined ? parsed.int : parsed.value)
        if (isFinite(value) && value >= 0)
          values.push(Math.max(0, Math.min(root.maxGrabMarginComponent, value)))
      } catch (e) {}
    }
    if (values.length !== 2 || resizeOnBorder === undefined) return null
    return {
      borderSize: values[0],
      extendBorderGrabArea: values[1],
      resizeOnBorder: resizeOnBorder,
      margin: resizeOnBorder ? Math.max(0, values[0] + values[1]) : values[0]
    }
  }

  function refreshGrabMargin(force) {
    if (!root.petEnabled || !root.petInteraction) {
      root.grabMarginReady = false
      return
    }
    if (!force && root.grabMarginReady) return
    if (grabMarginProcess.running) return
    root.grabMarginReady = false
    grabMarginProcess.running = true
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
  readonly property bool petVillains: { configRevision; return setting("petVillains", true) !== false }
  readonly property string petActivity: {
    configRevision
    var value = String(setting("petActivity", "On focus"))
    return ["On focus", "Always while visible", "Playful", "Celebrations only"].indexOf(value) >= 0
      ? value : "On focus"
  }
  readonly property bool reduceMotion: { configRevision; return setting("reduceMotion", false) === true }
  readonly property bool petInteraction: { configRevision; return setting("petInteraction", true) !== false }
  readonly property string petRoaming: {
    configRevision
    var value = String(setting("petRoaming", "Top edge"))
    return ["Top edge", "Whole border"].indexOf(value) >= 0 ? value : "Top edge"
  }
  readonly property bool petDrag: { configRevision; return setting("petDrag", true) !== false }
  readonly property string petHoverHalo: {
    configRevision
    var value = String(setting("petHoverHalo", "Off"))
    return ["Off", "Small", "Large"].indexOf(value) >= 0 ? value : "Off"
  }
  readonly property string petVoice: {
    configRevision
    var value = String(setting("petVoice", "Off"))
    return ["Off", "Kind", "Sassy", "Savage"].indexOf(value) >= 0 ? value : "Off"
  }
  readonly property string petSound: {
    configRevision
    var value = String(setting("petSound", "Off"))
    return ["Off", "Quiet", "Normal"].indexOf(value) >= 0 ? value : "Off"
  }
  readonly property bool petRememberPosition: {
    configRevision
    return setting("petRememberPosition", true) !== false
  }
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
    root.commandLatestStatus = 0
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
    root.commandLatestStatus = status
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
    id: grabMarginProcess
    command: ["bash", "-c", "hyprctl -j getoption general:border_size; hyprctl -j getoption general:extend_border_grab_area; hyprctl -j getoption general:resize_on_border"]
    stdout: StdioCollector { id: grabMarginOutput; waitForEnd: true }
    running: false
    onExited: {
      var raw = String(grabMarginOutput.text || "")
      var options = root.parseGrabOptions(raw)
      if (!options) {
        root.grabMargin = root.fallbackGrabMargin
        root.logDebug("grab margin query failed; using fallback " + root.fallbackGrabMargin + "px")
      } else {
        root.grabMargin = options.margin
        root.logDebug("grab margin=" + options.margin + "px; resize_on_border=" + options.resizeOnBorder)
      }
      root.grabMarginReady = true
    }
  }

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
      root.grabMarginReady = false
      if (root.petEnabled && root.petInteraction) root.refreshGrabMargin()
      terminalStateRefreshTimer.restart()
      root.clearCommandUnread()
      if (!root.bondReadReady) root.requestBondRead()
    } else {
      // Hiding is a settle boundary for durable bond deltas too. The owning
      // service flushes; sibling services remain readers.
      root.flushBondState()
    }
  }
  onPetEnabledChanged: {
    if (!root.petEnabled) root.grabMarginReady = false
    else if (root.terminalVisible && root.petInteraction) root.refreshGrabMargin()
  }
  onPetInteractionChanged: {
    root.grabMarginReady = false
    if (root.terminalVisible && root.petEnabled && root.petInteraction) root.refreshGrabMargin()
  }
  onPetRememberPositionChanged: {
    if (root.petRememberPosition) root.requestPetStateRead()
    else {
      petStateWriteTimer.stop()
      petStateReadTimer.stop()
      root.pendingPetState = null
      root.petStateWriter = ""
    }
  }
  onRuntimeStateRootChanged: {
    root.requestPetStateRead()
    root.requestBondRead()
  }
  onTerminalMonitorChanged: {
    var newOwner = root.terminalMonitor ? String(root.terminalMonitor.name || "") : ""
    if (root.petStateWriter && root.petStateWriter !== newOwner)
      root.flushPetState(root.petStateWriter)
    if (root.bondWriter && root.bondWriter !== newOwner) {
      root.flushBondState(root.bondWriter)
      root.bondWriter = ""
    }
    // A new owner must reload before its first coalesced write. This also
    // prevents a stale sibling snapshot from being used after a transfer.
    root.requestPetStateRead()
    root.requestBondRead()
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
    root.requestBondRead()
    root.scheduleBondMidnight()
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
        root.grabMarginReady = false
        if (root.terminalVisible && root.petEnabled && root.petInteraction)
          root.refreshGrabMargin(true)
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
