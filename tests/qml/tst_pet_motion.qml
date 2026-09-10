import QtQuick
import QtTest
import "../.."

TestCase {
  name: "PetMotion"

  QtObject {
    id: screen
    property real x: 0
    property real y: 0
    property real width: 3440
    property real height: 1440
  }

  QtObject {
    id: service
    property rect terminalRect: Qt.rect(0, 24, 1, 1)
  }

  PetMotion {
    id: motion
    service: service
    hostScreen: screen
    frameWidth: 32
    frameHeight: 32
    renderScale: 1
  }

  function setTerminal(widthPercent, heightPercent) {
    var terminalWidth = screen.width * widthPercent / 100
    var terminalHeight = screen.height * heightPercent / 100
    service.terminalRect = Qt.rect((screen.width - terminalWidth) / 2, 24,
      terminalWidth, terminalHeight)
  }

  function test_room_for_reference_output() {
    setTerminal(20, 20)
    verify(motion.roomLeft > 0)
    verify(motion.roomRight > 0)
    verify(motion.roomBottom > 0)

    setTerminal(90, 45)
    verify(motion.roomLeft > 0)
    verify(motion.roomRight > 0)
    verify(motion.roomBottom > 0)

    setTerminal(100, 45)
    verify(motion.roomLeft < 0)
    verify(motion.roomRight < 0)
    verify(motion.roomBottom > 0)

    setTerminal(90, 100)
    verify(motion.roomLeft > 0)
    verify(motion.roomRight > 0)
    verify(motion.roomBottom < 0)
  }

  function test_anchor_compensation_inputs_are_scaled() {
    compare(motion.wallAnchorInset, 2)
    compare(motion.ledgeAnchorInset, 2)
    motion.renderScale = 2
    compare(motion.wallAnchorInset, 4)
    compare(motion.ledgeAnchorInset, 4)
  }
}
