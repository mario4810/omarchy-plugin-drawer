#!/usr/bin/env bash
# Exercises plugin-drawer-ctl.sh against a scratch shell.json; never touches the real one.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ctl="$here/../plugin-drawer-ctl.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

export OMARCHY_SHELL_JSON="$work/shell.json"
export OMARCHY_PLUGIN_DRAWER_REOPEN="$work/reopen"
self="io.github.mario4810.plugin-drawer"

fresh() {
  cat > "$OMARCHY_SHELL_JSON" <<JSON
{
  "version": 1,
  "bar": {
    "layout": {
      "left": [{ "id": "omarchy.menu" }],
      "center": [{ "id": "omarchy.clock", "format": "HH:mm" }],
      "right": [
        { "id": "a.one" },
        { "id": "b.two", "showPercentage": false },
        { "id": "c.three" },
        { "id": "$self", "icon": "x" }
      ]
    }
  },
  "plugins": [{ "id": "shell.settings" }]
}
JSON
  cp "$OMARCHY_SHELL_JSON" "$work/original.json"
  rm -f "$OMARCHY_PLUGIN_DRAWER_REOPEN"
}

fails=0
check() { # <description> <jq -e filter>
  if jq -e "$2" "$OMARCHY_SHELL_JSON" > /dev/null; then echo "ok   $1"
  else echo "FAIL $1"; fails=$((fails + 1)); fi
}
fails_with() { # <description> <command...>
  local desc="$1"; shift
  if "$@" 2> /dev/null; then echo "FAIL $desc"; fails=$((fails + 1)); else echo "ok   $desc"; fi
}

fresh
"$ctl" stash b.two
check "stash removes the widget from the bar" '[.bar.layout[][].id] | index("b.two") | not'
check "stash keeps its settings in the drawer" '[.bar.layout.right[] | select(.id == "'"$self"'")][0].items == [{"id":"b.two","showPercentage":false}]'
check "stash remembers the old neighbour" '[.bar.layout.right[] | select(.id == "'"$self"'")][0].origins["b.two"] == {"section":"right","after":"a.one"}'
check "stash leaves plugins alone by default" '.plugins == [{"id":"shell.settings"}]'
[[ -e $OMARCHY_PLUGIN_DRAWER_REOPEN ]] && echo "ok   stash flags the drawer to reopen" || { echo "FAIL reopen flag"; fails=$((fails + 1)); }

"$ctl" restore b.two
if diff <(jq -S . "$work/original.json") <(jq -S . "$OMARCHY_SHELL_JSON") > /dev/null; then
  echo "ok   restore after stash gives back the original config"
else echo "FAIL restore is not the inverse of stash"; fails=$((fails + 1)); fi

fresh
"$ctl" stash a.one --keep-enabled
check "--keep-enabled lists the plugin in plugins[]" '.plugins == [{"id":"shell.settings"},{"id":"a.one"}]'
"$ctl" stash c.three
check "several widgets can be stashed" '[.bar.layout.right[] | select(.id == "'"$self"'")][0].items | map(.id) == ["a.one","c.three"]'
"$ctl" restore a.one
check "restore drops the plugins[] entry it added" '.plugins == [{"id":"shell.settings"}]'
check "restore puts a first-in-section widget back first" '.bar.layout.right | map(.id) | .[0] == "a.one"'
check "restore leaves other stashed widgets alone" '[.bar.layout.right[] | select(.id == "'"$self"'")][0].items | map(.id) == ["c.three"]'

fresh
jq '.plugins += [{"id":"b.two"}]' "$OMARCHY_SHELL_JSON" > "$work/tmp" && mv "$work/tmp" "$OMARCHY_SHELL_JSON"
cp "$OMARCHY_SHELL_JSON" "$work/original.json"
"$ctl" stash b.two --keep-enabled
check "--keep-enabled does not duplicate an existing plugins[] entry" '[.plugins[] | select(.id == "b.two")] | length == 1'
"$ctl" restore b.two
if diff <(jq -S . "$work/original.json") <(jq -S . "$OMARCHY_SHELL_JSON") > /dev/null; then
  echo "ok   restore leaves a pre-existing plugins[] entry alone"
else echo "FAIL restore removed a plugins[] entry it did not add"; fails=$((fails + 1)); fi

fresh
"$ctl" stash omarchy.clock
"$ctl" restore omarchy.clock
check "a lone center widget returns to the center" '.bar.layout.center == [{"id":"omarchy.clock","format":"HH:mm"}]'

fresh
"$ctl" stash a.one --keep-enabled
"$ctl" stash b.two
"$ctl" restore-all
if diff <(jq -S . "$work/original.json") <(jq -S . "$OMARCHY_SHELL_JSON") > /dev/null; then
  echo "ok   restore-all empties the drawer back into the original config"
else echo "FAIL restore-all is not the inverse of the stashes"; fails=$((fails + 1)); fi
[[ ! -e $OMARCHY_PLUGIN_DRAWER_REOPEN ]] && echo "ok   restore-all leaves no reopen flag" || { echo "FAIL restore-all left the reopen flag"; fails=$((fails + 1)); }
"$ctl" restore-all
check "restore-all on an empty drawer changes nothing" '.bar.layout.right | map(.id) == ["a.one","b.two","c.three","'"$self"'"]'

fresh
fails_with "stashing something not in the bar fails" "$ctl" stash nope.missing
fails_with "restoring something not in the drawer fails" "$ctl" restore a.one
fails_with "the drawer cannot stash itself" "$ctl" stash "$self"
fails_with "unknown actions fail" "$ctl" frobnicate a.one
if diff <(jq -S . "$work/original.json") <(jq -S . "$OMARCHY_SHELL_JSON") > /dev/null; then
  echo "ok   failed calls leave the config untouched"
else echo "FAIL failed call changed the config"; fails=$((fails + 1)); fi

(( fails == 0 )) && echo "all passed" || { echo "$fails failed"; exit 1; }
