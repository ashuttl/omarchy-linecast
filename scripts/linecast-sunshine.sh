#!/bin/bash
# Omarchy bar module: countdown to the next sunrise/sunset, from `linecast sunshine`.
# The oneline output is cached for 30 min; the countdown is computed locally.

cache="$HOME/.cache/omarchy-bar-sunshine-oneline"
config="$HOME/.config/linecast/config.json"
max_age=1800
now=$(date +%s)

# Refresh when stale, or immediately after `linecast location set/auto`
if [[ ! -s "$cache" || $((now - $(stat -c %Y "$cache" 2>/dev/null || echo 0))) -gt $max_age || "$config" -nt "$cache" ]]; then
  fresh=$(linecast sunshine --oneline --print 2>/dev/null)
  [[ -n "$fresh" ]] && printf '%s' "$fresh" >"$cache"
fi

line=$(cat "$cache" 2>/dev/null)

# Oneline format: "↑5:41a ↓7:50p 14h08m −2m38s 󰽥"
if [[ ! "$line" =~ ↑([0-9]+:[0-9]+)([ap]).*↓([0-9]+:[0-9]+)([ap]) ]]; then
  echo '{"text": "", "class": "unavailable"}'
  exit 0
fi

sunrise=$(date -d "${BASH_REMATCH[1]}${BASH_REMATCH[2]}m" +%s)
sunset=$(date -d "${BASH_REMATCH[3]}${BASH_REMATCH[4]}m" +%s)

# Glyphs match linecast's own usage: 󰖜 sunrise, 󰖛 sunset
if ((now < sunrise)); then
  target=$sunrise icon="󰖜" event="Sunrise"
elif ((now < sunset)); then
  target=$sunset icon="󰖛" event="Sunset"
else
  target=$(date -d "tomorrow ${BASH_REMATCH[1]}${BASH_REMATCH[2]}m" +%s)
  icon="󰖜" event="Sunrise"
fi

mins=$(((target - now + 59) / 60))
if ((mins >= 60)); then
  until_str="$((mins / 60))h$(printf '%02d' $((mins % 60)))m"
else
  until_str="${mins}m"
fi

jq -cn --arg text "$icon $until_str" \
  --arg tooltip "$event in $until_str — $line" \
  '{text: $text, tooltip: $tooltip}'
