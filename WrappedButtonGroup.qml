import QtQuick
import qs.Commons
import qs.Ui

// A compact variant of Omarchy's ButtonGroup. Its Flow layout wraps option
// chips to the available panel width instead of letting a long enum run out
// through the card border.
Flow {
  id: root

  property var options: []
  property string value: ""
  property color foreground: Color.foreground
  property color background: Color.background
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property bool focusable: true
  property int cursorIndex: -1
  property int _focusedIndex: -1

  signal changed(string value)
  signal hovered(int index, bool isHovered)

  spacing: Style.spacing.md
  activeFocusOnTab: focusable

  function optionValue(option) {
    return (option && typeof option === "object") ? String(option.value) : String(option)
  }
  function optionLabel(option) {
    return (option && typeof option === "object" && option.label !== undefined)
      ? String(option.label) : String(option)
  }
  function optionIcon(option) {
    return (option && typeof option === "object" && option.icon) ? String(option.icon) : ""
  }
  function optionTooltip(option) {
    return (option && typeof option === "object" && option.tooltip) ? String(option.tooltip) : ""
  }
  function selectedOptionIndex() {
    for (var i = 0; i < options.length; i++)
      if (optionValue(options[i]) === value) return i
    return -1
  }
  function activateFocused() {
    if (_focusedIndex < 0 || _focusedIndex >= options.length) return
    root.changed(root.optionValue(options[_focusedIndex]))
  }

  onActiveFocusChanged: {
    if (activeFocus) {
      var selected = root.selectedOptionIndex()
      root._focusedIndex = selected < 0 ? 0 : selected
    } else {
      root._focusedIndex = -1
    }
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Left || event.key === Qt.Key_H || event.text === "h") {
      root._focusedIndex = Math.max(0, (root._focusedIndex < 0 ? 0 : root._focusedIndex) - 1)
      event.accepted = true
    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L || event.text === "l") {
      var next = (root._focusedIndex < 0 ? 0 : root._focusedIndex) + 1
      root._focusedIndex = Math.min(root.options.length - 1, next)
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
               || event.key === Qt.Key_Space) {
      root.activateFocused()
      event.accepted = true
    }
  }

  Repeater {
    model: root.options

    delegate: Button {
      required property var modelData
      required property int index
      text: root.optionLabel(modelData)
      iconText: root.optionIcon(modelData)
      tooltipText: root.optionTooltip(modelData)
      selected: root.optionValue(modelData) === root.value
      hasCursor: root.cursorIndex === index
        || (root.activeFocus && root._focusedIndex === index)
      bordered: true
      foreground: root.foreground
      background: root.background
      accent: root.accent
      fontFamily: root.fontFamily
      fontSize: root.fontSize
      onClicked: root.changed(root.optionValue(modelData))
      onHovered: function(isHovered) { root.hovered(index, isHovered) }
    }
  }
}
