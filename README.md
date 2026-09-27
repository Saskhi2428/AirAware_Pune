# AirAware Pune — Real-Time Clean Air & Environmental Intelligence Platform

A production-ready, real-time air quality monitoring, safe commute navigation, and personal exposure tracking platform specifically engineered for the **Pune Metropolitan Region (PMC & PCMC)**.

Works seamlessly across all platforms: **Web, Android phones, iPhones, and Mac/Windows**.

---

## 🌟 Key Features (Pune-Specific)

1. **Real-Time NAQI Speedometer & Gauge**:
   - Indian CPCB methodology (0-50 Good, 51-100 Satisfactory, 101-200 Moderate, 201-300 Poor, 301-400 Very Poor, 401-500 Severe).
   - Real-time dominant pollutant indicator (PM2.5, PM10, NO2, SO2, CO, O3) and sub-indices.
   - City-wide average aggregated across 25 official Pune monitoring stations.

2. **Interactive Pune GIS Air Quality Map**:
   - Interactive Leaflet map centered on Pune (18.5204° N, 73.8567° E).
   - Color-coded pins for all 25 Pune stations: Karve Road, Shivajinagar, Kothrud, Hinjawadi Phase 1, Bhosari Industrial, Pashan (IITM), Katraj, Hadapsar, Viman Nagar, Baner, Aundh, Wakad, Nigdi, etc.
   - Interactive popups with instant 24-hour trend line charts.

3. **Ward-Level Neighborhood Leaderboard**:
   - Ranked list of Pune localities from cleanest (Pashan, Baner Hills) to most polluted (Bhosari Industrial, Swargate).
   - Categorized by: Residential & Green, IT Hubs & Tech Corridors, Industrial, and Heavy Traffic.

4. **Smart Diurnal Activity & Health Advisor ("Best Time to Step Out")**:
   - Pune-specific diurnal advice tailored to traffic and inversion patterns.
   - Guidance for morning walkers, sensitive/asthma patients, transit commuters, and home ventilation windows.

5. **Pune Safe Commute & Route Exposure Planner**:
   - Compare transit corridors (e.g. Swargate to Hinjawadi, Kothrud to Viman Nagar).
   - Calculates estimated travel duration, average AQI, personal inhaled PM2.5 dosage (µg), and recommends greener alternative routes.

6. **Live Personal Exposure Tracker**:
   - Digital stopwatch session tracker for outdoor running, brisk walking, cycling, and bike commuting in Pune.
   - Real-time ticker of liters of air breathed and micrograms of PM2.5 inhaled against daily WHO safety benchmarks.

7. **Citizen AirWatch**:
   - Community reporting tool for local garbage burning, construction dust, and industrial smoke across Pune wards with upvoting and status tracking.

---

## 🚀 How to Run Across All Platforms

The Flutter project is fully scaffolded for `android`, `ios`, `macos`, `web`, and `windows`:

```bash
cd flutter

# Run on Web (Chrome):
flutter run -d chrome

# Run on Android Phone (or emulator):
flutter run -d android

# Build Android APK:
flutter build apk

# Run on macOS (on a Mac):
flutter run -d macos
```

---

## 📁 Project Structure

```
airaware/
├── backend/                  # FastAPI backend + Supabase integration
│   ├── app/
│   │   ├── api/v1/pune.py    # Pune intelligence endpoints (overview, leaderboard, route, reports)
│   │   ├── services/         # AQI calculation, ingestion, and Pune station population
│   │   └── static/           # Universal Web & PWA application build
│   └── migrations/           # 26 PostgreSQL/PostGIS Supabase tables
|
├── flutter/                  # Flutter multi-platform application
│   ├── lib/                  # Riverpod state management & screens
│   ├── android/              # Native Android runner
│   ├── ios/                  # Native iOS runner
│   ├── macos/                # Native macOS runner
│   └── web/                  # Flutter web runner
└── run_realtime_app.bat      # One-click startup script
```

