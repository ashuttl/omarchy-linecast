# omarchy-linecast

An [Omarchy](https://omarchy.org) bar-widget plugin for
[linecast](https://github.com/ashuttl/linecast) — terminal weather, solar
arc, moon, and tides.

![preview](preview.png)

## What you get

- **Weather pill**, always visible: icon + temperature, full oneline summary
  as tooltip. **Sunshine, moon, and tide pills** tuck away and slide out on
  the bar's center-section hover hold (the same gesture as the stock
  indicators widget).
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

Inline in the widget's `shell.json` entry:

- `weatherRefreshSeconds` (default 600) — weather pill refresh interval.

## Notes

The pills shell out to `scripts/linecast-*.sh`, which cache linecast's
`--oneline` output under `~/.cache/`; each panel face runs its
`linecast <command> --json` on first open and refetches when stale.
Location follows `linecast location`.

Panels can be driven from scripts or keybindings:

```bash
omarchy-shell ashuttl.linecast openSection tides   # weather|sunshine|moon|tides
omarchy-shell shell toggle ashuttl.linecast        # last-used face
```
