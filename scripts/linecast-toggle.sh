#!/bin/bash
# Float a linecast view in its own terminal window: open if absent, close
# if present. Usage: linecast-toggle.sh <name>
# (weather, sunshine, moon, tides, radar, maps)

name="$1"
class="org.omarchy.linecast-$name"

case "$name" in
  radar | maps) size="1280 820" ;;
  tides) size="1100 680" ;;
  *) size="1000 640" ;;
esac

addr=$(hyprctl clients -j | jq -r --arg c "$class" 'first(.[] | select(.class == $c)) | .address // empty')

if [[ -n "$addr" ]]; then
  # Lua-form dispatch takes a window *selector*, not a bare address key.
  # With no valid target it falls back to the active window, which is why
  # a stray { address = ... } arg used to close whatever was focused.
  hyprctl dispatch "hl.dsp.window.close({ window = \"address:$addr\" })" >/dev/null 2>&1 \
    || hyprctl dispatch closewindow "address:$addr" >/dev/null 2>&1
  exit 0
fi

flags=""
[[ "$name" == weather ]] && flags="${LINECAST_TEMP:-}"
cmd="xdg-terminal-exec --app-id=$class --title=${name^} -e linecast $name $flags"
rules="[float; size $size; center]"

# Hyprland 0.56+ takes dispatches as Lua; older releases keep the plain form.
hyprctl eval "hl.dispatch(hl.dsp.exec_cmd(\"$rules $cmd\"))" >/dev/null 2>&1 \
  || hyprctl dispatch exec "$rules $cmd" >/dev/null 2>&1 \
  || exec setsid uwsm-app -- $cmd
