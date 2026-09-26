# AIRAWare Handbook — Setup, Run, and Flow

This covers everything needed to get the current build (Phase 0–2) running
end to end, and exactly how data moves through the system.

---

## 1. What you need before starting

| Requirement | Why | Where to get it |
|---|---|---|
| A Supabase project | Database + Auth | https://supabase.com — you said you already have one |
| Python 3.11+ | Runs the FastAPI backend | https://python.org |
| Flutter SDK 3.24+ | Runs the mobile app | https://flutter.dev (install on your own machine — not available in this sandbox) |
| An OpenAQ API key (free) | Real Pune station data | https://explore.openaq.org/register |
| A data.gov.in API key (free) | Real CPCB station data | https://www.data.gov.in/user/register → My Account → API Key |
| Android emulator, iOS simulator, or a physical phone | To actually run the Flutter app | Comes with Flutter/Xcode/Android Studio |

No key for weather — the default provider (Open-Meteo) is free and keyless.

---

## 2. Step-by-step: Database (Supabase)

1. Open your Supabase project → **SQL Editor**.
2. Open `backend/migrations/0001_core_schema.sql` from this repo, copy its
   full contents, paste into the SQL Editor, and run it.
   - It's idempotent (`if not exists` everywhere) — safe to re-run.
   - It enables the `postgis` extension (needed for station distance
     queries) and `uuid-ossp`. If your project blocks extensions, enable
     PostGIS first via **Database → Extensions** in the Supabase dashboard.
3. Confirm tables exist: **Table Editor** should now show `monitoring_stations`,
   `air_quality_readings`, `aqi_computations`, `pollutants`, `data_sources`,
   etc.
4. Copy three values from **Project Settings → API**:
   - `Project URL` → this is `SUPABASE_URL`
   - `anon public` key → this is `SUPABASE_ANON_KEY`
   - `service_role` key → this is `SUPABASE_SERVICE_ROLE_KEY` (**backend only, never in Flutter**)
5. Copy the direct Postgres connection string from **Project Settings →
   Database → Connection string → URI** → this is `DATABASE_URL`.

---

## 3. Step-by-step: Backend (FastAPI)

```bash
cd backend
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt

cp .env.example .env
# now edit .env and fill in:
#   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY, DATABASE_URL
#   OPENAQ_API_KEY        (from explore.openaq.org)
#   CPCB_DATAGOVIN_API_KEY (from data.gov.in)

uvicorn app.main:app --reload
```

Then verify:

```bash
curl http://localhost:8000/health
```

You should see `openaq_configured: true` and `cpcb_configured: true` if the
keys are filled in. If either is `false`, that provider will be skipped by
the scheduler (not faked) until you add the key.

Open `http://localhost:8000/docs` for the interactive Swagger UI — every
endpoint listed there is real and callable right now.

---

## 4. Step-by-step: first real data pull

The scheduler (APScheduler, started automatically with the app) polls on
its own once running — but the very **first** run only happens once you
trigger station discovery, because polling for observations needs stations
to already exist in the database. Trigger it manually once via the admin
endpoint (this is the one legitimate use of "Sync Now" per spec section 11):

```bash
# You'll need a real Supabase session token for an admin user — see
# step 5 below for how to make your first user an admin.
curl -X POST "http://localhost:8000/api/v1/admin/sync?provider_code=openaq" \
  -H "Authorization: Bearer <your-supabase-access-token>"

curl -X POST "http://localhost:8000/api/v1/admin/sync?provider_code=cpcb_datagovin" \
  -H "Authorization: Bearer <your-supabase-access-token>"
```

Then check what actually landed in the database:

```bash
curl http://localhost:8000/api/v1/pune/stations
```

If `cpcb_datagovin` returns `unresolved_station_names` in the sync
response, that's expected and honest — see §7 "CPCB coordinate mapping"
below; those stations are real but skipped until you verify their
coordinates.

---

## 5. Making yourself an admin

Admin registration is deliberately not public-facing (spec section 36).
After you sign up once through the Flutter app (or via Supabase's own Auth
UI), promote your account manually in Supabase's SQL Editor:

```sql
update profiles set role = 'admin' where id =
  (select id from auth.users where email = 'you@example.com');
```

(The `profiles` row is created automatically the first time that user logs
in, via Supabase Auth — if it doesn't exist yet, sign in through the app
once first.)

---

## 6. Step-by-step: Flutter app

```bash
cd flutter
flutter pub get

cp .env.example .env
# edit .env: SUPABASE_URL, SUPABASE_ANON_KEY (same values as backend),
# and API_BASE_URL pointing at your running backend.
#   - Android emulator reaching your laptop: http://10.0.2.2:8000/api/v1
#   - iOS simulator reaching your laptop:     http://localhost:8000/api/v1
#   - Physical phone: use your laptop's LAN IP, e.g. http://192.168.1.20:8000/api/v1

flutter analyze     # run this yourself — no Dart SDK was available in the
                     # sandbox that built this, so this hasn't been verified yet
flutter run
```

**Important:** this backend has no HTTPS/TLS configured for local
development — that's expected for `localhost`/LAN testing, but before any
real device outside your network talks to it, put it behind HTTPS (see
`docs/SECURITY.md`, not yet written in this phase — flagged as a Phase 26
item).

---

## 7. How to actually use the app right now

| Screen | What it does | Backed by |
|---|---|---|
| **Login / Sign up** | Real Supabase Auth — email+password | `auth.users`, `profiles` |
| **Home** | Shows the freshest-reporting station's AQI as a hero card. Shows an honest empty state if no station has fresh data yet. | `GET /api/v1/pune/stations` |
| **Explore (map)** | OpenStreetMap tiles + one marker per real station, colored by AQI category. Tap a marker → station detail. | `GET /api/v1/pune/map` |
| **Station Detail** | Current AQI, per-pollutant readings, location-type transparency ("Directly measured" vs "Mapped station reading" etc.) | `GET /api/v1/pune/stations/{id}` |
| **Insights / Alerts / Profile** | Explicitly marked "not built yet" with the phase that will add them — intentionally honest placeholders, not fake data. | — |

---

## 8. End-to-end data flow (how a number gets onto your phone)

```
1. External provider (OpenAQ / CPCB via data.gov.in)
      │  real HTTP GET, requires your API key
      ▼
2. Backend provider class (OpenAQProvider / CPCBProvider)
      │  parses response into RawStation / RawObservation — skips anything
      │  it can't map to a real coordinate or known pollutant, never guesses
      ▼
3. Ingestion service (app/services/ingestion_service.py)
      │  upserts monitoring_stations
      │  validates each reading (app/services/data_quality.py)
      │  inserts air_quality_readings (only if it passes hard checks)
      ▼
4. AQI calculator (app/services/aqi_calculator.py)
      │  CPCB sub-index method across whatever pollutants passed validation
      │  writes aqi_computations (aqi_value, category, dominant_pollutant)
      ▼
5. Supabase Postgres (source of truth)
      ▼
6. FastAPI read endpoints (/pune/stations, /pune/map, /pune/stations/{id})
      │  plain SQL reads — no caching layer yet, so this is always current
      │  as of the last successful ingestion run
      ▼
7. Flutter repository (PuneApiRepository) → Riverpod providers
      ▼
8. Screens (Home hero card, Explore map markers, Station Detail)
```

**What's not yet in this chain:** Supabase Realtime push (Phase 10) — right
now Flutter pulls on screen load / pull-to-refresh, it doesn't get pushed
updates the instant new data lands. That's the very next phase to build.

---

## 9. CPCB coordinate mapping (an honest limitation, not a bug)

The data.gov.in CPCB dataset gives you station **name** and pollutant
values, but not latitude/longitude per record. Rather than guess
coordinates, `CPCBProvider` only accepts a station once you've added a
verified coordinate to
`backend/app/services/providers/station_coordinates.json` (or via
`POST /api/v1/admin/stations` once that endpoint is built out in a later
phase). Until then, CPCB stations show up as "unresolved" in the sync
response and are simply not added to the map — which is the correct, honest
behavior per the project's own "no fake stations" rule.

To resolve one: look up the station's real address on
https://airquality.cpcb.gov.in/AQI_India/, note the coordinates, add:

```json
"Exact Station Name From API": { "lat": 18.xxxx, "lng": 73.xxxx }
```

---

## 10. Troubleshooting

| Symptom | Likely cause |
|---|---|
| `/health` shows `openaq_configured: false` | `OPENAQ_API_KEY` missing/blank in `backend/.env` |
| Admin sync returns `"not_configured"` | Same — provider key missing |
| Admin sync succeeds but `/pune/stations` is empty | Check `stations_found` in the sync response; if 0, your bbox or the provider genuinely has no stations there right now |
| Flutter shows "Network error reaching AIRAWare backend" | `API_BASE_URL` in `flutter/.env` doesn't match how your emulator/device reaches your machine (see §6) |
| Flutter login fails immediately | `SUPABASE_URL`/`SUPABASE_ANON_KEY` mismatch between backend and Flutter `.env`, or email confirmation is required and pending |
| CPCB sync returns many `unresolved_station_names` | Expected — see §9 |

---

## 11. What to build next (phase order)

Pick up at **Phase 3** (aggregation/backfill), then **Phase 10** (Supabase
Realtime — replace polling with live push to the map/hero card), following
the same phase order as the original spec (section 55). Each phase should
be verified the same way this one was: real API calls tested, real
calculations tested with sample numbers, imports/syntax verified, before
moving on.
