"""
Background scheduler. Frequencies come from .env, not hardcoded guesses,
so they can be tuned to whatever the real provider's rate limit allows
without a code change.
"""
from __future__ import annotations

import logging

from apscheduler.schedulers.asyncio import AsyncIOScheduler

from app.core.config import settings
from app.services.ingestion_service import run_station_sync, run_latest_observations
from app.services.providers.openaq_provider import OpenAQProvider
from app.services.providers.cpcb_provider import CPCBProvider

from app.services.populate_pune_stations import populate_pune_stations
from app.services.platform_maintenance_service import run_full_platform_maintenance

logger = logging.getLogger("airaware.scheduler")

_BBOX = (settings.PUNE_BBOX_MIN_LAT, settings.PUNE_BBOX_MIN_LNG,
          settings.PUNE_BBOX_MAX_LAT, settings.PUNE_BBOX_MAX_LNG)

_openaq = OpenAQProvider()
_cpcb = CPCBProvider()

scheduler = AsyncIOScheduler()


async def _job_pune_realtime_sync():
    try:
        logger.info("Executing scheduled Pune real-time atmospheric telemetry sync...")
        res = await populate_pune_stations()
        logger.info("Pune real-time sync completed: %s", res.get("status"))
    except Exception as e:
        logger.error("Error in automatic Pune telemetry sync: %s", e)


async def _job_platform_maintenance():
    try:
        logger.info("Executing scheduled platform maintenance & table health sync...")
        res = await run_full_platform_maintenance()
        logger.info("Platform maintenance sync completed: %s", res)
    except Exception as e:
        logger.error("Error in automatic platform maintenance: %s", e)


async def _job_station_sync():
    for provider in (_openaq, _cpcb):
        if provider.is_configured():
            try:
                await run_station_sync(provider, _BBOX)
            except Exception as e:
                logger.warning("Station sync failed for provider %s: %s", provider.code, e)
        else:
            logger.info("Skipping station sync for %s — not configured", provider.code)


async def _job_latest_observations():
    for provider in (_openaq, _cpcb):
        if provider.is_configured():
            try:
                await run_latest_observations(provider)
            except Exception as e:
                logger.warning("Latest-observations sync failed for provider %s: %s", provider.code, e)
        else:
            logger.info("Skipping latest-observations for %s — not configured", provider.code)


def start_scheduler():
    scheduler.add_job(_job_pune_realtime_sync, "interval",
                       minutes=15, id="pune_realtime_sync")
    scheduler.add_job(_job_platform_maintenance, "interval",
                       minutes=30, id="platform_maintenance")
    scheduler.add_job(_job_station_sync, "interval",
                       minutes=settings.JOB_STATION_SYNC_INTERVAL_MIN, id="station_sync",
                       next_run_time=None)  # first run triggered manually via /admin/sync
    scheduler.add_job(_job_latest_observations, "interval",
                       minutes=settings.JOB_LATEST_OBSERVATIONS_INTERVAL_MIN, id="latest_observations")
    scheduler.start()
    logger.info("Scheduler started: pune_realtime_sync every 15m, platform_maintenance every 30m, station_sync every %sm, latest_observations every %sm",
                settings.JOB_STATION_SYNC_INTERVAL_MIN, settings.JOB_LATEST_OBSERVATIONS_INTERVAL_MIN)
