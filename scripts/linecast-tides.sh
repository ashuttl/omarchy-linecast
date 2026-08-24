#!/bin/bash
# Omarchy bar module: next tide event, from `linecast tides`.
# The oneline output is cached for 30 min. Collapses quietly when the
# location has no tide station within range (inland travel, no network).


# The bar keeps a 24-hour clock unless the widget's clock setting says
# 12h; linecast's oneline output is 12-hour in English, so convert here.
clock_fix() {
  if [[ "${PILL_CLOCK:-24h}" == "12h" ]]; then cat; else
    perl -pe 's/\b(\d{1,2}):(\d{2})([ap])\b/sprintf("%02d:%s", ($1 % 12) + ($3 eq "p" ? 12 : 0), $2)/ge'
  fi
}

cache="$HOME/.cache/omarchy-bar-tides-oneline"
config="$HOME/.config/linecast/config.json"
max_age=1800
now=$(date +%s)

refresh=0
if [[ ! -s "$cache" || $((now - $(stat -c %Y "$cache" 2>/dev/null || echo 0))) -gt $max_age ]]; then
  refresh=1
fi
# Location just changed: the cached line is for the wrong place, so a failed
# fetch must clear it rather than fall back to it.
[[ "$config" -nt "$cache" ]] && refresh=2

if ((refresh)); then
  fresh=$(linecast tides --oneline --print 2>/dev/null)
  if [[ -n "$fresh" ]] || ((refresh == 2)); then
    printf '%s' "$fresh" >"$cache"
  fi
fi

line=$(cat "$cache" 2>/dev/null)

# Oneline format: "Gardiner ▲High 2:13a 7.1′ ▼Low 9:04a 0.0′"
if [[ ! "$line" =~ ([▲▼])[^\ ]*\ ([0-9]+:[0-9]+[ap]) ]]; then
  echo '{"text": "", "class": "unavailable"}'
  exit 0
fi

jq -cn --arg text "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}" --arg tooltip "$line" \
  '{text: $text, tooltip: $tooltip}' | clock_fix
