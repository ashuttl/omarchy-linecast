# omarchy-linecast

An [Omarchy](https://omarchy.org) bar-widget plugin for
[linecast](https://github.com/ashuttl/linecast) — terminal weather, solar
arc, moon, and tides.

![preview](preview.png)

## What you get

- **Weather pill**, always visible: icon + temperature, full oneline summary
  as tooltip. **Sunshine, moon, and tide pills** tuck away and slide out on
  hover (the same gesture as the stock indicators widget).
- **Or take the pills apart.** The widget can be added more than once, so
  the four don't have to travel together: give each one its own entry and
  put weather beside the clock and tides over by the tray, each with its
  own panel anchored under it. See [Several widgets](#several-widgets).
- **Left click on any pill opens its panel**, anchored to that pill; right
  click opens the full linecast TUI in a floating terminal. `r` refetches,
  `Escape` closes, `Tab` switches to neighboring bar panels.
- **Weather panel**: current conditions with the plain-English comparison
  line, weather alerts, a 24-hour temperature strip and a week of range
  bars in linecast's temperature colors, and wind / humidity / sun times /
  AQI at a glance.
- **Sunshine panel**: countdown to the next sunrise/sunset over a drawn
  solar arc with the sun at its current position, day length and its
  day-to-day drift, solar noon, tomorrow's sunrise.
- **Moon panel**: a drawn phase disc (correct terminator, hemisphere
  aware), phase and illumination, moonrise/moonset, next full and new
  moons.
- **Tides panel**: countdown to the next high/low over the tide curve
  (past dimmed, extremes marked), the upcoming turns, and the station
  name.

## Requirements

- linecast with `weather --json` support (newer than v1.8.0; in the dev
  tree as of 2026-08-14)
- A Nerd Font in the bar (linecast's default glyph set)
- `jq` (used by the pill scripts)

## Install

```bash
omarchy plugin add https://github.com/ashuttl/omarchy-linecast.git --enable
```

Then add the widget to the bar if it wasn't added automatically:

```bash
omarchy bar move ashuttl.linecast --section center
```

## Settings

Inline in the widget's `shell.json` entry (hot-reloads on save):

- `pills` (default `["weather", "sunshine", "moon", "tides"]`) — which
  pills show, in display order. The first entry is the always-visible
  pill and hosts the popup; the rest slide out on hover.
  For example, weather and tides only:

  ```json
  { "id": "ashuttl.linecast", "pills": ["weather", "tides"] }
  ```

- `alwaysShow` (default `false`) — keep every pill out instead of sliding
  the extras in on hover.
- `weatherRefreshSeconds` (default 600) — weather pill refresh interval.

## Several widgets

The manifest sets `allowMultiple`, so the bar takes as many Linecast
entries as you want. One pill each spreads them around the bar, and every
one keeps its own panel, anchored under itself:

```json
"center": [
  { "id": "ashuttl.clock" },
  { "id": "ashuttl.linecast", "pills": ["weather"] }
],
"right": [
  { "id": "ashuttl.linecast", "pills": ["tides"] },
  { "id": "omarchy.tray" }
]
```

Two things to know:

- **Place them by editing `shell.json`.** `omarchy bar put/move/set` and
  `omarchy plugin enable/disable` all address a widget by its plugin id,
  which no longer picks out one entry. They still work when a single
  Linecast widget is on the bar.
- **Grouped widgets reveal on their own hover** as well as on the bar's
  center-section hold, so a widget carrying extras works just as well
  parked in `left` or `right`.

## Notes

The pills shell out to `scripts/linecast-*.sh`, which cache linecast's
`--oneline` output under `~/.cache/`; each panel face runs its
`linecast <command> --json` on first open and refetches when stale.
Location follows `linecast location`, and the picker's recents are shared
by every Linecast widget in
`~/.local/state/omarchy/linecast-recent-locations.json`.

Panels can be driven from scripts or keybindings:

```bash
omarchy-shell ashuttl.linecast openSection tides   # weather|sunshine|moon|tides
omarchy-shell shell toggle ashuttl.linecast        # last-used face
```

`openSection` finds the widget carrying that pill and opens its panel
there. The plain `toggle` names no pill, so with several widgets up it
acts on whichever one the bar would route a hotkey to — bind
`openSection` per pill if you want a key each.
