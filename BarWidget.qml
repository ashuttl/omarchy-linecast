import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Linecast bar widget: the first configured pill is always visible and
// hosts the popup; the remaining pills tuck away and slide out on hover,
// same as the stock indicators widget. Which pills show (and their order)
// comes from the `pills` array on the widget's shell.json entry, defaulting
// to all four.
//
// The manifest allows multiple instances, so the four pills do not have to
// travel together: one entry per pill puts weather in the center and tides
// over on the right, each with its own panel anchored under it. Every
// instance is independent apart from the location, which is linecast's own
// global setting, and the picker's recents, which live in a shared file
// (see RecentLocations.qml).
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

  // Pill roster, same shape as the stock indicators widget's `items`
  // setting: the shell.json entry may carry `pills: ["weather", "tides"]`
  // to pick which pills show and in what order. Unknown names and dupes
  // are dropped; an empty or missing setting means all four.
  readonly property var knownPills: ["weather", "sunshine", "moon", "tides"]
  readonly property var pillOrder: {
    var requested = root.setting("pills", knownPills)
    var result = []
    var count = requested && typeof requested.length === "number" ? requested.length : 0
    for (var i = 0; i < count; i++) {
      var name = String(requested[i])
      if (knownPills.indexOf(name) !== -1 && result.indexOf(name) === -1) result.push(name)
    }
    return result.length > 0 ? result : knownPills
  }

  function sectionEnabled(section) {
    return pillOrder.indexOf(section) !== -1
  }

  function refreshSecondsFor(name) {
    if (name === "weather") return root.setting("weatherRefreshSeconds", 600)
    if (name === "sunshine") return 60
    return 300
  }

  readonly property bool alwaysShow: root.setting("alwaysShow", false) === true

  readonly property bool revealExtras: root.alwaysShow
    || root.pillsHovered
    || (bar && bar.centerSectionRevealHeld === true
        && bar.centerHoverRevealSuppressed !== true)
    // An open extras panel is anchored to its pill, so the extras
    // must stay out while it is up — hover has moved to the panel
    // by then and the reveal hold alone would let them collapse.
    || (root.opened && root.activeSection !== root.pillOrder[0])

  // Reveal on our own hover as well as the bar's reveal hold. The hold is a
  // center-section gesture, so a widget parked in left or right never sees
  // it and would keep its extras tucked away forever. In the center this
  // adds nothing: pointing at the pills already means pointing at the
  // section that raises the hold.
  property bool pillsHovered: false

  function setPillsHovered(hovered) {
    if (hovered) {
      pillsCollapseTimer.stop()
      root.pillsHovered = true
    } else {
      // Collapse on a delay, the way the bar holds its own reveal: sliding
      // the extras out moves the neighbours, and a pointer that lands in the
      // seam for a frame should not snap them shut.
      pillsCollapseTimer.restart()
    }
  }

  Timer {
    id: pillsCollapseTimer
    interval: 120
    onTriggered: root.pillsHovered = false
  }

  HoverHandler {
    onHoveredChanged: root.setPillsHovered(hovered)
  }

  // The section the panel is showing (or last showed): pill clicks set it,
  // and the extras hold-open and panel indicator follow it.
  property string activeSection: pillOrder[0]

  // A settings edit can drop the pill the panel last showed; fall back to
  // the anchor pill so the section never points at a pill that isn't there.
  onPillOrderChanged: {
    if (!sectionEnabled(activeSection)) setSection(pillOrder[0])
  }

  function pillFor(section) {
    for (var i = 0; i < anchorRepeater.count; i++) {
      var a = anchorRepeater.itemAt(i)
      if (a && a.pillName === section) return a
    }
    for (var j = 0; j < extrasRepeater.count; j++) {
      var e = extrasRepeater.itemAt(j)
      if (e && e.pillName === section) return e
    }
    return anchorRepeater.count > 0 ? anchorRepeater.itemAt(0) : null
  }

  function setSection(section) {
    root.activeSection = section
    var p = panelLoader.item
    if (!p) return
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

  // The IPC route. A per-target handler only reaches whichever widget claimed
  // the target, and that is rarely the one the caller means: bar surfaces are
  // built per monitor, and with the pills split across several entries the
  // widget carrying `tides` may not be the one holding the handler. So the
  // claimant resolves the request itself — point every copy that carries the
  // pill at it, then open the copy the bar would have summoned.
  //
  // bar.summonBarWidget can't do the picking for us: it resolves by plugin
  // id, which no longer identifies one widget.
  function openSectionFromIpc(section) {
    var name = String(section || "")
    var slots = bar && bar.moduleSlots ? bar.moduleSlots : []
    var owners = []
    for (var i = 0; i < slots.length; i++) {
      var slot = slots[i]
      if (!slot || !slot.activeItem || slot.moduleName !== root.moduleName) continue
      var item = slot.activeItem
      if (typeof item.sectionEnabled !== "function" || !item.sectionEnabled(name)) continue
      item.setSection(name)
      owners.push(slot)
    }
    // No widget on the bar carries this pill (or we have no bar to ask):
    // fall back to our own anchor pill rather than doing nothing.
    if (owners.length === 0) {
      openSection(sectionEnabled(name) ? name : pillOrder[0])
      return
    }
    var target = pickOwnerSlot(owners)
    if (target && target.activeItem) target.activeItem.open()
  }

  // The same narrowing Bar.findPanelWidget applies, restricted to the slots
  // that carry the pill we were asked for. An already-open copy wins, so
  // a repeat call reaches the panel the user can see; otherwise the focused
  // monitor's copy does. Anchored center modules leave a zero-size
  // placeholder slot behind, so prefer one that is actually drawn.
  function pickOwnerSlot(slots) {
    var pool = slots.filter(function(slot) { return slot.activeItem.opened === true })
    if (pool.length === 0) pool = slots

    var focused = bar && typeof bar.focusedScreenName === "function" ? bar.focusedScreenName() : ""
    if (focused && typeof bar.slotScreenName === "function") {
      var onFocused = pool.filter(function(slot) { return bar.slotScreenName(slot) === focused })
      if (onFocused.length > 0) pool = onFocused
    }

    for (var i = 0; i < pool.length; i++) {
      if (pool[i].visible === true && pool[i].width > 0 && pool[i].height > 0) return pool[i]
    }
    return pool.length > 0 ? pool[0] : null
  }

  // open/close/toggle name no pill, so they act on the Linecast widget the
  // bar would route a hotkey to rather than on whichever copy happens to
  // hold the IPC target.
  function ipcPanelWidget() {
    var slots = bar && bar.moduleSlots ? bar.moduleSlots : []
    var mine = []
    for (var i = 0; i < slots.length; i++) {
      var slot = slots[i]
      if (slot && slot.activeItem && slot.moduleName === root.moduleName) mine.push(slot)
    }
    if (mine.length === 0) return root
    var target = pickOwnerSlot(mine)
    return target && target.activeItem ? target.activeItem : root
  }

  function refresh() {
    for (var i = 0; i < anchorRepeater.count; i++) anchorRepeater.itemAt(i).rerun()
    for (var j = 0; j < extrasRepeater.count; j++) extrasRepeater.itemAt(j).rerun()
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

  // The bar centers the open-panel mark on the whole slot and takes only
  // a width hint, so a pill-sized mark can't sit under its pill when the
  // extras are out — span the row instead so centered is also aligned.
  readonly property real openPanelIndicatorWidth: pillRow.implicitWidth
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
    function open(): void { root.ipcPanelWidget().open() }
    function close(): void { root.ipcPanelWidget().close() }
    function show(): void { root.ipcPanelWidget().open() }
    function hide(): void { root.ipcPanelWidget().close() }
    function toggle(): void { root.ipcPanelWidget().togglePanel() }
    function openSection(name: string): void { root.openSectionFromIpc(name) }
  }

  Row {
    id: pillRow
    anchors.verticalCenter: parent.verticalCenter
    spacing: 0

    Repeater {
      id: anchorRepeater
      model: root.pillOrder.slice(0, 1)

      // pillName is required, which turns off the delegate's implicit
      // modelData context — declare it required so the Repeater injects it.
      LinecastPill {
        required property var modelData
        pillName: modelData
        refreshSeconds: root.refreshSecondsFor(modelData)
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

        Repeater {
          id: extrasRepeater
          model: root.pillOrder.slice(1)

          LinecastPill {
            required property var modelData
            pillName: modelData
            refreshSeconds: root.refreshSecondsFor(modelData)
          }
        }
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
