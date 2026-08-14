# Linecast for Omarchy

An [Omarchy](https://omarchy.org) bar-widget plugin for
[linecast](https://github.com/ashuttl/linecast) — terminal weather, solar
arc, moon, and tides.

![preview](preview.png)

## What you get

- **Weather pill**, always visible: icon + temperature, full oneline summary
  as tooltip. Left click opens an anchored weather panel; right click opens
  the full linecast weather TUI in a floating terminal.
- **Sunshine, moon, and tide pills** that tuck away and slide out on the
  bar's center-section hover hold (the same gesture as the stock indicators
  widget). Clicking any of them toggles its linecast TUI in a floating
  terminal.
- **Weather panel**: current conditions, weather alerts, a 24-hour
  temperature strip, a week of range bars, and wind / humidity / sun times /
  AQI at a glance. `r` refetches, `Escape` closes, `Tab` switches panels.

## Requirements

- linecast with `weather --json` support (newer than v1.8.0; in the dev
  tree as of 2026-08-14)
- A Nerd Font in the bar (linecast's default glyph set)
- `jq` (used by the pill scripts)

## Install

```bash
omarchy plugin add <this-repo-url> --enable
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
`--oneline` output under `~/.cache/`; the panel runs `linecast weather
--json` on open (at most every 10 minutes while open). Location follows
`linecast location`.
