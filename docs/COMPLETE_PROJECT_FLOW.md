# AirAware Pune: End-to-End System & Data Flow Architecture

This document provides a comprehensive, lifecycle-based explanation of how data originates, travels, transforms, and is presented across the **AirAware** mobile platform. It traces every user interaction, background sensor telemetry pipeline, spatial query, and database transaction.

---

## 1. High-Level System Architecture Diagram

```mermaid
flowchart TD
    subgraph ExternalSources["External Ingestion Sources"]
        CPCB["CPCB Sensors (Central Govt)"]
        SAFAR["SAFAR Pune (IITM)"]
        OpenAQ["OpenAQ Ground Stations"]
        IMD["IMD Weather Telemetry"]
    end

    subgraph BackendIngestion["FastAPI Ingestion & REST Services"]
        IngestionWorker["Ingestion Cron Worker\n(5-minute cycle)"]
        Validation["Data Validator & Outlier Filter"]
        AQICalculator["CPCB Sub-Index Engine"]
        RESTRouter["FastAPI REST Endpoints\n(/api/v1/*)"]
    end

    subgraph SupabaseDB["Supabase Cloud Database (PostgreSQL 15 + PostGIS)"]
        StationsTable["stations"]
        ReadingsTable["air_quality_readings"]
        WardsTable["wards (Polygons)"]
        ReportsTable["citizen_reports"]
        SessionsTable["exposure_sessions"]
        ProfilesTable["profiles & preferences"]
        RealtimeEngine["Supabase Realtime\n(WAL CDC Replication)"]
    end

    subgraph MobileClient["Flutter Android Mobile Application"]
        DeviceGPS["Android Hardware GPS\n(Geolocator)"]
        NotificationMgr["Local Notification Service\n(Thresholds & Cooldowns)"]
        RiverpodState["Riverpod State Layer\n(Stations, Pulse, Reports)"]
        Screens["UI Presentation\n(Home, Map, Exposure, Insights, Alerts)"]
    end

    CPCB --> IngestionWorker
    SAFAR --> IngestionWorker
    OpenAQ --> IngestionWorker
    IMD --> IngestionWorker

    IngestionWorker --> Validation
    Validation --> AQICalculator
    AQICalculator --> ReadingsTable

    ReadingsTable --> RealtimeEngine
    ReportsTable --> RealtimeEngine

    ReadingsTable --> RESTRouter
    StationsTable --> RESTRouter
    WardsTable --> RESTRouter

    RESTRouter --> RiverpodState
    RealtimeEngine --> RiverpodState

    DeviceGPS --> Screens
    RiverpodState --> Screens
    Screens --> NotificationMgr
    Screens --> ReportsTable
    Screens --> SessionsTable
    Screens --> ProfilesTable
```

---

## 2. Ingestion to Database Pipeline (The 5-Minute Ingestion Loop)

Every 5 minutes, the automated ingestion engine runs to refresh air quality readings across Pune's 49 monitoring stations:

```mermaid
sequenceDiagram
    autonumber
    participant Ext as Sensor APIs (CPCB/SAFAR)
    participant Worker as FastAPI Ingestion Worker
    participant Math as AQI Calculation Engine
    participant DB as Supabase PostgreSQL
    participant Pub as Realtime WAL Publisher

    Worker->>Ext: Poll raw pollutant JSON metrics (PM2.5, PM10, NO2, SO2, CO, O3)
    Ext-->>Worker: Raw readings + timestamps + unit measurements
    Worker->>Worker: Sanitize values (filter negative or impossible sensor spikes)
    Worker->>Math: Compute sub-indices for each pollutant using Indian CPCB formula
    Math-->>Worker: Primary pollutant identified, AQI index calculated (0-500)
    Worker->>DB: INSERT into air_quality_readings (station_id, aqi, pm25, pm10, recorded_at)
    DB->>DB: Trigger: Update station last_reported_at and latest_aqi
    DB->>Pub: Write-Ahead Log (WAL) notifies changes on 'air_quality_readings'
    Pub-->>Worker: Broadcast ACK
```

### Ingestion Details:
1. **Source Multiplexing**: If a primary CPCB station is offline, the ingestion engine falls back to secondary OpenAQ or SAFAR monitors within the same ward.
2. **Indian National AQI (CPCB) Standard**:
   - Sub-index calculated for all valid pollutants.
   - Overall AQI equals the maximum sub-index:
     $$\text{AQI} = \max(I_{PM_{2.5}}, I_{PM_{10}}, I_{NO_2}, I_{SO_2}, I_{CO}, I_{O_3})$$
   - A minimum of 3 pollutants (with at least one being $PM_{2.5}$ or $PM_{10}$) must be active to publish an authoritative AQI.

---

## 3. Mobile Startup & Telemetry Pre-Warming Flow

When a Pune citizen launches the AirAware Android app:

```mermaid
sequenceDiagram
    autonumber
    participant User as Citizen / Mobile App
    participant Splash as SplashScreen
    participant Router as GoRouter
    participant Notif as NotificationService
    participant Riverpod as Riverpod Providers
    participant Repo as PuneApiRepository
    participant DB as Supabase PostgREST
    participant Home as HomeScreen

    User->>Splash: App Launch
    Splash->>Notif: NotificationService.initialize() (Request POST_NOTIFICATIONS)
    Splash->>Riverpod: Pre-warm stationsProvider & cityPulseProvider in parallel
    Riverpod->>Repo: getStations() & getLatestReadings()
    Repo->>DB: SELECT * FROM stations JOIN air_quality_readings
    DB-->>Repo: 49 Pune stations with latest telemetry
    Repo-->>Riverpod: Cached station objects & computed City Pulse
    Splash->>Router: Telemetry ready -> Navigate to '/'
    Router->>Home: Render HomeScreen with instant, flicker-free data
```

---

## 4. Real-Time Outdoor Exposure & Dosage Tracking Flow

This is one of the most critical features of AirAware, enabling joggers, cyclists, and commuters to record real inhaled pollution:

```mermaid
sequenceDiagram
    autonumber
    participant User as Commuter / Jogger
    participant UI as ExposureScreen
    participant GPS as Android Hardware GPS
    participant Repo as PuneApiRepository
    participant Notif as Android Foreground Notification
    participant DB as Supabase exposure_sessions

    User->>UI: Tap "Start Exposure Tracking" (Select activity: Cycling)
    UI->>Notif: Launch Foreground Service ("AirAware Exposure Tracker Active")
    UI->>GPS: Geolocator.getPositionStream(distanceFilter: 10m)
    loop Every GPS Movement (>10m)
        GPS-->>UI: New GPS Fix (lat, lon, speed, timestamp)
        UI->>UI: Geolocator.distanceBetween() -> Add to cumulative distance
        UI->>Repo: Find nearest station to (lat, lon)
        Repo-->>UI: Nearest Station (e.g., Karve Road, PM2.5 = 78 µg/m³)
        UI->>UI: Calculate incremental inhaled PM2.5 dosage based on ventilation rate
        UI->>Notif: Update notification with live distance, AQI, and inhaled dosage
        UI->>UI: Update live UI counters (Duration, Speed, Peak AQI, Total Dosage)
    end
    User->>UI: Tap "Stop Tracking"
    UI->>Notif: Terminate Foreground Service
    UI->>DB: INSERT into exposure_sessions (user_id, duration, distance, avg_aqi, peak_aqi, dosage)
    DB-->>UI: Session saved successfully!
    UI->>User: Display summary modal with health recovery tips
```

### Inhaled Dosage Formula:
AirAware implements the clinical inhalation model:
$$\text{Dosage } (\mu g) = \sum_{i=1}^{n} \left[ C_i \times V_E \times \Delta t_i \right]$$
Where:
- $C_i$: Ambient concentration of $PM_{2.5}$ ($\mu g/m^3$) at interval $i$ from nearest station.
- $V_E$: Minute ventilation rate ($m^3/\text{minute}$):
  - **Sedentary/Rest**: $0.008 \, m^3/\text{min}$
  - **Walking**: $0.015 \, m^3/\text{min}$
  - **Running/Cycling**: $0.035 \, m^3/\text{min}$
- $\Delta t_i$: Elapsed interval in minutes.

---

## 5. Community Watch & Citizen Incident Reporting Flow

When a citizen detects localized pollution (e.g., open trash burning, dust emission):

```mermaid
sequenceDiagram
    autonumber
    participant User as Pune Citizen
    participant UI as AlertsScreen
    participant GPS as Device GPS
    participant Repo as PuneApiRepository
    participant DB as Supabase citizen_reports
    participant Community as Other Citizens' Devices

    User->>UI: Tap "Report Pollution Incident"
    UI->>GPS: Get high-accuracy GPS coordinates (lat, lon)
    GPS-->>UI: Lat: 18.5089, Lon: 73.8123 (Kothrud)
    UI->>UI: Pre-fill ward name based on coordinates
    User->>UI: Select Category: "Garbage Burning", add description
    User->>UI: Tap "Submit Report"
    UI->>Repo: submitCitizenReport(ward, category, description, lat, lon)
    Repo->>DB: INSERT into citizen_reports (ward, category, description, latitude, longitude, votes: 0)
    DB-->>Repo: Report created with UUID
    Repo-->>UI: Report successfully published!
    UI->>UI: Invalidate citizenReportsProvider
    DB-)Community: Supabase Realtime broadcast -> New report appears on Community Watch feed
    loop Upvoting by Community
        Community->>Repo: voteCitizenReport(reportId)
        Repo->>DB: UPDATE citizen_reports SET votes = votes + 1 WHERE id = reportId
        DB-->>Community: Updated vote count rendered in real-time
    end
```

---

## 6. Personal AQI Alert & Cooldown Deduplication Engine

To avoid overwhelming users with repeated alerts while keeping them protected from sudden pollution spikes:

```mermaid
flowchart TD
    StartCheck["Periodic Telemetry Evaluation / Background Ping"] --> ReadUserSetting["Read user's alert threshold (e.g., 150 AQI)"]
    ReadUserSetting --> GetLocalAQI["Determine current AQI at user's location"]
    GetLocalAQI --> Condition{"Current AQI > Threshold?"}
    
    Condition -- No --> EndCheck["Do nothing (Conditions safe)"]
    Condition -- Yes --> CheckCooldown{"Has an alert fired in the last 30 minutes?"}
    
    CheckCooldown -- Yes --> Suppress["Suppress notification (Cooldown active to avoid spam)"]
    CheckCooldown -- No --> BuildNotif["Build High-Priority Android Notification\nChannel: 'Air Quality Alerts'\nBadge: CPCB Color\nVibrate: True"]
    
    BuildNotif --> DispatchNotif["Dispatch Notification via flutter_local_notifications"]
    DispatchNotif --> UpdateCache["Update lastAlertTime = DateTime.now()"]
    UpdateCache --> Done["User alerted with actionable health advice"]
```

---

## 7. Interactive Map & Spatial Queries Flow

When a citizen browses the interactive Pune map:

1. **Vector Tiles**: Map tiles are rendered dynamically using OpenStreetMap/CartoDB tiles via `flutter_map`.
2. **Ward Overlay**: `assets/pune_wards.geojson` is loaded into memory, rendering the geographic boundaries of all 49 Pune Municipal Corporation administrative wards with semi-transparent fills reflecting the ward's aggregate AQI.
3. **Station Pins**: 49 station pins are placed precisely at their EPSG:4326 coordinates ($(\text{lon}, \text{lat})$). Pins are styled with live CPCB color gradients.
4. **User Recenter**: Tapping the "Locate Me" button queries `Geolocator.getCurrentPosition()`, smoothly animating the camera to the user's location without colliding with the bottom navigation bar.

---

## 8. Summary of Data Resilience & Integrity Guarantees

- **No Stale UI**: All Riverpod providers feature smart caching with periodic refresh invalidation.
- **Fail-Safe Offline Mode**: If network connectivity drops, the app gracefully presents the last known telemetry from local cache with a clear "Offline - Showing cached data" badge.
- **Zero Mock Compromise**: Every screen in the app connects to genuine database tables and device hardware APIs.
