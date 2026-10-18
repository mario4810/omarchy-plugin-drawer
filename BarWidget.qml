import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "PluginDrawerModel.js" as PluginDrawerModel

// The bar-side half of the drawer: a single icon button that opens the drawer
// (PluginDrawer.qml) holding the widgets that were moved out of the bar.
BarWidget {
  id: root
  moduleName: "io.github.mario4810.plugin-drawer"

  // The interface the shell looks for when routing
  // `omarchy-shell shell toggle io.github.mario4810.plugin-drawer` to a bar widget,
  // so the drawer can be bound to a key.
  readonly property bool opened: drawer.open
  function open() { drawer.show() }
  function close() { drawer.hide() }
  function toggle() { drawer.toggle() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: setting("icon", "󰇘")
    tooltipText: "Plugin Drawer"
    active: drawer.open
    onPressed: function(mouseButton) { root.toggle() }
  }

  // What the drawer holds lives inline on this widget's own entry in
  // shell.json, next to its other settings.
  PluginDrawer {
    id: drawer
    anchorItem: button
    bar: root.bar
    scriptDir: root.pluginDir
    items: root.items
    movable: root.movable
  }

  // What the drawer holds and what could join it, each replaced only when it
  // actually changes. The bar re-assigns its layout snapshot whenever a hosted
  // widget registers a click target, so binding straight to it would rebuild
  // the widgets, which register click targets again, and round it goes.
  property var items: []
  property var movable: []
  property string itemsKey: ""
  property string movableKey: ""

  function refresh() {
    var layout = bar ? bar.layoutConfig : {}
    var nextItems = PluginDrawerModel.drawerItems(setting("items", []), catalog, layout)
    var itemsJson = JSON.stringify(nextItems)
    if (itemsJson !== itemsKey) { itemsKey = itemsJson; items = nextItems }
    var nextMovable = PluginDrawerModel.movable(layout, catalog, moduleName)
    var movableJson = JSON.stringify(nextMovable)
    if (movableJson !== movableKey) { movableKey = movableJson; movable = nextMovable }
  }

  onSettingsChanged: refresh()
  onBarChanged: refresh()
  onCatalogChanged: refresh()

  Connections {
    target: root.bar
    function onLayoutConfigChanged() { if (root) root.refresh() }
  }

  // Every bar-widget plugin on the system with the path to its entry point,
  // rescanned whenever the drawer opens so new installs show up.
  property var catalog: []

  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace("file://", "")).replace(/\/$/, "")

  Process {
    id: scan
    command: [
      "bash", root.pluginDir + "/scan-plugins.sh",
      (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/shell/plugins",
      Quickshell.env("HOME") + "/.config/omarchy/plugins"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.catalog = JSON.parse(text) }
        catch (e) { console.warn("plugin-drawer: could not read plugin list:", e) }
      }
    }
  }

  Connections {
    target: drawer
    function onOpenChanged() { if (drawer.open && !scan.running) scan.running = true }
  }

  // Moving a widget rebuilds the bar and this widget with it. plugin-drawer-ctl
  // leaves a short-lived flag behind; if it is there, pick up where the last
  // instance left off with the edit view open.
  Process {
    id: reopen
    command: ["bash", "-c", 'f="${XDG_RUNTIME_DIR:-/tmp}/omarchy-plugin-drawer-reopen"; '
      + '[ -e "$f" ] && [ $(( $(date +%s) - $(stat -c %Y "$f") )) -lt 15 ] && echo yes; rm -f "$f"']
    stdout: StdioCollector {
      onStreamFinished: if (text.trim() === "yes") { drawer.manage = true; drawer.show() }
    }
  }

  Component.onCompleted: { scan.running = true; reopen.running = true }
}
