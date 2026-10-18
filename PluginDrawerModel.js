.pragma library

// Pure helpers for working out what the drawer holds and what could be moved
// into it. No QML types in here so they can be tested under plain node.

// Structural widgets that make no sense in a drawer.
var NOT_STASHABLE = { "omarchy.spacer": true }

var SECTIONS = ["left", "center", "right"]

function indexCatalog(catalog) {
  var byId = {}
  for (var i = 0; i < (catalog || []).length; i++) byId[catalog[i].id] = catalog[i]
  return byId
}

function layoutIds(layout) {
  var ids = {}
  for (var s = 0; s < SECTIONS.length; s++) {
    var entries = layout && layout[SECTIONS[s]] || []
    for (var i = 0; i < entries.length; i++) ids[entries[i].id] = SECTIONS[s]
  }
  return ids
}

// A third-party plugin with a service or panel needs a plugins[] entry to stay
// loaded once it has no bar slot; first-party ones load regardless.
function needsKeepEnabled(manifest) {
  if (!manifest || manifest.firstParty) return false
  return (manifest.kinds || []).some(function(kind) { return kind !== "bar-widget" })
}

// What the drawer shows: stored items in the order they were stashed. Anything
// the bar shows again (say it was re-enabled from the plugin manager) is left
// out so a widget is never on screen twice. Items whose plugin is gone stay in
// the list, flagged `missing`, so they can still be sent back.
function drawerItems(items, catalog, layout) {
  var byId = indexCatalog(catalog)
  var onBar = layoutIds(layout)
  var out = []
  for (var i = 0; i < (items || []).length; i++) {
    var item = items[i]
    if (!item || !item.id || onBar[item.id]) continue
    var manifest = byId[item.id]
    var settings = {}
    for (var key in item) if (key !== "id") settings[key] = item[key]
    out.push({
      id: item.id,
      name: manifest ? manifest.name : item.id,
      url: manifest ? "file://" + manifest.entry : "",
      settings: settings,
      missing: !manifest
    })
  }
  return out
}

// Bar widgets that can be moved into the drawer: layout entries backed by a
// bar-widget plugin, not the drawer itself. Custom command/qml modules have no
// plugin to load, so they stay where they are.
function movable(layout, catalog, selfId) {
  var byId = indexCatalog(catalog)
  var out = []
  for (var s = 0; s < SECTIONS.length; s++) {
    var entries = layout && layout[SECTIONS[s]] || []
    for (var i = 0; i < entries.length; i++) {
      var id = entries[i].id
      var manifest = byId[id]
      if (!manifest || id === selfId || NOT_STASHABLE[id]) continue
      out.push({
        id: id,
        name: manifest.name,
        section: SECTIONS[s],
        keepEnabled: needsKeepEnabled(manifest)
      })
    }
  }
  return out
}
