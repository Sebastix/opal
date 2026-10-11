import QtQuick
import QtTest
import Quickshell.Io
import "../../shell-plugin"

Item {
  width: 400; height: 300
  Field { id: a; width: 300; height: 40 }
  Field { id: b; y: 50; width: 300; height: 40 }
  Field { id: pw; y: 100; width: 300; height: 40; password: true }
  TextInput { id: src; y: 200; width: 300 }

  SignalSpy { id: accepted; target: a; signalName: "accepted" }
  SignalSpy { id: flips; target: a; signalName: "readOnlyChanged" }

  TestCase {
    name: "Field"; when: windowShown

    function init() {
      src.forceActiveFocus()
      a.text = ""; b.text = ""; pw.text = ""
      a._undo = []; a._redo = []
      accepted.clear(); flips.clear()
      FakeClipboard.text = ""; FakeClipboard.code = 0; FakeClipboard.hang = false
      FakeClipboard.runs = 0; FakeClipboard.lastCommand = []
    }

    function cleanup() { compare(flips.count, 0, "never left read-only") }

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

    function paste(field) {
      const runs = FakeClipboard.runs
      keyClick(Qt.Key_V, Qt.ControlModifier)
      compare(FakeClipboard.runs, runs + 1, "asked read-clipboard.sh")
      tryCompare(field, "_reading", null)
    }

    function test_paste_reads_through_the_bounded_script() {
      offer("Qt's own clipboard")
      FakeClipboard.text = "PASTED"
      a.text = "one two"
      a.forceActiveFocus()
      a.cursorPosition = 3
      paste(a)
      compare(a.text, "onePASTED two")
      compare(a.cursorPosition, 9)
      verify(!a.canPaste, "Qt's reader never ran")
      const c = FakeClipboard.lastCommand
      compare(c[0], "bash")
      verify(/\/shell-plugin\/read-clipboard\.sh$/.test(c[1]), c[1])
      compare(c[2], "16384"); compare(c[3], "2")
      a.select(0, 3)
      paste(a)
      compare(a.text, "PASTEDPASTED two", "paste replaces the selection")
      keyClick(Qt.Key_Insert, Qt.ShiftModifier)
      tryCompare(a, "_reading", null)
      compare(a.text, "PASTEDPASTEDPASTED two", "Shift+Insert pastes too")
    }

    function test_paste_refuses_what_it_shouldnt_take() {
      a.forceActiveFocus()
      FakeClipboard.text = "x".repeat(16385)
      paste(a)
      compare(a.text, "", "over the limit: refused, not cut off")
      FakeClipboard.text = "é".repeat(8193)
      paste(a)
      compare(a.text, "", "the limit is bytes, not characters")
      FakeClipboard.text = "x".repeat(16384)
      paste(a)
      compare(a.text.length, 16384, "up to the limit is fine")
      a.text = ""
      FakeClipboard.text = "partial"; FakeClipboard.code = 124
      paste(a)
      compare(a.text, "", "a failed or timed-out read puts nothing in")
      FakeClipboard.text = "line one\r\nline two\tend\u0007"; FakeClipboard.code = 0
      paste(a)
      compare(a.text, "line one line two end", "made one line")
    }

    function test_a_hung_paste_is_given_up_on() {
      a.forceActiveFocus()
      FakeClipboard.hang = true
      keyClick(Qt.Key_V, Qt.ControlModifier)
      verify(a._reading !== null)
      keyClick(Qt.Key_V, Qt.ControlModifier)
      compare(FakeClipboard.runs, 1, "one read at a time")
      type("ok")
      compare(a.text, "ok", "typing goes on meanwhile")
      tryCompare(a, "_reading", null, 6000)
      FakeClipboard.hang = false; FakeClipboard.text = "!"
      paste(a)
      compare(a.text, "ok!")
    }

    function test_cut_and_undo() {
      a.forceActiveFocus()
      type("abc")
      a.select(0, 2)
      keyClick(Qt.Key_X, Qt.ControlModifier)
      compare(a.text, "c")
      src.text = ""
      src.paste()
      compare(src.text, "ab", "cut copies")
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
