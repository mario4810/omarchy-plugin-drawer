#!/usr/bin/env bash
# Move bar widgets in and out of the drawer by editing shell.json.
#
#   plugin-drawer-ctl.sh stash   <widget-id> [--keep-enabled]
#   plugin-drawer-ctl.sh restore <widget-id>
#   plugin-drawer-ctl.sh restore-all
#
# `stash` takes the widget's entry out of bar.layout and parks it, settings
# and all, in the drawer's own `items` list, remembering where it came from
# so `restore` can put it back next to its old neighbour. With
# --keep-enabled the plugin id is also listed in `plugins[]` (unless it
# already was), which is how the shell keeps a plugin that has a service or
# panel loaded once it has no bar slot. `restore` removes only an entry that
# `stash` added. `restore-all` empties the drawer, which is what to run
# before removing the plugin.
#
# The shell only reads shell.json and the bar widget cannot write it (only
# full-bar plugins get a config mutator), so this script edits the file
# directly with one atomic replace, the same way the shell persists it.
set -euo pipefail

self="io.github.mario4810.plugin-drawer"
config="${OMARCHY_SHELL_JSON:-$HOME/.config/omarchy/shell.json}"
# The bar rebuilds every widget when its layout changes, which takes the open
# drawer with it. The drawer looks for this flag when it comes back up.
reopen_flag="${OMARCHY_PLUGIN_DRAWER_REOPEN:-${XDG_RUNTIME_DIR:-/tmp}/omarchy-plugin-drawer-reopen}"

die() { echo "plugin-drawer-ctl: $*" >&2; exit 1; }

edit() { # <jq args...>
  local tmp
  tmp="$(mktemp "$config.XXXXXX")"
  if ! jq "$@" "$config" > "$tmp"; then rm -f "$tmp"; return 1; fi
  touch "$reopen_flag"
  mv "$tmp" "$config"
}

stash() {
  local id="$1" keep="$2"
  edit --arg self "$self" --arg id "$id" --argjson keep "$keep" '
    def sections: ["left", "center", "right"];
    (.bar.layout // {}) as $layout
    | ([sections[] as $s | ($layout[$s] // []) | to_entries[]
        | select(.value.id == $id)
        | {section: $s, index: .key, entry: .value,
           after: (if .key > 0 then ($layout[$s][.key - 1].id) else null end)}] | first) as $found
    | if $found == null then error("\($id) is not in the bar") else . end
    | if ([sections[] as $s | ($layout[$s] // [])[] | select(.id == $self)] | length) == 0
      then error("the drawer is not in the bar") else . end
    | (($keep) and (((.plugins // []) | any(.id == $id)) | not)) as $addPlugin
    | .bar.layout[$found.section] |= map(select(.id != $id))
    | .bar.layout |= map_values(map(
        if .id == $self then
          .items = (((.items // []) | map(select(.id != $id))) + [$found.entry])
          | .origins = ((.origins // {}) + {($id): ({section: $found.section, after: $found.after}
              + (if $addPlugin then {plugin: true} else {} end))})
        else . end))
    | if $addPlugin then .plugins = ((.plugins // []) + [{id: $id}]) else . end'
}

restore() {
  local id="$1"
  edit --arg self "$self" --arg id "$id" '
    def sections: ["left", "center", "right"];
    (.bar.layout // {}) as $layout
    | ([sections[] | ($layout[.] // [])[] | select(.id == $self)] | first) as $me
    | if $me == null then error("the drawer is not in the bar") else . end
    | ([($me.items // [])[] | select(.id == $id)] | first) as $item
    | if $item == null then error("\($id) is not in the drawer") else . end
    | ($me.origins[$id] // {section: "right", after: null}) as $origin
    | (if ($layout[$origin.section] // null) == null then "right" else $origin.section end) as $section
    | .bar.layout |= map_values(map(
        if .id == $self then
          .items |= map(select(.id != $id))
          | if (.items | length) == 0 then del(.items, .origins)
            else .origins |= (. // {} | del(.[$id])) end
        else . end))
    | .bar.layout[$section] |= (
        map(.id) as $ids
        | ($origin.after as $after
           | if $after == null then 0
             else (($ids | index($after)) as $at | if $at == null then length else $at + 1 end)
             end) as $at
        | .[:$at] + [$item] + .[$at:])
    | if $origin.plugin == true then .plugins |= map(select(.id != $id)) else . end'
}

restore_all() {
  local id
  # Newest first: each stash recorded its neighbour as the bar stood then,
  # so undoing them in reverse gives back the exact original order.
  jq -r --arg self "$self" '
    [.bar.layout // {} | .[][] | select(.id == $self)] | first // {}
    | (.items // []) | reverse[].id' "$config" |
    while IFS= read -r id; do restore "$id"; done
  # Nothing is left to reopen; this usually runs on the way out.
  rm -f "$reopen_flag"
}

[[ -f $config ]] || die "no shell config at $config"
command -v jq > /dev/null || die "jq is required"

action="${1:-}"; id="${2:-}"
if [[ $action == restore-all ]]; then restore_all; exit; fi
[[ -n $id ]] || die "usage: plugin-drawer-ctl.sh stash|restore <widget-id> [--keep-enabled] | restore-all"
[[ $id != "$self" ]] || die "the drawer cannot hold itself"

case "$action" in
  stash)   stash "$id" "$([[ ${3:-} == --keep-enabled ]] && echo true || echo false)" ;;
  restore) restore "$id" ;;
  *)       die "unknown action '$action'" ;;
esac
