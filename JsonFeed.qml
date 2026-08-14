import QtQuick
import Quickshell.Io
import "Model.js" as Model

// One linecast --json feed: run the command, keep the last good payload,
// refetch on demand or when stale. Every panel view owns one of these.
Item {
  id: feed

  property string command: ""
  property var payload: null
  property bool fetching: false
  property double fetchedAtMs: 0
  property int staleAfterMs: 10 * 60 * 1000

  function refresh() {
    if (proc.running || feed.command === "") return
    feed.fetching = true
    proc.running = true
  }

  function refreshIfStale() {
    if (!payload || Date.now() - fetchedAtMs > staleAfterMs) refresh()
  }

  Process {
    id: proc
    command: ["bash", "-lc", feed.command + " 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        feed.fetching = false
        var parsed = Model.parsePayload(text)
        if (parsed) {
          feed.payload = parsed
          feed.fetchedAtMs = Date.now()
        }
      }
    }
  }
}
