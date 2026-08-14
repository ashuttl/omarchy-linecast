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

  readonly property var activeView: section === "sunshine" ? sunshineView
    : section === "moon" ? moonView
    : section === "tides" ? tidesView
    : weatherView

  function refresh() {
    if (activeView && activeView.refresh) activeView.refresh()
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
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
      }

      WeatherView {
        id: weatherView
        width: parent.width
        bar: root.bar
        visible: root.section === "weather"
        shown: visible && root.opened
      }

      SunshineView {
        id: sunshineView
        width: parent.width
        bar: root.bar
        visible: root.section === "sunshine"
        shown: visible && root.opened
      }

      MoonView {
        id: moonView
        width: parent.width
        bar: root.bar
        visible: root.section === "moon"
        shown: visible && root.opened
      }

      TidesView {
        id: tidesView
        width: parent.width
        bar: root.bar
        visible: root.section === "tides"
        shown: visible && root.opened
      }
    }
  }
}
