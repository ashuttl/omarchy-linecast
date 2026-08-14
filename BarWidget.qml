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
    && ((bar.centerSectionRevealHeld === true
         && bar.centerHoverRevealSuppressed !== true)
        // An open sunshine/moon/tides panel is anchored to its pill, so the
        // extras must stay out while it is up — hover has moved to the
        // panel by then and the reveal hold alone would let them collapse.
        || (root.opened && root.activeSection !== "weather"))

  // The section the panel is showing (or last showed): pill clicks set it,
  // and the extras hold-open and panel indicator follow it.
  property string activeSection: "weather"

  function pillFor(section) {
    if (section === "sunshine") return sunshinePill
    if (section === "moon") return moonPill
    if (section === "tides") return tidesPill
    return weatherPill
  }

  function setSection(section) {
    var p = panelLoader.item
    if (!p) return
    root.activeSection = section
    p.section = section
    p.anchorItem = pillFor(section)
  }

  function openSection(section) {
    var p = panelLoader.item
    if (!p) return
    if (root.opened && root.activeSection === section) {
      p.close()
      return
    }
    setSection(section)
    p.open()
  }

  // The IPC route: a per-target handler only reaches whichever per-monitor
  // instance claimed the target (which may be the zero-size placeholder for
  // anchored center modules), so set the section on every instance and let
  // the bar's summon path pick the surface to open on — same routing
  // shell.summon uses.
  function openSectionFromIpc(section) {
    var items = bar && typeof bar.moduleWidgets === "function"
      ? bar.moduleWidgets(moduleName) : [root]
    for (var i = 0; i < items.length; i++) {
      if (items[i] && typeof items[i].setSection === "function") items[i].setSection(section)
    }
    if (bar && typeof bar.summonBarWidget === "function") bar.summonBarWidget(moduleName)
    else openSection(section)
  }

  function refresh() {
    weatherPill.rerun()
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function toggleTerminal(name) {
    if (root.bar) root.bar.run(root.scriptsDir + "/linecast-toggle.sh " + name)
  }

  // ---- Popup plumbing. Shape contract for shell.summon/hide/toggle
  //      routing: Bar.findPanelWidget requires open/close/opened on the
  //      bar-widget root, and the popout coordinator identifies the panel
  //      by this widget, not the nested Panel item.
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

  readonly property real openPanelIndicatorWidth: pillFor(activeSection).labelWidth
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
    if ("anchorItem" in target) target.anchorItem = pillFor(root.activeSection)
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
    function openSection(name: string): void { root.openSectionFromIpc(name) }
  }

  Row {
    id: pillRow
    anchors.verticalCenter: parent.verticalCenter
    spacing: 0

    LinecastPill {
      id: weatherPill
      pillName: "weather"
      refreshSeconds: root.setting("weatherRefreshSeconds", 600)
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

        LinecastPill { id: sunshinePill; pillName: "sunshine"; refreshSeconds: 60 }
        LinecastPill { id: moonPill; pillName: "moon"; refreshSeconds: 300 }
        LinecastPill { id: tidesPill; pillName: "tides"; refreshSeconds: 300 }
      }
    }
  }

  component LinecastPill: WidgetButton {
    id: pill

    required property string pillName
    property int refreshSeconds: 300

    // Instances override this rather than adding an onPressed handler:
    // a handler declared on the instance would fire alongside this one,
    // not replace it. Default: left click opens this pill's panel face,
    // right click floats the full TUI.
    property var activate: function(b) {
      if (b === Qt.RightButton) root.toggleTerminal(pill.pillName)
      else root.openSection(pill.pillName)
    }

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
