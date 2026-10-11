pragma Singleton
import QtQuick

// What the stand-in Process answers with, and what it was asked to run.
QtObject {
  property string text: ""
  property int code: 0
  property bool hang: false
  property var lastCommand: []
  property int runs: 0
}
