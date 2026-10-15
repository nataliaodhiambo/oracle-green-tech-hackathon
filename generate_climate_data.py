import json
import csv
import random
import numpy as np
from datetime import datetime, timedelta

COUNTIES = ["Kajiado", "Machakos"]
FARMER_NAMES = [
    "Wanjiru N.", "Juma K.", "Amina O.", "Kipkorir M.", "Mwangi P.",
    "Nanjala S.", "Ochieng E.", "Muthoni R.", "Chebet L.", "Otieno B."
]

def calculate_crs(ndvi, rainfall_pct, temp_stress, drought_risk):
    # Scale NDVI (0.0 to 1.0) -> 0 to 100
    ndvi_score = np.clip(ndvi * 100, 0, 100)
    
    # Scale Rainfall % (50% to 150%) -> 0 to 100
    rain_score = np.clip(((rainfall_pct - 50) / (150 - 50)) * 100, 0, 100)
    
    # Stress indices (lower stress = higher resilience score)
    temp_score = (1.0 - np.clip(temp_stress, 0, 1)) * 100
    drought_score = (1.0 - np.clip(drought_risk, 0, 1)) * 100
    
    # Weighted calculation
    crs = (ndvi_score * 0.35) + (rain_score * 0.35) + (temp_score * 0.15) + (drought_score * 0.15)
    return round(float(crs), 1)

plots = []
# Generate historical data for 3 consecutive months
months = ["2026-08-01", "2026-09-01", "2026-10-01"]

for i in range(1, 26):
    plot_id = f"PLOT_{i:03d}"
    farmer = random.choice(FARMER_NAMES)
    county = random.choice(COUNTIES)
    
    # Base coordinates by county
    if county == "Kajiado":
        lat = round(-1.85 + random.uniform(-0.05, 0.05), 4)
        lon = round(36.78 + random.uniform(-0.05, 0.05), 4)
    else:  # Machakos
        lat = round(-1.51 + random.uniform(-0.05, 0.05), 4)
        lon = round(37.26 + random.uniform(-0.05, 0.05), 4)
    
    # Generate time series for each plot
    for record_date in months:
        ndvi = round(random.uniform(0.18, 0.75), 2)
        rainfall_pct = round(random.uniform(55.0, 135.0), 1)
        temp_stress = round(random.uniform(0.10, 0.65), 2)
        drought_risk = round(random.uniform(0.05, 0.60), 2)
        
        crs = calculate_crs(ndvi, rainfall_pct, temp_stress, drought_risk)
        
        # Determine loan action / parametric status
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

# Export to JSON and CSV
with open("climate_data.json", "w") as f:
    json.dump(plots, f, indent=2)

keys = plots[0].keys()
with open("climate_data.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=keys)
    writer.writeheader()
    writer.writerows(plots)

print("Updated climate_data.json & climate_data.csv with county, record_date, and parametric status!")