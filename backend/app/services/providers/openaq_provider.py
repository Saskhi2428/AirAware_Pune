"""
OpenAQProvider — wraps the real OpenAQ v3 API (api.openaq.org/v3).

Verified live against the actual API on 2026-09-11:
  - GET /v3/locations requires header 'X-API-Key'; an unauthenticated
    request returns HTTP 401 (confirmed empirically).
  - GET /v3/locations supports `bbox=minLng,minLat,maxLng,maxLat`.
  - GET /v3/locations/{id}/latest returns the latest value per sensor.

Docs: https://docs.openaq.org
Register a free key: https://explore.openaq.org/register

Pollutant name normalization: OpenAQ parameter names ('pm25','pm10','no2',
'so2','o3','co') map 1:1 to our internal pollutant codes except no mapping
is invented for parameters we don't recognize — those are skipped, not
guessed.
"""
from __future__ import annotations

from datetime import datetime, timezone

import httpx

from app.core.config import settings
from app.services.providers.base import (
    AirQualityProvider, ProviderUnavailableError, RawObservation, RawStation,
)

_PARAM_MAP = {
    "pm25": "pm25", "pm10": "pm10", "no2": "no2",
    "so2": "so2", "o3": "o3", "co": "co", "nh3": "nh3",
}


class OpenAQProvider(AirQualityProvider):
    code = "openaq"

    def __init__(self) -> None:
        self.base_url = settings.OPENAQ_BASE_URL
        self.api_key = settings.OPENAQ_API_KEY

    def is_configured(self) -> bool:
        return bool(self.api_key)

    def _headers(self) -> dict:
        if not self.api_key:
            raise ProviderUnavailableError(
                "OPENAQ_API_KEY is not set. Register free at "
                "https://explore.openaq.org/register and add it to backend/.env"
            )
        return {"X-API-Key": self.api_key}

    async def discover_stations(self, bbox: tuple[float, float, float, float]) -> list[RawStation]:
        min_lat, min_lng, max_lat, max_lng = bbox
        # OpenAQ bbox order is minLng,minLat,maxLng,maxLat
        params = {"bbox": f"{min_lng},{min_lat},{max_lng},{max_lat}", "limit": 1000}
        async with httpx.AsyncClient(timeout=20) as client:
            try:
                resp = await client.get(f"{self.base_url}/locations", params=params, headers=self._headers())
            except httpx.HTTPError as e:
                raise ProviderUnavailableError(f"OpenAQ request failed: {e}") from e

        if resp.status_code == 401:
            raise ProviderUnavailableError("OpenAQ rejected the API key (401). Check OPENAQ_API_KEY.")
        if resp.status_code != 200:
            raise ProviderUnavailableError(f"OpenAQ returned HTTP {resp.status_code}: {resp.text[:300]}")

        results = resp.json().get("results", [])
        stations: list[RawStation] = []
        for loc in results:
            coords = loc.get("coordinates") or {}
            lat, lng = coords.get("latitude"), coords.get("longitude")
            if lat is None or lng is None:
                continue  # never invent coordinates
            stations.append(RawStation(
                external_id=str(loc["id"]),
                name=loc.get("name") or f"OpenAQ-{loc['id']}",
                latitude=lat,
                longitude=lng,
                location_type="measured_station",
                raw=loc,
            ))
        return stations

    async def fetch_latest(self, stations: list[RawStation]) -> list[RawObservation]:
        if not stations:
            return []
        observations: list[RawObservation] = []
        async with httpx.AsyncClient(timeout=20) as client:
            for st in stations:
                try:
                    resp = await client.get(
                        f"{self.base_url}/locations/{st.external_id}/latest",
                        headers=self._headers(),
                    )
                except httpx.HTTPError:
                    continue  # skip this station this cycle; do not fabricate a value
                if resp.status_code != 200:
                    continue
                for row in resp.json().get("results", []):
                    param = (row.get("parameter") or {}).get("name") or row.get("parameter")
                    code = _PARAM_MAP.get(param)
                    if not code:
                        continue  # unrecognized pollutant — skip, don't guess
                    value = row.get("value")
                    dt_str = (row.get("datetime") or {}).get("utc") if isinstance(row.get("datetime"), dict) else row.get("date")
                    if value is None or not dt_str:
                        continue
                    try:
                        observed_at = datetime.fromisoformat(str(dt_str).replace("Z", "+00:00"))
                    except ValueError:
                        continue
                    observations.append(RawObservation(
                        station_external_id=st.external_id,
                        pollutant_code=code,
                        value=float(value),
                        unit=(row.get("parameter") or {}).get("units", ""),
                        observed_at=observed_at.astimezone(timezone.utc),
                        raw=row,
                    ))
        return observations
