import os
import json
import csv
import random
import numpy as np

# Ensure target directory exists
os.makedirs("data", exist_ok=True)

COUNTIES = ["Kajiado", "Machakos"]
FARMER_NAMES = [
    "Wanjiru N.", "Juma K.", "Amina O.", "Kipkorir M.", "Mwangi P.",
    "Nanjala S.", "Ochieng E.", "Muthoni R.", "Chebet L.", "Otieno B."
]

# Indicator definitions: units and directionality
INDICATOR_METADATA = {
    "ndvi": {"unit": "Index (-1.0 to +1.0)", "direction": "Higher is better (denser, healthier green canopy)"},
    "rainfall_pct": {"unit": "Percentage (%)", "direction": "Higher is better (100% = normal long-term rainfall average)"},
    "temp_stress": {"unit": "Index (0.0 to 1.0)", "direction": "Lower is better (0.0 = minimal heat stress, 1.0 = severe topsoil heat)"},
    "drought_risk": {"unit": "Index (0.0 to 1.0)", "direction": "Lower is better (0.0 = low drought probability, 1.0 = extreme drought)"},
    "crs_score": {"unit": "Score (0.0 to 100.0)", "direction": "Higher is better (composite climate resilience score)"}
}

def calculate_crs(ndvi, rainfall_pct, temp_stress, drought_risk):
    ndvi_score = np.clip(ndvi * 100, 0, 100)
    rain_score = np.clip(((rainfall_pct - 50) / (150 - 50)) * 100, 0, 100)
    temp_score = (1.0 - np.clip(temp_stress, 0, 1)) * 100
    drought_score = (1.0 - np.clip(drought_risk, 0, 1)) * 100
    
    crs = (ndvi_score * 0.35) + (rain_score * 0.35) + (temp_score * 0.15) + (drought_score * 0.15)
    return round(float(crs), 1)

plots = []
months = ["2026-08-01", "2026-09-01", "2026-10-01"]

for i in range(1, 26):
    plot_id = f"PLOT_{i:03d}"
    farmer_code = f"FARM_{100 + i:03d}"
    farmer = random.choice(FARMER_NAMES)
    county = random.choice(COUNTIES)
    area_hectares = round(random.uniform(0.5, 4.5), 2)
    
    # Location coordinates
    if county == "Kajiado":
        lat = round(-1.85 + random.uniform(-0.05, 0.05), 4)
        lon = round(36.78 + random.uniform(-0.05, 0.05), 4)
    else:
        lat = round(-1.51 + random.uniform(-0.05, 0.05), 4)
        lon = round(37.26 + random.uniform(-0.05, 0.05), 4)
    
    # Demo Anchor: PLOT_003 (Wanjiru N.)
    if plot_id == "PLOT_003":
        farmer = "Wanjiru N."
        county = "Kajiado"
        lat, lon = -1.8521, 36.7821
        area_hectares = 1.80
    
    for idx, record_date in enumerate(months):
        # Demo trajectory for PLOT_003
        if plot_id == "PLOT_003":
            if idx == 0:
                ndvi, rainfall_pct, temp_stress, drought_risk = 0.25, 65.0, 0.50, 0.55
            elif idx == 1:
                ndvi, rainfall_pct, temp_stress, drought_risk = 0.42, 85.0, 0.35, 0.35
            else:
                ndvi, rainfall_pct, temp_stress, drought_risk = 0.58, 105.0, 0.20, 0.20
        
        # High Resilience Green Plots
        elif plot_id in ["PLOT_001", "PLOT_005", "PLOT_010", "PLOT_015", "PLOT_020"]:
            ndvi = round(random.uniform(0.72, 0.88), 2)
            rainfall_pct = round(random.uniform(110.0, 135.0), 1)
            temp_stress = round(random.uniform(0.05, 0.20), 2)
            drought_risk = round(random.uniform(0.05, 0.15), 2)
        
        else:
            ndvi = round(random.uniform(0.18, 0.65), 2)
            rainfall_pct = round(random.uniform(55.0, 115.0), 1)
            temp_stress = round(random.uniform(0.20, 0.60), 2)
            drought_risk = round(random.uniform(0.10, 0.55), 2)
        
        crs = calculate_crs(ndvi, rainfall_pct, temp_stress, drought_risk)
        
        if crs < 40.0:
            status = "PARAMETRIC_PAYOUT_TRIGGERED"
        elif crs >= 75.0:
            status = "QUALIFIES_FOR_DISCOUNT_RATE"
        else:
            status = "STANDARD_RATE"
            
        plots.append({
            "plot_id": plot_id,
            "farmer_code": farmer_code,
            "farmer_name": farmer,
            "county": county,
            "area_hectares": area_hectares,
            "assessment_date": record_date,
            "is_forecast": False,
            "latitude": lat,
            "longitude": lon,
            "ndvi": ndvi,
            "rainfall_pct": rainfall_pct,
            "temp_stress": temp_stress,
            "drought_risk": drought_risk,
            "crs_score": crs,
            "status": status
        })

# Wrap dataset with index metadata definitions
output_payload = {
    "indicator_definitions": INDICATOR_METADATA,
    "records": plots
}

# Save updated JSON and CSV
with open("data/climate_data.json", "w") as f:
    json.dump(output_payload, f, indent=2)

keys = plots[0].keys()
with open("data/climate_data.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=keys)
    writer.writeheader()
    writer.writerows(plots)

print("Updated data generated with assessment_date, farmer_code, area_hectares, is_forecast, and index metadata!")