class_name CitySim
extends RefCounted

# ─────────────────────────────────────────────────────────────
#  GRID
# ─────────────────────────────────────────────────────────────
const N := 40
const CELLS := N * N
const CELL := 20.0
const HOURS_PER_DAY := 24
const DAYS_PER_MONTH := 30

const POLLUTION_STRIDE := 2
const POLLUTION_COUPLING := 0.30

enum T { LAND, ROAD, WATER, PARK, PLAZA }
enum Z { NONE, RES, COM, IND, CIVIC }
enum U { NONE, POWER, WATER_TREAT, RECYCLE, LANDFILL, HOSPITAL, SCHOOL, POLICE, SOLAR, WIND }

# ─────────────────────────────────────────────────────────────
#  METRIC DESCRIPTORS
# ─────────────────────────────────────────────────────────────
const METRICS := {
	"population":          ["Society", "Population", "", 1.0, true],
	"households":          ["Society", "Households", "", 1.0, true],
	"housing_units":       ["Society", "Housing units", "", 1.0, true],
	"vacancy_rate":        ["Society", "Vacancy rate", "%", 100.0, false],
	"homeless_pct":        ["Society", "Homelessness", "%", 100.0, false],
	"unemployment_rate":   ["Society", "Unemployment", "%", 100.0, false],
	"median_income":       ["Society", "Median income", "$/yr", 1.0, true],
	"median_rent":         ["Society", "Median rent", "$/mo", 1.0, true],
	"affordability":       ["Society", "Affordability idx", "", 1.0, false],
	"avg_education":       ["Society", "Education level", "0–3", 1.0, false],
	"school_enrollment":   ["Society", "School enrollment", "%", 100.0, false],
	"life_expectancy":     ["Society", "Life expectancy", "yrs", 1.0, false],
	"health_index":        ["Society", "Health index", "0–100", 1.0, false],
	"safety_index":        ["Society", "Safety index", "0–100", 1.0, false],
	"crime_rate":          ["Society", "Crime rate", "/1k", 1.0, false],

	"gross_output":        ["Economy", "Gross output", "$/day", 1.0, true],
	"gdp_per_capita":      ["Economy", "GDP per capita", "$/yr", 1.0, true],
	"jobs_total":          ["Economy", "Jobs (capacity)", "", 1.0, true],
	"employed":            ["Economy", "Employed", "", 1.0, true],
	"avg_wage":            ["Economy", "Average wage", "$/day", 1.0, true],
	"local_business_share":["Economy", "Local business share", "%", 100.0, false],
	"exports_value":       ["Economy", "Exports", "$/day", 1.0, true],
	"imports_value":       ["Economy", "Imports", "$/day", 1.0, true],
	"trade_balance":       ["Economy", "Trade balance", "$/day", 1.0, true],
	"revenue":             ["Economy", "Municipal revenue", "$/day", 1.0, true],
	"expenses":            ["Economy", "Municipal expenses", "$/day", 1.0, true],
	"net_budget":          ["Economy", "Net budget", "$/day", 1.0, true],
	"reserve":             ["Economy", "Reserves", "$", 1.0, true],
	"tax_rate_income":     ["Economy", "Income tax rate", "%", 100.0, false],
	"tax_rate_business":   ["Economy", "Business tax rate", "%", 100.0, false],

	"energy_demand_mw":    ["Infrastructure", "Energy demand", "MW", 1.0, false],
	"energy_supply_mw":    ["Infrastructure", "Energy supply", "MW", 1.0, false],
	"renewable_share":     ["Infrastructure", "Renewable share", "%", 100.0, false],
	"brownout_hours":      ["Infrastructure", "Brownout hours", "h/day", 1.0, false],
	"water_demand_m3":     ["Infrastructure", "Water demand", "m³/day", 1.0, true],
	"water_supply_m3":     ["Infrastructure", "Water supply", "m³/day", 1.0, true],
	"water_quality":       ["Infrastructure", "Water quality", "0–100", 1.0, false],
	"leak_rate":           ["Infrastructure", "Distribution loss", "%", 100.0, false],
	"waste_generated_t":   ["Infrastructure", "Waste generated", "t/day", 1.0, false],
	"recycling_rate":      ["Infrastructure", "Recycling rate", "%", 100.0, false],
	"landfill_remaining":  ["Infrastructure", "Landfill remaining", "t", 1.0, true],
	"traffic_congestion":  ["Infrastructure", "Congestion", "%", 100.0, false],
	"transit_share":       ["Infrastructure", "Transit mode share", "%", 100.0, false],
	"avg_commute_min":     ["Infrastructure", "Avg commute", "min", 1.0, false],
	"road_load":           ["Infrastructure", "Road capacity used", "%", 100.0, false],

	"aqi":                 ["Environment", "Air quality index", "AQI", 1.0, false],
	"pm25":                ["Environment", "PM2.5", "µg/m³", 1.0, false],
	"co2_day":             ["Environment", "CO₂ emissions", "t/day", 1.0, false],
	"co2_per_capita":      ["Environment", "CO₂ per capita", "t/yr", 1.0, false],
	"green_m2_capita":     ["Environment", "Green space/capita", "m²", 1.0, false],
	"wastewater_treated":  ["Environment", "Wastewater treated", "%", 100.0, false],
	"noise_index":         ["Environment", "Noise index", "0–100", 1.0, false],
	"sustainability":      ["Environment", "Sustainability index", "0–100", 1.0, false],

	"smart_grid":          ["Smart Systems", "Smart grid penetration", "%", 100.0, false],
	"smart_home":          ["Smart Systems", "Smart home penetration", "%", 100.0, false],
	"smart_traffic":       ["Smart Systems", "Adaptive traffic control", "%", 100.0, false],
	"iot_sensors":         ["Smart Systems", "IoT sensors deployed", "", 1.0, true],
	"digital_adoption":    ["Smart Systems", "Digital service adoption", "%", 100.0, false],
}

# ─────────────────────────────────────────────────────────────
#  HOURLY DEMAND PROFILES
# ─────────────────────────────────────────────────────────────
const P_RES := [0.62,0.58,0.55,0.54,0.55,0.60,0.72,0.85,0.92,0.95,0.96,0.98,
				1.00,0.98,0.95,0.94,0.98,1.12,1.20,1.22,1.15,1.02,0.86,0.72]
const P_COM := [0.35,0.32,0.30,0.30,0.32,0.38,0.52,0.72,0.92,1.05,1.12,1.15,
				1.12,1.14,1.15,1.12,1.05,0.92,0.75,0.62,0.55,0.50,0.45,0.38]
const P_IND := [0.88,0.86,0.85,0.85,0.86,0.90,0.96,1.00,1.02,1.04,1.04,1.02,
				0.98,1.00,1.02,1.03,1.02,1.00,0.96,0.94,0.92,0.90,0.89,0.88]
const P_TRIP:= [0.18,0.12,0.08,0.06,0.07,0.14,0.34,0.72,1.10,0.82,0.62,0.66,
				0.74,0.70,0.68,0.86,1.18,1.34,1.02,0.76,0.62,0.54,0.42,0.28]

# ─────────────────────────────────────────────────────────────
#  STATE
# ─────────────────────────────────────────────────────────────
var terrain := PackedByteArray()
var zone := PackedByteArray()
var util := PackedByteArray()
var floors := PackedByteArray()
var occupancy := PackedFloat32Array()
var land_value := PackedFloat32Array()
var air_pol := PackedFloat32Array()
var water_pol := PackedFloat32Array()
var wealth := PackedFloat32Array()

var s: Dictionary = {}
var metrics: Metrics

var tick := 0
var founded_year := 2026

var _terrain_counts: Dictionary = {}
var _util_counts: Dictionary = {}
var _static_emit := PackedFloat32Array()
var _pollution_tmp := PackedFloat32Array()
var _water_pol_sum := 0.0
var _air_pol_sum := 0.0

# Set to true by the UI when a slider moves. Recomputed on the next sim-hour.
var _needs_recompute := false

# ─────────────────────────────────────────────────────────────
func _init() -> void:
	terrain.resize(CELLS); terrain.fill(T.LAND)
	zone.resize(CELLS);    zone.fill(Z.NONE)
	util.resize(CELLS);    util.fill(U.NONE)
	floors.resize(CELLS);  floors.fill(0)
	occupancy.resize(CELLS); occupancy.fill(0.0)
	land_value.resize(CELLS); land_value.fill(0.0)
	air_pol.resize(CELLS); air_pol.fill(0.0)
	water_pol.resize(CELLS); water_pol.fill(0.0)
	wealth.resize(CELLS); wealth.fill(0.0)
	_static_emit.resize(CELLS); _static_emit.fill(0.0)
	_pollution_tmp.resize(CELLS)

	for k in METRICS:
		s[k] = 0.0

	# legacy budget keys (kept for compatibility)
	s["budget_health"] = 0.20
	s["budget_education"] = 0.22
	s["budget_safety"] = 0.14
	s["budget_transit"] = 0.12
	s["budget_environment"] = 0.10
	s["budget_infrastructure"] = 0.22

	# ── policy sliders (0.0 = min, 1.0 = max, 0.5 = status quo) ──
	s["pol_min_wage"]        = 0.50
	s["pol_housing_supply"]  = 0.50
	s["pol_police_funding"]  = 0.50
	s["pol_education_spend"] = 0.50
	s["pol_transit_invest"]  = 0.50
	s["pol_green_space"]     = 0.50
	s["pol_pollution_ctrl"]  = 0.50
	s["pol_waste_mgmt"]      = 0.50
	s["pol_water_treat"]     = 0.50
	s["pol_tax_income"]      = 0.50
	s["pol_tax_business"]    = 0.50

	# tax rate derived keys
	s["tax_rate_income"] = 0.10
	s["tax_rate_business"] = 0.07
	s["tax_rate_property"] = 0.006

	s["reserve"] = 25_000_000.0
	s["smart_grid"] = 0.08
	s["smart_home"] = 0.06
	s["smart_traffic"] = 0.05
	s["digital_adoption"] = 0.30
	s["local_business_share"] = 0.42
	s["avg_education"] = 1.45
	s["infra_condition"] = 0.72
	s["landfill_remaining"] = 4_200_000.0
	s["health_index"] = 74.0
	s["safety_index"] = 71.0

	# ── internal working values (seeded so day 1 is stable) ──
	s["population"] = 0.0
	s["households"] = 0.0
	s["jobs_com"] = 0.0
	s["jobs_ind"] = 0.0
	s["jobs_total"] = 0.0
	s["workforce"] = 0.0
	s["employed"] = 0.0
	s["unemployment_rate"] = 0.0
	s["housing_units"] = 0.0
	s["housing_capacity"] = 0.0
	s["median_income"] = 15_000.0
	s["median_rent"] = 900.0
	s["avg_wage"] = 60.0
	s["affordability"] = 1.4
	s["brownout"] = 0.0
	s["transit_share"] = 0.14
	s["renewable_share"] = 0.0
	s["co2_day"] = 0.0
	s["co2_per_capita"] = 0.0
	s["co2_energy_day"] = 0.0
	s["crime_rate"] = 20.0
	s["_water_demand_acc"] = 0.0
	s["_water_supply_acc"] = 0.0
	s["_brownout_acc"] = 0.0
	s["uncollected_waste"] = 0.0
	s["gross_output"] = 0.0
	s["gdp_per_capita"] = 0.0
	s["revenue"] = 0.0
	s["expenses"] = 0.0
	s["net_budget"] = 0.0
	s["exports_value"] = 0.0
	s["imports_value"] = 0.0
	s["trade_balance"] = 0.0
	s["green_m2_capita"] = 0.0
	s["wastewater_treated"] = 0.0
	s["water_quality"] = 80.0
	s["leak_rate"] = 0.10
	s["vacancy_rate"] = 0.05
	s["homeless_pct"] = 0.0
	s["life_expectancy"] = 78.0
	s["school_enrollment"] = 0.9
	s["iot_sensors"] = 0.0
	s["waste_generated_t"] = 0.0
	s["recycling_rate"] = 0.0
	s["traffic_congestion"] = 0.0
	s["road_load"] = 0.0
	s["avg_commute_min"] = 15.0
	s["energy_demand_mw"] = 0.0
	s["energy_supply_mw"] = 0.0
	s["brownout_hours"] = 0.0
	s["water_demand_m3"] = 0.0
	s["water_supply_m3"] = 0.0
	s["pm25"] = 0.0
	s["noise_index"] = 0.0
	s["sustainability"] = 0.0
	s["water_stress"] = 0.0

	# derived effective values used by downstream systems
	s["_effective_employed"] = 0.0
	s["_effective_police"] = 0.0

	metrics = Metrics.new()
	metrics.declare(METRICS.keys())

# ─────────────────────────────────────────────────────────────
func generate(seed_val: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	terrain.fill(T.LAND); zone.fill(Z.NONE); util.fill(U.NONE)
	floors.fill(0); land_value.fill(0.0)
	air_pol.fill(0.0); water_pol.fill(0.0)

	for x in N:
		var cy: int = int(N * 0.72 + sin(x * 0.17) * 4.0 + sin(x * 0.06) * 2.5)
		var w: int = 1 + int(rng.randf() * 2.0)
		for dy in range(-w, w + 1):
			var y: int = cy + dy
			if y >= 0 and y < N:
				terrain[_i(x, y)] = T.WATER

	for y in N:
		for x in N:
			var i := _i(x, y)
			if terrain[i] == T.WATER: continue
			if x % 8 == 0 or y % 8 == 0:
				terrain[i] = T.ROAD

	var downtown := Vector2i(17, 12)
	var industrial_origin := Vector2i(28, 28)

	for y in N:
		for x in N:
			var i := _i(x, y)
			if terrain[i] == T.ROAD or terrain[i] == T.WATER: continue

			var df: float = _district_factor(x, y)
			var in_industrial: bool = x >= industrial_origin.x and y >= industrial_origin.y

			if _near_water(x, y, 2) and rng.randf() < 0.55:
				terrain[i] = T.PARK
				continue
			if rng.randf() < 0.035:
				terrain[i] = T.PARK
				continue

			if in_industrial:
				zone[i] = Z.IND
				floors[i] = 1 + int(rng.randf() * 3.0)
				occupancy[i] = 0.88
			elif df > 0.62:
				# urban core
				zone[i] = Z.COM
				floors[i] = int(4.0 + df * 16.0 + rng.randf() * 3.0)
				occupancy[i] = 0.90
			elif df > 0.32:
				# mixed-use belt
				if rng.randf() < 0.45:
					zone[i] = Z.COM
					floors[i] = 2 + int(df * 8.0 + rng.randf() * 3.0)
					occupancy[i] = 0.85
				else:
					zone[i] = Z.RES
					floors[i] = max(1, int(3.0 + df * 6.0 + rng.randf() * 2.0))
					occupancy[i] = 0.85 + rng.randf() * 0.12
			else:
				# suburban residential
				zone[i] = Z.RES
				var base: float = 2.0 + df * 4.5
				floors[i] = max(1, int(base + rng.randf() * 2.5))
				occupancy[i] = 0.82 + rng.randf() * 0.14

			land_value[i] = _compute_land_value(x, y, df, rng)

	_place_util(downtown.x + 3, downtown.y - 3, U.HOSPITAL, 5)
	_place_util(downtown.x - 3, downtown.y + 2, U.HOSPITAL, 3)
	_place_util(downtown.x - 5, downtown.y - 4, U.SCHOOL, 4)
	_place_util(downtown.x + 6, downtown.y + 4, U.SCHOOL, 3)
	_place_util(downtown.x + 2, downtown.y + 5, U.POLICE, 3)
	_place_util(downtown.x - 6, downtown.y + 6, U.POLICE, 2)

	_place_util(36, 36, U.POWER, 2)
	_place_util(34, 38, U.POWER, 2)
	_place_util(6, 30, U.WATER_TREAT, 2)
	_place_util(12, 31, U.WATER_TREAT, 2)
	_place_util(31, 33, U.RECYCLE, 2)
	_place_util(38, 31, U.LANDFILL, 1)
	_place_util(3, 4, U.SOLAR, 1)
	_place_util(5, 3, U.SOLAR, 1)
	_place_util(3, 36, U.WIND, 1)
	_place_util(2, 33, U.WIND, 1)

	s["population"] = 12_000.0
	s["housing_units"] = 0.0
	_rebuild_caches()
	_recompute_housing()
	_recompute_wealth()

# ─────────────────────────────────────────────────────────────
func _rebuild_caches() -> void:
	_terrain_counts.clear()
	_util_counts.clear()
	_air_pol_sum = 0.0
	_water_pol_sum = 0.0

	for i in CELLS:
		var t: int = terrain[i]
		_terrain_counts[t] = _terrain_counts.get(t, 0) + 1
		var u: int = util[i]
		_util_counts[u] = _util_counts.get(u, 0) + 1

		var e := 0.0
		match zone[i]:
			Z.IND: e = floors[i] * 0.16
			Z.COM: e = floors[i] * 0.020
			Z.RES: e = floors[i] * 0.012
		if u == U.POWER:    e += 2.4
		if u == U.LANDFILL: e += 0.9
		if t == T.PARK:     e -= 0.55
		_static_emit[i] = e

		_air_pol_sum   += air_pol[i]
		_water_pol_sum += water_pol[i]

# ─────────────────────────────────────────────────────────────
func step_hour() -> void:
	# if a slider moved since the last tick, recompute the daily cascade first
	if _needs_recompute:
		_needs_recompute = false
		_update_daily()

	var h: int = tick % HOURS_PER_DAY
	_update_energy(h)
	_update_water(h)
	_update_traffic(h)

	if tick % POLLUTION_STRIDE == 0:
		_update_pollution(h)

	if h == 23:
		_update_daily()
		_push_metrics()

	tick += 1

# ── ENERGY ───────────────────────────────────────────────────
func _update_energy(h: int) -> void:
	var pop: float = s["population"]
	var jobs_com: float = s["jobs_com"]
	var jobs_ind: float = s["jobs_ind"]

	var demand_kw: float = pop * 1.15 * P_RES[h] \
		+ jobs_com * 1.45 * P_COM[h] \
		+ jobs_ind * 3.10 * P_IND[h]

	var eff: float = 1.0 - 0.10 * s["smart_grid"] - 0.05 * s["smart_home"]
	demand_kw *= eff

	var solar_cap := float(_count_util(U.SOLAR)) * 900.0
	var wind_cap  := float(_count_util(U.WIND)) * 700.0
	var gas_cap   := float(_count_util(U.POWER)) * 14_000.0

	var solar_f := 0.0
	if h >= 6 and h <= 18:
		solar_f = sin((h - 6) / 12.0 * PI)
	var wind_f: float = 0.36 + 0.16 * sin(tick / 41.0) + 0.08 * sin(tick / 13.0)
	wind_f = clampf(wind_f, 0.05, 1.0)

	var renew_kw: float = solar_cap * solar_f + wind_cap * wind_f
	var gas_used: float = clampf(demand_kw - renew_kw, 0.0, gas_cap)
	var supply_kw: float = renew_kw + gas_used
	var brownout: float = clampf(1.0 - supply_kw / max(demand_kw, 1.0), 0.0, 1.0)

	s["energy_demand_mw"] = demand_kw / 1000.0
	s["energy_supply_mw"] = supply_kw / 1000.0
	s["brownout"] = brownout
	s["renewable_share"] = renew_kw / max(supply_kw, 1.0)
	s["co2_energy_day"] = s["co2_energy_day"] + gas_used * 0.00052

	if h == 23:
		s["brownout_hours"] = s["_brownout_acc"]
		s["_brownout_acc"] = 0.0
	else:
		s["_brownout_acc"] = s["_brownout_acc"] + (1.0 if brownout > 0.02 else 0.0)

# ── WATER ────────────────────────────────────────────────────
func _update_water(h: int) -> void:
	var pop: float = s["population"]
	var ind: float = s["jobs_ind"]

	var demand: float = (pop * 0.165 + ind * 0.95 + s["jobs_com"] * 0.12) * (0.6 + 0.6 * P_RES[h])
	var capacity: float = float(_count_util(U.WATER_TREAT)) * 42_000.0
	var leak: float = 0.07 + 0.20 * (1.0 - s["infra_condition"])
	var delivered: float = min(demand, capacity) * (1.0 - leak)

	s["_water_demand_acc"] = s["_water_demand_acc"] + demand
	s["_water_supply_acc"] = s["_water_supply_acc"] + delivered
	s["leak_rate"] = leak
	s["water_stress"] = clampf(demand / max(capacity, 1.0), 0.0, 2.0)

	var avg_wp: float = _water_pol_sum / float(CELLS)
	# water treatment slider lifts effective quality by up to ±10 points
	var treat_bonus: float = 10.0 * (s["pol_water_treat"] - 0.5)
	s["water_quality"] = clampf(
		96.0 - avg_wp * 5.5 + s["infra_condition"] * 6.0 + treat_bonus,
		0.0, 100.0)

# ── TRAFFIC ──────────────────────────────────────────────────
func _update_traffic(h: int) -> void:
	var pop: float = s["population"]
	var trips: float = pop * 0.68 * P_TRIP[h]
	var transit: float = s["transit_share"]
	var car_trips: float = trips * (1.0 - transit)

	var road_cells: int = _count_terrain(T.ROAD)
	var base_cap: float = float(road_cells) * 120.0
	var smart_bonus: float = 1.0 + 0.28 * s["smart_traffic"]
	var capacity: float = base_cap * smart_bonus

	var road_usage: float = car_trips / max(capacity, 1.0)
	var congestion: float = clampf(road_usage, 0.0, 1.6)

	s["road_load"] = min(road_usage, 1.0)
	s["traffic_congestion"] = min(congestion, 1.0)
	s["avg_commute_min"] = 13.5 * (1.0 + 1.9 * pow(min(congestion, 1.2), 2.0))

# ── POLLUTION ────────────────────────────────────────────────
func _update_pollution(_h: int) -> void:
	var wind_x: float = 0.75 + 0.25 * sin(tick / 96.0)
	var c: float = POLLUTION_COUPLING
	var road_emit: float = s["traffic_congestion"] * 0.62
	var tmp := _pollution_tmp

	# pollution-control slider scales all emission sources
	var ctrl_mult: float = 1.0 - 0.5 * s["pol_pollution_ctrl"]

	var new_air_sum := 0.0
	for y in N:
		var row: int = y * N
		for x in N:
			var i: int = row + x
			var p: float = air_pol[i]

			var sum := 0.0
			var cnt := 0
			if x > 0:     sum += air_pol[i - 1]; cnt += 1
			if x < N - 1: sum += air_pol[i + 1]; cnt += 1
			if y > 0:     sum += air_pol[i - N]; cnt += 1
			if y < N - 1: sum += air_pol[i + N]; cnt += 1
			var avg: float = sum / float(cnt)

			if x > 0:
				avg = lerp(avg, air_pol[i - 1], wind_x * 0.35)

			var emit: float = _static_emit[i] * ctrl_mult
			if terrain[i] == T.ROAD: emit += road_emit * ctrl_mult

			var v: float = maxf(0.0, (p + c * (avg - p)) * 0.985 + emit * 0.02)
			tmp[i] = v
			new_air_sum += v

	air_pol = tmp
	_air_pol_sum = new_air_sum

	var treat: float = float(_count_util(U.WATER_TREAT)) / maxf(float(CELLS) / 400.0, 1.0)
	var treat_factor: float = 1.0 - clampf(treat * 0.06, 0.0, 0.5)
	var road_em: float = s["traffic_congestion"] * 0.004
	var new_w_sum := 0.0
	for i in CELLS:
		var wp: float = water_pol[i]
		var em := 0.0
		if zone[i] == Z.IND: em += floors[i] * 0.010 * ctrl_mult
		if terrain[i] == T.ROAD: em += road_em * ctrl_mult
		wp = wp * 0.992 + em * 0.02
		wp *= treat_factor
		water_pol[i] = wp
		new_w_sum += wp
	_water_pol_sum = new_w_sum

	s["aqi"] = clampf((_air_pol_sum / float(CELLS)) * 2.1, 0.0, 500.0)
	s["pm25"] = s["aqi"] * 0.42
	s["noise_index"] = clampf(s["traffic_congestion"] * 62.0 + s["jobs_ind"] * 0.0008, 0.0, 100.0)

# ── DAILY UPDATE ─────────────────────────────────────────────
func _update_daily() -> void:
	_update_population()
	_update_housing()
	_update_employment()
	_update_economy()
	_update_waste()
	_update_health_safety_education()
	_update_sustainability()
	_recompute_wealth()
	s["co2_energy_day"] = 0.0

func _update_population() -> void:
	var housing_cap: float = s["housing_capacity"]
	var jobs: float = s["jobs_total"]

	var attract := 0.55
	attract += clampf(jobs / maxf(s["workforce"], 1.0) - 0.9, -0.25, 0.25)
	attract += (s["health_index"] - 60.0) / 400.0
	attract += (s["safety_index"] - 60.0) / 400.0
	attract -= clampf(s["aqi"] / 400.0, 0.0, 0.30)
	attract -= clampf((s["median_rent"] / maxf(s["median_income"] / 12.0, 1.0)) - 0.32, 0.0, 0.30)
	# income tax reduces attractiveness at high rates
	attract -= (s["pol_tax_income"] - 0.5) * 0.08
	attract = clampf(attract, 0.10, 0.98)

	var target: float = housing_cap * attract
	s["population"] = lerpf(s["population"], target, 0.012)
	s["households"] = s["population"] / 2.38

func _update_housing() -> void:
	var units := 0.0
	for i in CELLS:
		if zone[i] == Z.RES:
			units += floors[i] * 6.0

	# ── housing supply slider: +25% / −25% of physical capacity ──
	var supply_bonus: float = (s["pol_housing_supply"] - 0.5) * 2.0
	units = maxf(units * (1.0 + 0.25 * supply_bonus), units * 0.5)

	s["housing_units"] = units
	s["housing_capacity"] = units * 2.38

	var vac: float = 1.0 - (s["households"] / maxf(units, 1.0))
	s["vacancy_rate"] = clampf(vac, -0.05, 0.4)

	var land_avg := 0.0
	for v in land_value: land_avg += v
	land_avg /= float(CELLS)

	s["median_rent"] = 880.0 * (1.0 + 2.2 * clampf(0.06 - vac, 0.0, 0.06) / 0.06) \
		* (0.55 + land_avg / 2_200_000.0)

	# income now reflects effective employment (minimum wage affects who works)
	var eff_emp: float = s["_effective_employed"]
	var income_share: float = eff_emp / maxf(s["workforce"], 1.0)
	s["median_income"] = s["avg_wage"] * 250.0 * clampf(income_share, 0.3, 1.0)

	var afford: float = (s["median_income"] / 12.0) / maxf(s["median_rent"], 1.0)
	s["affordability"] = afford

	# ── homelessness: rent elasticity + minimum-wage disemployment effect ──
	var rent_elastic: float = 0.55 + 2.0 * clampf(s["pol_housing_supply"], 0.0, 1.0)
	var rent_effect: float = clampf(
		1.0 + (1.0 - s["pol_housing_supply"]) * rent_elastic * 0.8, 0.5, 3.0)
	var wage_homeless: float = 0.20 * (s["pol_min_wage"] - 0.5) * 2.0

	var base_homeless: float = clampf(
		pow(clampf(1.0 - afford, 0.0, 1.0), 2.0) * 0.085
		+ s["unemployment_rate"] * 0.06
		- 0.012, 0.0, 0.14)

	s["homeless_pct"] = clampf(base_homeless * rent_effect + wage_homeless * 0.02, 0.0, 0.20)

func _update_employment() -> void:
	var jobs := 0.0
	for i in CELLS:
		match zone[i]:
			Z.COM: jobs += floors[i] * 22.0
			Z.IND: jobs += floors[i] * 9.0
			Z.CIVIC: jobs += floors[i] * 14.0
	jobs *= 0.92

	s["jobs_total"] = jobs
	s["jobs_com"] = 0.0
	s["jobs_ind"] = 0.0
	for i in CELLS:
		if zone[i] == Z.COM: s["jobs_com"] += floors[i] * 22.0
		if zone[i] == Z.IND: s["jobs_ind"] += floors[i] * 9.0

	var workforce: float = s["population"] * 0.615
	s["workforce"] = workforce
	var employed: float = min(workforce, jobs)
	s["employed"] = employed
	s["unemployment_rate"] = clampf(1.0 - employed / maxf(workforce, 1.0), 0.0, 0.6)

func _update_economy() -> void:
	var edu_bonus: float = 0.62 + 0.40 * (s["avg_education"] / 3.0)
	var congestion_pen: float = 1.0 - 0.34 * s["traffic_congestion"]
	var brownout_pen: float = 1.0 - 0.55 * s["brownout"]
	var health_f: float = 0.80 + 0.25 * (s["health_index"] / 100.0)
	var water_f: float = 0.90 + 0.12 * (s["water_quality"] / 100.0)

	# ── MINIMUM WAGE ──
	# low: higher employment, lower wages / high: lower employment, higher wages
	var mw: float = s["pol_min_wage"]
	var wage_mult: float = 0.70 + 0.60 * mw

	var employment_mult: float = 1.0
	if mw > 0.5:
		employment_mult = 1.0 - 0.18 * pow((mw - 0.5) * 2.0, 1.4)
	else:
		employment_mult = 1.0 + 0.08 * (0.5 - mw) * 2.0

	var productivity: float = 185.0 * edu_bonus * congestion_pen * brownout_pen * health_f * water_f
	s["avg_wage"] = productivity * 0.42 * wage_mult

	var effective_employed: float = s["employed"] * employment_mult
	s["_effective_employed"] = effective_employed
	s["employed"] = effective_employed

	var output: float = effective_employed * productivity
	s["gross_output"] = output
	s["gdp_per_capita"] = output * 365.0 / maxf(s["population"], 1.0)

	# trade
	var domestic_goods: float = s["jobs_ind"] * 62.0 * (1.0 + 0.3 * s["avg_education"])
	var demand_goods: float = s["population"] * 0.42 + s["jobs_com"] * 0.55
	s["exports_value"] = maxf(0.0, domestic_goods - demand_goods)
	s["imports_value"] = maxf(0.0, demand_goods - domestic_goods)
	s["trade_balance"] = s["exports_value"] - s["imports_value"]

	# local business share responds to business tax slider
	var tax_penalty: float = 1.0 - 0.35 * (s["pol_tax_business"] - 0.5) * 2.0
	var target_local: float = clampf(
		(0.30 + 0.35 * s["local_business_share"]
		 + 0.20 * (1.0 - clampf(s["imports_value"] / maxf(demand_goods, 1.0), 0.0, 1.0)))
		* tax_penalty,
		0.05, 0.95)
	s["local_business_share"] = lerpf(s["local_business_share"], target_local, 0.004)

	# ── TAX SLIDERS → revenue ──
	var income_tax: float = 0.03 + 0.17 * s["pol_tax_income"]
	var biz_tax_rate: float = 0.02 + 0.14 * s["pol_tax_business"]
	s["tax_rate_income"] = income_tax
	s["tax_rate_business"] = biz_tax_rate

	var wages_total: float = effective_employed * s["avg_wage"]
	var land_total := 0.0
	for v in land_value: land_total += v

	var rev: float = 0.0
	rev += wages_total * income_tax
	rev += output * biz_tax_rate
	rev += land_total * s["tax_rate_property"] / 365.0
	s["revenue"] = rev

	var infra_cells: float = float(CELLS)
	var spend: float = 0.0
	spend += s["population"] * 12.0 * s["budget_health"] / 0.20
	spend += s["population"] * 12.0 * s["budget_education"] / 0.22
	spend += s["population"] * 12.0 * s["budget_safety"] / 0.14
	spend += s["population"] * 12.0 * s["budget_transit"] / 0.12
	spend += s["population"] * 12.0 * s["budget_environment"] / 0.10
	spend += infra_cells * 18.0 * s["budget_infrastructure"] / 0.22
	spend += s["population"] * 12.0 * 0.22
	s["expenses"] = spend

	s["net_budget"] = rev - spend
	s["reserve"] = s["reserve"] + s["net_budget"]

	var spend_ratio: float = s["budget_infrastructure"] / 0.22
	var wear: float = 0.0016 * (1.0 + 0.6 * (1.0 - s["infra_condition"]))
	var repair: float = 0.0022 * spend_ratio * clampf(s["reserve"] / 5_000_000.0, 0.0, 1.0)
	s["infra_condition"] = clampf(s["infra_condition"] - wear + repair, 0.05, 1.0)

func _update_waste() -> void:
	var gen: float = s["population"] * 0.00115 \
		+ s["jobs_ind"] * 0.0042 \
		+ s["jobs_com"] * 0.0016

	# ── WASTE MANAGEMENT SLIDER ──
	var recycle_cap: float = float(_count_util(U.RECYCLE)) * 900.0 \
		* (0.5 + 1.0 * s["pol_waste_mgmt"])
	var recycle_rate: float = clampf(recycle_cap / maxf(gen, 0.001), 0.0, 0.72)
	recycle_rate *= (0.65 + 0.35 * s["digital_adoption"])

	var recycled: float = gen * recycle_rate
	var landfill_cap: float = float(_count_util(U.LANDFILL)) * 3200.0
	var landfilled: float = min(gen - recycled, landfill_cap)
	var uncollected: float = maxf(0.0, gen - recycled - landfilled)

	s["waste_generated_t"] = gen
	s["recycling_rate"] = recycle_rate
	s["landfill_remaining"] = maxf(0.0, s["landfill_remaining"] - landfilled)
	s["uncollected_waste"] = uncollected

	if uncollected > 0.5:
		var waste_health_mult: float = 1.5 - s["pol_waste_mgmt"]
		s["health_index"] -= uncollected * 0.05 * waste_health_mult
		for i in CELLS:
			if zone[i] == Z.RES:
				water_pol[i] += uncollected * 0.0004 * waste_health_mult

func _update_health_safety_education() -> void:
	# ── HEALTH ──
	var hospital_cap: float = float(_count_util(U.HOSPITAL)) * 42_000.0
	var access: float = clampf(hospital_cap / maxf(s["population"], 1.0), 0.0, 1.0)

	var green_cells := _count_terrain(T.PARK)
	var green_pc_physical: float = float(green_cells) * CELL * CELL / maxf(s["population"], 1.0)
	s["green_m2_capita"] = green_pc_physical
	# green-space slider boosts effective benefit even without new physical parks
	var effective_green: float = green_pc_physical * (0.5 + s["pol_green_space"])

	# pollution-control slider reduces effective AQI impact
	var effective_aqi: float = s["aqi"] * (1.0 - 0.5 * s["pol_pollution_ctrl"])

	var h := 78.0
	h -= clampf(effective_aqi * 0.16, 0.0, 22.0)
	h -= clampf((100.0 - s["water_quality"]) * 0.12, 0.0, 14.0)
	h += clampf(access * 12.0, 0.0, 12.0)
	h += clampf(effective_green * 0.05, 0.0, 6.0)
	h -= clampf((s["avg_commute_min"] - 20.0) * 0.35, 0.0, 10.0)
	h -= clampf(s["unemployment_rate"] * 25.0, 0.0, 10.0)
	h -= clampf(s["homeless_pct"] * 120.0, 0.0, 8.0)
	h += 0.02 * (s["avg_education"] - 1.5) * 10.0
	s["health_index"] = clampf(lerpf(s["health_index"], h, 0.02), 0.0, 100.0)
	s["life_expectancy"] = 68.0 + s["health_index"] * 0.18

	# ── SAFETY ──
	var police_base: float = float(_count_util(U.POLICE)) * 30_000.0
	var police_slider_mult: float = 0.5 + s["pol_police_funding"]
	var effective_police: float = police_base * police_slider_mult
	s["_effective_police"] = effective_police

	var coverage: float = clampf(effective_police / maxf(s["population"], 1.0), 0.0, 1.0)
	var density_factor: float = clampf(s["population"] / 60_000.0, 0.4, 1.8)

	# high minimum wage → disemployment → slightly more crime
	var mw_crime_mult: float = 1.0 + 0.35 * maxf(s["pol_min_wage"] - 0.5, 0.0) * 2.0

	var crime: float = 33.0 \
		* (1.0 + s["unemployment_rate"] * 1.6) \
		* (1.0 - coverage * 0.55) \
		* (1.0 - (s["avg_education"] / 3.0) * 0.42) \
		* density_factor \
		* (1.0 + (1.0 - s["infra_condition"]) * 0.3) \
		* mw_crime_mult
	s["crime_rate"] = crime
	var tgt_safety: float = clampf(100.0 - crime * 1.25, 0.0, 100.0)
	s["safety_index"] = lerpf(s["safety_index"], tgt_safety, 0.03)

	# ── EDUCATION ──
	var school_cap: float = float(_count_util(U.SCHOOL)) * 2_600.0 \
		* (0.6 + 0.8 * s["pol_education_spend"])
	var students: float = s["population"] * 0.175
	s["school_enrollment"] = clampf(school_cap / maxf(students, 1.0), 0.0, 1.0)

	var spending_bonus: float = (s["pol_education_spend"] - 0.5) * 0.4
	var target_edu: float = 0.85 + 1.95 * s["school_enrollment"] \
		+ 0.15 * s["digital_adoption"] + spending_bonus
	s["avg_education"] = clampf(lerpf(s["avg_education"], target_edu, 0.0009), 0.0, 3.0)

func _update_sustainability() -> void:
	var co2_transport: float = s["population"] * 0.68 * 0.00021 * 24.0 * (1.0 + s["traffic_congestion"])
	var co2_waste: float = s["waste_generated_t"] * 0.42 * (1.0 - s["recycling_rate"])
	var co2_energy: float = s["co2_energy_day"]

	var ctrl: float = s["pol_pollution_ctrl"]
	s["co2_day"] = (co2_energy + co2_transport + co2_waste) * (1.0 - 0.3 * ctrl)
	s["co2_per_capita"] = s["co2_day"] * 365.0 / maxf(s["population"], 1.0)

	var treated: float = clampf(
		float(_count_util(U.WATER_TREAT)) * 42_000.0 / maxf(s["_water_demand_acc"], 1.0),
		0.0, 1.0)
	s["wastewater_treated"] = treated

	var score := 0.0
	score += s["renewable_share"] * 26.0
	score += s["recycling_rate"] * 20.0
	score += clampf(s["green_m2_capita"] / 22.0, 0.0, 1.0) * 16.0
	score += clampf(1.0 - s["co2_per_capita"] / 9.0, 0.0, 1.0) * 20.0
	score += s["transit_share"] * 12.0
	score += s["wastewater_treated"] * 6.0
	s["sustainability"] = clampf(score, 0.0, 100.0)

	# transit share responds to investment slider + congestion
	var tgt_transit: float = clampf(
		0.08 + s["pol_transit_invest"] * 0.45 + s["traffic_congestion"] * 0.15,
		0.05, 0.75)
	s["transit_share"] = lerpf(s["transit_share"], tgt_transit, 0.01)

	# smart systems growth (unaffected by sliders)
	var growth: float = 0.00035 * (0.4 + s["digital_adoption"])
	s["smart_grid"] = clampf(s["smart_grid"] + growth * 1.1, 0.0, 0.98)
	s["smart_home"] = clampf(s["smart_home"] + growth * 1.4, 0.0, 0.98)
	s["smart_traffic"] = clampf(s["smart_traffic"] + growth * 1.2, 0.0, 0.98)
	s["digital_adoption"] = clampf(s["digital_adoption"]
		+ 0.0009 * (0.5 + s["avg_education"] / 3.0), 0.0, 0.99)
	s["iot_sensors"] = int(s["population"] * 0.28 * s["smart_grid"] + s["smart_home"] * 4200.0)

# ── METRICS ──────────────────────────────────────────────────
func _push_metrics() -> void:
	var packed := {}
	for k in METRICS:
		packed[k] = s[k]

	packed["water_demand_m3"] = s["_water_demand_acc"]
	packed["water_supply_m3"] = s["_water_supply_acc"]
	packed["renewable_share"] = s["renewable_share"]
	packed["co2_day"] = s["co2_day"]
	packed["co2_per_capita"] = s["co2_per_capita"]

	metrics.push(packed)

	s["_water_demand_acc"] = 0.0
	s["_water_supply_acc"] = 0.0

# ─────────────────────────────────────────────────────────────
#  WEALTH
# ─────────────────────────────────────────────────────────────
func _recompute_wealth() -> void:
	for i in CELLS:
		var lv: float = clampf(land_value[i] / 1_200_000.0, 0.0, 1.0)
		var fh: float = clampf(float(floors[i]) / 24.0, 0.0, 1.0)
		var oc: float = clampf(occupancy[i], 0.0, 1.0)

		var zone_premium := 0.0
		match zone[i]:
			Z.RES:   zone_premium = 0.35
			Z.COM:   zone_premium = 1.00
			Z.IND:   zone_premium = 0.15
			Z.CIVIC: zone_premium = 0.60

		var w: float = lv * 0.55 + fh * 0.20 + oc * 0.15 + zone_premium * 0.10
		w *= 0.60 + 0.40 * oc
		wealth[i] = clampf(w, 0.0, 1.0)

# ─────────────────────────────────────────────────────────────
#  HELPERS
# ─────────────────────────────────────────────────────────────
func _i(x: int, y: int) -> int:
	return y * N + x
	
	
func _district_factor(x: int, y: int) -> float:
	# Weighted blend of distance to multiple centers, mixing Euclidean and
	# Manhattan metrics + per-cell noise, so district boundaries hug the grid
	# instead of forming perfect circles.
	var centers := [
		[17.0, 12.0, 1.00, 8.5],   # primary downtown
		[ 8.0, 22.0, 0.55, 4.5],   # west hub
		[28.0,  8.0, 0.50, 4.0],   # northeast hub
		[32.0, 30.0, 0.45, 4.0],   # southeast (near industrial)
		[10.0,  6.0, 0.40, 3.5],   # northwest
	]
	var f := 0.0
	for c in centers:
		var dx: float = absf(float(x) - c[0])
		var dy: float = absf(float(y) - c[1])
		var euclid: float = sqrt(dx * dx + dy * dy)
		var manh: float = (dx + dy) * 0.65
		var d: float = (euclid + manh) * 0.5
		var n: float = _hash_noise(x, y) * 0.7
		var v: float = c[2] * clampf(1.0 - (d + n) / c[3], 0.0, 1.0)
		f = maxf(f, v)
	return clampf(f, 0.0, 1.0)

func _hash_noise(x: int, y: int) -> float:
	# Deterministic cheap hash → [-1, 1]
	var h: int = x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return (float(h & 0xFFFF) / 32768.0) - 1.0

func world_pos(x: int, y: int) -> Vector3:
	return Vector3((x - N * 0.5 + 0.5) * CELL, 0.0, (y - N * 0.5 + 0.5) * CELL)

func _near_water(x: int, y: int, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var nx := x + dx; var ny := y + dy
			if nx < 0 or ny < 0 or nx >= N or ny >= N: continue
			if terrain[_i(nx, ny)] == T.WATER: return true
	return false

func _count_terrain(t: int) -> int:
	return _terrain_counts.get(t, 0)

func _count_util(u: int) -> int:
	return _util_counts.get(u, 0)

func _place_util(x: int, y: int, kind: int, fl: int) -> void:
	if x < 0 or y < 0 or x >= N or y >= N: return
	var i := _i(x, y)
	if terrain[i] == T.WATER: return
	util[i] = kind
	zone[i] = Z.CIVIC if kind in [U.HOSPITAL, U.SCHOOL, U.POLICE] else Z.IND
	terrain[i] = T.LAND
	floors[i] = fl
	occupancy[i] = 1.0

func _compute_land_value(x: int, y: int, df: float, rng: RandomNumberGenerator) -> float:
	var v: float = 180_000.0 + 1_300_000.0 * df * df
	v *= 0.85 + rng.randf() * 0.4
	if _near_water(x, y, 3): v *= 1.22
	return v

func _recompute_housing() -> void:
	var units := 0.0
	for i in CELLS:
		if zone[i] == Z.RES: units += floors[i] * 6.0
	s["housing_units"] = units
	s["housing_capacity"] = units * 2.38

# ─────────────────────────────────────────────────────────────
#  TIME / DISPLAY
# ─────────────────────────────────────────────────────────────
func year() -> int:  return founded_year + int(tick / float(HOURS_PER_DAY * DAYS_PER_MONTH * 12))
func month() -> int: return 1 + int(tick / float(HOURS_PER_DAY * DAYS_PER_MONTH)) % 12
func day() -> int:   return 1 + int(tick / float(HOURS_PER_DAY)) % DAYS_PER_MONTH
func hour() -> int:  return tick % HOURS_PER_DAY

func date_string() -> String:
	return "%04d-%02d-%02d  %02d:00" % [year(), month(), day(), hour()]

func day_fraction() -> float:
	return float(tick % HOURS_PER_DAY) / 24.0
