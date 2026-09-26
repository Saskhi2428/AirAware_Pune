"""
WeatherProvider — wraps the real Open-Meteo API (api.open-meteo.com).
Chosen as the default because it requires NO API key and its forecast/current
endpoint is public and free for non-commercial use, which keeps Phase 2
runnable without asking you to register yet another account before we've
confirmed the rest of the pipeline works. Swap WEATHER_PROVIDER in .env to
add a keyed provider later (e.g. OpenWeatherMap) behind this same interface.

Docs: https://open-meteo.com/en/docs
"""
from __future__ import annotations

from datetime import datetime, timezone

import httpx

from app.core.config import settings


class WeatherFetchError(Exception):
    pass


async def fetch_current_weather(lat: float, lng: float) -> dict:
    params = {
        "latitude": lat,
        "longitude": lng,
        "current": ",".join([
            "temperature_2m", "relative_humidity_2m", "wind_speed_10m",
            "wind_direction_10m", "surface_pressure", "precipitation",
        ]),
        "timezone": "Asia/Kolkata",
    }
    async with httpx.AsyncClient(timeout=15) as client:
        try:
            resp = await client.get(f"{settings.WEATHER_BASE_URL}/forecast", params=params)
        except httpx.HTTPError as e:
            raise WeatherFetchError(f"Open-Meteo request failed: {e}") from e
    if resp.status_code != 200:
        raise WeatherFetchError(f"Open-Meteo returned HTTP {resp.status_code}: {resp.text[:300]}")

    payload = resp.json()
    current = payload.get("current")
    if not current:
        raise WeatherFetchError("Open-Meteo response had no 'current' block.")

    return {
        "observed_at": datetime.now(timezone.utc),
        "temperature_c": current.get("temperature_2m"),
        "humidity_pct": current.get("relative_humidity_2m"),
        "wind_speed_ms": current.get("wind_speed_10m"),
        "wind_direction_deg": current.get("wind_direction_10m"),
        "pressure_hpa": current.get("surface_pressure"),
        "rainfall_mm": current.get("precipitation"),
        "source": "open_meteo",
    }
