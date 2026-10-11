import QtQuick

// An image from a URL someone else chose (a profile picture, album art).
//
// The shell never loads such a URL itself: Qt would read the whole
// response, and a small file can decode to gigabytes. The daemon fetches
// it within limits, decodes it in a separate limited process and hands back
// a small PNG from its cache, which is all this ever loads.
Image {
  id: root

  property var svc: null
  // https://, or file:// for a music player's local art.
  property string url: ""
  property string _path: ""

  function _load() {
    const url = root.url
    _path = ""
    if (!svc || !(url.indexOf("https://") === 0 || url.indexOf("file://") === 0)) return
    svc.thumbnail(url, function(path) {
      if (root.url === url) root._path = path
    })
  }

  onUrlChanged: _load()
  onSvcChanged: _load()
  Component.onCompleted: _load()

  Connections {
    target: root.svc
    // Asked before signing in: ask again now.
    function onUiTokenChanged() { if (root._path === "") root._load() }
  }

  onStatusChanged: if (status === Image.Error && _path !== "" && svc) {
    svc.forgetThumbnail(url)
    _path = ""
  }

  source: _path !== "" ? encodeURI("file://" + _path) : ""
  asynchronous: true
  cache: false
}
