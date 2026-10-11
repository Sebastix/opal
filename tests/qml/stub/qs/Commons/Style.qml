pragma Singleton
import QtQuick

// Just enough of Omarchy's Style for the plugin parts under test.
QtObject {
  readonly property QtObject font: QtObject {
    readonly property string family: "sans"
    readonly property int body: 12
    readonly property int heading: 14
  }
  function space(n) { return n }
  function selectedFillFor(fg, accent) { return accent }
}
