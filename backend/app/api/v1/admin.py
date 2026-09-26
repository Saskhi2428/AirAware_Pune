from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import require_admin
from app.core.config import settings
from app.core.db import db_dependency
from app.core.responses import ok
from app.services.ingestion_service import run_station_sync, run_latest_observations
from app.services.providers.openaq_provider import OpenAQProvider
from app.services.providers.cpcb_provider import CPCBProvider

router = APIRouter(prefix="/admin", tags=["admin"], dependencies=[Depends(require_admin)])

_PROVIDERS = {"openaq": OpenAQProvider(), "cpcb_datagovin": CPCBProvider()}
_BBOX = (settings.PUNE_BBOX_MIN_LAT, settings.PUNE_BBOX_MIN_LNG,
         settings.PUNE_BBOX_MAX_LAT, settings.PUNE_BBOX_MAX_LNG)


@router.get("/dashboard")
async def dashboard(session: AsyncSession = Depends(db_dependency)):
    stats = (await session.execute(text("""
        select
          (select count(*) from profiles) as total_users,
          (select count(*) from monitoring_stations where is_active=true) as total_stations,
          (select count(*) from monitoring_stations where is_active=true and health='healthy') as healthy_stations,
          (select count(*) from monitoring_stations where is_active=true and health='offline') as offline_stations,
          (select count(*) from air_quality_readings where created_at > now() - interval '24 hours') as records_today,
          (select max(finished_at) from ingestion_runs where status='success') as last_successful_ingestion,
          (select count(*) from ingestion_runs where status='failed' and started_at > now() - interval '24 hours') as failed_ingestion_24h,
          (select count(*) from alerts where is_enabled=true) as active_alerts,
          (select count(*) from anomaly_events where detected_at > now() - interval '24 hours') as anomalies_24h,
          (select count(*) from hotspot_events where detected_at > now() - interval '24 hours') as hotspots_24h
    """))).mappings().first()
    data = dict(stats)
    if data.get("last_successful_ingestion"):
        data["last_successful_ingestion"] = data["last_successful_ingestion"].isoformat()
    return ok(data)


@router.get("/ingestion")
async def ingestion_runs(limit: int = 50, session: AsyncSession = Depends(db_dependency)):
    rows = (await session.execute(text("""
        select id, job_name, status, started_at, finished_at,
               records_fetched, records_inserted, records_rejected, error_message
        from ingestion_runs order by started_at desc limit :limit
    """), {"limit": limit})).mappings().all()
    data = [{**dict(r), "id": str(r["id"]),
             "started_at": r["started_at"].isoformat(),
             "finished_at": r["finished_at"].isoformat() if r["finished_at"] else None} for r in rows]
    return ok(data)


@router.post("/sync")
async def sync_now(provider_code: str = "openaq"):
    """Manual emergency sync — normal operation relies on the scheduler, not this."""
    provider = _PROVIDERS.get(provider_code)
    if not provider:
        return ok(None, message=f"Unknown provider '{provider_code}'. Options: {list(_PROVIDERS)}")
    station_result = await run_station_sync(provider, _BBOX)
    obs_result = await run_latest_observations(provider)
    return ok({"station_sync": station_result, "latest_observations": obs_result})
