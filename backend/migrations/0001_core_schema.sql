-- AIRAWare :: 0001_core_schema.sql
-- Pune Air Quality Intelligence Platform — core schema
-- Run via Supabase SQL editor or `supabase db push`
-- Safe to run once. Uses IF NOT EXISTS everywhere so re-running is non-destructive.

create extension if not exists "uuid-ossp";
create extension if not exists postgis;   -- for geography/distance queries on stations

-- =========================================================
-- ENUM TYPES
-- =========================================================
do $$ begin
  create type location_type_enum as enum ('measured_station','mapped_station','estimated','modelled');
exception when duplicate_object then null; end $$;

do $$ begin
  create type data_quality_enum as enum ('excellent','good','fair','poor','unavailable');
exception when duplicate_object then null; end $$;

do $$ begin
  create type station_health_enum as enum ('healthy','warning','offline','unknown');
exception when duplicate_object then null; end $$;

do $$ begin
  create type user_role_enum as enum ('user','researcher','admin');
exception when duplicate_object then null; end $$;

do $$ begin
  create type alert_type_enum as enum ('aqi_threshold','pm25_threshold','pollutant_threshold','forecast','anomaly','saved_location','data_quality');
exception when duplicate_object then null; end $$;

-- =========================================================
-- PROFILES (extends Supabase auth.users)
-- =========================================================
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role user_role_enum not null default 'user',
  home_location_id uuid,
  college_location_id uuid,
  office_location_id uuid,
  notification_prefs jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deactivated_at timestamptz
);

-- =========================================================
-- DATA SOURCES (provider registry)
-- =========================================================
create table if not exists data_sources (
  id uuid primary key default uuid_generate_v4(),
  code text unique not null,            -- 'openaq', 'cpcb_datagovin', 'weather_xyz'
  display_name text not null,
  base_url text,
  typical_refresh_minutes int not null default 15,
  requires_api_key boolean not null default true,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- =========================================================
-- POLLUTANTS (reference table)
-- =========================================================
create table if not exists pollutants (
  id uuid primary key default uuid_generate_v4(),
  code text unique not null,            -- 'pm25','pm10','no2','so2','o3','co','nh3'
  display_name text not null,
  unit text not null                    -- 'µg/m³' or 'mg/m³'
);

insert into pollutants (code, display_name, unit) values
  ('pm25','PM2.5','µg/m³'),
  ('pm10','PM10','µg/m³'),
  ('no2','NO2','µg/m³'),
  ('so2','SO2','µg/m³'),
  ('o3','O3','µg/m³'),
  ('co','CO','mg/m³'),
  ('nh3','NH3','µg/m³')
on conflict (code) do nothing;

-- =========================================================
-- MONITORING STATIONS / LOCATIONS (Pune registry)
-- =========================================================
create table if not exists monitoring_stations (
  id uuid primary key default uuid_generate_v4(),
  name text not null,                          -- e.g. "Bhosari", "Karve Road"
  area text,                                    -- locality label used in UI
  location_type location_type_enum not null default 'estimated',
  data_source_id uuid references data_sources(id),
  external_station_id text,                     -- provider's own station/location id
  latitude double precision not null,
  longitude double precision not null,
  geog geography(Point,4326) generated always as (
    ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
  ) stored,
  is_active boolean not null default true,
  health station_health_enum not null default 'unknown',
  last_observation_at timestamptz,
  last_ingested_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deactivated_at timestamptz,
  unique (data_source_id, external_station_id)
);

create index if not exists idx_stations_geog on monitoring_stations using gist (geog);
create index if not exists idx_stations_active on monitoring_stations (is_active);

-- =========================================================
-- RAW POLLUTANT OBSERVATIONS (time-series, one row per pollutant reading)
-- =========================================================
create table if not exists air_quality_readings (
  id uuid primary key default uuid_generate_v4(),
  station_id uuid not null references monitoring_stations(id) on delete cascade,
  pollutant_id uuid not null references pollutants(id),
  observed_at timestamptz not null,     -- when the sensor took the reading
  ingested_at timestamptz not null default now(),
  value double precision not null,
  unit text not null,
  source text not null,
  quality_score smallint,              -- 0-100, filled by validation pipeline
  quality_flag data_quality_enum,
  is_valid boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists idx_readings_station_time on air_quality_readings (station_id, observed_at desc);
create index if not exists idx_readings_pollutant on air_quality_readings (pollutant_id, observed_at desc);
-- prevent duplicate ingestion of the same (station, pollutant, observed_at)
create unique index if not exists uq_reading_dedup on air_quality_readings (station_id, pollutant_id, observed_at);

-- =========================================================
-- COMPUTED AQI (one row per station per computation, not per pollutant)
-- =========================================================
create table if not exists aqi_computations (
  id uuid primary key default uuid_generate_v4(),
  station_id uuid not null references monitoring_stations(id) on delete cascade,
  computed_for timestamptz not null,      -- the observation timestamp this AQI represents
  aqi_value int not null,
  aqi_category text not null,             -- Good / Satisfactory / Moderate / Poor / Very Poor / Severe (CPCB) 
  dominant_pollutant text not null,
  standard text not null default 'CPCB-NAQI-2014',
  quality_score smallint,
  created_at timestamptz not null default now(),
  unique (station_id, computed_for)
);

create index if not exists idx_aqi_station_time on aqi_computations (station_id, computed_for desc);

-- =========================================================
-- WEATHER
-- =========================================================
create table if not exists weather_data (
  id uuid primary key default uuid_generate_v4(),
  station_id uuid references monitoring_stations(id) on delete set null,
  latitude double precision,
  longitude double precision,
  observed_at timestamptz not null,
  temperature_c double precision,
  humidity_pct double precision,
  wind_speed_ms double precision,
  wind_direction_deg double precision,
  pressure_hpa double precision,
  rainfall_mm double precision,
  source text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_weather_time on weather_data (observed_at desc);

-- =========================================================
-- STATION STATUS / HEALTH LOG
-- =========================================================
create table if not exists station_status (
  id uuid primary key default uuid_generate_v4(),
  station_id uuid not null references monitoring_stations(id) on delete cascade,
  checked_at timestamptz not null default now(),
  health station_health_enum not null,
  minutes_since_last_update int,
  data_quality_pct smallint,
  note text
);

create index if not exists idx_station_status_station on station_status (station_id, checked_at desc);

-- =========================================================
-- DATA QUALITY LOGS (validation pipeline audit trail)
-- =========================================================
create table if not exists data_quality_logs (
  id uuid primary key default uuid_generate_v4(),
  reading_id uuid references air_quality_readings(id) on delete cascade,
  station_id uuid references monitoring_stations(id),
  check_name text not null,             -- e.g. 'negative_value','future_timestamp','stale'
  passed boolean not null,
  detail text,
  created_at timestamptz not null default now()
);

-- =========================================================
-- INGESTION RUNS (per scheduler job execution)
-- =========================================================
create table if not exists ingestion_runs (
  id uuid primary key default uuid_generate_v4(),
  job_name text not null,               -- 'openaq_latest', 'cpcb_latest', 'weather_refresh', ...
  data_source_id uuid references data_sources(id),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  status text not null default 'running',  -- running | success | partial | failed
  records_fetched int default 0,
  records_inserted int default 0,
  records_rejected int default 0,
  error_message text
);

create index if not exists idx_ingestion_runs_job on ingestion_runs (job_name, started_at desc);

-- =========================================================
-- ML: predictions, model registry, metrics
-- =========================================================
create table if not exists model_registry (
  id uuid primary key default uuid_generate_v4(),
  model_name text not null,             -- 'AQI-XGB'
  version text not null,                -- 'v1','v2'
  algorithm text not null default 'xgboost',
  trained_on_start timestamptz,
  trained_on_end timestamptz,
  features jsonb,
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  unique (model_name, version)
);

create table if not exists model_metrics (
  id uuid primary key default uuid_generate_v4(),
  model_id uuid not null references model_registry(id) on delete cascade,
  mae double precision,
  rmse double precision,
  r2 double precision,
  evaluated_at timestamptz not null default now()
);

create table if not exists predictions (
  id uuid primary key default uuid_generate_v4(),
  station_id uuid not null references monitoring_stations(id) on delete cascade,
  model_id uuid references model_registry(id),
  target_time timestamptz not null,     -- the future time this predicts
  horizon_minutes int not null,         -- 60 / 360 / 1440
  predicted_aqi double precision not null,
  confidence double precision,
  top_factors jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_predictions_station_target on predictions (station_id, target_time);

-- =========================================================
-- ANOMALIES + HOTSPOTS
-- =========================================================
create table if not exists anomaly_events (
  id uuid primary key default uuid_generate_v4(),
  station_id uuid references monitoring_stations(id) on delete cascade,
  detected_at timestamptz not null default now(),
  observed_at timestamptz not null,
  anomaly_type text not null,           -- 'aqi_spike','pollutant_spike','sensor_anomaly','missing_data'
  severity text,
  detail jsonb,
  method text not null default 'isolation_forest'
);

create table if not exists hotspot_events (
  id uuid primary key default uuid_generate_v4(),
  cluster_id text not null,
  detected_at timestamptz not null default now(),
  window_start timestamptz not null,
  window_end timestamptz not null,
  center_lat double precision not null,
  center_lng double precision not null,
  radius_m double precision,
  avg_aqi double precision,
  peak_aqi double precision,
  dominant_pollutant text,
  station_count int,
  confidence double precision,
  method text not null default 'dbscan'
);

-- =========================================================
-- USER-FACING: saved locations, preferences, alerts, exposure, notifications
-- =========================================================
create table if not exists saved_locations (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references profiles(id) on delete cascade,
  label text not null,                  -- 'Home','College','Office','Custom'
  latitude double precision not null,
  longitude double precision not null,
  nearest_station_id uuid references monitoring_stations(id),
  created_at timestamptz not null default now()
);

create table if not exists user_preferences (
  user_id uuid primary key references profiles(id) on delete cascade,
  units text not null default 'metric',
  theme text not null default 'system',
  updated_at timestamptz not null default now()
);

create table if not exists alerts (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references profiles(id) on delete cascade,
  alert_type alert_type_enum not null,
  saved_location_id uuid references saved_locations(id) on delete cascade,
  pollutant_code text,
  threshold_value double precision,
  is_enabled boolean not null default true,
  cooldown_minutes int not null default 60,
  last_triggered_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists notification_tokens (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references profiles(id) on delete cascade,
  platform text not null,               -- 'ios','android'
  token text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (user_id, token)
);

create table if not exists exposure_sessions (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references profiles(id) on delete cascade,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  duration_seconds int,
  avg_aqi double precision,
  peak_aqi double precision,
  peak_at timestamptz,
  relative_exposure_score smallint,
  created_at timestamptz not null default now()
);

-- generalized (privacy-conscious) route points, not raw continuous GPS
create table if not exists exposure_points (
  id uuid primary key default uuid_generate_v4(),
  session_id uuid not null references exposure_sessions(id) on delete cascade,
  sampled_at timestamptz not null,
  latitude double precision not null,
  longitude double precision not null,
  nearest_station_id uuid references monitoring_stations(id),
  aqi_at_point double precision,
  is_estimated boolean not null default false
);

create table if not exists audit_logs (
  id uuid primary key default uuid_generate_v4(),
  actor_id uuid references profiles(id),
  action text not null,
  entity_type text,
  entity_id text,
  detail jsonb,
  created_at timestamptz not null default now()
);

-- =========================================================
-- ROW LEVEL SECURITY
-- =========================================================
alter table profiles enable row level security;
alter table saved_locations enable row level security;
alter table user_preferences enable row level security;
alter table alerts enable row level security;
alter table notification_tokens enable row level security;
alter table exposure_sessions enable row level security;
alter table exposure_points enable row level security;

-- profiles: user can read/update only their own row
drop policy if exists profiles_self on profiles;
create policy profiles_self on profiles for select using (auth.uid() = id);
drop policy if exists profiles_self_update on profiles;
create policy profiles_self_update on profiles for update using (auth.uid() = id);

-- saved_locations: owner only
drop policy if exists saved_locations_owner on saved_locations;
create policy saved_locations_owner on saved_locations for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- user_preferences: owner only
drop policy if exists user_preferences_owner on user_preferences;
create policy user_preferences_owner on user_preferences for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- alerts: owner only
drop policy if exists alerts_owner on alerts;
create policy alerts_owner on alerts for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- notification_tokens: owner only
drop policy if exists notif_tokens_owner on notification_tokens;
create policy notif_tokens_owner on notification_tokens for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- exposure_sessions / points: owner only
drop policy if exists exposure_sessions_owner on exposure_sessions;
create policy exposure_sessions_owner on exposure_sessions for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists exposure_points_owner on exposure_points;
create policy exposure_points_owner on exposure_points for all
  using (auth.uid() = (select user_id from exposure_sessions s where s.id = session_id));

-- Public read tables (stations, readings, aqi, weather, hotspots, anomalies) stay open-read
-- because they are public environmental data, not personal data. No RLS needed there.
