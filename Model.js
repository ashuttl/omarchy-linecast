// Data layer for the linecast weather panel. The payload comes from
// `linecast weather --json` (schema 1); everything here is defensive
// because the panel renders whatever an older or partial payload gives it.
.pragma library

function parsePayload(raw) {
  var trimmed = String(raw || "").trim()
  if (trimmed === "") return null
  try {
    var data = JSON.parse(trimmed)
    return data && data.schema === 1 ? data : null
  } catch (e) {
    return null
  }
}

function roundTemp(value) {
  return (value === null || value === undefined || isNaN(value)) ? "–" : String(Math.round(value)) + "°"
}

function num(value, fallback) {
  return (value === null || value === undefined || isNaN(value)) ? fallback : Number(value)
}

// "2026-08-14T14:00" -> "2p" (linecast's own compact hour style).
function hourLabel(isoTime) {
  var m = /T(\d{2}):/.exec(String(isoTime || ""))
  if (!m) return ""
  var h = parseInt(m[1], 10)
  var suffix = h < 12 ? "a" : "p"
  var display = h % 12
  if (display === 0) display = 12
  return display + suffix
}

// "2026-08-14T05:41" -> "5:41a"
function clockLabel(isoTime) {
  var m = /T(\d{2}):(\d{2})/.exec(String(isoTime || ""))
  if (!m) return ""
  var h = parseInt(m[1], 10)
  var suffix = h < 12 ? "a" : "p"
  var display = h % 12
  if (display === 0) display = 12
  return display + ":" + m[2] + suffix
}

// Sample every `step`-th hour so 24 hourly entries become a readable strip.
function sampleHours(hourly, step, maxColumns) {
  var out = []
  if (!hourly || !hourly.length) return out
  for (var i = 0; i < hourly.length && out.length < maxColumns; i += step)
    out.push(hourly[i])
  return out
}

function tempExtent(entries, lowKey, highKey) {
  var min = NaN, max = NaN
  for (var i = 0; i < (entries ? entries.length : 0); i++) {
    var lo = num(entries[i][lowKey], NaN)
    var hi = num(entries[i][highKey === undefined ? lowKey : highKey], NaN)
    if (!isNaN(lo) && (isNaN(min) || lo < min)) min = lo
    if (!isNaN(hi) && (isNaN(max) || hi > max)) max = hi
  }
  if (isNaN(min) || isNaN(max)) return { min: 0, max: 1, span: 1 }
  var span = max - min
  return { min: min, max: max, span: span > 0 ? span : 1 }
}

// 0..1 position of a value within an extent, clamped.
function extentPos(value, extent) {
  var v = num(value, extent.min)
  return Math.min(1, Math.max(0, (v - extent.min) / extent.span))
}

// "2026-08-14" + index -> "Today" / short weekday.
function dayLabel(dateStr, index, locale) {
  if (index === 0) return "Today"
  var parts = String(dateStr || "").split("-")
  if (parts.length !== 3) return ""
  var d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
  return locale.dayName(d.getDay(), 1 /* Locale.ShortFormat */)
}

function severityIsUrgent(severity) {
  var s = String(severity || "").toLowerCase()
  return s === "severe" || s === "extreme" || s === "warning"
}

// Alert badge tone, mirroring the TUI: red for severe/extreme, amber for
// moderate, quiet for the rest.
function severityTone(severity) {
  var s = String(severity || "").toLowerCase()
  if (s === "severe" || s === "extreme" || s === "warning") return "severe"
  if (s === "moderate") return "moderate"
  return "minor"
}

// "2026-08-16T23:00" -> "Sun 11pm" (minutes only when they matter),
// matching the TUI's alert timeframe style.
function alertClock(iso, locale) {
  var t = parseIsoLocal(iso)
  if (isNaN(t)) return ""
  var d = new Date(t)
  var h = d.getHours()
  var suffix = h < 12 ? "am" : "pm"
  var display = h % 12
  if (display === 0) display = 12
  var mins = d.getMinutes()
  return locale.dayName(d.getDay(), 1 /* Locale.ShortFormat */) + " "
    + display + (mins > 0 ? ":" + (mins < 10 ? "0" : "") + mins : "") + suffix
}

function alertTimeframe(effective, expires, locale) {
  var from = alertClock(effective, locale)
  var to = alertClock(expires, locale)
  if (from !== "" && to !== "") return from + " – " + to
  return from !== "" ? from : (to !== "" ? "until " + to : "")
}

// "Fayette, Maine, United States" -> "Fayette, Maine".
function shortLocation(label) {
  return String(label || "").split(",").slice(0, 2).join(",").trim()
}

// Temperature → color, mirroring linecast's own TEMP_COLORS stops
// (_weather_style.py): the ramp lingers in the cool band and turns over
// quickly through the warm one, so 72°F is already yellow and 82°F
// orange — a linear hue sweep leaves whole forecasts green. Like the
// TUI, the anchors sample the theme's ANSI colors (buildTempStops);
// these fixed RGBs are the fallback when no theme palette is readable.
// Stops are in °F; Celsius payloads convert first.
var TEMP_STOPS = [
  [0,  0.42, 0.55, 0.85],  // deep blue
  [32, 0.31, 0.56, 0.85],  // blue
  [45, 0.25, 0.75, 0.75],  // cyan
  [55, 0.35, 0.77, 0.44],  // green
  [65, 0.66, 0.79, 0.31],  // green-yellow
  [72, 0.88, 0.76, 0.31],  // yellow
  [82, 0.91, 0.60, 0.31],  // orange
  [95, 0.88, 0.36, 0.31],  // red
]

// colors.toml -> { name: "#rrggbb" }, or null when nothing parses (same
// line shape the shell's Color singleton reads).
function parseColorsToml(raw) {
  var out = null
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
    if (m) {
      if (!out) out = {}
      out[m[1]] = m[2]
    }
  }
  return out
}

function hexToRgb(hex) {
  var m = /^#([0-9A-Fa-f]{6})$/.exec(String(hex || ""))
  if (!m) return null
  return {
    r: parseInt(m[1].slice(0, 2), 16) / 255,
    g: parseInt(m[1].slice(2, 4), 16) / 255,
    b: parseInt(m[1].slice(4, 6), 16) / 255
  }
}

function contrastRatio(a, b) {
  function lum(c) {
    function ch(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b)
  }
  var la = lum(a), lb = lum(b)
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}

// A ramp anchor from the theme: the plain ANSI color when it reads
// against the background, its bright twin when it doesn't — the TUI's
// best_contrast pick. New-format themes name their colors; generated
// palettes (colors-from-alacritty) only have color0..15 slots.
var ANSI_SLOT = { red: 1, green: 2, yellow: 3, blue: 4, magenta: 5, cyan: 6 }

function themeAnchor(colors, name, bg, fallback) {
  var slot = ANSI_SLOT[name]
  var plain = colors
    ? hexToRgb(colors[name]) || (slot ? hexToRgb(colors["color" + slot]) : null)
    : null
  var bright = colors
    ? hexToRgb(colors["bright_" + name]) || (slot ? hexToRgb(colors["color" + (slot + 8)]) : null)
    : null
  if (plain && (!bg || contrastRatio(plain, bg) >= 2.1)) return plain
  if (bright && (!bg || contrastRatio(bright, bg) >= 2.1)) return bright
  if (plain && bright && bg)
    return contrastRatio(plain, bg) >= contrastRatio(bright, bg) ? plain : bright
  return plain || bright || fallback
}

// The TUI's TEMP_COLORS built from a parsed theme palette; the fixed
// stops when there is none.
function buildTempStops(colors, background) {
  if (!colors) return TEMP_STOPS
  var bg = background ? { r: background.r, g: background.g, b: background.b } : null
  var blue = themeAnchor(colors, "blue", bg, { r: 0.31, g: 0.56, b: 0.85 })
  var cyan = themeAnchor(colors, "cyan", bg, { r: 0.25, g: 0.75, b: 0.75 })
  var green = themeAnchor(colors, "green", bg, { r: 0.35, g: 0.77, b: 0.44 })
  var yellow = themeAnchor(colors, "yellow", bg, { r: 0.88, g: 0.76, b: 0.31 })
  var red = themeAnchor(colors, "red", bg, { r: 0.88, g: 0.36, b: 0.31 })
  function mix(a, b, f) {
    return { r: a.r + (b.r - a.r) * f, g: a.g + (b.g - a.g) * f, b: a.b + (b.b - a.b) * f }
  }
  function stop(t, c) { return [t, c.r, c.g, c.b] }
  return [
    stop(0, mix(blue, cyan, 0.15)),
    stop(32, blue),
    stop(45, cyan),
    stop(55, green),
    stop(65, mix(green, yellow, 0.45)),
    stop(72, yellow),
    stop(82, mix(yellow, red, 0.45)),
    stop(95, red),
  ]
}

function tempColor(value, tempUnit, themeStops) {
  var t = num(value, 60)
  if (String(tempUnit || "").indexOf("C") >= 0) t = t * 9 / 5 + 32
  var stops = themeStops || TEMP_STOPS
  if (t <= stops[0][0]) return Qt.rgba(stops[0][1], stops[0][2], stops[0][3], 1)
  var last = stops[stops.length - 1]
  if (t >= last[0]) return Qt.rgba(last[1], last[2], last[3], 1)
  for (var i = 0; i < stops.length - 1; i++) {
    var a = stops[i], b = stops[i + 1]
    if (t >= a[0] && t <= b[0]) {
      var f = (t - a[0]) / (b[0] - a[0])
      return Qt.rgba(a[1] + (b[1] - a[1]) * f,
                     a[2] + (b[2] - a[2]) * f,
                     a[3] + (b[3] - a[3]) * f, 1)
    }
  }
  return Qt.rgba(last[1], last[2], last[3], 1)
}

// "2026-08-14T05:42" (local, second optional) -> epoch ms, NaN if unparsable.
function parseIsoLocal(iso) {
  var m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?/.exec(String(iso || ""))
  if (!m) return NaN
  return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]),
                  Number(m[4]), Number(m[5]), Number(m[6] || 0)).getTime()
}

// Seconds -> "14h08m", "6h12m", "2m38s", "45s". Compact, linecast-style.
function fmtDuration(totalSeconds) {
  var s = Math.round(Math.abs(num(totalSeconds, 0)))
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  if (h > 0) return h + "h" + (m < 10 ? "0" : "") + m + "m"
  if (m > 0) return m + "m" + (s % 60 > 0 ? (s % 60) + "s" : "")
  return (s % 60) + "s"
}

// Signed duration with linecast's typographic minus: +2m38s / −2m38s.
function fmtDeltaDuration(totalSeconds) {
  var v = num(totalSeconds, NaN)
  if (isNaN(v) || v === 0) return ""
  return (v > 0 ? "+" : "−") + fmtDuration(v)
}

// Local extrema of a numeric series for chart labeling: a point that is
// the strict max (or min) of its ±window neighborhood, kept only if it is
// at least minGap indices from the previous kept extremum of the same
// kind. Mirrors the TUI's one-label-per-swing look.
function findExtrema(values, window, minGap) {
  var out = []
  var lastMax = -minGap * 2
  var lastMin = -minGap * 2
  for (var i = 0; i < values.length; i++) {
    var v = num(values[i], NaN)
    if (isNaN(v)) continue
    var isMax = true, isMin = true
    for (var j = Math.max(0, i - window); j <= Math.min(values.length - 1, i + window); j++) {
      if (j === i) continue
      var u = num(values[j], NaN)
      if (isNaN(u)) continue
      if (u >= v) isMax = false
      if (u <= v) isMin = false
      if (!isMax && !isMin) break
    }
    if (isMax && i - lastMax >= minGap) {
      out.push({ index: i, kind: "max", value: v })
      lastMax = i
    } else if (isMin && i - lastMin >= minGap) {
      out.push({ index: i, kind: "min", value: v })
      lastMin = i
    }
  }
  return out
}

var SNOW_CODES = { 71: 1, 73: 1, 75: 1, 77: 1, 85: 1, 86: 1 }
var STORM_CODES = { 95: 1, 96: 1, 99: 1 }

// Precipitation color role by WMO code, mirroring the TUI: snow near-white,
// storms theme-yellow, everything else theme-blue. Returns {r,g,b} 0..1.
function precipColorFor(code, foreground, colors) {
  var c = num(code, 0)
  if (SNOW_CODES[c]) return { r: foreground.r, g: foreground.g, b: foreground.b }
  if (STORM_CODES[c]) return themeAnchor(colors, "yellow", null, { r: 0.88, g: 0.76, b: 0.31 })
  return themeAnchor(colors, "blue", null, { r: 0.31, g: 0.56, b: 0.85 })
}

// The TUI's wind arrows: "N wind blows south", one glyph per 45° sector.
var WIND_ARROWS = "↓↙←↖↑↗→↘"
function windArrow(directionDeg) {
  var d = num(directionDeg, NaN)
  if (isNaN(d)) return ""
  return WIND_ARROWS.charAt(Math.round(((d % 360) + 360) % 360 / 45) % 8)
}

// Wind significance threshold, matching the TUI (15 mph / 25 km/h).
function windSignificant(speed, windUnit) {
  var v = num(speed, 0)
  return v > (String(windUnit || "").indexOf("km") >= 0 ? 25 : 15)
}

// Daily precip amount label when it clears the TUI's floor (0.05″ / 1 mm).
function precipAmountLabel(amount, precipUnit) {
  var v = num(amount, 0)
  var metric = String(precipUnit || "").indexOf("″") < 0
  if (v < (metric ? 1 : 0.05)) return ""
  return (metric ? Math.round(v) : (Math.round(v * 10) / 10)) + String(precipUnit || "")
}

// "2026-08-27" or a full ISO stamp -> "Aug 27".
function shortDate(iso) {
  var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso || ""))
  if (!m) return ""
  var d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
  return Qt.locale().monthName(d.getMonth(), 1 /* Locale.ShortFormat */) + " " + d.getDate()
}

function secondsUntil(iso, nowMs) {
  var t = parseIsoLocal(iso)
  return isNaN(t) ? NaN : (t - nowMs) / 1000
}

function windLine(current, units) {
  var speed = num(current ? current.wind_speed : NaN, NaN)
  if (isNaN(speed)) return ""
  var line = Math.round(speed) + " " + String(units && units.wind || "")
  var gusts = num(current ? current.wind_gusts : NaN, NaN)
  if (!isNaN(gusts) && gusts >= speed + 5) line += " (" + Math.round(gusts) + ")"
  return line
}
