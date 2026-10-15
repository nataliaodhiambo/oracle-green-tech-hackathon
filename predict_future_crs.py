import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestRegressor

# 1. Load your generated climate data
df = pd.read_csv("climate_data.csv")

# 2. Features for ML training: NDVI, Rainfall Pct, Temp Stress, Drought Risk
X = df[["ndvi", "rainfall_pct", "temp_stress", "drought_risk"]]
y = df["crs_score"]

# 3. Train a lightweight Random Forest model
model = RandomForestRegressor(n_estimators=50, random_state=42)
model.fit(X, y)

# 4. Predict next month's score for a plot experiencing incoming heat stress
sample_upcoming_conditions = np.array([[0.35, 70.0, 0.45, 0.50]])
predicted_score = model.predict(sample_upcoming_conditions)[0]

print("\n--- OCI PREDICTIVE CLIMATE MODEL ---")
print(f"Current Parameters -> NDVI: 0.35 | Rainfall: 70% | Temp Stress: 0.45")
print(f"Predicted Next-Month CRS: {round(predicted_score, 1)} / 100")

if predicted_score < 40.0:
    print("ALERT: High probability of drought risk! Pre-emptive loan relief recommended.")
else:
    print("STATUS: Stable climate resilience predicted.")