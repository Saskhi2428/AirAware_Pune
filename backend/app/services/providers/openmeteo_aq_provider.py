"""
OpenMeteoAQProvider — Fetches real-time atmospheric air quality observations
from the Open-Meteo Air Quality API (Copernicus CAMS & atmospheric assimilation).

Publicly accessible, requires NO API key, providing genuine real-time PM2.5, PM10,
NO2, SO2, CO, and O3 measurements across Pune coordinates.
"""
from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

import httpx

from app.services.providers.base import (
    AirQualityProvider,
    ProviderUnavailableError,
    RawObservation,
    RawStation,
)

logger = logging.getLogger("airaware.provider.openmeteo")

_METEO_URL = "https://air-quality-api.open-meteo.com/v1/air-quality"


class OpenMeteoAQProvider(AirQualityProvider):
    code = "openmeteo_aq"

    def is_configured(self) -> bool:
        return True

    async def discover_stations(self, bbox: tuple[float, float, float, float]) -> list[RawStation]:
        # Stations in Pune are pre-registered with official CPCB/MPCB/SAFAR locations
        return []

    async def fetch_station_telemetry(self, lat: float, lng: float, station_id: str) -> list[RawObservation]:
        """Fetch real-time current air quality observation for a given coordinate."""
        params = {
            "latitude": lat,
            "longitude": lng,
            "current": "pm10,pm2_5,carbon_monoxide,nitrogen_dioxide,sulphur_dioxide,ozone",
            "timezone": "Asia/Kolkata",
        }
        async with httpx.AsyncClient(timeout=15) as client:
            try:
                resp = await client.get(_METEO_URL, params=params)
            except httpx.HTTPError as e:
                raise ProviderUnavailableError(f"Open-Meteo AQ request failed: {e}") from e

        if resp.status_code != 200:
            raise ProviderUnavailableError(f"Open-Meteo AQ returned HTTP {resp.status_code}: {resp.text[:200]}")

        data = resp.json()
        current = data.get("current") or {}
        time_str = current.get("time")
        if not time_str:
            observed_at = datetime.now(timezone.utc)
        else:
            try:
                observed_at = datetime.fromisoformat(time_str).replace(tzinfo=timezone.utc)
            except Exception:
                observed_at = datetime.now(timezone.utc)

        observations: list[RawObservation] = []

        mapping = [
            ("pm2_5", "pm25", "µg/m³", 1.0),
            ("pm10", "pm10", "µg/m³", 1.0),
            ("nitrogen_dioxide", "no2", "µg/m³", 1.0),
            ("sulphur_dioxide", "so2", "µg/m³", 1.0),
            ("ozone", "o3", "µg/m³", 1.0),
            ("carbon_monoxide", "co", "mg/m³", 0.001),  # convert µg/m³ to mg/m³ for CPCB NAQI
        ]

        for meteo_key, pollutant_code, unit, scale in mapping:
            raw_val = current.get(meteo_key)
            if raw_val is not None:
                try:
                    val = round(float(raw_val) * scale, 2)
                    observations.append(
                        RawObservation(
                            station_external_id=station_id,
                            pollutant_code=pollutant_code,
                            value=val,
                            unit=unit,
                            observed_at=observed_at,
                            raw=current,
                        )
                    )
                except (ValueError, TypeError):
                    continue

        return observations

    async def fetch_station_hourly(self, lat: float, lng: float, station_id: str) -> list[dict[str, Any]]:
        """Fetch past 24 hours of authentic hourly observations for historical trend."""
        params = {
            "latitude": lat,
            "longitude": lng,
            "hourly": "pm10,pm2_5,carbon_monoxide,nitrogen_dioxide,sulphur_dioxide,ozone",
            "past_days": 1,
            "forecast_days": 0,
            "timezone": "Asia/Kolkata",
        }
        async with httpx.AsyncClient(timeout=15) as client:
            try:
                resp = await client.get(_METEO_URL, params=params)
                if resp.status_code == 200:
                    data = resp.json().get("hourly") or {}
                    times = data.get("time") or []
                    pm25 = data.get("pm2_5") or []
                    pm10 = data.get("pm10") or []
                    no2 = data.get("nitrogen_dioxide") or []
                    so2 = data.get("sulphur_dioxide") or []
                    co = data.get("carbon_monoxide") or []
                    o3 = data.get("ozone") or []

                    records = []
                    for i in range(len(times)):
                        try:
                            t = datetime.fromisoformat(times[i]).replace(tzinfo=timezone.utc)
                            records.append({
                                "observed_at": t,
                                "pollutants": {
                                    "pm25": float(pm25[i]) if i < len(pm25) and pm25[i] is not None else None,
                                    "pm10": float(pm10[i]) if i < len(pm10) and pm10[i] is not None else None,
                                    "no2": float(no2[i]) if i < len(no2) and no2[i] is not None else None,
                                    "so2": float(so2[i]) if i < len(so2) and so2[i] is not None else None,
                                    "o3": float(o3[i]) if i < len(o3) and o3[i] is not None else None,
                                    "co": round(float(co[i]) * 0.001, 2) if i < len(co) and co[i] is not None else None,
                                }
                            })
                        except Exception:
                            continue
                    return records
            except Exception as e:
                logger.warning(f"Error fetching hourly data from Open-Meteo for station {station_id}: {e}")
        return []

    async def fetch_latest(self, stations: list[RawStation]) -> list[RawObservation]:
        all_obs: list[RawObservation] = []
        for st in stations:
            try:
                obs = await self.fetch_station_telemetry(st.latitude, st.longitude, st.external_id)
                all_obs.extend(obs)
            except Exception as e:
                logger.warning(f"Could not fetch OpenMeteo telemetry for {st.name}: {e}")
        return all_obs
