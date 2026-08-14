#!/bin/bash
# Omarchy bar module: moon phase icon + next rise/set event, from `linecast moon`.
# Pure local astronomy (no network), but cache anyway to keep the bar cheap.

cache="$HOME/.cache/omarchy-bar-moon-oneline"
config="$HOME/.config/linecast/config.json"
max_age=900
now=$(date +%s)

if [[ ! -s "$cache" || $((now - $(stat -c %Y "$cache" 2>/dev/null || echo 0))) -gt $max_age || "$config" -nt "$cache" ]]; then
  fresh=$(linecast moon --oneline --print 2>/dev/null)
  [[ -n "$fresh" ]] && printf '%s' "$fresh" >"$cache"
fi

line=$(cat "$cache" 2>/dev/null)

if [[ -z "$line" ]]; then
  echo '{"text": "", "class": "unavailable"}'
  exit 0
fi

# Oneline format: "󰽥 Waning Crescent 2% ↑5:23a ↓7:57p"
# Events are the *next* rise/set in chronological order, so the first is
# always upcoming; a leading ↓ means the moon is up right now. Near the
# poles events can be days away and absent — fall back to the icon alone.
icon="${line%% *}"
if [[ "$line" =~ ([↑↓])([0-9]+:[0-9]+[ap]?) ]]; then
  text="$icon ${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
else
  text="$icon"
fi

jq -cn --arg text "$text" --arg tooltip "$line" \
  '{text: $text, tooltip: $tooltip}'
