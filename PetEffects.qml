import QtQuick
import qs.Commons

// Two tiny finite effect slots. They are decorative, bounded, and never
// intercept input; the controller only triggers them for authored actions.
Item {
  id: root

  property string burstKind: ""
  property int burstSerial: 0
  property real originX: 0
  property real originY: 0
  property bool reducedMotion: false
  property real progress: 0

  readonly property bool active: root.burstKind !== "" && !root.reducedMotion && root.progress < 1
  readonly property color accentColor: Color.accent
  readonly property color quietColor: Color.muted

  function burst(kind) {
    if (root.reducedMotion || ["land", "success", "failure"].indexOf(kind) < 0) return
    root.burstKind = kind
    root.progress = 0
    root.burstSerial++
    burstAnimation.restart()
  }

  function finish() {
    root.progress = 1
    root.burstKind = ""
  }

  function cancel() {
    burstAnimation.stop()
    root.progress = 1
    root.burstKind = ""
  }

  ParallelAnimation {
    id: burstAnimation
    NumberAnimation {
      target: root
      property: "progress"
      from: 0
      to: 1
      duration: root.burstKind === "failure" ? 360 : 440
      easing.type: Easing.OutCubic
    }
    onFinished: root.finish()
  }

  Repeater {
    model: 2
    delegate: Rectangle {
      width: root.burstKind === "failure" ? Style.space(3) : Style.space(4)
      height: width
      radius: width / 2
      color: index === 0 ? root.accentColor : root.quietColor
      visible: root.active
      opacity: root.active ? 1 - root.progress : 0
      x: root.originX + (index === 0 ? -Style.space(5) : Style.space(5))
        + (index === 0 ? -1 : 1) * root.progress * Style.space(7)
      y: root.originY - root.progress * (Style.space(8) + index * Style.space(4))
    }
  }

  Text {
    visible: root.active && root.burstKind === "success"
    text: "✦"
    color: root.accentColor
    font.pixelSize: Style.font.bodySmall
    x: root.originX - width / 2
    y: root.originY - Style.space(18) - root.progress * Style.space(5)
    opacity: root.active ? 1 - root.progress : 0
  }
}
