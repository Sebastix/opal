import QtQuick
import QtTest
import "../../shell-plugin"

Item {
  width: 400; height: 200
  Field { id: a; width: 300; height: 40; text: "hello world" }
  Field { id: b; y: 60; width: 300; height: 40 }
  TextInput { id: src; y: 120; text: "from another program" }

  TestCase {
    name: "Field"; when: windowShown

    function init() { src.forceActiveFocus(); a.text = "hello world"; b.text = "" }

    function test_an_unfocused_field_skips_the_clipboard() {
      src.selectAll(); src.copy()
      verify(a.readOnly)
      verify(!a.canPaste, "read-only, so the clipboard isn't read")
      a.forceActiveFocus()
      verify(a.canPaste, "focused, it reads it")
      src.forceActiveFocus()
      verify(a.readOnly)
      verify(!a.canPaste)
    }

    function test_clicking_in_still_edits_where_clicked() {
      mouseClick(a, 20, 20)
      verify(a.activeFocus)
      verify(!a.readOnly)
      verify(a.cursorPosition < a.text.length, "cursor at " + a.cursorPosition)
      keyClick(Qt.Key_X)
      verify(a.text.indexOf("x") > 0 && a.text.indexOf("x") < a.text.length - 1, a.text)
    }

    function test_moving_focus_on() {
      a.forceActiveFocus()
      b.forceActiveFocus()
      verify(a.readOnly)
      keyClick(Qt.Key_Y)
      compare(b.text, "y")
    }
  }
}
