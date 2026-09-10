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
  property string bubbleText: ""
  property bool bubbleShown: false
  property string bubbleEdge: "top"
  property real spriteX: 0
  property real spriteY: 0
  property real spriteWidth: 32
  property real spriteHeight: 32
  property double bubbleStartedAt: 0
  property var recentVoiceLines: []

  readonly property bool active: root.burstKind !== "" && !root.reducedMotion && root.progress < 1
  readonly property color accentColor: Color.accent
  readonly property color quietColor: Color.muted

  function showBubble(text, edge) {
    var value = String(text || "").trim()
    if (!value) return false
    root.bubbleText = value
    root.bubbleEdge = String(edge || "top")
    root.bubbleStartedAt = Date.now()
    root.bubbleShown = true
    bubbleFadeIn.restart()
    bubbleTimer.interval = Math.min(4000, 2400 + value.length * 40)
    bubbleTimer.restart()
    return true
  }

  function dismissBubble() {
    bubbleTimer.stop()
    bubbleFadeIn.stop()
    bubbleFadeOut.stop()
    root.bubbleShown = false
    root.bubbleText = ""
  }

  function burst(kind) {
    if (root.reducedMotion || ["land", "success", "failure", "hearts", "puff"].indexOf(kind) < 0) return
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
      duration: root.burstKind === "failure" ? 360 : (root.burstKind === "puff" ? 520 : 440)
      easing.type: Easing.OutCubic
    }
    onFinished: root.finish()
  }

  Repeater {
    model: root.burstKind === "puff" ? 4 : 2
    delegate: Rectangle {
      width: root.burstKind === "failure" ? Style.space(3) : Style.space(4)
      height: width
      radius: width / 2
      color: index === 0 ? root.accentColor : root.quietColor
      visible: root.active
      opacity: root.active ? 1 - root.progress : 0
      x: root.originX + (root.burstKind === "puff"
        ? (index % 2 === 0 ? -1 : 1) * (Style.space(4) + index * Style.space(2))
        : (index === 0 ? -Style.space(5) : Style.space(5)))
        + (root.burstKind === "puff" ? (index % 2 === 0 ? -1 : 1) : (index === 0 ? -1 : 1))
          * root.progress * Style.space(7)
      y: root.originY - root.progress * (Style.space(8) + index * Style.space(4))
    }
  }

  Repeater {
    model: root.burstKind === "hearts" ? 6 : 0
    delegate: Text {
      text: "♥"
      color: index % 2 === 0 ? root.accentColor : root.quietColor
      font.pixelSize: Style.font.bodySmall
      visible: root.active
      opacity: root.active ? 1 - root.progress : 0
      x: root.originX + (index - 2.5) * Style.space(5)
      y: root.originY - root.progress * (Style.space(12) + (index % 3) * Style.space(4))
        - (index % 2) * Style.space(3)
      rotation: (index - 2.5) * 8
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

  Timer {
    id: bubbleTimer
    repeat: false
    onTriggered: {
      if (root.reducedMotion) root.dismissBubble()
      else bubbleFadeOut.restart()
    }
  }

  NumberAnimation {
    id: bubbleFadeIn
    target: bubble
    property: "opacity"
    from: 0
    to: 1
    duration: root.reducedMotion ? 0 : 160
  }

  NumberAnimation {
    id: bubbleFadeOut
    target: bubble
    property: "opacity"
    from: 1
    to: 0
    duration: root.reducedMotion ? 0 : 160
    onFinished: root.dismissBubble()
  }

  // Speech is decoration and never participates in the input region. The
  // container uses only the host palette, radius, spacing, and body-small
  // typography token.
  Item {
    id: bubble
    enabled: false
    visible: root.bubbleShown
    z: 5
    width: Math.min(root.width - Style.space(8), Math.max(Style.space(96), bubbleLabel.implicitWidth + Style.space(20)))
    height: bubbleLabel.implicitHeight + Style.space(16)
    x: bubble.clamp(root.spriteX + root.spriteWidth / 2 - width / 2, Style.space(4),
      Math.max(Style.space(4), root.width - width - Style.space(4)))
    y: root.bubbleEdge === "bottom"
      ? Math.min(root.height - height - Style.space(4), root.spriteY + root.spriteHeight + Style.space(8))
      : Math.max(Style.space(4), root.spriteY - height - Style.space(8))
    opacity: root.reducedMotion ? 1 : 0

    function clamp(value, low, high) { return Math.max(low, Math.min(high, value)) }

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Util.alpha(Color.background, 0.92)
      border.color: Color.popups.border
      border.width: 1
    }
    Text {
      id: bubbleLabel
      anchors.fill: parent
      anchors.margins: Style.space(8)
      text: root.bubbleText
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }
    Rectangle {
      width: Style.space(6)
      height: Style.space(6)
      rotation: 45
      color: Color.background
      border.color: Color.popups.border
      border.width: 1
      x: parent.width / 2 - width / 2
      y: root.bubbleEdge === "bottom" ? -width / 2 : parent.height - width / 2
    }
  }
}
