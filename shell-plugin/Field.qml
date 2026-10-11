import QtQuick
import qs.Ui

// The kit's TextField, kept read-only with the editing done here.
//
// An editable TextInput reads the clipboard every time it changes, to keep
// `canPaste` current, and on Wayland that read takes whatever another program
// offers with no size limit or deadline: a hostile clipboard owner could
// stall or exhaust the shell while you type. A read-only TextInput skips the
// read, so the field never leaves read-only except for the instant of a
// paste you asked for. Qt still does selection, cursor movement, select-all,
// copy and Enter on a read-only field; typing, deleting, cut, paste and undo
// are handled below. Input methods don't attach to a read-only field, so
// text comes from key events (xkb compose and dead keys still work).
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

  function _paste() {
    const s = selectionStart, e = selectionEnd, len = text.length
    _remember()
    // Leaving read-only moves the cursor to the end; put the selection back
    // so the paste replaces it.
    readOnly = false
    select(s, e)
    paste()
    const after = e + text.length - len
    readOnly = true
    cursorPosition = after
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
