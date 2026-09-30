# AirAware Pune: Comprehensive File-by-File & Directory Architecture

This document provides an exhaustive, directory-by-directory and file-by-file breakdown of the entire **AirAware** production mobile ecosystem. Every single component across the Flutter mobile application, the FastAPI backend ingestion service, database migrations, configuration manifests, and documentation is analyzed in detail.

---

## 1. Directory Tree Overview

```
airaware/
├── .gitignore                                 # Git ignore definitions (ignores trash/, .env, build artifacts)
├── README.md                                  # Top-level repository overview
├── backend/                                   # FastAPI Ingestion Engine & REST Services
│   ├── app/
│   │   ├── api/
│   │   │   └── endpoints/
│   │   │       ├── alerts.py                  # Alerts & advisory REST endpoints
│   │   │       ├── analytics.py               # Historical analytics & trend queries
│   │   │       ├── health.py                  # Server health check endpoints
│   │   │       ├── live.py                    # Real-time station AQI readings
│   │   │       ├── stations.py                # Pune station registry endpoints
│   │   │       └── wards.py                   # PMC Ward boundary & aggregated AQI
│   │   ├── core/
│   │   │   ├── config.py                      # Pydantic environment settings
│   │   │   └── database.py                    # Async SQLAlchemy & Supabase engine
│   │   ├── crud/                              # Database abstraction operations
│   │   ├── models/                            # SQLAlchemy ORM models
│   │   ├── schemas/                           # Pydantic request/response schemas
│   │   ├── services/                          # Business logic & telemetry calculators
│   │   └── main.py                            # FastAPI app entry point (Mobile API router)
│   ├── Dockerfile                             # Container specification
│   ├── requirements.txt                       # Python dependencies
│   └── run_server.py                          # Uvicorn startup script
├── docs/                                      # Comprehensive Engineering & Academic Documentation
│   ├── AIRAWARE_COMPLETE_PROJECT_GUIDE.md     # System handbook & mobile architecture guide
│   ├── FILE_BY_FILE_EXPLANATION.md            # (This file) Complete file-by-file breakdown
│   ├── COMPLETE_PROJECT_FLOW.md               # End-to-end data pipelines & workflows
│   ├── DATABASE_DEEP_EXPLANATION.md           # 24 tables, PostGIS, ER diagram, RLS
│   ├── API_AND_DATA_FLOW.md                   # REST API catalog, schemas & payload contracts
│   ├── SUPABASE_ARCHITECTURE.md               # Auth, PostgREST, Realtime & PostgreSQL
│   ├── FEATURE_IMPLEMENTATION_MATRIX.md       # Audit verification matrix (Zero-mock proof)
│   └── README_FOR_STUDENT.md                  # Student Viva handbook & presentation guide
├── flutter/                                   # Production Flutter Android Client
│   ├── android/                               # Native Android configuration
│   │   └── app/src/main/AndroidManifest.xml   # Android permissions & foreground service
│   ├── assets/                                # Static branding, icons & geojson
│   │   └── pune_wards.geojson                 # GeoJSON boundaries of 49 Pune Municipal Wards
│   ├── lib/                                   # Dart Application Source Code
│   │   ├── config/
│   │   │   ├── app_config.dart                # Supabase URL/keys, API baseUrl, timeouts
│   │   │   └── app_theme.dart                 # Dark/Light Material 3 themes, AQI color bands
│   │   ├── maps/
│   │   │   └── pune_map_screen.dart           # Interactive Mapbox/OSM Pune vector map
│   │   ├── models/
│   │   │   ├── aqi_reading.dart               # Pollutant breakdown & sub-index calculations
│   │   │   ├── alert_model.dart               # Alert threshold & notification schema
│   │   │   ├── station.dart                   # Air monitoring station model
│   │   │   └── ward.dart                      # Municipal Ward geometry & summary model
│   │   ├── providers/
│   │   │   ├── pune_providers.dart            # Riverpod state providers (Stations, Reports, City Pulse)
│   │   │   └── theme_provider.dart            # Theme state notifier
│   │   ├── repositories/
│   │   │   └── pune_api_repository.dart       # HTTP client & Supabase PostgREST query layer
│   │   ├── routing/
│   │   │   ├── app_router.dart                # GoRouter route declarations & redirect logic
│   │   │   └── app_shell.dart                 # Persistent bottom navigation shell
│   │   ├── screens/
│   │   │   ├── alerts_screen.dart             # Community Watch, push alert tests, citizen reports
│   │   │   ├── exposure_screen.dart           # GPS foreground tracking & inhaled dosage math
│   │   │   ├── home_screen.dart               # Main dashboard, city pulse, station cards
│   │   │   ├── insights_screen.dart           # Ward rankings, diurnal trends, pollutant breakdown
│   │   │   ├── profile_screen.dart            # Supabase user profile & 5 health personas
│   │   │   ├── splash_screen.dart             # Animated launch screen & pre-warm cache
│   │   │   └── station_detail_screen.dart     # Single station telemetry, 24h charts & health advice
│   │   ├── services/
│   │   │   └── notification_service.dart      # Android notification channels & cooldown engine
│   │   ├── widgets/
│   │   │   ├── ai_assistant_dialog.dart       # Gemini AI air quality advisor
│   │   │   ├── aqi_badge.dart                 # Material AQI color pill
│   │   │   └── station_card.dart              # Summary station card with mini telemetry
│   │   └── main.dart                          # App bootstrap, Supabase init, Notification init
│   ├── pubspec.yaml                           # Flutter package dependencies
│   └── test/                                  # Unit, widget & integration tests
│       └── auth_and_location_test.dart        # Core provider, auth & calculation test suite
└── trash/                                     # Safely archived legacy/duplicate files (Git ignored)
```

---

## 2. Flutter Mobile Application (`flutter/lib/`)

### 2.1 Core Bootstrapping & Configuration

#### `flutter/lib/main.dart`
* **Role**: Primary entry point of the Flutter application.
* **Responsibilities**:
  1. Ensures Flutter widget binding is initialized (`WidgetsFlutterBinding.ensureInitialized()`).
  2. Initializes the Supabase client using credentials from `AppConfig.supabaseUrl` and `AppConfig.supabaseAnonKey`.
  3. Initializes the local notification engine (`NotificationService.initialize()`), requesting Android 13+ POST_NOTIFICATIONS runtime permissions.
  4. Wraps the app in `ProviderScope` to enable Riverpod dependency injection throughout the widget tree.
  5. Mounts `AirAwareApp`, consuming the GoRouter configuration and dynamic theme provider.
* **Dependencies**: `package:flutter/material.dart`, `package:flutter_riverpod/flutter_riverpod.dart`, `package:supabase_flutter/supabase_flutter.dart`, `notification_service.dart`, `app_config.dart`, `app_router.dart`.

#### `flutter/lib/config/app_config.dart`
* **Role**: Centralized environment and operational constants.
* **Responsibilities**:
  - Houses the Supabase Project URL (`https://your-project.supabase.co`) and public anonymous key.
  - Configures the FastAPI backend endpoint fallback (`http://10.0.2.2:8000` for Android emulator or LAN IP `http://192.168.x.x:8000` for physical devices).
  - Defines network connection timeouts (10 seconds connect, 15 seconds receive).
  - Specifies Pune geographic center coordinates (Latitude `18.5204`, Longitude `73.8567`) and default zoom bounds.

#### `flutter/lib/config/app_theme.dart`
* **Role**: Design system, Material 3 color schemes, and AQI standard palette.
* **Responsibilities**:
  - Implements official CPCB (Central Pollution Control Board) 6-stage AQI color standards:
    - **Good (0–50)**: Emerald Green (`#00E400` / `#10B981`)
    - **Satisfactory (51–100)**: Light Green / Yellow-Green (`#84CC16`)
    - **Moderate (101–200)**: Warm Yellow / Amber (`#F59E0B`)
    - **Poor (201–300)**: Orange (`#F97316`)
    - **Very Poor (301–400)**: Crimson Red (`#EF4444`)
    - **Severe (401–500+)**: Deep Purple / Maroon (`#7C3AED` / `#881337`)
  - Provides dark mode and light mode `ThemeData` with crisp typography (Inter/Roboto), high-contrast surface colors, and rounded card styling (`borderRadius: 16`).

---

### 2.2 Routing & Navigation

#### `flutter/lib/routing/app_router.dart`
* **Role**: Declarative navigation system built on `GoRouter`.
* **Responsibilities**:
  - Declares all valid app routes:
    - `/splash`: Animated launch screen with telemetry pre-warming.
    - `/`: Home screen (Main AQI Dashboard).
    - `/map`: Interactive Pune Station & Ward vector map.
    - `/exposure`: Foreground GPS outdoor exposure & inhaled dosage tracker.
    - `/insights`: Ward rankings, diurnal patterns, and historical analytics.
    - `/alerts`: Community Watch, citizen incident reporting, and notification settings.
    - `/profile`: User account, authentication, health persona selector, and preferences.
    - `/station/:id`: Detailed real-time view of a specific air monitoring station.
  - Implements the `ShellRoute` wrapper, nesting tabs inside `AppShell` while keeping bottom navigation persistent across tab transitions.

#### `flutter/lib/routing/app_shell.dart`
* **Role**: Persistent bottom navigation scaffold.
* **Responsibilities**:
  - Houses the 5-destination bottom navigation bar: **Home**, **Map**, **Exposure**, **Insights**, **Alerts**, **Profile**.
  - Handles active tab highlighting based on current URI location.
  - Carefully engineered without invasive floating action buttons or bottom overlaps, ensuring clean edge-to-edge rendering on modern gesture-navigation Android devices.

---

### 2.3 State Management & Data Providers (`flutter/lib/providers/`)

#### `flutter/lib/providers/pune_providers.dart`
* **Role**: Reactive state layer powered by Riverpod.
* **Responsibilities**:
  - `puneRepositoryProvider`: Instantiates and provides the singleton `PuneApiRepository`.
  - `stationsProvider`: `FutureProvider<List<Station>>` fetching all 49 Pune monitoring stations.
  - `cityPulseProvider`: Computed provider calculating city-wide average AQI, minimum AQI, maximum AQI, dominant pollutant, and total active stations.
  - `selectedStationIdProvider`: `StateProvider<String?>` tracking the currently highlighted or selected station.
  - `selectedStationProvider`: Computed provider resolving the full `Station` object for the active ID.
  - `citizenReportsProvider`: `FutureProvider<List<CitizenReport>>` loading live citizen reports from Supabase.
  - `userPersonaProvider`: Tracks the user's active health profile (e.g., General, Asthmatic, Child, Senior, Athlete).

#### `flutter/lib/providers/theme_provider.dart`
* **Role**: Theme mode management.
* **Responsibilities**:
  - Stores whether the application is running in Dark Mode, Light Mode, or following System preferences.
  - Persists preference locally using `shared_preferences`.

---

### 2.4 Data Repositories & API Layer (`flutter/lib/repositories/`)

#### `flutter/lib/repositories/pune_api_repository.dart`
* **Role**: Direct data interface connecting the mobile app to FastAPI and Supabase.
* **Responsibilities**:
  - Fetches real-time station lists and sensor telemetry via Supabase PostgREST queries on the `stations` and `air_quality_readings` tables.
  - Performs spatial queries to locate the nearest station to arbitrary GPS coordinates using the Haversine formula and PostGIS endpoints.
  - Queries `citizen_reports` table, ordering by `reported_at DESC` without any mock or dummy fallbacks.
  - Posts new citizen reports directly to Supabase with real latitude, longitude, category, ward, and description.
  - Submits report upvotes (`voteCitizenReport`), incrementing the `votes` column atomically.
  - Saves completed exposure tracking sessions to `exposure_sessions` with calculated average AQI, peak AQI, duration, and dosage.

---

### 2.5 Screens & User Interfaces (`flutter/lib/screens/`)

#### `flutter/lib/screens/splash_screen.dart`
* **Role**: Fluid startup screen with background telemetry pre-warming.
* **Responsibilities**:
  - Renders a clean breathing animation of the AirAware logo and tagline ("Pune Clean Air Initiative").
  - Triggers asynchronous pre-fetching of `stationsProvider` and `cityPulseProvider` in parallel.
  - Automatically transitions to the `/` home dashboard once telemetry is primed or after a 2-second timeout.

#### `flutter/lib/screens/home_screen.dart`
* **Role**: Primary executive dashboard for Pune citizens.
* **Responsibilities**:
  - **City Pulse Header**: Displays current city average AQI, category badge, and health descriptor.
  - **Health Advisor Banner**: Dynamically renders health guidance tailored to the user's active health persona (e.g., "Asthma Alert: PM2.5 elevated in Shivajinagar. Keep rescue inhaler nearby").
  - **Station Carousel / List**: Renders all active monitoring stations with live AQI values, primary pollutants, and color-coded status pills.
  - **Search & Filter**: Allows instant filtering by ward name, station name, or AQI category (e.g., Severe only).

#### `flutter/lib/maps/pune_map_screen.dart`
* **Role**: Interactive geospatial map of Pune.
* **Responsibilities**:
  - Utilizes `flutter_map` with OpenStreetMap or Mapbox vector tiles.
  - Plots all 49 Pune air stations with color-coded circular pins indicating live AQI.
  - Renders PMC Ward boundary polygons loaded from `assets/pune_wards.geojson`.
  - Tapping a station reveals a bottom modal card with complete pollutant breakdown and navigation shortcut.
  - **Recenter Button**: Positioned safely at `bottom: 96` to eliminate bottom navigation bar overlap.

#### `flutter/lib/screens/exposure_screen.dart`
* **Role**: Real-time outdoor exposure monitoring & inhaled dosage tracker.
* **Responsibilities**:
  - Initiates continuous GPS tracking using `Geolocator.getPositionStream` with `AndroidSettings` foreground notification (`AirAware Exposure Tracker Active`).
  - Calculates cumulative distance walked/cycled using `Geolocator.distanceBetween` between successive GPS fixes.
  - Dynamically detects the nearest air monitoring station every 15 seconds.
  - Computes real-time inhaled $PM_{2.5}$ dosage in micrograms ($\mu g$) based on minute ventilation rates ($V_E$) matching user activity:
    $$\text{Dosage } (\mu g) = \sum \left( \frac{\text{Station } PM_{2.5} \, (\mu g/m^3) \times V_E \, (m^3/min) \times \Delta t \, (min)}{1} \right)$$
  - Saves complete session metrics (duration, distance, avg AQI, peak AQI, dosage) to Supabase on session stop.

#### `flutter/lib/screens/insights_screen.dart`
* **Role**: Deep analytics, ward rankings, and diurnal trend analysis.
* **Responsibilities**:
  - Displays top 5 cleanest and top 5 most polluted wards in Pune.
  - Generates diurnal (time-of-day) trend visualizations showing morning peak (traffic), afternoon dip (solar mixing), and evening inversion.
  - Analyzes dominant pollutant distributions across all active Pune sensors.

#### `flutter/lib/screens/alerts_screen.dart`
* **Role**: Community Watch incident reporting and push notification testing.
* **Responsibilities**:
  - Lists live community-reported pollution incidents (garbage burning, construction dust, industrial smoke).
  - Features an interactive "Report Incident" floating action sheet that grabs real device GPS coordinates, auto-fills nearest ward, and submits to Supabase.
  - Enables community members to upvote incidents to increase urgency.
  - Provides a "Test Local Notification" button to verify Android notification channels and threshold triggers.

#### `flutter/lib/screens/profile_screen.dart`
* **Role**: User identity, preferences, and health persona configuration.
* **Responsibilities**:
  - Allows editing of user profile details (full name, email) saved to the `profiles` table in Supabase.
  - Configures 5 Health Personas:
    1. **General Public**: Standard CPCB advisories.
    2. **Asthma / Respiratory**: Tightened $PM_{2.5}$ thresholds ($>60 \, \mu g/m^3$).
    3. **Children & School**: Morning outdoor activity limits.
    4. **Elderly & Cardiac**: Stricter cardiovascular stress precautions.
    5. **Athletes & Outdoor Workers**: High-ventilation dosage alerts.
  - Manages notification thresholds and theme preferences.

#### `flutter/lib/screens/station_detail_screen.dart`
* **Role**: High-granularity analysis of a single monitoring station.
* **Responsibilities**:
  - Displays complete pollutant breakdown: $PM_{2.5}$, $PM_{10}$, $NO_2$, $SO_2$, $CO$, $O_3$.
  - Shows 24-hour historical trend line charts.
  - Shows weather parameters: Temperature, Humidity, Wind Speed, Wind Direction.

---

### 2.6 Services & Widgets (`flutter/lib/services/`, `flutter/lib/widgets/`)

#### `flutter/lib/services/notification_service.dart`
* **Role**: Native Android notification management.
* **Responsibilities**:
  - Configures `FlutterLocalNotificationsPlugin` with Android high-importance notification channel (`airaware_alerts`, "Air Quality Alerts").
  - Implements `checkThresholdAndNotify()` to alert users when their local AQI exceeds their chosen threshold.
  - Features a 30-minute cooldown cache to prevent notification spamming while conditions remain elevated.
  - Implements foreground service notifications for ongoing outdoor exposure sessions.

#### `flutter/lib/widgets/ai_assistant_dialog.dart`
* **Role**: Interactive Gemini AI air quality advisor modal.
* **Responsibilities**:
  - Allows users to ask natural language questions ("Is it safe for my 6-year-old to play outside in Kothrud right now?").
  - Injects current station telemetry and the user's active health persona into the prompt context.
  - Styled with edge-to-edge insets to prevent keyboard overlapping on mobile screens.

#### `flutter/lib/widgets/aqi_badge.dart`
* **Role**: Reusable visual badge displaying AQI number and label with standard CPCB color coding.

#### `flutter/lib/widgets/station_card.dart`
* **Role**: Dashboard card summarizing station status, AQI, distance from user, and primary pollutant.

---

## 3. FastAPI Backend Service (`backend/app/`)

### 3.1 Application Core & Startup

#### `backend/app/main.py`
* **Role**: FastAPI application factory and router aggregator.
* **Responsibilities**:
  - Configures CORS middleware for mobile client communication.
  - Mounts API routers under `/api/v1/`: `live`, `stations`, `wards`, `alerts`, `analytics`, `health`.
  - Provides a root `/` JSON health endpoint verifying database connectivity.

#### `backend/app/core/config.py`
* **Role**: Pydantic BaseSettings class reading environment variables (`SUPABASE_URL`, `SUPABASE_KEY`, `DATABASE_URL`, `GEMINI_API_KEY`).

#### `backend/app/core/database.py`
* **Role**: Async SQLAlchemy database engine and session maker connected to Supabase PostgreSQL.

---

### 3.2 API Endpoints (`backend/app/api/endpoints/`)

#### `backend/app/api/endpoints/live.py`
* **Role**: Real-time telemetry feed endpoint.
* **Endpoints**:
  - `GET /api/v1/live`: Returns latest readings for all 49 stations.
  - `GET /api/v1/live/{station_id}`: Returns latest reading for a specific station.

#### `backend/app/api/endpoints/stations.py`
* **Role**: Station metadata and geographic discovery.
* **Endpoints**:
  - `GET /api/v1/stations`: Returns list of all stations with coordinates, ward, and operator.
  - `GET /api/v1/stations/nearest`: Accepts `lat` and `lon` query params, returning the closest active station using PostGIS `ST_Distance`.

#### `backend/app/api/endpoints/wards.py`
* **Role**: PMC Ward boundaries and aggregated air quality statistics.
* **Endpoints**:
  - `GET /api/v1/wards`: Returns GeoJSON feature collection of Pune wards with computed average AQI.

#### `backend/app/api/endpoints/alerts.py`
* **Role**: Community Watch and critical advisory management.
* **Endpoints**:
  - `GET /api/v1/alerts/active`: Active government or sensor-triggered alerts.
  - `POST /api/v1/alerts/reports`: Citizen incident submission endpoint.
  - `POST /api/v1/alerts/reports/{report_id}/vote`: Increment incident upvote count.

#### `backend/app/api/endpoints/analytics.py`
* **Role**: Historical data aggregation and diurnal trends.
* **Endpoints**:
  - `GET /api/v1/analytics/diurnal`: Hourly averages for past 7/30 days.
  - `GET /api/v1/analytics/rankings`: Cleanest and most polluted wards.

---

## 4. Native Android Configuration (`flutter/android/`)

#### `flutter/android/app/src/main/AndroidManifest.xml`
* **Role**: Android OS contract declaring application capabilities, hardware permissions, and background services.
* **Key Declared Permissions**:
  - `android.permission.INTERNET`: Required for Supabase and FastAPI network communication.
  - `android.permission.ACCESS_FINE_LOCATION`: Required for high-accuracy GPS tracking in Exposure Mode.
  - `android.permission.ACCESS_COARSE_LOCATION`: Required for cell/Wi-Fi based proximity detection.
  - `android.permission.FOREGROUND_SERVICE`: Required to keep GPS tracking active when the user locks their screen or switches apps.
  - `android.permission.FOREGROUND_SERVICE_LOCATION`: Android 14+ requirement for background location tracking.
  - `android.permission.POST_NOTIFICATIONS`: Android 13+ requirement for threshold alerts and exposure status updates.
  - `android.permission.VIBRATE`: Haptic alert feedback on critical AQI warnings.

---

## 5. Summary of Key Architectural Decisions

1. **Pure Mobile Architecture**: Completely eliminated redundant static web files and legacy duplicated backends, moving them to `trash/`.
2. **True Dynamic Data**: Eliminated all mock fallbacks in repositories and UI cards.
3. **Resilient Offline / Sparse Handling**: Implemented intelligent fallback interpolation so that when individual sensor telemetry is temporarily sparse, the app displays computed estimates rather than crashing.
4. **Battery-Conscious Geolocation**: Exposure tracking uses adaptive distance filters (10 meters) to balance location precision with battery longevity.
