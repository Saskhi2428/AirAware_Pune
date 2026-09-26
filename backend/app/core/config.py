"""
Central configuration. Everything comes from environment variables (.env).
No secret ever has a hardcoded fallback value — if it's missing, the app
must fail loudly rather than silently using a fake/default key.
"""
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    ENVIRONMENT: str = "development"
    API_V1_PREFIX: str = "/api/v1"
    CORS_ALLOWED_ORIGINS: str = "http://localhost:3000"

    # Supabase
    SUPABASE_URL: str
    SUPABASE_ANON_KEY: str
    SUPABASE_SERVICE_ROLE_KEY: str
    DATABASE_URL: str

    # OpenAQ
    OPENAQ_API_KEY: str = ""
    OPENAQ_BASE_URL: str = "https://api.openaq.org/v3"

    # CPCB via data.gov.in
    CPCB_DATAGOVIN_API_KEY: str = ""
    CPCB_DATAGOVIN_RESOURCE_ID: str = "3b01bcb8-0b14-4abf-b6f2-c1bfd384ba69"
    CPCB_BASE_URL: str = "https://api.data.gov.in/resource"

    # Weather
    WEATHER_PROVIDER: str = "open_meteo"
    WEATHER_BASE_URL: str = "https://api.open-meteo.com/v1"
    WEATHER_API_KEY: str = ""

    # Scheduling
    JOB_STATION_SYNC_INTERVAL_MIN: int = 1440
    JOB_LATEST_OBSERVATIONS_INTERVAL_MIN: int = 15
    JOB_WEATHER_INTERVAL_MIN: int = 60
    JOB_HOTSPOT_ANALYSIS_INTERVAL_MIN: int = 180
    JOB_ANOMALY_ANALYSIS_INTERVAL_MIN: int = 60
    JOB_DAILY_AGGREGATION_HOUR_UTC: int = 20

    # Pune Metropolitan Region bounding box (generous — includes PCMC)
    PUNE_BBOX_MIN_LAT: float = 18.35
    PUNE_BBOX_MIN_LNG: float = 73.65
    PUNE_BBOX_MAX_LAT: float = 18.80
    PUNE_BBOX_MAX_LNG: float = 74.05

    @property
    def openaq_configured(self) -> bool:
        return bool(self.OPENAQ_API_KEY)

    @property
    def cpcb_configured(self) -> bool:
        return bool(self.CPCB_DATAGOVIN_API_KEY)


settings = Settings()
