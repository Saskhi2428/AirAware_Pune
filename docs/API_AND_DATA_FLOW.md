# AirAware Pune: REST API & Telemetry Data Flow Specification

This document provides the exhaustive specification for all REST endpoints, WebSocket streams, and PostgREST direct query interfaces across the **AirAware** mobile backend architecture.

---

## 1. API Architecture Overview

The AirAware mobile application interacts with data via a hybrid dual-channel architecture:
1. **FastAPI Microservice (`http://<backend-host>:8000/api/v1/`)**: Specialized endpoints for spatial lookups, CPCB sub-index calculations, ward boundary aggregation, and diurnal analytics.
2. **Supabase PostgREST Gateway (`https://<project-ref>.supabase.co/rest/v1/`)**: High-performance, direct database query layer utilized by the Flutter mobile client for real-time reads, citizen report insertions, and authenticated profile updates.
3. **Supabase Realtime Engine (WebSockets)**: Push-based Change Data Capture (CDC) streaming instantaneous updates on `air_quality_readings` and `citizen_reports`.

---

## 2. FastAPI REST Endpoint Catalog (`/api/v1/`)

### 2.1 Health & Service Verification

#### `GET /api/v1/health`
* **Purpose**: Verifies that the FastAPI microservice and connected database pool are healthy.
* **Authentication**: None (Public).
* **Response `200 OK`**:
```json
{
  "status": "healthy",
  "database": "connected",
  "timestamp": "2026-09-30T13:45:00.000Z",
  "active_stations": 49
}
```

---

### 2.2 Live Telemetry Endpoints (`/api/v1/live`)

#### `GET /api/v1/live`
* **Purpose**: Returns the most recent air quality readings across all active Pune monitoring stations.
* **Authentication**: None (Public).
* **Query Parameters**:
  - `limit` (int, optional, default: 50): Number of stations to return.
  - `ward` (string, optional): Filter stations by PMC Ward name (e.g. `?ward=Shivajinagar`).
* **Response `200 OK`**:
```json
[
  {
    "station_id": "pune_shivajinagar_01",
    "station_name": "Shivajinagar CAAQMS",
    "ward": "Shivajinagar",
    "latitude": 18.5314,
    "longitude": 73.8446,
    "aqi": 142,
    "category": "Moderate",
    "dominant_pollutant": "PM2.5",
    "pollutants": {
      "pm25": 54.2,
      "pm10": 118.0,
      "no2": 32.1,
      "so2": 14.5,
      "co": 1.1,
      "ozone": 28.4
    },
    "weather": {
      "temperature": 27.5,
      "humidity": 68.0,
      "wind_speed": 3.2
    },
    "recorded_at": "2026-09-30T13:40:00Z"
  }
]
```

#### `GET /api/v1/live/{station_id}`
* **Purpose**: Fetches the detailed real-time reading for a single monitoring station.
* **Path Parameters**:
  - `station_id` (string, required): Unique station code.
* **Response `200 OK`**: Single telemetry object matching schema above.
* **Error Response `404 Not Found`**:
```json
{
  "detail": "Station 'pune_unknown_99' not found or currently inactive."
}
```

---

### 2.3 Station Geospatial Endpoints (`/api/v1/stations`)

#### `GET /api/v1/stations`
* **Purpose**: Retrieves metadata for all 49 Pune air stations.
* **Response `200 OK`**: Array of station metadata objects containing `id`, `name`, `ward`, `operator`, `latitude`, `longitude`, `is_active`.

#### `GET /api/v1/stations/nearest`
* **Purpose**: Performs a server-side PostGIS spatial query to find the nearest station to arbitrary device coordinates.
* **Query Parameters**:
  - `lat` (float, required): User GPS latitude (e.g. `18.5089`).
  - `lon` (float, required): User GPS longitude (e.g. `73.8123`).
* **Response `200 OK`**:
```json
{
  "station_id": "pune_kothrud_02",
  "name": "Kothrud Stand CAAQMS",
  "distance_meters": 432.5,
  "aqi": 118,
  "category": "Moderate",
  "dominant_pollutant": "PM2.5"
}
```

---

### 2.4 Wards & Aggregated Analytics (`/api/v1/wards`)

#### `GET /api/v1/wards`
* **Purpose**: Returns GeoJSON FeatureCollection of all 49 Pune administrative wards with real-time average AQI embedded in properties.
* **Response `200 OK`**:
```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "properties": {
        "ward_number": 12,
        "ward_name": "Kothrud",
        "zone": "Zone 2",
        "station_count": 2,
        "average_aqi": 115,
        "status": "Moderate"
      },
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[73.805, 18.501], [73.820, 18.505], [73.815, 18.515], [73.805, 18.501]]]
      }
    }
  ]
}
```

---

### 2.5 Community Watch & Alerts (`/api/v1/alerts`)

#### `GET /api/v1/alerts/reports`
* **Purpose**: Fetches verified or active citizen pollution reports.
* **Query Parameters**:
  - `ward` (string, optional): Filter by ward.
  - `category` (string, optional): Filter by incident type.
* **Response `200 OK`**:
```json
[
  {
    "id": "7b3b44b8-2e06-4c28-9892-e4e69b0fae3e",
    "ward": "Kothrud",
    "category": "Garbage Burning",
    "description": "Thick smoke near DP Road garbage depot. Burning plastic.",
    "latitude": 18.5042,
    "longitude": 73.8149,
    "votes": 14,
    "status": "pending",
    "reported_at": "2026-09-30T12:15:00Z"
  }
]
```

#### `POST /api/v1/alerts/reports`
* **Purpose**: Submits a new citizen incident report.
* **Headers**: `Content-Type: application/json`, `Authorization: Bearer <JWT>`
* **Request Body**:
```json
{
  "ward": "Kothrud",
  "category": "Garbage Burning",
  "description": "Open fire behind commercial complex.",
  "latitude": 18.5042,
  "longitude": 73.8149
}
```
* **Response `201 Created`**: Returns newly created report object with generated UUID.

#### `POST /api/v1/alerts/reports/{report_id}/vote`
* **Purpose**: Increments community upvote count on an incident.
* **Response `200 OK`**:
```json
{
  "report_id": "7b3b44b8-2e06-4c28-9892-e4e69b0fae3e",
  "new_vote_count": 15
}
```

---

### 2.6 Diurnal & Historical Analytics (`/api/v1/analytics`)

#### `GET /api/v1/analytics/diurnal`
* **Purpose**: Hourly average AQI and pollutant concentrations computed over a 7-day or 30-day window.
* **Response `200 OK`**:
```json
{
  "period": "7d",
  "hourly_profile": [
    { "hour": 0, "avg_aqi": 135, "pm25": 48.1 },
    { "hour": 6, "avg_aqi": 165, "pm25": 62.4 },
    { "hour": 12, "avg_aqi": 98, "pm25": 31.0 },
    { "hour": 18, "avg_aqi": 172, "pm25": 68.9 }
  ]
}
```

---

## 3. Direct PostgREST Query Specification (`Supabase SDK`)

The Flutter mobile client directly issues PostgREST queries using `supabase-flutter` to achieve sub-50ms latency:

### 3.1 Fetching All Stations with Latest Telemetry
```dart
final response = await supabase
    .from('stations')
    .select('*, air_quality_readings(*)')
    .eq('is_active', true)
    .order('name');
```

### 3.2 Inserting an Exposure Tracking Session
```dart
await supabase.from('exposure_sessions').insert({
  'user_id': supabase.auth.currentUser!.id,
  'activity_type': 'cycling',
  'started_at': startTime.toIso8601String(),
  'ended_at': endTime.toIso8601String(),
  'duration_seconds': durationInSeconds,
  'distance_meters': totalDistanceMeters,
  'avg_aqi': averageAqi,
  'peak_aqi': peakAqi,
  'relative_exposure_score': inhaledDosageMicrograms,
});
```

---

## 4. WebSocket Realtime Protocol

AirAware subscribes to Supabase Realtime Postgres Changes via WebSocket:

```dart
final channel = supabase.channel('public:citizen_reports')
  .onPostgresChanges(
    event: PostgresChangeEvent.all,
    schema: 'public',
    table: 'citizen_reports',
    callback: (payload) {
      // Trigger Riverpod provider invalidation -> UI updates instantaneously
      ref.invalidate(citizenReportsProvider);
    },
  )
  .subscribe();
```
- **Heartbeat Interval**: 30 seconds.
- **Automatic Reconnection**: Backoff strategy with jitter ($1s, 2s, 4s, 8s \dots$).
- **Transport**: Secure WebSockets (`wss://<ref>.supabase.co/realtime/v1/websocket`).
