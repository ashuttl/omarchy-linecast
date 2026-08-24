#!/bin/bash
# Omarchy bar module: linecast weather
# Bar shows "<icon> <temp>", tooltip shows the full oneline summary.

if ! command -v linecast >/dev/null 2>&1; then
  # No linecast yet: the pill stays visible so the panel can offer to
  # install it.
  echo '{"text": "󰖐 Linecast", "tooltip": "linecast is not installed — open the panel to install it", "class": "missing"}'
  exit 0
fi

line=$(linecast weather --oneline --print 2>/dev/null)

if [[ -z "$line" ]]; then
  # Collapse the module when weather is unavailable (matches omarchy default behavior)
  echo '{"text": "", "class": "unavailable"}'
  exit 0
fi

# Oneline format: "<City> <temp>°F <icon> <Condition> Wind <n>mph 💧<n>%"
temp=$(grep -oE -- '-?[0-9]+°[FC]' <<<"$line" | head -1)
icon=$(sed -E 's/.*-?[0-9]+°[FC] ([^ ]+) .*/\1/' <<<"$line")

jq -cn --arg text "$icon ${temp%[FC]}" --arg tooltip "$line" \
  '{text: $text, tooltip: $tooltip}'
