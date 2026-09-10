import QtQuick
import Quickshell.Io

// Sound is intentionally a lazy component. With the default Off setting this
// file is never instantiated, so no audio backend or player process exists.
Item {
  id: root

  property string level: "Off"
  property bool reducedMotion: false
  property bool playerAvailable: false
  property string diagnostic: ""
  property double lastPlayedAt: 0
  readonly property real volume: root.level === "Normal" ? 0.7 : 0.35
  readonly property string assetRoot: Qt.resolvedUrl("assets/sounds/").toString()
  readonly property bool audioEnabled: ["Quiet", "Normal"].indexOf(root.level) >= 0

  function cuePath(cue) {
    var name = ["pet", "success", "failure", "land"].indexOf(String(cue)) >= 0
      ? String(cue) : ""
    return name ? Qt.resolvedUrl("assets/sounds/" + name + ".ogg").toString()
      .replace(/^file:\/\//, "") : ""
  }

  function play(cue) {
    if (!root.audioEnabled || !root.playerAvailable || playerProcess.running) return false
    if (Date.now() - root.lastPlayedAt < 700) return false
    var path = root.cuePath(cue)
    if (!path) return false
    root.lastPlayedAt = Date.now()
    if (root.playerKind === "pw-play")
      playerProcess.command = ["pw-play", "--volume", String(root.volume), path]
    else
      playerProcess.command = ["paplay", "--volume", String(Math.round(root.volume * 65536)), path]
    playerProcess.running = true
    return true
  }

  property string playerKind: ""
  Process {
    id: playerProbe
    command: ["bash", "-c", "command -v pw-play || command -v paplay"]
    stdout: StdioCollector { id: playerProbeOutput; waitForEnd: true }
    running: root.audioEnabled
    onExited: {
      var found = String(playerProbeOutput.text || "").trim().split(/\r?\n/)[0]
      if (found === "pw-play" || found.endsWith("/pw-play")) {
        root.playerKind = "pw-play"
        root.playerAvailable = true
        root.diagnostic = ""
      } else if (found === "paplay" || found.endsWith("/paplay")) {
        root.playerKind = "paplay"
        root.playerAvailable = true
        root.diagnostic = ""
      } else {
        root.playerKind = ""
        root.playerAvailable = false
        root.diagnostic = "Unavailable: pw-play or paplay not found"
      }
    }
  }
  Process {
    id: playerProcess
    command: []
    running: false
  }
  onLevelChanged: {
    if (root.audioEnabled && !playerProbe.running && !root.playerAvailable) playerProbe.running = true
    if (!root.audioEnabled) { playerProbe.running = false; root.playerAvailable = false; root.diagnostic = "" }
  }
  Component.onCompleted: if (!root.audioEnabled) root.diagnostic = ""
}
