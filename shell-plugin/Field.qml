import QtQuick
import qs.Ui

// The kit's TextField, read-only until it has focus.
//
// Every editable TextInput reads the clipboard whenever it changes, to keep
// `canPaste` current, and on Wayland that read takes whatever another program
// offers with no size limit or deadline. A read-only one skips it, so an
// unfocused field never touches the clipboard. Clicking or tabbing in still
// focuses it; the cursor stays where the click put it, since leaving
// read-only otherwise moves it to the end.
TextField {
  readOnly: true
  onActiveFocusChanged: {
    const p = cursorPosition
    readOnly = !activeFocus
    cursorPosition = p
  }
}
