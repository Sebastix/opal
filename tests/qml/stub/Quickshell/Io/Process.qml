import QtQuick

// Stands in for Quickshell's Process: instead of running `command`, it
// answers from FakeClipboard (or never, when it hangs).
QtObject {
  id: p
  property var command: []
  property bool running: false
  property QtObject stdout
  signal exited(int exitCode, int exitStatus)

  onRunningChanged: if (running) {
    FakeClipboard.lastCommand = command
    FakeClipboard.runs++
    if (FakeClipboard.hang) return
    const text = FakeClipboard.text, code = FakeClipboard.code
    Qt.callLater(function() {
      if (!p.running) return
      p.stdout.text = text
      p.stdout.streamFinished()
      p.running = false
      p.exited(code, 0)
    })
  }
}
