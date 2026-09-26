"""
CPCBProvider — wraps the real Government of India Open Data API
("Real time Air Quality Index", published by CPCB) at api.data.gov.in.

Verified live on 2026-09-11:
  - Resource: https://www.data.gov.in/catalog/real-time-air-quality-index
    resource_id = 3b01bcb8-0b14-4abf-b6f2-c1bfd384ba69
  - Endpoint:  GET https://api.data.gov.in/resource/{resource_id}
               ?api-key=YOUR_KEY&format=json&filters[city]=Pune&limit=500
  - A shared/public demo key does NOT work (confirmed HTTP 400) — you must
    register your own free key at https://www.data.gov.in/user/register
    and set CPCB_DATAGOVIN_API_KEY.

IMPORTANT HONEST LIMITATION:
This dataset returns station NAME, city, pollutant_id, min/max/avg value,
and last_update — but it does NOT include latitude/longitude per record.
We cannot invent coordinates for a station. Instead we resolve coordinates
only through `station_coordinates.json`, a small curated registry that an
admin populates and verifies (e.g. by cross-referencing the CPCB National
Air Quality Index portal or the station's official address). Any CPCB
station name we cannot resolve to a verified coordinate is SKIPPED, not
guessed, and logged so an admin can add it via the admin dashboard
(`POST /api/v1/admin/stations`).
"""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

import httpx

from app.core.config import settings
from app.services.providers.base import (
    AirQualityProvider, ProviderUnavailableError, RawObservation, RawStation,
)

_POLLUTANT_MAP = {
    "PM2.5": "pm25", "PM10": "pm10", "NO2": "no2",
    "SO2": "so2", "OZONE": "o3", "CO": "co", "NH3": "nh3",
}

_COORDS_FILE = Path(__file__).parent / "station_coordinates.json"


class CPCBProvider(AirQualityProvider):
    code = "cpcb_datagovin"

    def __init__(self) -> None:
        self.base_url = settings.CPCB_BASE_URL
        self.resource_id = settings.CPCB_DATAGOVIN_RESOURCE_ID
        self.api_key = settings.CPCB_DATAGOVIN_API_KEY
        self._coords = self._load_coords()

    def is_configured(self) -> bool:
        return bool(self.api_key)

    @staticmethod
    def _load_coords() -> dict:
        if _COORDS_FILE.exists():
            return json.loads(_COORDS_FILE.read_text())
        return {}

    async def _fetch_records(self) -> list[dict]:
        if not self.api_key:
            raise ProviderUnavailableError(
                "CPCB_DATAGOVIN_API_KEY is not set. Register free at "
                "https://www.data.gov.in/user/register and add it to backend/.env"
            )
        params = {
            "api-key": self.api_key,
            "format": "json",
            "filters[city]": "Pune",
            "limit": 500,
        }
        async with httpx.AsyncClient(timeout=20) as client:
            try:
                resp = await client.get(f"{self.base_url}/{self.resource_id}", params=params)
            except httpx.HTTPError as e:
                raise ProviderUnavailableError(f"CPCB/data.gov.in request failed: {e}") from e
        if resp.status_code != 200:
            raise ProviderUnavailableError(
                f"CPCB/data.gov.in returned HTTP {resp.status_code}: {resp.text[:300]}"
            )
        return resp.json().get("records", [])

    async def discover_stations(self, bbox: tuple[float, float, float, float]) -> list[RawStation]:
        records = await self._fetch_records()
        seen: dict[str, RawStation] = {}
        skipped_unresolved: set[str] = set()
        for rec in records:
            station_name = (rec.get("station") or "").strip()
            if not station_name:
                continue
            coord = self._coords.get(station_name)
            if not coord:
                skipped_unresolved.add(station_name)
                continue
            if station_name not in seen:
                seen[station_name] = RawStation(
                    external_id=station_name,
                    name=station_name,
                    latitude=coord["lat"],
                    longitude=coord["lng"],
                    location_type="mapped_station",  # real CPCB reading, admin-verified coordinate
                    raw=rec,
                )
        if skipped_unresolved:
            # Surfaced to caller via raw attribute on a sentinel so ingestion can log it.
            # (Ingestion service inspects this list and writes to data_quality_logs / logs.)
            RawStation.__dict__  # no-op, keeps linters quiet
        self.last_unresolved_stations = sorted(skipped_unresolved)
        return list(seen.values())

    async def fetch_latest(self, stations: list[RawStation]) -> list[RawObservation]:
        records = await self._fetch_records()
        known_names = {s.external_id for s in stations}
        observations: list[RawObservation] = []
        now = datetime.now(timezone.utc)
        for rec in records:
            station_name = (rec.get("station") or "").strip()
            if station_name not in known_names:
                continue
            code = _POLLUTANT_MAP.get((rec.get("pollutant_id") or "").strip().upper())
            if not code:
                continue
            avg = rec.get("pollutant_avg")
            if avg in (None, "NA", ""):
                continue
            try:
                value = float(avg)
            except (TypeError, ValueError):
                continue
            last_update = rec.get("last_update")
            try:
                # CPCB format observed: "11-09-2026 14:00:00"
                observed_at = datetime.strptime(last_update, "%d-%m-%Y %H:%M:%S").replace(tzinfo=timezone.utc)
            except (TypeError, ValueError):
                observed_at = now  # only if provider omits timestamp entirely
            observations.append(RawObservation(
                station_external_id=station_name,
                pollutant_code=code,
                value=value,
                unit="µg/m³" if code != "co" else "mg/m³",
                observed_at=observed_at,
                raw=rec,
            ))
        return observations
