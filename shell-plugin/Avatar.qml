import QtQuick
import QtQuick.Effects
import qs.Commons

// Round profile picture with a glyph fallback.
Item {
  id: root
  property string picture: ""
  // OpalService, which fetches the picture (see RemoteImage).
  property var svc: null
  property real size: Style.space(32)
  property color foreground: Color.foreground

  width: size
  height: size

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: Style.selectedFillFor(root.foreground, Color.accent)
    visible: img.status !== Image.Ready
    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: "󰀄"
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: root.size * 0.5
    }
  }

  RemoteImage {
    id: img
    anchors.fill: parent
    svc: root.svc
    // Pictures come from strangers: https only.
    url: root.picture.indexOf("https://") === 0 ? root.picture : ""
    sourceSize.width: root.size * 2
    sourceSize.height: root.size * 2
    fillMode: Image.PreserveAspectCrop
    visible: false
  }

  Rectangle {
    id: mask
    anchors.fill: parent
    radius: width / 2
    visible: false
    layer.enabled: true
  }

  MultiEffect {
    anchors.fill: parent
    source: img
    visible: img.status === Image.Ready
    maskEnabled: true
    maskSource: mask
  }
}
