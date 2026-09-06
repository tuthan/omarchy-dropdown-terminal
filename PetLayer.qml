import QtQuick
import Quickshell
import Quickshell.Wayland

// Pet-only overlay. Keeping this in its own lazy component means a user who
// chooses entrance effects never pays for pet manifests, atlas decoding, or
// the pet state machine, and a pet-only setup never creates Qt particles.
Item {
  id: root

  property var service: null
  property var hostScreen: null

  readonly property rect terminalRect: service ? service.terminalRect : Qt.rect(0, 0, 0, 0)
  readonly property var terminalMonitor: service ? service.terminalMonitor : null
  readonly property bool terminalGeometryValid: terminalRect.width > 0 && terminalRect.height > 0
  readonly property bool hostMatchesTerminal: !!hostScreen && !!terminalMonitor
    && String(hostScreen.name || "") === String(terminalMonitor.name || "")
  readonly property bool surfaceReady: !!service && service.petEnabled === true
    && service.terminalVisible === true && root.hostMatchesTerminal
    && root.terminalGeometryValid
  readonly property string petDiagnostic: petController.assetDiagnostic

  PanelWindow {
    id: panel
    screen: root.hostScreen
    visible: root.surfaceReady
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    WlrLayershell.namespace: "io.github.tuthan.dropdown-terminal.pets"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // The overlay is decorative; it must never steal terminal input.
    mask: Region {}

    PetController {
      id: petController
      anchors.fill: parent
      service: root.service
      hostScreen: root.hostScreen
      surfaceReady: root.surfaceReady
    }
  }
}
