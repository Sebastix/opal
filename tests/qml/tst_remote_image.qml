import QtQuick
import QtTest
import "../../shell-plugin"

Item {
  width: 200; height: 200

  // Stands in for OpalService: records what it was asked for and answers
  // with the fixture.
  QtObject {
    id: svc
    property string uiToken: ""
    property var asked: []
    property var forgotten: []
    property string answer: Qt.resolvedUrl("fixtures/thumb.png").toString().replace(/^file:\/\//, "")
    function thumbnail(url, done) { asked = asked.concat([url]); done(answer) }
    function forgetThumbnail(url) { forgotten = forgotten.concat([url]) }
  }

  RemoteImage { id: img; svc: svc; width: 20; height: 20 }
  Avatar { id: av; svc: svc; size: 20; y: 50 }

  TestCase {
    name: "RemoteImage"; when: windowShown

    function init() { img.url = ""; av.picture = ""; svc.asked = []; svc.forgotten = [] }

    function test_loads_the_daemons_thumbnail_not_the_url() {
      img.url = "https://example.com/huge.png"
      compare(svc.asked, ["https://example.com/huge.png"])
      verify(String(img.source).indexOf("example.com") === -1, img.source)
      verify(/fixtures\/thumb\.png$/.test(String(img.source)), img.source)
      tryCompare(img, "status", Image.Ready)
    }

    function test_music_players_local_art_goes_through_it_too() {
      img.url = "file:///tmp/art.jpg"
      compare(svc.asked, ["file:///tmp/art.jpg"])
      verify(String(img.source).indexOf("/tmp/art.jpg") === -1)
    }

    function test_other_urls_load_nothing() {
      for (const u of ["http://example.com/a.png", "data:image/png;base64,AAAA", "qrc:/x.png", "/etc/x.png"]) {
        img.url = u
        compare(String(img.source), "", u)
      }
      compare(svc.asked, [])
    }

    function test_no_thumbnail_means_no_image() {
      svc.answer = ""
      img.url = "https://example.com/not-an-image"
      compare(String(img.source), "")
      svc.answer = Qt.resolvedUrl("fixtures/thumb.png").toString().replace(/^file:\/\//, "")
    }

    function test_a_pruned_file_is_forgotten() {
      svc.answer = "/nonexistent/gone.png"
      img.url = "https://example.com/pruned.png"
      tryCompare(img, "status", Image.Null)
      compare(svc.forgotten, ["https://example.com/pruned.png"])
      svc.answer = Qt.resolvedUrl("fixtures/thumb.png").toString().replace(/^file:\/\//, "")
    }

    function test_avatar_only_takes_https_and_never_loads_it() {
      av.picture = "http://example.com/a.png"
      compare(svc.asked, [])
      av.picture = "https://example.com/me.png"
      compare(svc.asked, ["https://example.com/me.png"])
    }

    function test_asks_again_after_signing_in() {
      svc.answer = ""
      img.url = "https://example.com/later.png"
      svc.answer = Qt.resolvedUrl("fixtures/thumb.png").toString().replace(/^file:\/\//, "")
      svc.uiToken = "t"
      compare(svc.asked.length, 2)
      verify(String(img.source) !== "")
      svc.uiToken = ""
    }
  }
}
