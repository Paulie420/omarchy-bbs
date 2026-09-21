// BbsService.qml
import QtQuick
import Quickshell
import Quickshell.Io
import "BbsModel.js" as BbsModel

Item {
  id: root

  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, ""))
  readonly property string cacheFile: Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")
  readonly property string listCachePath: root.cacheFile + "/omarchy-bbs/list.json"

  property var rawEntries: []
  property var tiers: ({ best: [], great: [], good: [] })
  readonly property var entries: BbsModel.joinTiers(root.rawEntries, root.tiers)
  property bool fetching: false
  property string fetchError: ""

  function applyList(raw) {
    try {
      var parsed = JSON.parse(raw || "[]")
      root.rawEntries = Array.isArray(parsed) ? parsed : []
      root.fetchError = ""
    } catch (error) {
      root.fetchError = "Could not read the cached BBS list."
    }
  }

  function applyTiers(raw) {
    try {
      var parsed = JSON.parse(raw || "{}")
      root.tiers = {
        best: Array.isArray(parsed.best) ? parsed.best : [],
        great: Array.isArray(parsed.great) ? parsed.great : [],
        good: Array.isArray(parsed.good) ? parsed.good : []
      }
    } catch (error) {
      root.tiers = { best: [], great: [], good: [] }
    }
  }

  function refresh() {
    if (root.fetching) return
    root.fetching = true
    fetchProcess.command = [root.pluginDir + "bbs-fetch", "refresh"]
    fetchProcess.running = true
  }

  FileView {
    id: tiersFile
    path: root.pluginDir + "assets/tiers.json"
    watchChanges: true
    onLoaded: root.applyTiers(text())
    onFileChanged: reload()
  }

  FileView {
    id: listFile
    path: root.listCachePath
    watchChanges: true
    onLoaded: root.applyList(text())
    onLoadFailed: function (error) {
      // The cache file does not exist yet on first run. Trigger a fetch
      // instead of treating this as an error.
      root.refresh()
    }
    onFileChanged: reload()
  }

  Process {
    id: primeProcess
    command: [root.pluginDir + "bbs-fetch", "list"]
    onExited: function (exitCode) {
      if (exitCode === 0) listFile.reload()
    }
  }

  Process {
    id: fetchProcess
    command: []
    onExited: function (exitCode) {
      root.fetching = false
      if (exitCode === 0) {
        listFile.reload()
      } else {
        root.fetchError = "Could not refresh the BBS list."
      }
    }
  }

  Component.onCompleted: {
    primeProcess.running = true
  }
}
