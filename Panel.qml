import QtQuick
import qs.Commons
import qs.Ui

// The linecast popup: one panel, four faces. Whichever pill was clicked
// picks the section and the anchor, so the popup drops from the weather,
// sunshine, moon, or tide pill it belongs to. Views own their data
// (JsonFeed each) and fetch lazily the first time they are shown.
//
// BarWidget.qml owns the pills, drives `section`, and re-points
// `anchorItem` at the matching pill before opening.
Panel {
  id: root
  moduleName: "ashuttl.linecast"
  ipcTarget: "ashuttl.linecast"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel, so everything the bar identifies a panel by must be that
  // widget (popout coordinator, switchPanelFrom).
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property string section: "weather"

  // Bumped when the user changes location from the panel, so every face
  // drops its payload and refetches for the new place.
  property int locationEpoch: 0

  // Shared theme sampler: the temperature ramp anchored on the current
  // theme's ANSI colors, TUI style.
  property ThemePalette themePalette: ThemePalette {}

  readonly property var activeView: section === "sunshine" ? sunshineView
    : section === "moon" ? moonView
    : section === "tides" ? tidesView
    : weatherView

  function refresh() {
    if (activeView && activeView.refresh) activeView.refresh()
  }

  // Same write-back path as the stock panels: applied locally first so the
  // panel reacts on the click, then persisted through the bar into the
  // widget's shell.json entry.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function open() {
    root.controller.show()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears
    // the shared flag (same dance as the clock panel).
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.activeView ? root.activeView.panelWidth : Style.space(360))
    contentHeight: panel.fittedContentHeight(root.activeView ? root.activeView.implicitHeight : Style.space(200))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Typing in a view's text field must reach the field, not the panel
      // keys (same dance as the clock's life-expectancy editor).
      blocked: weatherView.editingText === true
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        var target = viewScroll.contentY + dy * Style.space(48)
        viewScroll.contentY = Math.max(0, Math.min(
          Math.max(0, viewScroll.contentHeight - viewScroll.height), target))
      }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
      }

      Flickable {
        id: viewScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: root.activeView ? root.activeView.implicitHeight : 0
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

      WeatherView {
        id: weatherView
        width: parent.width
        bar: root.bar
        host: root
        palette: root.themePalette
        locationEpoch: root.locationEpoch
        visible: root.section === "weather"
        shown: visible && root.opened
        onLocationChangedByUser: {
          root.locationEpoch++
          // The pills follow the config change on their own schedule; a
          // location switch should show in the bar now, not in ten minutes.
          if (root.hostWidget && typeof root.hostWidget.refresh === "function")
            root.hostWidget.refresh()
        }
      }

      SunshineView {
        id: sunshineView
        width: parent.width
        bar: root.bar
        palette: root.themePalette
        locationEpoch: root.locationEpoch
        visible: root.section === "sunshine"
        shown: visible && root.opened
      }

      MoonView {
        id: moonView
        width: parent.width
        bar: root.bar
        locationEpoch: root.locationEpoch
        visible: root.section === "moon"
        shown: visible && root.opened
      }

      TidesView {
        id: tidesView
        width: parent.width
        bar: root.bar
        locationEpoch: root.locationEpoch
        visible: root.section === "tides"
        shown: visible && root.opened
      }
      }
    }
  }
}
