import QtQuick
import Quickshell
import Quickshell.Io

// The location picker's recents, shared by every Linecast widget on the bar.
//
// These used to ride on the widget's own shell.json entry, which stops
// working the moment there is more than one Linecast widget: the shell's
// updateEntryInline writes the settings object onto *every* layout entry
// carrying the plugin id, so the tides widget saving a recent would stamp
// its own `pills` over the weather widget's entry too.
//
// A file is the right home for them anyway. The location itself is
// linecast's own global setting, so its recents are shared state, not
// per-widget configuration — one list, watched by every instance, so a place
// picked from the weather panel shows up in the tide panel's menu as well.
Item {
  id: store

  readonly property string path: Quickshell.env("HOME")
    + "/.local/state/omarchy/linecast-recent-locations.json"

  readonly property int limit: 10

  property var entries: []

  // Recents left on a widget entry by v0.5 and earlier. Used only while the
  // file has nothing in it; the first save writes them out for good.
  property var legacyEntries: []

  function normalize(value) {
    var out = []
    var count = value && typeof value.length === "number" ? value.length : 0
    for (var i = 0; i < count && out.length < store.limit; i++) {
      var row = value[i]
      if (!row) continue
      var label = String(row.label || "")
      var query = String(row.query || "")
      if (label === "" || query === "") continue
      out.push({ label: label, query: query })
    }
    return out
  }

  function load(text) {
    var parsed = null
    try { parsed = JSON.parse(String(text || "")) } catch (e) { parsed = null }
    var rows = normalize(parsed)
    store.entries = rows.length > 0 ? rows : normalize(store.legacyEntries)
  }

  function remember(entry) {
    var head = normalize([entry])
    if (head.length === 0) return

    var next = head
    for (var i = 0; i < store.entries.length && next.length < store.limit; i++) {
      var row = store.entries[i]
      if (row && row.label !== next[0].label) next.push(row)
    }

    // Applied locally first so the menu reorders on the click; the write
    // comes back through the file watcher as the same list, and reaches the
    // other widgets' stores the same way.
    store.entries = next
    file.setText(JSON.stringify(next, null, 2) + "\n")
  }

  FileView {
    id: file
    path: store.path
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: store.load(text())
    // First run: no file yet, so fall back to whatever the legacy setting
    // carried rather than leaving the menu empty.
    onLoadFailed: store.load("")
    onFileChanged: reload()
  }
}
