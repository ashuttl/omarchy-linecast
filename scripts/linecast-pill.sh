#!/bin/bash
# Omarchy bar module: one linecast pill, as Waybar-style JSON on stdout.
# Usage: linecast-pill.sh weather|sunshine|moon|tides
#
# Sunshine, moon, and tides are read from `linecast <name> --json`, whose
# times are ISO strings, so the pill never depends on how linecast writes
# a clock: 12-hour or 24-hour, in any language. PILL_CLOCK (24h or 12h,
# from the widget's clock setting) decides how the pill writes them.
#
# The payload is cached, and the countdowns are worked out from it on
# every run, so the bar stays cheap and the minutes stay current.

name="${1:-weather}"
clock="${PILL_CLOCK:-24h}"
# linecast picks plain icons when its output is piped; the bar has a
# Nerd Font, so ask for those.
export LINECAST_ICONS="${LINECAST_ICONS:-nerd}"

unavailable() {
  echo '{"text": "", "class": "unavailable"}'
  exit 0
}

if [[ "$name" == weather ]]; then
  # linecast keeps its own forecast cache, and --oneline is its lightest call.
  line=$(linecast weather --oneline --print ${LINECAST_TEMP:-} 2>/dev/null | head -1)
  # "<Place> <temp>°F <icon> <Condition> …": the place may be several words.
  if [[ ! "$line" =~ (-?[0-9]+)°[FC]?\ +([^ ]+) ]]; then unavailable; fi
  jq -cn --arg text "${BASH_REMATCH[2]} ${BASH_REMATCH[1]}°" --arg tooltip "$line" \
    '{text: $text, tooltip: $tooltip}'
  exit 0
fi

case "$name" in
  sunshine) max_age=1800 ;;
  moon) max_age=900 ;;
  tides) max_age=1800 ;;
  *) unavailable ;;
esac

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
cache="$cache_dir/omarchy-bar-$name.json"
config="${XDG_CONFIG_HOME:-$HOME/.config}/linecast/config.json"
now=$(date +%s)
mtime=$(stat -c %Y "$cache" 2>/dev/null || echo 0)

refresh=0
[[ ! -s "$cache" ]] || ((now - mtime > max_age)) && refresh=1
# The location or units just changed: the cached payload is for the wrong
# place, so a failed fetch must clear it rather than fall back to it.
[[ "$config" -nt "$cache" ]] && refresh=2

if ((refresh)); then
  mkdir -p "$cache_dir"
  tmp=$(mktemp "$cache.XXXXXX") || unavailable
  if linecast "$name" --json 2>/dev/null | head -c 2097152 >"$tmp" \
    && jq -e '.schema' "$tmp" >/dev/null 2>&1; then
    mv -f "$tmp" "$cache"
    mtime=$now
  else
    rm -f "$tmp"
    ((refresh == 2)) && rm -f "$cache"
  fi
fi

[[ -s "$cache" ]] || unavailable

# Times in the payload are local to the place and carry no zone. Read
# them all as if UTC and move "now" along from fetched_at by the cache's
# age: the differences come out right wherever the place and this
# machine are.
jq -c --arg name "$name" --arg clock "$clock" --argjson age $((now - mtime)) '
  def ts: strptime("%Y-%m-%dT%H:%M") | mktime;
  def hhmm:
    .[11:16] as $t
    | if $clock == "12h"
      then ($t[0:2] | tonumber) as $h
        | "\(if $h % 12 == 0 then 12 else $h % 12 end):\($t[3:5])\(if $h < 12 then "a" else "p" end)"
      else $t end;
  def pad: tostring | if length < 2 then "0" + . else . end;
  def hm: (. / 60 | floor) as $m | "\($m / 60 | floor)h\($m % 60 | pad)m";
  def countdown:
    ((. + 59) / 60 | floor) as $m
    | if $m >= 60 then "\($m / 60 | floor)h\($m % 60 | pad)m" else "\($m)m" end;
  def delta:
    (if . < 0 then "−" else "+" end) as $sign
    | (if . < 0 then -. else . end | floor) as $s
    | $sign + (if $s >= 60 then "\($s / 60 | floor)m" else "" end)
      + (if $s % 60 > 0 or $s < 60 then "\($s % 60)s" else "" end);
  def unavailable: {text: "", class: "unavailable"};
  def upcoming($now): map(select(.time != null and (.time | ts) > $now));

  ((.fetched_at | ts) + $age) as $now
  | if $name == "sunshine" then
      # Glyphs match linecast: sunrise, sunset; a sun or a moon for the
      # polar seasons, which have neither.
      ([{kind: "sunrise", time: .sunrise}, {kind: "sunset", time: .sunset},
        {kind: "sunrise", time: .tomorrow_sunrise}, {kind: "sunset", time: .tomorrow_sunset}]
       | upcoming($now) | first) as $next
      | if $next then
          (($next.time | ts) - $now | countdown) as $until
          | {text: "\(if $next.kind == "sunrise" then "󰖜" else "󰖛" end) \($until)",
             tooltip: ("\(if $next.kind == "sunrise" then "Sunrise" else "Sunset" end) in \($until) — "
               + ([.sunrise, .sunset] | map(select(. != null)) as $t
                  | if ($t | length) == 2 then "↑\($t[0] | hhmm) ↓\($t[1] | hhmm) " else "" end)
               + "\(.day_length_seconds // 0 | hm) \(.day_length_delta_seconds // 0 | delta)")}
        elif .polar == "day" then {text: "󰖙", tooltip: "Polar day"}
        elif .polar == "night" then {text: "󰖔", tooltip: "Polar night"}
        else unavailable end
    elif $name == "moon" then
      # The first event still ahead is the next one; a ↓ means the moon
      # is up now. Near the poles there may be none for days: icon alone.
      def arrow: if .kind == "rise" then "↑" else "↓" end;
      ((.events // []) | upcoming($now)) as $events
      | if (.icon // "") == "" then unavailable else
          {text: ([.icon] + ($events[:1] | map(arrow + (.time | hhmm))) | join(" ")),
           tooltip: ([.icon, .phase, "\(.illumination // 0 | round)%"]
                     + ($events[:2] | map(arrow + (.time | hhmm))) | map(select(. != null)) | join(" "))}
        end
    elif $name == "tides" then
      # No station in range (inland, offline) leaves no events: collapse.
      def mark: if .kind == "high" then "▲" else "▼" end;
      (.units.height // "") as $unit
      | ((.events // []) | upcoming($now)) as $events
      | if ($events | length) == 0 then unavailable else
          {text: ($events[0] | "\(mark) \(.time | hhmm)"),
           tooltip: ([.station // .location]
                     + ($events[:2] | map("\(mark) \(.time | hhmm) \(.height * 10 | round / 10)\(if $unit == "ft" then "′" else " " + $unit end)"))
                     | map(select(. != null and . != "")) | join(" "))}
        end
    else unavailable end
' "$cache" 2>/dev/null || unavailable
