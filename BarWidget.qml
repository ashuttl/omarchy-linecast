import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Linecast bar widget: the first configured pill is always visible and
// hosts the popup; the remaining pills tuck away and slide out on hover,
// same as the stock indicators widget. Which pills show (and their order)
// comes from the `pills` array on the widget's shell.json entry.
//
// This is also the base the companion plugins are built from — the tide
// pill as its own bar widget is this component with `defaultPills:
// ["tides"]` and a manifest of its own. They need separate plugin ids
// rather than several entries of one id because Omarchy identifies a bar
// widget by that id alone: the drag-and-drop reorder resolves the dragged
// widget with a first-match-by-id lookup (Bar.moveModuleInConfig), so with
// duplicate ids it moves whichever entry comes first rather than the one
// under the pointer. Same for `omarchy bar move/set`.
//
// The companions load this file from ../ashuttl.linecast, so Qt.resolvedUrl
// here still points at this directory: they share the one copy of the
// scripts, the panel, and the views, and only bring their own identity.
//
// Pills read the scripts/ helpers (Waybar-style JSON from linecast's
// --oneline output). Left click on a pill opens its anchored panel;
// right click floats the full linecast TUI.
BarWidget {
  id: root

  // moduleName is injected by the bar from the layout entry's id, which is
  // what tells this widget apart from its companions. Everything identity
  // shaped hangs off it — the IPC target, the slot lookups — so nothing
  // here hardcodes the plugin id.

  // Marks the whole family for cross-plugin routing: `openSection` and
  // `refresh` reach the tide widget from the weather widget's IPC target,
  // whichever plugin each of them came from.
  readonly property bool linecastWidget: true

  // Absolute path of this plugin's directory, for Process commands.
  readonly property string pluginDir: {
    var url = Qt.resolvedUrl(".").toString()
    return url.indexOf("file://") === 0 ? url.substring(7) : url
  }
  readonly property string scriptsDir: pluginDir + "scripts"

  // Pill roster, same shape as the stock indicators widget's `items`
  // setting: the shell.json entry may carry `pills: ["weather", "tides"]`
  // to pick which pills show and in what order. Unknown names and dupes
  // are dropped; an empty or missing setting means defaultPills, which the
  // companion plugins narrow to their own single pill.
  readonly property var knownPills: ["weather", "sunshine", "moon", "tides"]
  property var defaultPills: knownPills
  readonly property var pillOrder: {
    var requested = root.setting("pills", defaultPills)
    var result = []
    var count = requested && typeof requested.length === "number" ? requested.length : 0
    for (var i = 0; i < count; i++) {
      var name = String(requested[i])
      if (knownPills.indexOf(name) !== -1 && result.indexOf(name) === -1) result.push(name)
    }
    return result.length > 0 ? result : defaultPills
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

  // Every Linecast widget on the bar, whichever plugin shipped it, so a
  // request can cross from one companion to another. A bar surface is built
  // per monitor, so each widget appears here once per screen.
  function familySlots(sameModuleOnly) {
    var slots = bar && bar.moduleSlots ? bar.moduleSlots : []
    var found = []
    for (var i = 0; i < slots.length; i++) {
      var slot = slots[i]
      if (!slot || !slot.activeItem || slot.activeItem.linecastWidget !== true) continue
      if (sameModuleOnly && slot.moduleName !== root.moduleName) continue
      found.push(slot)
    }
    return found
  }

  // The IPC route, and the reason `openSection tides` still works when tides
  // is a separate plugin: the widget that owns the pill may not be the one
  // holding the target the call came in on. So point every copy carrying the
  // pill at it, then open the copy the bar would have summoned.
  //
  // bar.summonBarWidget can't do the picking for us — it resolves by plugin
  // id, and the pill we were handed is what identifies the widget here.
  function openSectionFromIpc(section) {
    var name = String(section || "")
    var slots = familySlots(false)
    var owners = []
    for (var i = 0; i < slots.length; i++) {
      var item = slots[i].activeItem
      if (typeof item.sectionEnabled !== "function" || !item.sectionEnabled(name)) continue
      item.setSection(name)
      owners.push(slots[i])
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

  // `refresh` is about the data behind the pills, which every Linecast widget
  // shares, so it reaches the whole family rather than stopping at this
  // plugin's own copies.
  function refreshFamily() {
    var slots = familySlots(false)
    var seen = []
    for (var i = 0; i < slots.length; i++) {
      var item = slots[i].activeItem
      if (seen.indexOf(item) !== -1 || typeof item.refresh !== "function") continue
      seen.push(item)
      item.refresh()
    }
    if (seen.indexOf(root) === -1) root.refresh()
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

  // open/close/toggle name no pill, so they stay within the plugin whose
  // target they arrived on and pick the copy the bar would route a hotkey to
  // — per monitor, rather than whichever one happens to hold the target.
  function ipcPanelWidget() {
    var mine = familySlots(true)
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

  // One target per plugin id — `ashuttl.linecast`, `ashuttl.linecast-tides`,
  // and so on — so each companion answers under its own name. Held back
  // until the bar has injected the id, or the handlers would all register
  // an empty target and collide.
  IpcHandler {
    target: root.moduleName
    enabled: root.moduleName !== ""

    function refresh(): void { root.refreshFamily() }
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
      command: ["bash", "-lc", "PILL_CLOCK=" + root.setting("clock", "24h") + " " + root.scriptsDir + "/linecast-" + pill.pillName + ".sh"]
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
