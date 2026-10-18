// Run with: node test/plugin-drawer-model.test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")

// Qt loads PluginDrawerModel.js as a QML library; node needs the pragma line gone.
const source = fs.readFileSync(path.join(__dirname, "..", "PluginDrawerModel.js"), "utf8")
  .replace(/^\.pragma library\s*$/m, "")
const M = new Function(source + "; return { drawerItems, movable, needsKeepEnabled }")()

const catalog = [
  { id: "omarchy.clock", name: "Clock", kinds: ["bar-widget"], entry: "/fp/clock.qml", firstParty: true },
  { id: "omarchy.spacer", name: "Spacer", kinds: ["bar-widget"], entry: "/fp/spacer.qml", firstParty: true },
  { id: "acme.chat", name: "Chat", kinds: ["service", "bar-widget"], entry: "/u/chat/Bar.qml", firstParty: false },
  { id: "acme.gh", name: "GitHub", kinds: ["bar-widget"], entry: "/u/gh/Panel.qml", firstParty: false },
  { id: "omarchy.media", name: "Media", kinds: ["service", "bar-widget"], entry: "/fp/media.qml", firstParty: true }
]
const layout = {
  left: [{ id: "omarchy.clock" }],
  center: [{ id: "omarchy.spacer" }],
  right: [{ id: "acme.gh", limit: 3 }, { id: "some-command", type: "command" }, { id: "self" }]
}

let n = 0
const test = (name, fn) => { fn(); n++; console.log("ok  ", name) }

test("keep-enabled only for third-party plugins with more than a widget", () => {
  assert.strictEqual(M.needsKeepEnabled(catalog[2]), true)
  assert.strictEqual(M.needsKeepEnabled(catalog[3]), false)
  assert.strictEqual(M.needsKeepEnabled(catalog[4]), false)
  assert.strictEqual(M.needsKeepEnabled(undefined), false)
})

test("movable lists real bar widgets with where they are", () => {
  const got = M.movable(layout, catalog, "self")
  assert.deepStrictEqual(got.map(m => [m.id, m.section]), [["omarchy.clock", "left"], ["acme.gh", "right"]])
})

test("movable skips the spacer, custom modules and the drawer itself", () => {
  const ids = M.movable(layout, catalog.concat([{ id: "self", name: "Drawer", kinds: ["bar-widget"], entry: "/x" }]), "self").map(m => m.id)
  assert.ok(!ids.includes("omarchy.spacer") && !ids.includes("some-command") && !ids.includes("self"))
})

test("movable flags plugins that need a plugins[] entry", () => {
  const got = M.movable({ right: [{ id: "acme.chat" }, { id: "acme.gh" }] }, catalog, "self")
  assert.deepStrictEqual(got.map(m => m.keepEnabled), [true, false])
})

test("drawerItems resolves entry points and strips the id from settings", () => {
  const got = M.drawerItems([{ id: "acme.gh", limit: 3 }], catalog, {})
  assert.deepStrictEqual(got, [{ id: "acme.gh", name: "GitHub", url: "file:///u/gh/Panel.qml", settings: { limit: 3 }, missing: false }])
})

test("drawerItems keeps stash order", () => {
  const got = M.drawerItems([{ id: "omarchy.media" }, { id: "acme.gh" }], catalog, {})
  assert.deepStrictEqual(got.map(i => i.id), ["omarchy.media", "acme.gh"])
})

test("drawerItems hides anything the bar shows again", () => {
  const got = M.drawerItems([{ id: "acme.gh" }, { id: "omarchy.media" }], catalog, layout)
  assert.deepStrictEqual(got.map(i => i.id), ["omarchy.media"])
})

test("drawerItems keeps uninstalled plugins so they can be sent back", () => {
  const got = M.drawerItems([{ id: "gone.plugin" }], catalog, {})
  assert.deepStrictEqual([got[0].missing, got[0].url, got[0].name], [true, "", "gone.plugin"])
})

test("tolerates missing input", () => {
  assert.deepStrictEqual(M.drawerItems(undefined, undefined, undefined), [])
  assert.deepStrictEqual(M.movable(undefined, undefined, "self"), [])
})

console.log(n + " passed")
