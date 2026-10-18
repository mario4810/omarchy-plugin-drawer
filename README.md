# Plugin Drawer

An [Omarchy](https://omarchy.org/) shell plugin that gives a busy bar some
room. It adds **one button** to the bar. Clicking it opens a small drawer under
the button, and the drawer holds the bar widgets you moved out of the bar.

The widgets in the drawer are the real thing: they show their live state and
open their own popups (a calendar, a device list, a GitHub feed) just as they
would on the bar.

## Requirements

- Omarchy 4 (the Quickshell-based `omarchy-shell`)
- `bash` and `jq`, both part of a standard Omarchy install

## Install

```sh
omarchy plugin add https://github.com/mario4810/omarchy-plugin-drawer --enable --yes
```

Or by hand:

```sh
git clone https://github.com/mario4810/omarchy-plugin-drawer ~/.config/omarchy/plugins/io.github.mario4810.plugin-drawer
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.mario4810.plugin-drawer
```

Move the button where you want it with `omarchy bar move`, or drag it on the
bar.

## Update

```sh
omarchy plugin update io.github.mario4810.plugin-drawer
```

It shows the diff and fast-forwards the checkout. Run `omarchy restart shell`
afterwards: the shell reloads `BarWidget.qml` by itself, but not the files it
uses.

## Remove

Empty the drawer first. Widgets in the drawer are not in the bar layout, so
removing the plugin while it holds some takes them off the bar too.

```sh
~/.config/omarchy/plugins/io.github.mario4810.plugin-drawer/plugin-drawer-ctl.sh restore-all
omarchy plugin remove io.github.mario4810.plugin-drawer --yes
```

`restore-all` puts every widget back where it came from, with its settings,
and drops the `plugins[]` entries the drawer added to keep some of them
running. Clicking each row under **In the drawer** in the edit view does the
same thing one widget at a time.

`omarchy plugin disable io.github.mario4810.plugin-drawer` takes the button
off the bar but keeps the plugin installed; empty the drawer before that too.

If you removed it with widgets still inside, put them back by hand
(`omarchy plugin list` shows the ids):

```sh
omarchy bar put <widget-id> --section right
```

### Coming from `io.github.mario4810.drawer`

Versions before 0.2.0 used the id `io.github.mario4810.drawer` and the repo
`omarchy-drawer`. The id is also the install folder, so `omarchy plugin update`
cannot move an old install over. Empty the old drawer through its edit view,
then:

```sh
omarchy plugin remove io.github.mario4810.drawer --yes
omarchy plugin add https://github.com/mario4810/omarchy-plugin-drawer --enable --yes
```

## Using it

1. Click the button (`󰇘`). The drawer opens; an empty drawer opens straight into
   the edit view.
2. Click the pencil at the end of the drawer to open the edit view. It has two
   lists:
   - **In the drawer**: click a row to put the widget back on the bar, where it
     was, with the settings it had.
   - **On the bar**: click a row to move the widget into the drawer.
3. Click outside the drawer to close it. Opening another bar popup closes it
   too.

The bar rebuilds itself whenever its layout changes, so it blinks once when you
move a widget. The drawer reopens by itself in the edit view afterwards.

To open it from a key binding:

```sh
omarchy-shell shell toggle io.github.mario4810.plugin-drawer
```

Works with a horizontal or a vertical bar; on a vertical bar the drawer is a column.

### Settings

Set on the plugin's entry in `~/.config/omarchy/shell.json`:

| Key    | Default | Meaning                    |
|--------|---------|----------------------------|
| `icon` | `󰇘`     | Glyph shown on the button. |

The drawer stores what it holds in the same entry (`items`, plus `origins` for
where each widget came from). You should not need to edit those by hand.

## What it can hold

Any plugin that ships a `bar-widget`, first- or third-party. Custom `command`
and `qml` modules from `bar.layout` and the spacer are not offered, since there
is no plugin to load for them.

Things to know:

- **Stashed widgets show as disabled** in `omarchy plugin list` and the plugin
  manager, since they are no longer in the bar layout. Turning one back on there
  puts it on the bar again, and it leaves the drawer.
- **A widget that hides itself stays hidden.** An update indicator with nothing
  to report takes no room in the drawer either.
- **Widgets start fresh each time the drawer opens** and stop while it is
  closed, so a widget that polls (GitHub, containers) refreshes on open. Plugins
  with a service of their own (Omasend, Spotify) keep running; the drawer
  keeps them enabled.
- **Settings a hosted widget saves from its own UI are not persisted.** The
  shell only lets a plugin rewrite its own entry in `shell.json`. Change such
  settings while the widget is on the bar, then move it in; they travel along.
- **The widgets run in your shell**, as they always did; the drawer just loads
  their code by path, the way the bar does.

## How it works

The bar only hands a plugin's widget component to its own slots, and a widget
cannot hide itself from the outside. So rather than hide widgets, the drawer
takes them out of `bar.layout` and loads each one's `barWidget` entry point
itself, giving it the same `bar`, `moduleName` and `settings` a slot would.

- `BarWidget.qml`: the bar button. Keeps the plugin list and what could be
  moved, and asks for a rescan whenever the drawer opens.
- `PluginDrawer.qml`: the card and its two windows. Hosted widgets open popups that
  position themselves from the height of their own window, expecting the bar.
  So the card window reaches from the screen edge to just past the card, and
  those popups land right beyond it.
- `HostedWidget.qml`, `ManageList.qml`: one loaded widget, and the edit lists.
- `PluginDrawerModel.js`: what the drawer holds, and what can be moved into it.
- `scan-plugins.sh`: finds bar-widget plugins the way the shell does.
- `plugin-drawer-ctl.sh`: moves a widget in or out (or empties the drawer with
  `restore-all`) by editing `shell.json` with one atomic replace. The shell does not let a bar widget change the layout, only
  full-bar plugins can.

## Development

```sh
./test/plugin-drawer-ctl.test.sh        # layout edits against a scratch shell.json
node test/plugin-drawer-model.test.js  # model helpers
omarchy plugin validate .
```

The shell reloads a plugin's entry point (`BarWidget.qml`) when it changes, but
not the QML files it uses; after editing those, run `omarchy restart shell`.

## License

MIT, see `LICENSE`.
