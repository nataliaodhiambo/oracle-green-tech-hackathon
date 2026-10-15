# demo_live_prediction.py
import time

def predict_live_farm_score(farm_id, ndvi, rainfall_pct, temp_stress):
    print(f"\n[OCI Data Science Engine] Ingesting satellite telemetry for {farm_id}...")
    time.sleep(1) # Simulates OCI API call
    
    # Calculate score
    score = (ndvi * 35) + (rainfall_pct * 0.35) + ((1 - temp_stress) * 30)
    crs = round(min(max(score, 0), 100), 1)
    
    print(f"--> Live NDVI: {ndvi}")
    print(f"--> Rainfall Anomaly: {rainfall_pct}% of average")
    print(f"--> Computed Climate Resilience Score (CRS): {crs}/100")
    
    if crs >= 75:
        print("--> Status: HIGH RESILIENCE. Micro-loan interest rate reduced to 9.5%!")
    elif crs >= 50:
        print("--> Status: MODERATE RISK. Standard micro-loan interest rate applies (12%).")
    else:
        print("--> Status: CRITICAL DROUGHT RISK. Parametric relief payout triggered!")

# Run live demo trigger
predict_live_farm_score("PLOT_001 (Wanjiru N.)", ndvi=0.68, rainfall_pct=115, temp_stress=0.15)