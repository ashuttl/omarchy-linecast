import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// The current theme's ANSI palette, read from colors.toml and cooked into
// the TUI's temperature-ramp stops. Theme switches replace the whole
// current/theme directory, so the file can't be watched directly; instead
// the shell's Color singleton — which the switch updates over IPC after
// the directory lands — is the reload signal.
QtObject {
  id: root

  property var colors: null
  readonly property var tempStops: Model.buildTempStops(colors, Color.background)

  property Connections colorWatch: Connections {
    target: Color
    function onForegroundChanged() { root.file.reload() }
    function onBackgroundChanged() { root.file.reload() }
    function onAccentChanged() { root.file.reload() }
    function onUrgentChanged() { root.file.reload() }
  }

  property FileView file: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: false
    printErrors: false
    onLoaded: root.colors = Model.parseColorsToml(text())
    onLoadFailed: root.colors = null
  }
}
