# AIRAWare Pune: Production Deployment & Operations Guide

This guide details how to deploy and operate the **AIRAWare Pune Environmental Intelligence Platform** across cloud servers, containers, web browsers, and native mobile devices (Android, iOS).

---

## 🏗️ Architecture Overview

```
                      ┌────────────────────────────────────────┐
                      │             Clients                    │
                      │  • Universal Web PWA (Safari/Chrome)   │
                      │  • Flutter Web (/flutter/)             │
                      │  • Native Android APK (RMX3944/Pixel)   │
                      │  • Native iOS / Mac / Windows Desktop  │
                      └───────────────────┬────────────────────┘
                                          │ HTTPS / WSS
                                          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      FastAPI Production Backend (Port 8000)                  │
│                                                                             │
│  • GZip Compression (>1KB payloads)                                         │
│  • Security Headers (nosniff, SAMEORIGIN, strict-origin)                    │
│  • Static & PWA Assets Mount (/)                                            │
│  • Compiled Flutter Web Mount (/flutter/)                                   │
│  • APScheduler: 15-min OpenAQ / CPCB Observations Ingestor                  │
│                                                                             │
│  [API Endpoints]                                                            │
│   ├── /api/v1/pune/* (overview, leaderboard, map, weather, pulse, reports)  │
│   ├── /api/v1/locations/* (nearest-station, search, saved-locations)        │
│   ├── /api/v1/users/* (profile, preferences, roles)                         │
│   ├── /health (liveness probe)                                              │
│   └── /ready (readiness probe with PostgreSQL ping)                         │
│                                                                             │
│  [ML & Intelligence Services]                                               │
│   ├── DBSCAN Spatial Clustering (/pune/hotspots)                            │
│   ├── Isolation Forest Anomaly Detection (/pune/anomalies)                  │
│   ├── XGBoost 24h Probabilistic Forecasting (/pune/forecast)                 │
│   ├── SHAP Factor Attribution (/pune/explainability)                        │
│   └── Diurnal Best-Time Outdoor Activity Advisor (/pune/activity-advisor)   │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │
                                      ▼
                      ┌────────────────────────────────────────┐
                      │   Supabase Cloud PostgreSQL (PostGIS)   │
                      │   • 25 Pune Monitoring Stations        │
                      │   • Indian CPCB NAQI Computations      │
                      │   • User Profiles & Saved Locations    │
                      │   • Row Level Security (RLS)           │
                      └────────────────────────────────────────┘
```

---

## 🚀 Option 1: Docker & Container Deployment (Recommended)

### Prerequisites
- Docker Engine >= 24.0
- Docker Compose >= 2.20

### 1. Build and Run Container
From the repository root:
```bash
docker compose up -d --build
```

### 2. Verify Container Status
```bash
docker compose ps
docker compose logs -f airaware-platform
```

### 3. Test Health & Readiness Probes
```bash
# Liveness probe
curl http://localhost:8000/health

# Readiness probe (verifies database connectivity)
curl http://localhost:8000/ready
```

---

## ☁️ Option 2: Cloud Deployment (Railway, Render, Fly.io, AWS)

### Deploying to Railway / Render
1. Create a new Web Service and link your Git repository.
2. Select **Dockerfile** as the build method (points to `backend/Dockerfile`).
3. Set the following Environment Variables:
   ```env
   ENVIRONMENT=production
   PORT=8000
   API_V1_PREFIX=/api/v1
   CORS_ALLOWED_ORIGINS=*
   SUPABASE_URL=https://fzmtnzcjxsrdohaesfsz.supabase.co
   SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ6bXRuemNqeHNyZG9oYWVzZnN6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg4NDM1MTEsImV4cCI6MjEwNDQxOTUxMX0._UspiEY1l3QXT0IdmQFumi6unKCIB0uIe0do7hTd0o4
   DATABASE_URL=postgresql://postgres.fzmtnzcjxsrdohaesfsz:AIRAWare2026SecurePune@aws-0-ap-northeast-1.pooler.supabase.com:5432/postgres?sslmode=require
   PUNE_BBOX_MIN_LAT=18.35
   PUNE_BBOX_MIN_LNG=73.65
   PUNE_BBOX_MAX_LAT=18.80
   PUNE_BBOX_MAX_LNG=74.05
   JOB_LATEST_OBSERVATIONS_INTERVAL_MIN=15
   JOB_STATION_SYNC_INTERVAL_MIN=1440
   ```
4. Health check path: `/health`.

---

## 📱 Option 3: Mobile & Desktop Distribution

### 1. Android Release Build (APK & App Bundle)
To build a standalone installable release APK for Android phones:
```powershell
cd flutter
flutter build apk --release
```
The resulting APK is generated at:
`flutter/build/app/outputs/flutter-apk/app-release.apk`
You can transfer and install this APK directly on any Android device.

To build an Android App Bundle for Google Play Store upload:
```powershell
flutter build appbundle --release
```
Generated at: `flutter/build/app/outputs/bundle/release/app-release.aab`.

### 2. iOS / iPhone Deployment
- **Method A (Zero-install PWA)**:
  1. Open Safari on iPhone and navigate to `http://<your-server-ip>:8000/`.
  2. Tap the **Share** button -> **"Add to Home Screen"**.
  3. The app installs with native app icon, standalone display mode, and offline caching.
- **Method B (Native iOS Build via Xcode on macOS)**:
  ```bash
  cd flutter
  flutter build ipa --release
  ```

### 3. Flutter Web Release Build
To update the compiled Flutter web client:
```powershell
cd flutter
flutter build web --release
```
The FastAPI backend automatically serves this build at `/flutter/`.

---

## 💻 Option 4: Local Development & Verification

### Start the Server (Windows)
Double-click:
```
E:\Degree\DBMS\project\airaware\run_realtime_app.bat
```
Or run in PowerShell:
```powershell
cd E:\Degree\DBMS\project\airaware\backend
.\.venv\Scripts\activate
$env:PYTHONPATH="."
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

### Run Native Flutter App on Connected Device
```powershell
cd E:\Degree\DBMS\project\airaware\flutter
flutter run
```

---

## 📊 Live Endpoints Reference

| Endpoint | Method | Description |
| :--- | :---: | :--- |
| `/` | `GET` | Universal Responsive Web & PWA Client |
| `/flutter/` | `GET` | Compiled Flutter Web Application |
| `/docs` | `GET` | Interactive Swagger API Documentation |
| `/health` | `GET` | Service Liveness Probe |
| `/ready` | `GET` | Database Readiness Probe |
| `/api/v1/pune/overview` | `GET` | City-wide AQI, weather, and active station summary |
| `/api/v1/pune/pulse` | `GET` | Live Pune Air Pulse: Cleanest vs Most Polluted zones |
| `/api/v1/pune/leaderboard` | `GET` | Ranked Pune localities by CPCB NAQI |
| `/api/v1/pune/stations` | `GET` | Active monitoring stations with latest telemetry |
| `/api/v1/pune/map` | `GET` | Geo-snapshot of 25 Pune stations for GIS maps |
| `/api/v1/pune/hotspots` | `GET` | DBSCAN spatial pollution cluster detection |
| `/api/v1/pune/anomalies` | `GET` | Isolation Forest telemetry QA audit |
| `/api/v1/pune/forecast` | `GET` | XGBoost 1h/6h/24h probabilistic forecast |
| `/api/v1/pune/explainability` | `GET` | SHAP atmospheric factor attribution |
| `/api/v1/pune/activity-advisor` | `GET` | Diurnal best-time workout & commute advisor |
| `/api/v1/locations/nearest-station` | `GET` | Real-time GPS nearest-station resolution |
| `/api/v1/locations/search` | `GET` | Pune neighborhood search with live AQI |
| `/api/v1/locations/saved-locations` | `GET/POST/DELETE`| Saved places management (Home, College, Office) |
| `/api/v1/pune/route-exposure` | `POST`| Commute inhaled PM2.5 dosage & green route advisor |
| `/api/v1/pune/citizen-reports` | `GET/POST`| Community incident reporting (garbage burning, dust) |
