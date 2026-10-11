import QtQuick
import Quickshell.Io
import qs.Ui

// The kit's TextField, kept read-only with the editing done here.
//
// An editable TextInput reads the clipboard every time it changes, to keep
// `canPaste` current, and on Wayland that read takes whatever another program
// offers with no size limit or deadline: a hostile clipboard owner could
// stall or exhaust the shell while you type. A read-only TextInput skips the
// read, so the field never leaves read-only. Qt still does selection, cursor
// movement, select-all, copy and Enter on a read-only field; typing,
// deleting, cut, paste and undo are handled below. Input methods don't
// attach to a read-only field, so text comes from key events (xkb compose
// and dead keys still work).
//
// Paste never goes through Qt's reader either: read-clipboard.sh fetches
// the text in its own process, bounded in size and time, and it goes in
// when it arrives, so a hostile clipboard can't stall the shell or fill its
// memory even on a paste you asked for.
TextField {
  id: root

  readOnly: true
  cursorVisible: activeFocus

  property var _undo: []
  property var _redo: []

  function _remember() {
    _undo.push({ text: text, at: cursorPosition })
    if (_undo.length > 100) _undo.shift()
    _redo = []
  }

  function _restore(from, to) {
    if (!from.length) return
    to.push({ text: text, at: cursorPosition })
    const s = from.pop()
    text = s.text
    cursorPosition = Math.min(s.at, text.length)
  }

  function _dropSelection() {
    if (selectionStart === selectionEnd) return false
    remove(selectionStart, selectionEnd)
    return true
  }

  // Replace the selection with `t` and leave the cursor after it.
  function _type(t) {
    _remember()
    _dropSelection()
    insert(cursorPosition, t)
  }

  // Bytes a paste may bring; more is refused, not cut off.
  readonly property int pasteLimit: 16 * 1024
  readonly property int pasteSeconds: 2
  property var _reading: null

  function _paste() {
    if (_reading) return
    _reading = reader.createObject(root)
    if (!_reading) return
    _reading.running = true
    pasteDeadline.restart()
  }

  // read-clipboard.sh has its own timeout; this is the backstop.
  Timer {
    id: pasteDeadline
    interval: (root.pasteSeconds + 2) * 1000
    onTriggered: {
      const p = root._reading
      root._reading = null
      if (p) { p.running = false; p.destroy() }
    }
  }

  function _utf8Length(t) {
    let n = 0
    for (let i = 0; i < t.length; i++) {
      const c = t.charCodeAt(i)
      if (c < 0x80) n += 1
      else if (c < 0x800) n += 2
      else if (c >= 0xd800 && c < 0xdc00) { n += 4; i++ }
      else n += 3
    }
    return n
  }

  function _pasted(proc, ok, t) {
    if (proc !== _reading) return
    _reading = null
    pasteDeadline.stop()
    if (!ok || _utf8Length(t) > pasteLimit) return
    // One line: line breaks and tabs become spaces, other controls go.
    t = t.replace(/[\r\n\t]+/g, " ").replace(/[\x00-\x1f\x7f]/g, "")
    if (t.length) _type(t)
  }

  Component {
    id: reader
    Process {
      id: proc
      property bool _out: false
      property int _code: -1
      command: ["bash", decodeURIComponent(Qt.resolvedUrl("read-clipboard.sh").toString().replace(/^file:\/\//, "")),
                String(root.pasteLimit), String(root.pasteSeconds)]
      stdout: StdioCollector { id: out; onStreamFinished: { proc._out = true; proc._finish() } }
      onExited: function(code) { proc._code = code; proc._finish() }
      function _finish() {
        if (!_out || _code < 0) return
        _out = false
        root._pasted(proc, _code === 0, out.text)
        destroy()
      }
    }
  }

  function _printable(t) {
    if (!t.length) return false
    for (let i = 0; i < t.length; i++) {
      const c = t.charCodeAt(i)
      if (c < 0x20 || c === 0x7f) return false
    }
    return true
  }

  Keys.onPressed: function(event) {
    const ctrl = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)
    if (event.matches(StandardKey.Paste)) {
      _paste()
    } else if (event.matches(StandardKey.Cut)) {
      if (echoMode !== TextInput.Normal || selectionStart === selectionEnd) return
      copy()
      _remember()
      _dropSelection()
    } else if (event.matches(StandardKey.Undo)) {
      _restore(_undo, _redo)
    } else if (event.matches(StandardKey.Redo)) {
      _restore(_redo, _undo)
    } else if (event.key === Qt.Key_Backspace) {
      _remember()
      if (!_dropSelection() && cursorPosition > 0) {
        let from = cursorPosition - 1
        if (event.modifiers & Qt.ControlModifier) {
          const before = text.slice(0, cursorPosition)
          from = before.search(/\S*\s*$/)
        }
        remove(from, cursorPosition)
      }
    } else if (event.key === Qt.Key_Delete) {
      _remember()
      if (!_dropSelection() && cursorPosition < text.length)
        remove(cursorPosition, cursorPosition + 1)
    } else if (!ctrl && _printable(event.text)) {
      _type(event.text)
    } else {
      return
    }
    event.accepted = true
  }
}
