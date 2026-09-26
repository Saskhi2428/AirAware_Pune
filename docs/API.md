# API Reference — Phase 0–2 endpoints

Base URL: `{API_V1_PREFIX}` = `/api/v1` (see `backend/.env`)

All responses use the envelope:
```json
{ "success": true, "data": {...}, "message": null, "timestamp": "..." }
```
or on failure:
```json
{ "success": false, "data": null, "message": "...", "error_code": "...", "timestamp": "..." }
```

## Public (no auth)

### `GET /pune/stations`
All active Pune-region stations with their latest computed AQI, health,
and freshness (`fresh` / `delayed` / `stale` / `unavailable`).

### `GET /pune/map`
Same as above, trimmed to what a map marker needs (id, coords, AQI, health).

### `GET /pune/stations/{station_id}`
Full detail: station metadata, latest AQI + dominant pollutant, every
pollutant's latest individual reading with its quality score/flag.

### `GET /pune/stations/{station_id}/history?hours=24`
Historical AQI computations for that station over the given window.

### `GET /pune/weather?lat=..&lng=..`
Live weather at a coordinate (Open-Meteo passthrough, always current).

## Admin (requires `Authorization: Bearer <supabase-access-token>` for a
user whose `profiles.role = 'admin'`)

### `GET /admin/dashboard`
Live counts: total users, total/healthy/offline stations, records ingested
in the last 24h, last successful ingestion time, failed ingestion count,
active alerts, anomalies/hotspots in the last 24h.

### `GET /admin/ingestion?limit=50`
Recent ingestion run log — job name, status, fetched/inserted/rejected
counts, error message if failed.

### `POST /admin/sync?provider_code=openaq|cpcb_datagovin`
Manually triggers station discovery + latest-observation fetch for one
provider. This is the "SYNC NOW" emergency action from spec section 11 —
normal operation relies on the scheduler, not this endpoint.

## Not yet built (see HANDBOOK.md §11 for phase order)

`/pune/hotspots`, `/pune/anomalies`, `/pune/insights`, `/pune/compare`,
`/pune/best-time`, `/pune/forecast`, `/exposure/*`, `/saved-locations`,
`/alerts`, `/admin/stations` (add/edit), `/admin/models/*`,
`/admin/audit-logs`.
