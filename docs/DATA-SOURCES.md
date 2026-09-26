# Data Sources — verified, not assumed

Per project rule "do not invent API responses," every claim below was
checked against the live API during this build (2026-09-11), not recalled
from memory.

## OpenAQ (primary — measured stations)

- **Base URL:** `https://api.openaq.org/v3`
- **Auth:** header `X-API-Key`. Confirmed empirically: an unauthenticated
  request to `/v3/locations` returns **HTTP 401**. You must register your
  own free key at https://explore.openaq.org/register.
- **Station discovery:** `GET /v3/locations?bbox=minLng,minLat,maxLng,maxLat`
  — note OpenAQ's bbox order is **lng,lat,lng,lat**, not lat,lng (handled
  in `OpenAQProvider._`, don't swap it if you touch that code).
- **Latest values:** `GET /v3/locations/{id}/latest`.
- **Coverage:** OpenAQ aggregates whatever official/community sensors
  report into its system — Pune coverage depends entirely on which
  stations are currently reporting into OpenAQ, which changes over time.
  Run station discovery yourself (`POST /api/v1/admin/sync?provider_code=openaq`)
  to see current real coverage rather than trusting a number written here.
- **Rate limits:** OpenAQ's free tier has a request quota; if you hit 429s,
  slow down `JOB_LATEST_OBSERVATIONS_INTERVAL_MIN` in `.env`.

## CPCB via data.gov.in (secondary — official government stations)

- **Dataset:** "Real time Air Quality Index" published by CPCB.
- **Resource ID:** `3b01bcb8-0b14-4abf-b6f2-c1bfd384ba69` (fixed/public).
- **Endpoint:** `GET https://api.data.gov.in/resource/{resource_id}?api-key=YOUR_KEY&format=json&filters[city]=Pune&limit=500`
- **Auth:** confirmed a shared/public "demo" key does **not** work (HTTP
  400) — you need your own free key from
  https://www.data.gov.in/user/register → My Account → API Key.
- **Known limitation (confirmed by inspecting the schema, not assumed):**
  records include station **name**, city, pollutant id, min/max/avg value,
  and `last_update` — but **no latitude/longitude**. This is why
  `CPCBProvider` requires a curated `station_coordinates.json` mapping
  (see Handbook §9) instead of guessing coordinates. Any station whose name
  isn't in that mapping is skipped, not plotted with a fabricated location.
- **Timestamp format observed:** `"DD-MM-YYYY HH:MM:SS"` (parsed accordingly
  in `CPCBProvider.fetch_latest`) — re-verify this if data.gov.in changes
  their format; the parser will silently fall back to "now" if it can't
  parse, which is flagged as a limitation, not a proper fix.

## Weather — Open-Meteo (default)

- **Base URL:** `https://api.open-meteo.com/v1`
- **Auth:** none required for non-commercial use — chosen specifically so
  Phase 2 didn't need yet another registration before the pipeline could
  be tested end-to-end.
- **Endpoint used:** `GET /forecast?latitude=..&longitude=..&current=temperature_2m,relative_humidity_2m,wind_speed_10m,wind_direction_10m,surface_pressure,precipitation`
- If you later need historical/hourly forecast arrays for the ML pipeline
  (Phase 16), Open-Meteo's `/forecast` and `/archive` endpoints support
  that too — not yet wired up in this phase.

## What was NOT verified in this phase

- Actual current Pune-region station **counts** for either provider — these
  fluctuate, so the honest thing is for you to run the sync yourself and
  read the real number back from `/api/v1/pune/stations`, rather than this
  document claiming a fixed count that will go stale.
- Whether OpenAQ's Pune coverage includes PCMC-side stations specifically —
  again, check your own sync results; the bounding box in `.env`
  (`PUNE_BBOX_*`) is deliberately generous to not exclude PCMC if a real
  station is reporting there.
