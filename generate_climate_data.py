import os
import json
import csv
import random
import numpy as np

# Automatically create the 'data' folder if it doesn't exist
os.makedirs("data", exist_ok=True)

COUNTIES = ["Kajiado", "Machakos"]
FARMER_NAMES = [
    "Wanjiru N.", "Juma K.", "Amina O.", "Kipkorir M.", "Mwangi P.",
    "Nanjala S.", "Ochieng E.", "Muthoni R.", "Chebet L.", "Otieno B."
]

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
    farmer = random.choice(FARMER_NAMES)
    county = random.choice(COUNTIES)
    
    # Coordinates
    if county == "Kajiado":
        lat = round(-1.85 + random.uniform(-0.05, 0.05), 4)
        lon = round(36.78 + random.uniform(-0.05, 0.05), 4)
    else:
        lat = round(-1.51 + random.uniform(-0.05, 0.05), 4)
        lon = round(37.26 + random.uniform(-0.05, 0.05), 4)
    
    # Specific fix for PLOT_003 (Demo Anchor)
    if plot_id == "PLOT_003":
        farmer = "Wanjiru N."
        county = "Kajiado"
        lat, lon = -1.8521, 36.7821
    
    for idx, record_date in enumerate(months):
        # Controlled trajectory for PLOT_003 (Demo Story plot)
        if plot_id == "PLOT_003":
            if idx == 0:
                ndvi, rainfall_pct, temp_stress, drought_risk = 0.25, 65.0, 0.50, 0.55
            elif idx == 1:
                ndvi, rainfall_pct, temp_stress, drought_risk = 0.42, 85.0, 0.35, 0.35
            else:
                ndvi, rainfall_pct, temp_stress, drought_risk = 0.58, 105.0, 0.20, 0.20
        
        # High Resilience Plots (>= 75 score)
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
            "farmer_name": farmer,
            "county": county,
            "record_date": record_date,
            "latitude": lat,
            "longitude": lon,
            "ndvi": ndvi,
            "rainfall_pct": rainfall_pct,
            "temp_stress": temp_stress,
            "drought_risk": drought_risk,
            "crs_score": crs,
            "status": status
        })

# Export
with open("data/climate_data.json", "w") as f:
    json.dump(plots, f, indent=2)

keys = plots[0].keys()
with open("data/climate_data.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=keys)
    writer.writeheader()
    writer.writerows(plots)

print("Data regenerated successfully in the 'data' folder!")