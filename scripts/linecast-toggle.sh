#!/bin/bash
# Toggle a floating linecast window: open if absent, close if present.
# Usage: linecast-toggle.sh <name>   (e.g. weather, sunshine, tides)

name="$1"
class="org.omarchy.$name"

addr=$(hyprctl clients -j | jq -r --arg c "$class" 'first(.[] | select(.class == $c)) | .address // empty')

if [[ -n "$addr" ]]; then
  # Lua-form dispatch takes a window *selector*, not a bare address key.
  # With no valid target it falls back to the active window, which is why
  # a stray { address = ... } arg used to close whatever was focused.
  hyprctl dispatch "hl.dsp.window.close({ window = \"address:$addr\" })"
else
  exec setsid uwsm-app -- xdg-terminal-exec --app-id="$class" --title="${name^}" -e bash -c "linecast $name"
fi
