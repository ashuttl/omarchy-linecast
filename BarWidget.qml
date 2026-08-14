import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Linecast bar widget: the weather pill is always visible and hosts the
// weather popup; sunshine, moon, and tides tuck away and slide out on the
// bar's center-section reveal hold, same as the stock indicators widget.
//
// Pills read the scripts/ helpers (Waybar-style JSON from linecast's
// --oneline output). Left click on weather opens the anchored panel;
// right click on weather and any click on the extras toggle floating
// linecast TUI terminals.
BarWidget {
  id: root
  moduleName: "ashuttl.linecast"

  // Absolute path of this plugin's directory, for Process commands.
  readonly property string pluginDir: {
    var url = Qt.resolvedUrl(".").toString()
    return url.indexOf("file://") === 0 ? url.substring(7) : url
  }
  readonly property string scriptsDir: pluginDir + "scripts"

  readonly property bool revealExtras: bar
    && bar.centerSectionRevealHeld === true
    && bar.centerHoverRevealSuppressed !== true

  function refresh() {
    weatherPill.rerun()
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function toggleTerminal(name) {
    if (root.bar) root.bar.run(root.scriptsDir + "/linecast-toggle.sh " + name)
  }

  // ---- Weather popup. Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the bar-widget
  //      root, and the popout coordinator identifies the panel by this
  //      widget, not the nested Panel item.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  readonly property real openPanelIndicatorWidth: weatherPill.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = weatherPill
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: pillRow.implicitWidth
  implicitHeight: root.barSize

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "ashuttl.linecast"

    function refresh(): void { root.broadcast("refresh") }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  Row {
    id: pillRow
    anchors.verticalCenter: parent.verticalCenter
    spacing: 0

    LinecastPill {
      id: weatherPill
      pillName: "weather"
      refreshSeconds: root.setting("weatherRefreshSeconds", 600)
      activate: function(b) {
        if (b === Qt.RightButton) root.toggleTerminal("weather")
        else root.togglePanel()
      }
    }

    Item {
      clip: true
      width: root.revealExtras ? extrasRow.implicitWidth : 0
      implicitWidth: width
      height: root.implicitHeight

      Behavior on width {
        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
      }

      Row {
        id: extrasRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        LinecastPill { pillName: "sunshine"; refreshSeconds: 60 }
        LinecastPill { pillName: "moon"; refreshSeconds: 300 }
        LinecastPill { pillName: "tides"; refreshSeconds: 300 }
      }
    }
  }

  component LinecastPill: WidgetButton {
    id: pill

    required property string pillName
    property int refreshSeconds: 300

    // Instances override this rather than adding an onPressed handler:
    // a handler declared on the instance would fire alongside this one,
    // not replace it.
    property var activate: function(b) { root.toggleTerminal(pill.pillName) }

    bar: root.bar
    horizontalMargin: 7.5

    function rerun() {
      if (!pillProc.running) pillProc.running = true
    }

    function update(raw) {
      var trimmed = String(raw || "").trim()
      var data = {}
      try { data = JSON.parse(trimmed) } catch (e) { data = { text: trimmed } }
      pill.text = data.text || ""
      pill.tooltipText = data.tooltip || ""
    }

    onPressed: function(b) { pill.activate(b) }

    Process {
      id: pillProc
      command: ["bash", "-lc", root.scriptsDir + "/linecast-" + pill.pillName + ".sh"]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: pill.update(text)
      }
    }

    Timer {
      interval: pill.refreshSeconds * 1000
      running: true
      repeat: true
      triggeredOnStart: true
      onTriggered: pill.rerun()
    }
  }
}
