-- ============================================================================
-- AIRSENSE PUNE (AIRAWARE) — COMPREHENSIVE DBMS SPECIFICATION
-- COMPLETE DDL, DML, AND DQL MASTER SCRIPT
-- ============================================================================
-- Target Database : PostgreSQL 15+ with PostGIS Spatial Extension
-- Target Engine   : Supabase PostgreSQL (AWS ap-northeast-1)
-- Scope           : All 24 Application Tables, PostGIS Spatial Indexes,
--                   Row Level Security (RLS), Triggers, Real-time Publications,
--                   Data Ingestion (DML), Maintenance, and Analytical Queries (DQL).
-- ============================================================================

-- ============================================================================
-- SECTION 1: DATA DEFINITION LANGUAGE (DDL)
-- ============================================================================

-- 1.1 SPATIAL & CRYPTOGRAPHIC EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- 1.2 CUSTOM ENUM TYPES
DO $$ BEGIN
    CREATE TYPE aqi_category_enum AS ENUM (
        'Good',
        'Satisfactory',
        'Moderate',
        'Poor',
        'Very Poor',
        'Severe'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE station_health_enum AS ENUM (
        'online',
        'degraded',
        'offline',
        'unknown'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE data_source_type_enum AS ENUM (
        'government',
        'satellite',
        'cams',
        'crowdsourced'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE incident_type_enum AS ENUM (
        'garbage_burning',
        'construction_dust',
        'industrial_smoke',
        'vehicle_emission',
        'crop_residue'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE alert_type_enum AS ENUM (
        'aqi_threshold',
        'morning_briefing',
        'evening_commute',
        'severe_spike'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ----------------------------------------------------------------------------
-- 1.3 BASE METADATA & TELEMETRY TABLES (TABLES 1 - 7)
-- ----------------------------------------------------------------------------

-- Table 1: data_sources
CREATE TABLE IF NOT EXISTS data_sources (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    provider_type data_source_type_enum NOT NULL DEFAULT 'government',
    base_url TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table 2: pollutants
CREATE TABLE IF NOT EXISTS pollutants (
    id VARCHAR(32) PRIMARY KEY,
    name VARCHAR(128) NOT NULL,
    unit VARCHAR(32) NOT NULL,
    averaging_hours INTEGER NOT NULL DEFAULT 24,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table 3: monitoring_stations
CREATE TABLE IF NOT EXISTS monitoring_stations (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    source_id VARCHAR(64) REFERENCES data_sources(id) ON UPDATE CASCADE ON DELETE SET NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    location GEOGRAPHY(Point, 4326) NOT NULL,
    elevation_meters DOUBLE PRECISION DEFAULT 560.0,
    station_type VARCHAR(64) NOT NULL DEFAULT 'residential',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table 4: station_status
CREATE TABLE IF NOT EXISTS station_status (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    station_id VARCHAR(64) NOT NULL REFERENCES monitoring_stations(id) ON DELETE CASCADE,
    health_status station_health_enum NOT NULL DEFAULT 'online',
    packet_latency_seconds INTEGER NOT NULL DEFAULT 0,
    uptime_percentage_24h DOUBLE PRECISION NOT NULL DEFAULT 100.0,
    data_quality_score DOUBLE PRECISION NOT NULL DEFAULT 100.0,
    last_seen_at TIMESTAMPTZ NOT NULL,
    audited_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table 5: air_quality_readings (Raw High-Frequency Telemetry)
CREATE TABLE IF NOT EXISTS air_quality_readings (
    id BIGSERIAL PRIMARY KEY,
    station_id VARCHAR(64) NOT NULL REFERENCES monitoring_stations(id) ON DELETE CASCADE,
    pollutant_id VARCHAR(32) NOT NULL REFERENCES pollutants(id) ON DELETE RESTRICT,
    concentration DOUBLE PRECISION NOT NULL,
    raw_units VARCHAR(32) NOT NULL,
    observed_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table 6: aqi_computations (Official Derived CPCB NAQI)
CREATE TABLE IF NOT EXISTS aqi_computations (
    id BIGSERIAL PRIMARY KEY,
    station_id VARCHAR(64) NOT NULL REFERENCES monitoring_stations(id) ON DELETE CASCADE,
    aqi_value INTEGER NOT NULL CHECK (aqi_value >= 0),
    aqi_category aqi_category_enum NOT NULL,
    dominant_pollutant VARCHAR(32) NOT NULL REFERENCES pollutants(id),
    sub_indices JSONB NOT NULL DEFAULT '{}'::jsonb,
    computed_for TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table 7: weather_data
CREATE TABLE IF NOT EXISTS weather_data (
    id BIGSERIAL PRIMARY KEY,
    station_id VARCHAR(64) REFERENCES monitoring_stations(id) ON DELETE SET NULL,
    temperature_celsius DOUBLE PRECISION NOT NULL,
    relative_humidity_pct DOUBLE PRECISION NOT NULL CHECK (relative_humidity_pct BETWEEN 0 AND 100),
    wind_speed_kmh DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    wind_direction_degrees DOUBLE PRECISION NOT NULL DEFAULT 0.0 CHECK (wind_direction_degrees BETWEEN 0 AND 360),
    surface_pressure_hpa DOUBLE PRECISION NOT NULL DEFAULT 1013.25,
    recorded_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 1.4 MACHINE LEARNING & ANALYTICS TABLES (TABLES 8 - 14)
-- ----------------------------------------------------------------------------

-- Table 8: hotspot_events
CREATE TABLE IF NOT EXISTS hotspot_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cluster_name VARCHAR(255) NOT NULL,
    centroid_lat DOUBLE PRECISION NOT NULL,
    centroid_lng DOUBLE PRECISION NOT NULL,
    centroid_location GEOGRAPHY(Point, 4326) NOT NULL,
    severity_category aqi_category_enum NOT NULL,
    mean_aqi DOUBLE PRECISION NOT NULL,
    affected_station_count INTEGER NOT NULL DEFAULT 1,
    affected_stations JSONB NOT NULL DEFAULT '[]'::jsonb,
    detected_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table 9: predictions
CREATE TABLE IF NOT EXISTS predictions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    station_id VARCHAR(64) NOT NULL REFERENCES monitoring_stations(id) ON DELETE CASCADE,
    model_version VARCHAR(64) NOT NULL,
    forecast_start_time TIMESTAMPTZ NOT NULL,
    hourly_forecasts JSONB NOT NULL,
    generated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table 10: anomaly_events
CREATE TABLE IF NOT EXISTS anomaly_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    station_id VARCHAR(64) NOT NULL REFERENCES monitoring_stations(id) ON DELETE CASCADE,
    anomaly_type VARCHAR(64) NOT NULL,
    z_score DOUBLE PRECISION NOT NULL,
    confidence_percentage DOUBLE PRECISION NOT NULL,
    pollutant_deltas JSONB NOT NULL DEFAULT '{}'::jsonb,
    flagged_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table 11: model_registry
CREATE TABLE IF NOT EXISTS model_registry (
    id VARCHAR(64) PRIMARY KEY,
    algorithm VARCHAR(128) NOT NULL,
    target_variable VARCHAR(64) NOT NULL,
    features_used JSONB NOT NULL DEFAULT '[]'::jsonb,
    is_active_champion BOOLEAN NOT NULL DEFAULT TRUE,
    trained_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table 12: model_metrics
CREATE TABLE IF NOT EXISTS model_metrics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    model_id VARCHAR(64) NOT NULL REFERENCES model_registry(id) ON DELETE CASCADE,
    metric_mae DOUBLE PRECISION NOT NULL,
    metric_rmse DOUBLE PRECISION NOT NULL,
    metric_r2 DOUBLE PRECISION NOT NULL,
    evaluation_dataset_size INTEGER NOT NULL,
    evaluated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table 13: data_quality_logs
CREATE TABLE IF NOT EXISTS data_quality_logs (
    id BIGSERIAL PRIMARY KEY,
    check_type VARCHAR(64) NOT NULL,
    station_id VARCHAR(64) REFERENCES monitoring_stations(id) ON DELETE SET NULL,
    status VARCHAR(32) NOT NULL,
    details TEXT NOT NULL,
    checked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table 14: ingestion_runs
CREATE TABLE IF NOT EXISTS ingestion_runs (
    id BIGSERIAL PRIMARY KEY,
    job_name VARCHAR(128) NOT NULL,
    records_ingested INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(32) NOT NULL DEFAULT 'success',
    execution_time_ms INTEGER NOT NULL DEFAULT 0,
    executed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 1.5 USER, IDENTITY, EXPOSURE & COMMUNITY TABLES (TABLES 15 - 23)
-- ----------------------------------------------------------------------------

-- Table 15: profiles (Extends Supabase auth.users)
CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name VARCHAR(255) NOT NULL,
    role VARCHAR(64) NOT NULL DEFAULT 'citizen',
    email VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table 16: user_preferences
CREATE TABLE IF NOT EXISTS user_preferences (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE UNIQUE,
    health_persona VARCHAR(64) NOT NULL DEFAULT 'general',
    theme_mode VARCHAR(32) NOT NULL DEFAULT 'system',
    distance_unit VARCHAR(16) NOT NULL DEFAULT 'km',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table 17: saved_locations
CREATE TABLE IF NOT EXISTS saved_locations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    label VARCHAR(128) NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    location GEOGRAPHY(Point, 4326) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table 18: alerts
CREATE TABLE IF NOT EXISTS alerts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    alert_type alert_type_enum NOT NULL DEFAULT 'aqi_threshold',
    threshold_value INTEGER NOT NULL,
    station_id VARCHAR(64) REFERENCES monitoring_stations(id) ON DELETE CASCADE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table 19: notification_tokens
CREATE TABLE IF NOT EXISTS notification_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    device_token TEXT NOT NULL UNIQUE,
    device_platform VARCHAR(32) NOT NULL DEFAULT 'android',
    last_registered_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table 20: exposure_sessions
CREATE TABLE IF NOT EXISTS exposure_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    activity_type VARCHAR(64) NOT NULL DEFAULT 'walking',
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ,
    duration_minutes INTEGER,
    average_aqi DOUBLE PRECISION,
    peak_aqi INTEGER,
    inhaled_dose_score DOUBLE PRECISION,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table 21: exposure_points
CREATE TABLE IF NOT EXISTS exposure_points (
    id BIGSERIAL PRIMARY KEY,
    session_id UUID NOT NULL REFERENCES exposure_sessions(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    location GEOGRAPHY(Point, 4326) NOT NULL,
    nearest_station_id VARCHAR(64) NOT NULL REFERENCES monitoring_stations(id) ON DELETE CASCADE,
    distance_meters DOUBLE PRECISION NOT NULL,
    instantaneous_aqi INTEGER NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL
);

-- Table 22: citizen_reports
CREATE TABLE IF NOT EXISTS citizen_reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    incident_type incident_type_enum NOT NULL,
    description TEXT NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    location GEOGRAPHY(Point, 4326) NOT NULL,
    confirmation_votes INTEGER NOT NULL DEFAULT 1,
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    reported_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table 23: audit_logs
CREATE TABLE IF NOT EXISTS audit_logs (
    id BIGSERIAL PRIMARY KEY,
    action VARCHAR(128) NOT NULL,
    actor VARCHAR(128) NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'success',
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 1.6 INDEXES & CONSTRAINTS (B-Tree & PostGIS GIST)
-- ----------------------------------------------------------------------------

-- PostGIS Spatial GIST Indexes
CREATE INDEX IF NOT EXISTS idx_stations_location 
    ON monitoring_stations USING GIST(location);

CREATE INDEX IF NOT EXISTS idx_hotspots_centroid 
    ON hotspot_events USING GIST(centroid_location);

CREATE INDEX IF NOT EXISTS idx_saved_locations_geom 
    ON saved_locations USING GIST(location);

CREATE INDEX IF NOT EXISTS idx_exposure_points_geom 
    ON exposure_points USING GIST(location);

CREATE INDEX IF NOT EXISTS idx_citizen_reports_geom 
    ON citizen_reports USING GIST(location);

-- B-Tree Indexes for Fast Time-Series & Query Resolution
CREATE INDEX IF NOT EXISTS idx_readings_station_observed 
    ON air_quality_readings (station_id, observed_at DESC);

CREATE INDEX IF NOT EXISTS idx_aqi_station_computed 
    ON aqi_computations (station_id, computed_for DESC);

CREATE INDEX IF NOT EXISTS idx_status_station_health 
    ON station_status (station_id, audited_at DESC);

CREATE INDEX IF NOT EXISTS idx_exposure_session_user 
    ON exposure_sessions (user_id, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_alerts_user_active 
    ON alerts (user_id, is_active);

-- ----------------------------------------------------------------------------
-- 1.7 REAL-TIME REPLICATION PUBLICATION (Supabase Realtime)
-- ----------------------------------------------------------------------------
DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE 
        monitoring_stations,
        aqi_computations,
        alerts,
        exposure_sessions,
        citizen_reports;
EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- ----------------------------------------------------------------------------
-- 1.8 ROW LEVEL SECURITY (RLS) POLICIES
-- ----------------------------------------------------------------------------
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE saved_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE exposure_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE exposure_points ENABLE ROW LEVEL SECURITY;
ALTER TABLE citizen_reports ENABLE ROW LEVEL SECURITY;

-- Profiles Policy
CREATE POLICY "Public profiles are viewable by everyone" 
    ON profiles FOR SELECT USING (TRUE);
CREATE POLICY "Users can update own profile" 
    ON profiles FOR UPDATE USING (auth.uid() = id);

-- User Preferences Policy
CREATE POLICY "Users can manage own preferences" 
    ON user_preferences FOR ALL USING (auth.uid() = user_id);

-- Saved Locations Policy
CREATE POLICY "Users can manage own saved locations" 
    ON saved_locations FOR ALL USING (auth.uid() = user_id);

-- Alerts Policy
CREATE POLICY "Users can manage own alerts" 
    ON alerts FOR ALL USING (auth.uid() = user_id);

-- Exposure Sessions Policy
CREATE POLICY "Users can manage own exposure sessions" 
    ON exposure_sessions FOR ALL USING (auth.uid() = user_id);

-- Citizen Reports Policy (Public view, authenticated submit/vote)
CREATE POLICY "Citizen reports are viewable by everyone" 
    ON citizen_reports FOR SELECT USING (TRUE);
CREATE POLICY "Authenticated users can submit citizen reports" 
    ON citizen_reports FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Anyone can update vote counts" 
    ON citizen_reports FOR UPDATE USING (TRUE);

-- ----------------------------------------------------------------------------
-- 1.9 DATABASE TRIGGERS
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_profiles_updated_at ON profiles;
CREATE TRIGGER trg_profiles_updated_at
BEFORE UPDATE ON profiles
FOR EACH ROW EXECUTE FUNCTION set_updated_at_timestamp();

DROP TRIGGER IF EXISTS trg_user_preferences_updated_at ON user_preferences;
CREATE TRIGGER trg_user_preferences_updated_at
BEFORE UPDATE ON user_preferences
FOR EACH ROW EXECUTE FUNCTION set_updated_at_timestamp();


-- ============================================================================
-- SECTION 2: DATA MANIPULATION LANGUAGE (DML)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 2.1 INGESTION: SEED BASE METADATA
-- ----------------------------------------------------------------------------

-- Insert upstream providers into data_sources
INSERT INTO data_sources (id, name, provider_type, base_url, is_active)
VALUES
    ('cpcb', 'Central Pollution Control Board', 'government', 'https://api.data.gov.in', TRUE),
    ('safar', 'IITM SAFAR Pune Atmospheric Network', 'government', 'http://safar.tropmet.res.in', TRUE),
    ('openmeteo', 'European CAMS Atmospheric Telemetry', 'cams', 'https://air-quality-api.open-meteo.com', TRUE),
    ('citizen', 'Crowdsourced Pune Citizen Watch', 'crowdsourced', NULL, TRUE)
ON CONFLICT (id) DO UPDATE SET 
    name = EXCLUDED.name,
    is_active = EXCLUDED.is_active;

-- Insert core pollutants catalog
INSERT INTO pollutants (id, name, unit, averaging_hours, description)
VALUES
    ('pm25', 'Fine Particulate Matter (PM2.5)', 'ug/m3', 24, 'Microscopic airborne particles <= 2.5 micrometers penetrating deep into lungs'),
    ('pm10', 'Coarse Particulate Matter (PM10)', 'ug/m3', 24, 'Inhalable dust particles <= 10 micrometers originating from roads and construction'),
    ('no2', 'Nitrogen Dioxide', 'ug/m3', 24, 'Combustion gas emitted from vehicles and industrial plants'),
    ('so2', 'Sulphur Dioxide', 'ug/m3', 24, 'Pungent gas emitted from power generation and refineries'),
    ('co', 'Carbon Monoxide', 'mg/m3', 8, 'Colorless, odorless gas from incomplete vehicular tailpipe combustion'),
    ('o3', 'Surface Ozone', 'ug/m3', 8, 'Secondary photochemical oxidant formed under solar radiation'),
    ('aqi', 'Air Quality Index', 'index', 24, 'Composite Indian CPCB National Air Quality Index score')
ON CONFLICT (id) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 2.2 INGESTION: SEED OFFICIAL PUNE MONITORING STATIONS (With PostGIS Points)
-- ----------------------------------------------------------------------------
INSERT INTO monitoring_stations (id, name, source_id, latitude, longitude, location, elevation_meters, station_type, is_active)
VALUES
    ('shivajinagar-pune', 'Shivajinagar Weather Station', 'cpcb', 18.5314, 73.8446, ST_SetSRID(ST_MakePoint(73.8446, 18.5314), 4326)::geography, 560.0, 'residential', TRUE),
    ('katraj-pune', 'Katraj Zoo Environment Center', 'safar', 18.4529, 73.8552, ST_SetSRID(ST_MakePoint(73.8552, 18.4529), 4326)::geography, 610.0, 'residential', TRUE),
    ('hadapsar-pune', 'Hadapsar Mega Center CAAQMS', 'cpcb', 18.5089, 73.9260, ST_SetSRID(ST_MakePoint(73.9260, 18.5089), 4326)::geography, 570.0, 'traffic', TRUE),
    ('hinjawadi-phase1', 'Hinjawadi IT Park Phase 1', 'openmeteo', 18.5913, 73.7389, ST_SetSRID(ST_MakePoint(73.7389, 18.5913), 4326)::geography, 580.0, 'industrial', TRUE),
    ('kothrud-pune', 'Kothrud Ideal Colony Ground', 'safar', 18.5074, 73.8077, ST_SetSRID(ST_MakePoint(73.8077, 18.5074), 4326)::geography, 575.0, 'residential', TRUE),
    ('pashan-iitm', 'Pashan IITM Main Observatory', 'safar', 18.5398, 73.7978, ST_SetSRID(ST_MakePoint(73.7978, 18.5398), 4326)::geography, 590.0, 'background', TRUE),
    ('bhosari-pcmc', 'Bhosari MIDC Industrial Gate', 'cpcb', 18.6279, 73.8483, ST_SetSRID(ST_MakePoint(73.8483, 18.6279), 4326)::geography, 565.0, 'industrial', TRUE),
    ('alandi-pcmc', 'Alandi Indrayani Riverbank', 'openmeteo', 18.6775, 73.8967, ST_SetSRID(ST_MakePoint(73.8967, 18.6775), 4326)::geography, 560.0, 'residential', TRUE)
ON CONFLICT (id) DO UPDATE SET
    latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude,
    location = EXCLUDED.location;

-- ----------------------------------------------------------------------------
-- 2.3 TELEMETRY WRITES: RAW READINGS & DERIVED NAQI COMPUTATIONS
-- ----------------------------------------------------------------------------

-- Insert raw readings for Shivajinagar
INSERT INTO air_quality_readings (station_id, pollutant_id, concentration, raw_units, observed_at)
VALUES
    ('shivajinagar-pune', 'pm25', 75.4, 'ug/m3', NOW() - INTERVAL '15 minutes'),
    ('shivajinagar-pune', 'pm10', 142.0, 'ug/m3', NOW() - INTERVAL '15 minutes'),
    ('shivajinagar-pune', 'no2', 42.1, 'ug/m3', NOW() - INTERVAL '15 minutes'),
    ('shivajinagar-pune', 'so2', 18.5, 'ug/m3', NOW() - INTERVAL '15 minutes'),
    ('shivajinagar-pune', 'co', 1.4, 'mg/m3', NOW() - INTERVAL '15 minutes'),
    ('shivajinagar-pune', 'o3', 52.0, 'ug/m3', NOW() - INTERVAL '15 minutes');

-- Insert derived CPCB NAQI computation for Shivajinagar
INSERT INTO aqi_computations (station_id, aqi_value, aqi_category, dominant_pollutant, sub_indices, computed_for)
VALUES
    ('shivajinagar-pune', 149, 'Moderate', 'pm25', 
     '{"pm25": 149, "pm10": 128, "no2": 53, "so2": 23, "co": 65, "o3": 52}'::jsonb, 
     NOW() - INTERVAL '15 minutes');

-- Insert meteorological telemetry
INSERT INTO weather_data (station_id, temperature_celsius, relative_humidity_pct, wind_speed_kmh, wind_direction_degrees, surface_pressure_hpa, recorded_at)
VALUES
    ('shivajinagar-pune', 26.4, 62.0, 7.8, 245.0, 1012.8, NOW() - INTERVAL '15 minutes');

-- ----------------------------------------------------------------------------
-- 2.4 OPERATIONAL AUDIT: STATION STATUS & QA LOGS
-- ----------------------------------------------------------------------------
INSERT INTO station_status (station_id, health_status, packet_latency_seconds, uptime_percentage_24h, data_quality_score, last_seen_at)
VALUES
    ('shivajinagar-pune', 'online', 45, 98.5, 99.2, NOW() - INTERVAL '15 minutes'),
    ('hadapsar-pune', 'online', 60, 96.0, 97.8, NOW() - INTERVAL '20 minutes'),
    ('hinjawadi-phase1', 'online', 30, 99.0, 100.0, NOW() - INTERVAL '10 minutes')
ON CONFLICT DO NOTHING;

INSERT INTO data_quality_logs (check_type, station_id, status, details)
VALUES
    ('range_bounds', 'shivajinagar-pune', 'passed', 'PM2.5 (75.4 ug/m3) verified within physical threshold [0.0, 1000.0]'),
    ('rate_of_change', 'shivajinagar-pune', 'passed', 'Delta against previous reading (+3.2 ug/m3) within normal rate limits'),
    ('pm_ratio', 'shivajinagar-pune', 'passed', 'Plausibility check verified: PM2.5 (75.4) <= PM10 (142.0)');

-- ----------------------------------------------------------------------------
-- 2.5 MACHINE LEARNING: HOTSPOTS, ANOMALIES & PREDICTIONS
-- ----------------------------------------------------------------------------
INSERT INTO hotspot_events (cluster_name, centroid_lat, centroid_lng, centroid_location, severity_category, mean_aqi, affected_station_count, affected_stations)
VALUES
    ('Hadapsar-Manjri Industrial Corridor', 18.5120, 73.9310, 
     ST_SetSRID(ST_MakePoint(73.9310, 18.5120), 4326)::geography, 
     'Poor', 218.4, 3, '["hadapsar-pune", "magarpatta-pcmc", "manjri-farm"]'::jsonb);

INSERT INTO anomaly_events (station_id, anomaly_type, z_score, confidence_percentage, pollutant_deltas)
VALUES
    ('hadapsar-pune', 'smoke_plume', 3.42, 94.8, '{"co_spike_pct": 180, "pm25_spike_pct": 145}'::jsonb);

INSERT INTO model_registry (id, algorithm, target_variable, features_used, is_active_champion, trained_at)
VALUES
    ('pune_aqi_xgboost_24h', 'Gradient Boosted Decision Trees (XGBoost)', 'cpcb_overall_aqi', 
     '["pm25_lag1", "pm25_lag3", "pm10_lag1", "temp", "humidity", "wind_speed", "hour_sin", "hour_cos"]'::jsonb, 
     TRUE, NOW() - INTERVAL '1 day')
ON CONFLICT (id) DO NOTHING;

INSERT INTO model_metrics (model_id, metric_mae, metric_rmse, metric_r2, evaluation_dataset_size)
VALUES
    ('pune_aqi_xgboost_24h', 5.84, 8.92, 0.892, 14880);

-- ----------------------------------------------------------------------------
-- 2.6 CITIZEN WATCH: INCIDENT SUBMISSION & UPVOTING (DML UPDATE)
-- ----------------------------------------------------------------------------
INSERT INTO citizen_reports (id, incident_type, description, latitude, longitude, location, confirmation_votes, is_verified)
VALUES
    ('d4b68499-e45f-4a01-9a74-d2e8b2b9f390', 'garbage_burning', 
     'Dense smoke and burning municipal waste observed near riverbed', 
     18.5190, 73.8560, ST_SetSRID(ST_MakePoint(73.8560, 18.5190), 4326)::geography, 
     5, FALSE)
ON CONFLICT (id) DO NOTHING;

-- DML UPDATE: Community confirmation vote increment
UPDATE citizen_reports
SET confirmation_votes = confirmation_votes + 1
WHERE id = 'd4b68499-e45f-4a01-9a74-d2e8b2b9f390';

-- ----------------------------------------------------------------------------
-- 2.7 PERSONAL EXPOSURE ENGINE: SESSION LIFECYCLE (INSERT, UPDATE, DELETE)
-- ----------------------------------------------------------------------------

-- Step 1: User starts an outdoor session
INSERT INTO exposure_sessions (id, user_id, activity_type, status, started_at)
VALUES
    ('8f7c9e12-45a8-4b32-9c12-78d123e45678', 
     '2ded04ac-0981-46ed-9e5d-836661f89560', 
     'walking', 'active', NOW() - INTERVAL '30 minutes')
ON CONFLICT (id) DO NOTHING;

-- Step 2: Stream GPS breadcrumb into exposure_points
INSERT INTO exposure_points (session_id, latitude, longitude, location, nearest_station_id, distance_meters, instantaneous_aqi, recorded_at)
VALUES
    ('8f7c9e12-45a8-4b32-9c12-78d123e45678', 18.5320, 73.8450, 
     ST_SetSRID(ST_MakePoint(73.8450, 18.5320), 4326)::geography, 
     'shivajinagar-pune', 85.4, 149, NOW() - INTERVAL '25 minutes');

-- Step 3: Finish outdoor session (DML UPDATE with Dose Score)
UPDATE exposure_sessions
SET ended_at = NOW(),
    duration_minutes = 30,
    average_aqi = 142.5,
    peak_aqi = 165,
    inhaled_dose_score = 30 * 1.0 * (142.5 / 100.0), -- Duration * VentRate * (AvgAQI / 100)
    status = 'completed'
WHERE id = '8f7c9e12-45a8-4b32-9c12-78d123e45678';

-- ----------------------------------------------------------------------------
-- 2.8 HOUSEKEEPING DML: PURGE OLD DATA QUALITY LOGS (> 90 DAYS)
-- ----------------------------------------------------------------------------
DELETE FROM data_quality_logs
WHERE checked_at < NOW() - INTERVAL '90 days';


-- ============================================================================
-- SECTION 3: DATA QUERY LANGUAGE (DQL)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 3.1 BASIC RETRIEVAL: ACTIVE STATION ROSTER WITH LATEST AQI
-- ----------------------------------------------------------------------------
-- Fetches all active monitoring stations with coordinates, elevation, and source
SELECT 
    s.id AS station_code,
    s.name AS station_name,
    s.station_type,
    s.latitude,
    s.longitude,
    src.name AS telemetry_provider
FROM monitoring_stations s
LEFT JOIN data_sources src ON s.source_id = src.id
WHERE s.is_active = TRUE
ORDER BY s.name ASC;

-- ----------------------------------------------------------------------------
-- 3.2 SPATIAL POSTGIS QUERY: RESOLVE NEAREST STATION FROM GPS BREADCRUMB
-- ----------------------------------------------------------------------------
-- Given mobile user at FC Road Pune (Lat: 18.5204, Lng: 73.8410),
-- finds the closest active station using ellipsoidal geodesic distance.
SELECT 
    s.id,
    s.name,
    s.station_type,
    ROUND(ST_Distance(s.location, ST_SetSRID(ST_MakePoint(73.8410, 18.5204), 4326)::geography)::numeric, 1) AS distance_meters,
    latest.aqi_value,
    latest.aqi_category,
    latest.dominant_pollutant
FROM monitoring_stations s
LEFT JOIN LATERAL (
    SELECT aqi_value, aqi_category, dominant_pollutant
    FROM aqi_computations
    WHERE station_id = s.id
    ORDER BY computed_for DESC
    LIMIT 1
) latest ON TRUE
WHERE s.is_active = TRUE
ORDER BY s.location <-> ST_SetSRID(ST_MakePoint(73.8410, 18.5204), 4326)::geography
LIMIT 1;

-- ----------------------------------------------------------------------------
-- 3.3 SPATIAL RADIUS QUERY: ALL STATIONS WITHIN 5 KM RADIUS
-- ----------------------------------------------------------------------------
SELECT 
    s.id,
    s.name,
    ROUND((ST_Distance(s.location, ST_SetSRID(ST_MakePoint(73.8446, 18.5314), 4326)::geography) / 1000.0)::numeric, 2) AS dist_km
FROM monitoring_stations s
WHERE ST_DWithin(s.location, ST_SetSRID(ST_MakePoint(73.8446, 18.5314), 4326)::geography, 5000)
ORDER BY dist_km ASC;

-- ----------------------------------------------------------------------------
-- 3.4 COMPLEX MULTI-TABLE JOIN: CITY-WIDE MASTER DASHBOARD VIEW
-- ----------------------------------------------------------------------------
-- Joins 5 tables: stations, latest aqi, pollutants, station health, and weather
SELECT 
    s.id AS station_id,
    s.name AS station_name,
    c.aqi_value,
    c.aqi_category,
    c.dominant_pollutant,
    p.unit AS dominant_unit,
    st.health_status,
    st.uptime_percentage_24h,
    w.temperature_celsius,
    w.relative_humidity_pct,
    w.wind_speed_kmh,
    c.computed_for AS observation_timestamp
FROM monitoring_stations s
INNER JOIN LATERAL (
    SELECT aqi_value, aqi_category, dominant_pollutant, computed_for
    FROM aqi_computations
    WHERE station_id = s.id
    ORDER BY computed_for DESC
    LIMIT 1
) c ON TRUE
LEFT JOIN pollutants p ON c.dominant_pollutant = p.id
LEFT JOIN LATERAL (
    SELECT health_status, uptime_percentage_24h
    FROM station_status
    WHERE station_id = s.id
    ORDER BY audited_at DESC
    LIMIT 1
) st ON TRUE
LEFT JOIN LATERAL (
    SELECT temperature_celsius, relative_humidity_pct, wind_speed_kmh
    FROM weather_data
    WHERE station_id = s.id
    ORDER BY recorded_at DESC
    LIMIT 1
) w ON TRUE
WHERE s.is_active = TRUE
ORDER BY c.aqi_value DESC;

-- ----------------------------------------------------------------------------
-- 3.5 WINDOW FUNCTION: LATEST READING PER STATION WITH ROW_NUMBER()
-- ----------------------------------------------------------------------------
WITH RankedReadings AS (
    SELECT 
        r.station_id,
        s.name AS station_name,
        r.pollutant_id,
        r.concentration,
        r.raw_units,
        r.observed_at,
        ROW_NUMBER() OVER (PARTITION BY r.station_id, r.pollutant_id ORDER BY r.observed_at DESC) AS rn
    FROM air_quality_readings r
    JOIN monitoring_stations s ON r.station_id = s.id
)
SELECT 
    station_id,
    station_name,
    pollutant_id,
    concentration,
    raw_units,
    observed_at
FROM RankedReadings
WHERE rn = 1
ORDER BY station_name, pollutant_id;

-- ----------------------------------------------------------------------------
-- 3.6 TIME-SERIES AGGREGATION: 24-HOUR HOURLY TREND WITH DATE_TRUNC
-- ----------------------------------------------------------------------------
-- Produces hourly average AQI and peak values for Shivajinagar
SELECT 
    DATE_TRUNC('hour', computed_for) AS hourly_bucket,
    ROUND(AVG(aqi_value)::numeric, 1) AS avg_aqi,
    MIN(aqi_value) AS min_aqi,
    MAX(aqi_value) AS max_aqi,
    COUNT(*) AS computation_count
FROM aqi_computations
WHERE station_id = 'shivajinagar-pune'
  AND computed_for >= NOW() - INTERVAL '24 hours'
GROUP BY DATE_TRUNC('hour', computed_for)
ORDER BY hourly_bucket ASC;

-- ----------------------------------------------------------------------------
-- 3.7 AGGREGATION WITH GROUP BY & HAVING: DEGRADED STATIONS AUDIT
-- ----------------------------------------------------------------------------
-- Identifies any station where average 24h uptime has fallen below 90%
SELECT 
    s.id AS station_id,
    s.name AS station_name,
    ROUND(AVG(st.uptime_percentage_24h)::numeric, 2) AS avg_24h_uptime,
    MAX(st.packet_latency_seconds) AS max_latency_seconds,
    COUNT(st.id) AS audit_sample_count
FROM monitoring_stations s
JOIN station_status st ON s.id = st.station_id
WHERE st.audited_at >= NOW() - INTERVAL '24 hours'
GROUP BY s.id, s.name
HAVING AVG(st.uptime_percentage_24h) < 95.0
ORDER BY avg_24h_uptime ASC;

-- ----------------------------------------------------------------------------
-- 3.8 ANALYTICAL QUERY: CPCB NAQI LINEAR INTERPOLATION EMULATION IN SQL
-- ----------------------------------------------------------------------------
-- Emulates CPCB NAQI sub-index calculation directly within PostgreSQL using CASE
SELECT 
    station_id,
    concentration AS pm25_conc,
    CASE 
        -- Good (0 - 30 ug/m3 -> AQI 0 - 50)
        WHEN concentration <= 30 THEN 
            ROUND((50.0 / 30.0) * concentration)
        -- Satisfactory (31 - 60 ug/m3 -> AQI 51 - 100)
        WHEN concentration <= 60 THEN 
            ROUND(((100.0 - 51.0) / (60.0 - 31.0)) * (concentration - 31.0) + 51.0)
        -- Moderate (61 - 90 ug/m3 -> AQI 101 - 200)
        WHEN concentration <= 90 THEN 
            ROUND(((200.0 - 101.0) / (90.0 - 61.0)) * (concentration - 61.0) + 101.0)
        -- Poor (91 - 120 ug/m3 -> AQI 201 - 300)
        WHEN concentration <= 120 THEN 
            ROUND(((300.0 - 201.0) / (120.0 - 91.0)) * (concentration - 91.0) + 201.0)
        -- Very Poor (121 - 250 ug/m3 -> AQI 301 - 400)
        WHEN concentration <= 250 THEN 
            ROUND(((400.0 - 301.0) / (250.0 - 121.0)) * (concentration - 121.0) + 301.0)
        -- Severe (250+ ug/m3 -> AQI 401 - 500)
        ELSE 
            ROUND(((500.0 - 401.0) / (380.0 - 250.0)) * (concentration - 250.0) + 401.0)
    END AS computed_pm25_sub_index
FROM air_quality_readings
WHERE pollutant_id = 'pm25'
ORDER BY observed_at DESC
LIMIT 10;

-- ----------------------------------------------------------------------------
-- 3.9 PERSONAL EXPOSURE DOSAGE SUMMARY QUERY
-- ----------------------------------------------------------------------------
-- Summarizes outdoor exposure sessions for a user with total inhaled particulate load
SELECT 
    e.id AS session_id,
    e.activity_type,
    e.started_at,
    e.duration_minutes,
    ROUND(e.average_aqi::numeric, 1) AS avg_aqi,
    e.peak_aqi,
    ROUND(e.inhaled_dose_score::numeric, 2) AS inhaled_dose_score,
    COUNT(p.id) AS gps_breadcrumb_count,
    ROUND((AVG(p.distance_meters) / 1000.0)::numeric, 2) AS avg_dist_to_station_km
FROM exposure_sessions e
LEFT JOIN exposure_points p ON e.id = p.session_id
WHERE e.user_id = '2ded04ac-0981-46ed-9e5d-836661f89560'
  AND e.status = 'completed'
GROUP BY e.id
ORDER BY e.started_at DESC;

-- ----------------------------------------------------------------------------
-- 3.10 CITIZEN WATCH INCIDENTS WITH VOTE RANKING (DQL)
-- ----------------------------------------------------------------------------
SELECT 
    c.id,
    c.incident_type,
    c.description,
    c.latitude,
    c.longitude,
    c.confirmation_votes,
    c.is_verified,
    c.reported_at,
    RANK() OVER (ORDER BY c.confirmation_votes DESC) AS community_urgency_rank
FROM citizen_reports c
WHERE c.reported_at >= NOW() - INTERVAL '7 days'
ORDER BY c.confirmation_votes DESC;

-- ============================================================================
-- END OF COMPLETE DDL, DML, AND DQL MASTER SCRIPT
-- ============================================================================
