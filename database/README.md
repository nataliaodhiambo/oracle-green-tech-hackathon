# KilimoPesa: Role 1 to Role 2 data contract (v1) + 30-minute runbook

## One record = one plot at one assessment date

```json
[
  {
    "plot_id": "PLOT_001",
    "farmer_code": "FARM_001",
    "farmer_name": "Wanjiru N.",
    "county": "Kajiado",
    "latitude": -1.8521,
    "longitude": 36.7821,
    "area_hectares": 2.5,
    "assessment_date": "2026-10-01",
    "is_forecast": false,
    "ndvi": 0.62,
    "rainfall_pct": 110.0,
    "temp_stress": 0.20,
    "drought_risk": 0.10,
    "flood_index": 0.05,
    "crs_score": 82.4,
    "forecasted_crs": 80.1
  }
]
```

## Field definitions (Role 1 to confirm every line)

| Field | Required | Unit / range | Direction |
|---|---|---|---|
| `plot_id` | yes | stable string, unique per plot | n/a (becomes `plot_code`) |
| `farmer_code` | yes | stable string, unique per farmer (never an abbreviated name) | n/a |
| `farmer_name` | no | text | n/a |
| `county` | yes | text, e.g. `Kajiado` (consistent spelling) | n/a |
| `latitude`, `longitude` | yes | decimal degrees (WGS84), must fall inside Kenya | n/a |
| `area_hectares` | yes | hectares, > 0 | n/a |
| `assessment_date` | yes | `YYYY-MM-DD` | n/a |
| `is_forecast` | yes | JSON boolean. `false` = observed, `true` = modelled/future row | n/a |
| `crs_score` | yes | 0-100 | higher = more resilient (better) |
| `forecasted_crs` | no | 0-100, projected CRS for the next assessment period (Role 1: state the horizon, e.g. +30 days) | higher = better |
| `ndvi` | no | -1 to 1 | higher = healthier vegetation (better) |
| `rainfall_pct` | no | % of long-term average (100 = normal) | higher = wetter; below 100 = deficit (drought side), far above 100 = flood side |
| `temp_stress` | no | 0-1 normalised | higher = worse |
| `drought_risk` | no | 0-1 | higher = worse (drives DROUGHT payouts) |
| `flood_index` | no | 0-1, may be omitted or null | higher = worse (drives FLOOD payouts) |

## Rules both sides agree to
1. Send **observed** rows with `is_forecast: false`. Rows that are projections go in as `true`. The database only treats `false` rows as "current".
2. One row per (`plot_id`, `assessment_date`, `is_forecast`). Resending the same key updates it, so re-sends are safe.
3. Rows that break the ranges above are **rejected and listed** in `v_load_rejects`. They never reach the core tables.
4. Role 2 will not rename or remove columns in `v_farm_risk_latest`, `v_loan_portfolio`, `v_payout_events` or `v_kpi_summary`; columns may be added.

## Run order (30 minutes)

| Min | Step |
|---|---|
| 0-5 | Get a schema you own: Always Free Autonomous DB, or run the files in SQL Developer Web / APEX SQL Workshop on any account. |
| 5-10 | Run `00_reset.sql` (first time: skip), `01_schema.sql`, `02_logic.sql`, `03_views.sql`, each with **Run Script**. |
| 10-15 | Run `04_seed_and_tests.sql`. All T01-T15 must say PASS and the `user_errors` query must return no rows. Paste any failure to me. |
| 15-20 | Check that the ORDS step in `03_views.sql` worked. Open `https://<your-host>/ords/<schema>/v_farm_risk_latest/`. Send Roles 3 and 4 the four view URLs. |
| 20-25 | Send this file to Role 1 and ask them to confirm the unit/direction column. |
| 25-30 | Load their real JSON: `INSERT INTO stg_role1_json(payload) VALUES (:json) RETURNING load_id INTO :id;` then `BEGIN kp_load_role1(:id); END;`. Check `v_load_summary` and `v_load_rejects`. |

## Assumptions still to validate (list these in your status report)
- Flat interest, linear 8% to 12% pricing between CRS 80 and 40, and REVIEW below 40 are demo rules, not validated credit policy.
- Payout = 10% of principal at full severity, 50% of that at the threshold. Thresholds (drought 0.70, extreme 0.90) are placeholders.
- County is the event gate; each plot's own `drought_risk` / `flood_index` is the plot-level check.
- ORDS endpoints are public-read for the demo. Secure them before any real data.
