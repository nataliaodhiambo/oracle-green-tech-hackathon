# KilimoPesa Risk Engine 🌾🛰️

> **AI-Powered Satellite Climate Risk Scoring & Green Micro-Financing for Smallholder Farmers**

[![Hackathon](https://img.shields.io/badge/iLabAfrica-Green%20Tech%20Hackathon-green)](#)
[![Oracle](https://img.shields.io/badge/Cloud-Oracle%20OCI%20%26%20APEX-red)](#)
[![Python](https://img.shields.io/badge/Python-3.10%2B-blue)](#)

---

## 📌 Problem Statement
Over 70% of East African smallholder farmers are excluded from affordable green credit. Traditional micro-finance institutions (MFIs) and SACCOs lack hyper-local climate risk data, making small agricultural loans high-risk and expensive. Meanwhile, farmers lack visibility into how sustainable practices directly improve their financial creditworthiness.

## 💡 Solution
**KilimoPesa Risk Engine** bridges satellite climate analytics with green micro-financing through a 3-tier system:
1. **Satellite Data Processing Engine (Data & AI):** Ingests open Sentinel-2 and weather data to calculate a real-time **Climate Resilience Score (CRS: 0–100)** using vegetation health (NDVI), rainfall deficits, and temperature stress.
2. **Dynamic Financing Layer (Oracle OCI / APEX):** Allows SACCOs to evaluate plot resilience, automatically lower loan interest rates for sustainable practices, and trigger parametric drought relief payouts.
3. **Farmer Awareness (USSD/SMS):** Delivers accessible green score updates and actionable soil/water conservation advice directly to non-smartphone users.

---

## 🏗️ Architecture & Technology Stack
[ Sentinel-2 Satellite Data ] ──> [ Python / OCI ML Model ] ──> [ Climate Resilience Score (0-100) ]
│
▼
[ Farmer USSD/SMS Interface ] <─── [ Oracle APEX SACCO Portal ] <─── [ Oracle Autonomous Database ]

* **Data Layer & ML:** Python (`scikit-learn`, `numpy`), Sentinel-2 Satellite Open Data
* **Database:** Oracle Autonomous Database (Spatial Data & JSON indexing)
* **Lender Portal:** Oracle APEX Dashboard
* **Farmer Interface:** Africa's Talking USSD & SMS Simulator

---

## 🚀 Repository Structure

* `data/`: Sample plot coordinates, satellite metrics, and exported CSV/JSON datasets.
* `src/`: Core Python engine for score calculation and ML predictive modeling.
* `oracle_db/`: SQL scripts for database schema, tables, and finance logic routines.
* `ussd_simulator/`: Farmer-facing USSD/SMS interface script.

---

## ⚡ Quickstart & Local Setup

### Prerequisites
* Python 3.8+
* `pip` package manager

### Installation
```bash
# Clone the repository
git clone [https://github.com/YOUR_USERNAME/kilimopesa-risk-engine.git](https://github.com/YOUR_USERNAME/kilimopesa-risk-engine.git)
cd kilimopesa-risk-engine

# Install dependencies
pip install -r requirements.txt

# Generate baseline climate dataset
python src/generate_climate_data.py

# Run live predictive demo
python src/demo_live_prediction.py

### Step 4: Add `requirements.txt`

Create a file named `requirements.txt` in the root directory with these libraries:

```text
numpy>=1.21.0
pandas>=1.3.0
scikit-learn>=1.0.0
sentinelhub>=3.4.0
