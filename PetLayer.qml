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
  readonly property real localTerminalX: root.hostScreen ? terminalRect.x - root.hostScreen.x : 0
  readonly property real localTerminalY: root.hostScreen ? terminalRect.y - root.hostScreen.y : 0
  readonly property real grabMargin: service ? Number(service.grabMargin) : 17
  readonly property bool hostMatchesTerminal: !!hostScreen && !!terminalMonitor
    && String(hostScreen.name || "") === String(terminalMonitor.name || "")
  readonly property bool surfaceReady: !!service && service.petEnabled === true
    && service.terminalVisible === true && root.hostMatchesTerminal
    && root.terminalGeometryValid
  readonly property bool interactionEnabled: petController.interactionEnabled
  readonly property string petHoverHalo: service ? service.petHoverHalo : "Off"
  readonly property int hoverHaloExtent: root.petHoverHalo === "Large" ? 48
    : (root.petHoverHalo === "Small" ? 24 : 0)
  readonly property string petDiagnostic: petController.assetDiagnostic
    || petController.roamingDiagnostic || petController.roomDiagnostic
    || (petController.interactionDiagnostic || "")
    || (petController.voiceDiagnostic || "") || (petController.soundDiagnostic || "")

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
    // The sprite is the only interactive shape. Subtract the terminal client
    // plus Hyprland's active resize grab ring so those pixels remain terminal
    // input; Service leaves only the real border when resize-on-border is off.
    mask: Region {
      item: root.interactionEnabled ? petController.spriteItem : null
      Region {
        x: root.interactionEnabled && petController.spriteItem
          ? petController.spriteItem.x - root.hoverHaloExtent : 0
        y: root.interactionEnabled && petController.spriteItem
          ? petController.spriteItem.y - root.hoverHaloExtent : 0
        width: root.interactionEnabled && root.hoverHaloExtent > 0 && petController.spriteItem
          ? petController.spriteItem.width + 2 * root.hoverHaloExtent : 0
        height: root.interactionEnabled && root.hoverHaloExtent > 0 && petController.spriteItem
          ? petController.spriteItem.height + 2 * root.hoverHaloExtent : 0
      }
      Region {
        intersection: Intersection.Subtract
        x: Math.floor(root.localTerminalX - root.grabMargin)
        y: Math.floor(root.localTerminalY - root.grabMargin)
        width: Math.ceil(root.terminalRect.width + 2 * root.grabMargin)
        height: Math.ceil(root.terminalRect.height + 2 * root.grabMargin)
      }
    }

    PetController {
      id: petController
      anchors.fill: parent
      service: root.service
      hostScreen: root.hostScreen
      surfaceReady: root.surfaceReady
    }
  }
}
