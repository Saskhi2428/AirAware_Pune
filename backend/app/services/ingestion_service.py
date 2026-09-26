"""
Ingestion pipeline:
  provider.discover_stations() -> upsert monitoring_stations
  provider.fetch_latest()      -> validate -> insert air_quality_readings
                                -> group per station -> calculate_aqi() -> upsert aqi_computations

Every run is logged to `ingestion_runs` so the admin dashboard (section 35)
has real numbers, not placeholders.
"""
from __future__ import annotations

import logging
from collections import defaultdict
from datetime import datetime, timezone

from sqlalchemy import text

from app.core.db import get_session
from app.services.aqi_calculator import calculate_aqi
from app.services.data_quality import validate_observation
from app.services.providers.base import AirQualityProvider, ProviderUnavailableError

logger = logging.getLogger("airaware.ingestion")


async def _get_or_create_data_source(session, code: str, display_name: str) -> str:
    row = (await session.execute(text("select id from data_sources where code=:c"), {"c": code})).first()
    if row:
        return str(row[0])
    row = (await session.execute(
        text("insert into data_sources (code, display_name) values (:c,:d) returning id"),
        {"c": code, "d": display_name},
    )).first()
    return str(row[0])


async def run_station_sync(provider: AirQualityProvider, bbox: tuple[float, float, float, float]) -> dict:
    async with get_session() as session:
        run_id = (await session.execute(
            text("insert into ingestion_runs (job_name, status) values (:j,'running') returning id"),
            {"j": f"{provider.code}_station_sync"},
        )).first()[0]

        if not provider.is_configured():
            await session.execute(text(
                "update ingestion_runs set status='failed', finished_at=now(), "
                "error_message=:e where id=:id"
            ), {"e": f"{provider.code} not configured (missing API key)", "id": run_id})
            await session.commit()
            return {"status": "failed", "reason": "not_configured"}

        source_id = await _get_or_create_data_source(session, provider.code, provider.code.upper())
        try:
            stations = await provider.discover_stations(bbox)
        except ProviderUnavailableError as e:
            await session.execute(text(
                "update ingestion_runs set status='failed', finished_at=now(), error_message=:e where id=:id"
            ), {"e": str(e), "id": run_id})
            await session.commit()
            logger.warning("Station sync failed for %s: %s", provider.code, e)
            return {"status": "failed", "reason": str(e)}

        inserted = 0
        for st in stations:
            result = await session.execute(text("""
                insert into monitoring_stations
                    (name, area, location_type, data_source_id, external_station_id, latitude, longitude)
                values (:name, :area, :ltype, :src, :ext, :lat, :lng)
                on conflict (data_source_id, external_station_id) do update set
                    name = excluded.name, latitude = excluded.latitude, longitude = excluded.longitude,
                    updated_at = now()
                returning id
            """), {
                "name": st.name, "area": st.name, "ltype": st.location_type,
                "src": source_id, "ext": st.external_id, "lat": st.latitude, "lng": st.longitude,
            })
            if result.first():
                inserted += 1

        unresolved = getattr(provider, "last_unresolved_stations", [])
        await session.execute(text(
            "update ingestion_runs set status='success', finished_at=now(), "
            "records_fetched=:f, records_inserted=:i where id=:id"
        ), {"f": len(stations), "i": inserted, "id": run_id})
        await session.commit()
        return {"status": "success", "stations_found": len(stations),
                "stations_upserted": inserted, "unresolved_station_names": unresolved}


async def run_latest_observations(provider: AirQualityProvider) -> dict:
    async with get_session() as session:
        run_id = (await session.execute(
            text("insert into ingestion_runs (job_name, status) values (:j,'running') returning id"),
            {"j": f"{provider.code}_latest"},
        )).first()[0]

        if not provider.is_configured():
            await session.execute(text(
                "update ingestion_runs set status='failed', finished_at=now(), "
                "error_message=:e where id=:id"
            ), {"e": f"{provider.code} not configured", "id": run_id})
            await session.commit()
            return {"status": "failed", "reason": "not_configured"}

        # Load this provider's known stations from DB
        source_id_row = (await session.execute(
            text("select id from data_sources where code=:c"), {"c": provider.code}
        )).first()
        if not source_id_row:
            await session.execute(text(
                "update ingestion_runs set status='failed', finished_at=now(), "
                "error_message='run station_sync first' where id=:id"), {"id": run_id})
            await session.commit()
            return {"status": "failed", "reason": "no_stations_registered"}
        source_id = source_id_row[0]

        db_stations = (await session.execute(text(
            "select id, external_station_id, name, latitude, longitude from monitoring_stations "
            "where data_source_id=:src and is_active=true"), {"src": source_id})).all()

        from app.services.providers.base import RawStation
        raw_stations = [RawStation(external_id=r.external_station_id, name=r.name,
                                    latitude=r.latitude, longitude=r.longitude,
                                    location_type="measured_station", raw={}) for r in db_stations]
        station_id_by_ext = {r.external_station_id: r.id for r in db_stations}

        try:
            observations = await provider.fetch_latest(raw_stations)
        except ProviderUnavailableError as e:
            await session.execute(text(
                "update ingestion_runs set status='failed', finished_at=now(), error_message=:e where id=:id"
            ), {"e": str(e), "id": run_id})
            await session.commit()
            return {"status": "failed", "reason": str(e)}

        pollutant_ids = {r[0]: r[1] for r in (await session.execute(
            text("select code, id from pollutants"))).all()}

        inserted, rejected = 0, 0
        per_station_values: dict[str, dict[str, float]] = defaultdict(dict)
        per_station_time: dict[str, datetime] = {}

        for obs in observations:
            station_id = station_id_by_ext.get(obs.station_external_id)
            pollutant_id = pollutant_ids.get(obs.pollutant_code)
            if not station_id or not pollutant_id:
                rejected += 1
                continue

            qc = validate_observation(obs.pollutant_code, obs.value, obs.observed_at)
            await session.execute(text("""
                insert into air_quality_readings
                    (station_id, pollutant_id, observed_at, value, unit, source, quality_score, quality_flag, is_valid)
                values (:sid, :pid, :obs, :val, :unit, :src, :score, :flag, :valid)
                on conflict (station_id, pollutant_id, observed_at) do nothing
            """), {
                "sid": station_id, "pid": pollutant_id, "obs": obs.observed_at, "val": obs.value,
                "unit": obs.unit, "src": provider.code, "score": qc.quality_score,
                "flag": qc.classification, "valid": qc.passed,
            })
            if qc.passed:
                inserted += 1
                per_station_values[station_id][obs.pollutant_code] = obs.value
                per_station_time[station_id] = obs.observed_at
            else:
                rejected += 1

            for check in qc.failed_checks:
                await session.execute(text("""
                    insert into data_quality_logs (station_id, check_name, passed, detail)
                    values (:sid, :chk, false, :detail)
                """), {"sid": station_id, "chk": check, "detail": f"{obs.pollutant_code}={obs.value}"})

        # Compute AQI per station from whatever valid pollutants we have
        for station_id, values in per_station_values.items():
            result = calculate_aqi(values)
            if result is None:
                continue
            await session.execute(text("""
                insert into aqi_computations
                    (station_id, computed_for, aqi_value, aqi_category, dominant_pollutant, standard)
                values (:sid, :cf, :aqi, :cat, :dom, :std)
                on conflict (station_id, computed_for) do update set
                    aqi_value = excluded.aqi_value, aqi_category = excluded.aqi_category,
                    dominant_pollutant = excluded.dominant_pollutant
            """), {"sid": station_id, "cf": per_station_time[station_id], "aqi": result.aqi_value,
                   "cat": result.aqi_category, "dom": result.dominant_pollutant, "std": result.standard})
            await session.execute(text(
                "update monitoring_stations set last_observation_at=:t, last_ingested_at=now(), "
                "health='healthy' where id=:sid"
            ), {"t": per_station_time[station_id], "sid": station_id})

        await session.execute(text(
            "update ingestion_runs set status='success', finished_at=now(), "
            "records_fetched=:f, records_inserted=:i, records_rejected=:r where id=:id"
        ), {"f": len(observations), "i": inserted, "r": rejected, "id": run_id})
        await session.commit()
        return {"status": "success", "fetched": len(observations), "inserted": inserted, "rejected": rejected}
