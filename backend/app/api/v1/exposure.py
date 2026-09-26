import logging
from datetime import datetime, timezone
from typing import List, Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import get_current_user
from app.core.db import db_dependency
from app.core.responses import ok, fail

logger = logging.getLogger("airaware.exposure")
router = APIRouter(prefix="/exposure", tags=["exposure"])


class ExposureSessionStartRequest(BaseModel):
    activity_mode: str = "Walking"  # Walking, Running, Cycling, Driving


class ExposurePointPayload(BaseModel):
    latitude: float
    longitude: float
    sampled_at: Optional[datetime] = None


class ExposureSessionFinishRequest(BaseModel):
    ended_at: Optional[datetime] = None


@router.post("/sessions")
async def start_exposure_session(
    payload: ExposureSessionStartRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(db_dependency),
):
    """Start a new personal outdoor exposure tracking session."""
    try:
        insert_q = text("""
            INSERT INTO exposure_sessions (user_id, started_at)
            VALUES (:user_id, now())
            RETURNING id, started_at
        """)
        row = (await db.execute(insert_q, {"user_id": current_user["id"]})).mappings().first()
        await db.commit()
        return ok({
            "session_id": str(row["id"]),
            "started_at": row["started_at"].isoformat(),
            "activity_mode": payload.activity_mode,
            "status": "active"
        }, status_code=201)
    except Exception as e:
        await db.rollback()
        logger.error(f"Error starting exposure session: {e}", exc_info=True)
        return fail(f"Failed to start session: {str(e)}", status_code=500)


@router.post("/sessions/{session_id}/points")
async def add_exposure_point(
    session_id: UUID,
    payload: ExposurePointPayload,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(db_dependency),
):
    """Log a GPS breadcrumb point along route, interpolating nearest station AQI."""
    try:
        # Verify user owns session
        owner_q = text("SELECT id FROM exposure_sessions WHERE id = :id AND user_id = :user_id")
        session_row = (await db.execute(owner_q, {"id": session_id, "user_id": current_user["id"]})).first()
        if not session_row:
            return fail("Exposure session not found or unauthorized", status_code=404)

        # Find nearest active station with recent AQI
        nearest_q = text("""
            SELECT 
                s.id as station_id,
                ac.aqi_value,
                ST_Distance(
                    s.geog,
                    ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography
                ) as distance_m
            FROM monitoring_stations s
            JOIN LATERAL (
                SELECT aqi_value 
                FROM aqi_computations 
                WHERE station_id = s.id 
                ORDER BY computed_for DESC 
                LIMIT 1
            ) ac ON true
            WHERE s.is_active = true
            ORDER BY distance_m ASC
            LIMIT 1
        """)
        station_res = (await db.execute(nearest_q, {"lat": payload.latitude, "lng": payload.longitude})).mappings().first()

        nearest_station_id = station_res["station_id"] if station_res else None
        aqi_at_point = float(station_res["aqi_value"]) if station_res and station_res["aqi_value"] is not None else 85.0
        sampled_time = payload.sampled_at or datetime.now(timezone.utc)

        # Insert exposure point
        insert_pt_q = text("""
            INSERT INTO exposure_points (
                session_id, sampled_at, latitude, longitude,
                nearest_station_id, aqi_at_point, is_estimated
            ) VALUES (
                :session_id, :sampled_at, :lat, :lng,
                :station_id, :aqi, true
            )
            RETURNING id, aqi_at_point
        """)
        pt_row = (await db.execute(insert_pt_q, {
            "session_id": session_id,
            "sampled_at": sampled_time,
            "lat": payload.latitude,
            "lng": payload.longitude,
            "station_id": nearest_station_id,
            "aqi": aqi_at_point
        })).mappings().first()
        await db.commit()

        return ok({
            "point_id": str(pt_row["id"]),
            "aqi_at_point": pt_row["aqi_at_point"],
            "nearest_station_id": str(nearest_station_id) if nearest_station_id else None
        })
    except Exception as e:
        await db.rollback()
        logger.error(f"Error recording exposure point: {e}", exc_info=True)
        return fail(f"Failed to record point: {str(e)}", status_code=500)


@router.post("/sessions/{session_id}/finish")
async def finish_exposure_session(
    session_id: UUID,
    payload: ExposureSessionFinishRequest = ExposureSessionFinishRequest(),
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(db_dependency),
):
    """Complete exposure session, calculate duration, avg AQI, peak AQI, and dose score."""
    try:
        # Check ownership and fetch start time
        session_q = text("SELECT id, started_at FROM exposure_sessions WHERE id = :id AND user_id = :user_id")
        session_row = (await db.execute(session_q, {"id": session_id, "user_id": current_user["id"]})).mappings().first()
        if not session_row:
            return fail("Exposure session not found", status_code=404)

        end_time = payload.ended_at or datetime.now(timezone.utc)
        start_time = session_row["started_at"]
        duration_sec = max(int((end_time - start_time).total_seconds()), 1)

        # Aggregate points
        agg_q = text("""
            SELECT 
                COALESCE(AVG(aqi_at_point), 75.0) as avg_aqi,
                COALESCE(MAX(aqi_at_point), 75.0) as peak_aqi
            FROM exposure_points
            WHERE session_id = :session_id
        """)
        agg = (await db.execute(agg_q, {"session_id": session_id})).mappings().first()
        avg_aqi = round(float(agg["avg_aqi"]), 1)
        peak_aqi = round(float(agg["peak_aqi"]), 1)

        # Find peak time
        peak_time_q = text("""
            SELECT sampled_at FROM exposure_points 
            WHERE session_id = :session_id 
            ORDER BY aqi_at_point DESC, sampled_at ASC 
            LIMIT 1
        """)
        peak_time_row = (await db.execute(peak_time_q, {"session_id": session_id})).first()
        peak_at = peak_time_row[0] if peak_time_row else end_time

        # Calculate relative exposure score (0 - 100)
        # Normalized dose based on duration (hours) and AQI severity
        hours = duration_sec / 3600.0
        dose = (avg_aqi / 100.0) * hours * 25.0
        relative_score = min(int(round(dose)), 100)

        # Update session
        update_q = text("""
            UPDATE exposure_sessions
            SET ended_at = :ended_at,
                duration_seconds = :duration,
                avg_aqi = :avg_aqi,
                peak_aqi = :peak_aqi,
                peak_at = :peak_at,
                relative_exposure_score = :score
            WHERE id = :id
            RETURNING id, duration_seconds, avg_aqi, peak_aqi, relative_exposure_score
        """)
        res = (await db.execute(update_q, {
            "id": session_id,
            "ended_at": end_time,
            "duration": duration_sec,
            "avg_aqi": avg_aqi,
            "peak_aqi": peak_aqi,
            "peak_at": peak_at,
            "score": relative_score
        })).mappings().first()
        await db.commit()

        return ok({
            "session_id": str(res["id"]),
            "duration_seconds": res["duration_seconds"],
            "avg_aqi": res["avg_aqi"],
            "peak_aqi": res["peak_aqi"],
            "relative_exposure_score": res["relative_exposure_score"],
            "status": "completed"
        })
    except Exception as e:
        await db.rollback()
        logger.error(f"Error finishing exposure session: {e}", exc_info=True)
        return fail(f"Failed to finish session: {str(e)}", status_code=500)


@router.get("/sessions")
async def list_exposure_sessions(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(db_dependency),
):
    """Retrieve history of outdoor exposure sessions for authenticated user."""
    try:
        q = text("""
            SELECT 
                id, started_at, ended_at, duration_seconds,
                avg_aqi, peak_aqi, peak_at, relative_exposure_score, created_at
            FROM exposure_sessions
            WHERE user_id = :user_id AND ended_at IS NOT NULL
            ORDER BY started_at DESC
            LIMIT 20
        """)
        rows = (await db.execute(q, {"user_id": current_user["id"]})).mappings().all()

        sessions = [
            {
                "id": str(r["id"]),
                "started_at": r["started_at"].isoformat() if r["started_at"] else None,
                "ended_at": r["ended_at"].isoformat() if r["ended_at"] else None,
                "duration_seconds": r["duration_seconds"],
                "avg_aqi": r["avg_aqi"],
                "peak_aqi": r["peak_aqi"],
                "relative_exposure_score": r["relative_exposure_score"],
            }
            for r in rows
        ]
        return ok(sessions)
    except Exception as e:
        logger.error(f"Error listing exposure sessions: {e}", exc_info=True)
        return fail(f"Failed to fetch sessions: {str(e)}", status_code=500)
