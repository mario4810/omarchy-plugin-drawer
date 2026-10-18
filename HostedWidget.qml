import QtQuick

// One stashed widget, loaded from its own entry point and handed the same
// three properties the bar would inject into a slot.
Loader {
  id: root

  // { id, url, settings } from PluginDrawerModel.drawerItems
  required property var entry
  required property QtObject bar

  // A widget can hide itself (an update indicator with nothing to report);
  // give back its space when it does, as a bar slot would.
  readonly property bool occupied: item !== null && item.visible
  width: occupied ? item.implicitWidth : 0
  height: occupied ? item.implicitHeight : 0

  source: entry.url

  function inject() {
    if (!item) return
    if ("bar" in item) item.bar = root.bar
    if ("moduleName" in item) item.moduleName = entry.id
    if ("settings" in item) item.settings = entry.settings
  }

  onLoaded: {
    inject()
    Qt.callLater(inject)
  }
  onEntryChanged: inject()
}
