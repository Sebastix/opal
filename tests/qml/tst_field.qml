import QtQuick
import QtTest
import "../../shell-plugin"

Item {
  width: 400; height: 300
  Field { id: a; width: 300; height: 40 }
  Field { id: b; y: 50; width: 300; height: 40 }
  Field { id: pw; y: 100; width: 300; height: 40; password: true }
  TextInput { id: src; y: 200; width: 300 }

  SignalSpy { id: accepted; target: a; signalName: "accepted" }

  TestCase {
    name: "Field"; when: windowShown

    function init() {
      src.forceActiveFocus()
      a.text = ""; b.text = ""; pw.text = ""
      a._undo = []; a._redo = []
      accepted.clear()
    }

    function offer(t) { src.text = t; src.selectAll(); src.copy(); src.deselect() }

    function type(s) { for (const ch of s) keyClick(ch) }

    function test_never_reads_the_clipboard_on_its_own() {
      offer("from another program")
      verify(a.readOnly)
      verify(!a.canPaste, "unfocused")
      a.forceActiveFocus()
      type("hi")
      offer("changed while typing")
      a.forceActiveFocus()
      verify(a.readOnly, "still read-only while editing")
      verify(!a.canPaste, "focused and editing, still not read")
      compare(a.text, "hi")
    }

    function test_typing_and_deleting() {
      a.forceActiveFocus()
      verify(a.cursorVisible)
      type("hello world")
      compare(a.text, "hello world")
      keyClick(Qt.Key_Backspace)
      compare(a.text, "hello worl")
      keyClick(Qt.Key_Home)
      keyClick(Qt.Key_Delete)
      compare(a.text, "ello worl")
      keyClick(Qt.Key_End)
      keyClick(Qt.Key_Backspace, Qt.ControlModifier)
      compare(a.text, "ello ")
      keyClick(Qt.Key_A, Qt.ControlModifier)
      type("new")
      compare(a.text, "new", "typing replaces the selection")
      keyClick(Qt.Key_Tab)
      verify(!a.activeFocus, "Tab still moves on")
    }

    function test_clicking_in_types_where_clicked() {
      a.text = "hello world"
      mouseClick(a, 20, 20)
      verify(a.activeFocus)
      verify(a.cursorPosition > 0 && a.cursorPosition < a.text.length, "at " + a.cursorPosition)
      const at = a.cursorPosition
      keyClick("x")
      compare(a.text.charAt(at), "x")
    }

    function test_paste_goes_in_at_the_cursor() {
      offer("PASTED")
      a.text = "one two"
      a.forceActiveFocus()
      a.cursorPosition = 3
      keyClick(Qt.Key_V, Qt.ControlModifier)
      compare(a.text, "onePASTED two")
      compare(a.cursorPosition, 9)
      verify(a.readOnly)
      a.select(0, 3)
      keyClick(Qt.Key_V, Qt.ControlModifier)
      compare(a.text, "PASTEDPASTED two", "paste replaces the selection")
    }

    function test_cut_and_undo() {
      a.forceActiveFocus()
      type("abc")
      a.select(0, 2)
      keyClick(Qt.Key_X, Qt.ControlModifier)
      compare(a.text, "c")
      b.forceActiveFocus()
      keyClick(Qt.Key_V, Qt.ControlModifier)
      compare(b.text, "ab", "cut copies")
      a.forceActiveFocus()
      keyClick(Qt.Key_Z, Qt.ControlModifier)
      compare(a.text, "abc")
      keyClick(Qt.Key_Z, Qt.ControlModifier | Qt.ShiftModifier)
      compare(a.text, "c")
    }

    function test_enter_accepts() {
      a.forceActiveFocus()
      type("x")
      keyClick(Qt.Key_Return)
      compare(accepted.count, 1)
    }

    function test_password_field() {
      pw.forceActiveFocus()
      type("s3cret")
      compare(pw.text, "s3cret")
      pw.selectAll()
      keyClick(Qt.Key_X, Qt.ControlModifier)
      compare(pw.text, "s3cret", "no cutting a password")
    }
  }
}
