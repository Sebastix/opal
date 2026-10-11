import QtQuick
import QtQuick.Controls as C

// Stands in for Omarchy's kit TextField, which is a styled QtQuick.Controls
// TextField, so the plugin's Field can be tested outside the shell.
C.TextField {
  property color foreground
  property bool password: false
  echoMode: password ? TextInput.Password : TextInput.Normal
}
