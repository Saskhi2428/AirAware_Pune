"""
AirQualityProvider — abstract contract.

Every real data source (OpenAQ, CPCB/data.gov.in, future providers) implements
this interface. The ingestion pipeline only talks to this interface, never to
a specific provider's HTTP shape directly — so adding provider #3 later means
writing one new class, not touching ingestion logic.

CRITICAL RULE (per project spec section 53/63):
Implementations MUST return only data actually received from the live HTTP
API. If the API call fails or the API key is missing, raise
ProviderUnavailableError — never fabricate a reading, a station, or a value.
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime
from typing import Optional


class ProviderUnavailableError(Exception):
    """Raised when a provider cannot be reached or is not configured (missing key)."""


@dataclass
class RawStation:
    external_id: str
    name: str
    latitude: float
    longitude: float
    location_type: str  # 'measured_station' | 'mapped_station' | 'estimated' | 'modelled'
    raw: dict


@dataclass
class RawObservation:
    station_external_id: str
    pollutant_code: str        # normalized: pm25, pm10, no2, so2, o3, co, nh3
    value: float
    unit: str
    observed_at: datetime
    raw: dict


class AirQualityProvider(ABC):
    code: str  # unique provider code, matches data_sources.code in DB

    @abstractmethod
    async def discover_stations(self, bbox: tuple[float, float, float, float]) -> list[RawStation]:
        """Return stations within (min_lat, min_lng, max_lat, max_lng). Real API call only."""
        raise NotImplementedError

    @abstractmethod
    async def fetch_latest(self, stations: list[RawStation]) -> list[RawObservation]:
        """Return the latest pollutant observations for the given stations. Real API call only."""
        raise NotImplementedError

    def is_configured(self) -> bool:
        """Whether this provider has the credentials it needs to make real calls."""
        return True
