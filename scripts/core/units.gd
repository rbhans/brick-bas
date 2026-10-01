class_name Units
extends RefCounted

# Display units. The simulation, saves and BAS points stay SI internally
# (°C, m³/s, Pa, m, m²); everything the player reads goes through here and
# comes out in US customary units: °F, CFM, in. w.c., ft, sq ft.

const CFM_PER_M3S := 2118.88
const INWC_PER_PA := 0.0040146
const FT_PER_M := 3.28084
const SQFT_PER_M2 := 10.7639

# --- Values ---------------------------------------------------------------------------

static func fahrenheit(celsius: float) -> float:
	return celsius * 1.8 + 32.0

# A temperature difference (or a thermostat step) in °F, as kelvin.
static func kelvin_from_f(delta_f: float) -> float:
	return delta_f / 1.8

static func cfm(m3_s: float) -> float:
	return m3_s * CFM_PER_M3S

static func inwc(pa: float) -> float:
	return pa * INWC_PER_PA

static func feet(metres: float) -> float:
	return metres * FT_PER_M

static func sqft(m2: float) -> float:
	return m2 * SQFT_PER_M2

# --- Text -----------------------------------------------------------------------------

static func temp(celsius: float, decimals: int = 0) -> String:
	return ("%." + str(decimals) + "f °F") % fahrenheit(celsius)

# Just the number and a degree sign, for small displays.
static func degrees(celsius: float) -> String:
	return "%.0f°" % fahrenheit(celsius)

static func flow(m3_s: float) -> String:
	return "%s CFM" % _grouped(roundi(cfm(m3_s)))

static func pressure(pa: float) -> String:
	return "%.2f in. w.c." % inwc(pa)

static func length(metres: float) -> String:
	var ft := feet(metres)
	return ("%.0f ft" if ft >= 10.0 else "%.1f ft") % ft

static func area(m2: float) -> String:
	return "%s sq ft" % _grouped(roundi(sqft(m2)))

# Dollars: whole dollars with grouping, or cents below $100 ("$9.64").
static func money(usd: float) -> String:
	if absf(usd) < 100.0:
		return ("-" if usd < 0.0 else "") + "$%.2f" % absf(usd)
	return ("-" if usd < 0.0 else "") + "$" + _grouped(roundi(absf(usd)))

# "30 × 20 m" plan sizes as "98 × 66 ft".
static func size(width_m: float, depth_m: float) -> String:
	return "%.0f × %.0f ft" % [feet(width_m), feet(depth_m)]

# --- Trends -----------------------------------------------------------------------------
# Trend entries name a "quantity"; the chart converts raw SI history with it.

static func convert(quantity: String, value: float) -> float:
	match quantity:
		"temp": return fahrenheit(value)
		"flow": return cfm(value)
		"pressure": return inwc(value)
		"percent": return value * 100.0
	return value

static func suffix(quantity: String) -> String:
	match quantity:
		"temp": return "°F"
		"flow": return " CFM"
		"pressure": return "\""
		"percent": return "%"
		"co2": return " ppm"
	return ""

static func _grouped(value: int) -> String:
	var text := str(absi(value))
	var result := ""
	while text.length() > 3:
		result = "," + text.right(3) + result
		text = text.left(text.length() - 3)
	return ("-" if value < 0 else "") + text + result
