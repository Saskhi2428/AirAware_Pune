# Database — schema summary

Full source of truth: `backend/migrations/0001_core_schema.sql`. This file
just summarizes intent so you don't have to reverse-engineer SQL to
understand the model.

## Core reference tables
- `data_sources` — provider registry (`openaq`, `cpcb_datagovin`, ...)
- `pollutants` — pm25, pm10, no2, so2, o3, co, nh3 with units

## Station registry
- `monitoring_stations` — one row per real station/locality. `location_type`
  distinguishes `measured_station` / `mapped_station` / `estimated` /
  `modelled` (spec section 3) so the UI never claims a measurement that
  didn't happen. Has a generated PostGIS `geography` column for real
  distance queries (needed later for Smart Location / nearest-station logic).

## Time-series data
- `air_quality_readings` — one row per (station, pollutant, observed_at).
  Unique constraint on that triple prevents duplicate ingestion. Carries
  `quality_score`/`quality_flag`/`is_valid` from the validation pipeline.
- `aqi_computations` — one row per (station, computed_for) with the CPCB
  sub-index result: `aqi_value`, `aqi_category`, `dominant_pollutant`,
  `standard`.
- `weather_data` — per-station or per-coordinate weather snapshot.
- `station_status` — periodic health check log (healthy/warning/offline).

## Quality & operations
- `data_quality_logs` — every failed validation check, for audit/debugging.
- `ingestion_runs` — one row per scheduler job execution (status, counts,
  error message) — feeds the admin dashboard directly, no separate
  "fake" stats table.

## ML (schema ready, not yet populated — Phase 16+)
- `model_registry`, `model_metrics`, `predictions`.

## Spatial analysis (schema ready, not yet populated — Phase 14/15)
- `anomaly_events`, `hotspot_events`.

## User-facing (RLS-protected — owner-only access)
- `profiles` (extends `auth.users`, role: user/researcher/admin)
- `saved_locations`, `user_preferences`, `alerts`, `notification_tokens`
- `exposure_sessions`, `exposure_points` (generalized/sampled points, not
  continuous raw GPS — spec section 28 privacy requirement)
- `audit_logs`

## Row Level Security

Personal-data tables (`profiles`, `saved_locations`, `user_preferences`,
`alerts`, `notification_tokens`, `exposure_sessions`, `exposure_points`)
have RLS enabled with owner-only policies (`auth.uid() = user_id`).

Public environmental-data tables (`monitoring_stations`,
`air_quality_readings`, `aqi_computations`, `weather_data`,
`hotspot_events`, `anomaly_events`) are intentionally left without RLS —
they're public environmental data, not personal data, and the whole point
of the app is to expose them broadly.

**Reminder:** RLS protects rows from other end users going through the
Supabase client SDK. It does not protect against your own backend, which
uses the service-role key and bypasses RLS entirely — so backend input
validation still matters just as much.
