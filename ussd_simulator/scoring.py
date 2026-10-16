import json
from pathlib import Path

DATA_FILE = Path(__file__).resolve().parent.parent / "data" / "climate_data.json"

# Loan terms shown to farmers
STANDARD_RATE = 12.0
GREEN_RATE = 9.5
DISCOUNT_THRESHOLD = 75.0
PAYOUT_THRESHOLD = 40.0
EXAMPLE_LOAN_KES = 50_000

# Farmer actions and the indicator change each one is modelled to produce.
# Rainfall is weather, so no action targets it.
ACTIONS = [
    {"name": "Mulch & plant cover crops", "indicator": "ndvi", "change": +0.10},
    {"name": "Plant shade/fruit trees", "indicator": "temp_stress", "change": -0.15},
    {"name": "Dig zai pits / water pan", "indicator": "drought_risk", "change": -0.15},
    {"name": "Minimum tillage", "indicator": "ndvi", "change": +0.05},
]


def _clip(value, low, high):
    return max(low, min(high, value))


# Same formula as calculate_crs() in generate_climate_data.py
def calculate_crs(ndvi, rainfall_pct, temp_stress, drought_risk):
    ndvi_score = _clip(ndvi * 100, 0, 100)
    rain_score = _clip(((rainfall_pct - 50) / (150 - 50)) * 100, 0, 100)
    temp_score = (1.0 - _clip(temp_stress, 0, 1)) * 100
    drought_score = (1.0 - _clip(drought_risk, 0, 1)) * 100

    crs = (ndvi_score * 0.35) + (rain_score * 0.35) + (temp_score * 0.15) + (drought_score * 0.15)
    return round(float(crs), 1)


def load_plots():
    """Return {plot_id: [records sorted by assessment_date]}."""
    with open(DATA_FILE) as f:
        records = json.load(f)["records"]

    plots = {}
    for record in records:
        plots.setdefault(record["plot_id"], []).append(record)
    for history in plots.values():
        history.sort(key=lambda r: r["assessment_date"])
    return plots


def interest_rate(crs):
    return GREEN_RATE if crs >= DISCOUNT_THRESHOLD else STANDARD_RATE


def ranked_actions(record):
    """Actions sorted by estimated CRS gain for this plot's latest readings."""
    inputs = {k: record[k] for k in ("ndvi", "rainfall_pct", "temp_stress", "drought_risk")}
    current = calculate_crs(**inputs)

    results = []
    for action in ACTIONS:
        improved = dict(inputs)
        improved[action["indicator"]] += action["change"]
        gain = round(calculate_crs(**improved) - current, 1)
        if gain > 0:
            results.append({"name": action["name"], "gain": gain})
    return sorted(results, key=lambda a: a["gain"], reverse=True)
