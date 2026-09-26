import logging
from datetime import datetime, timezone
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Body
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import get_current_user
from app.core.db import db_dependency
from app.core.responses import ok, fail

logger = logging.getLogger("airaware.alerts")
router = APIRouter(tags=["alerts"])


class AlertCreateRequest(BaseModel):
    alert_type: str = "aqi_threshold"  # 'aqi_threshold','pm25_threshold','pollutant_threshold','forecast','anomaly','saved_location','data_quality'
    threshold_value: float = 150.0
    saved_location_id: Optional[UUID] = None
    pollutant_code: Optional[str] = None
    is_enabled: bool = True
    cooldown_minutes: int = 180


class PushTokenRequest(BaseModel):
    platform: str = "android"  # 'android', 'ios', 'web'
    token: str


@router.get("/alerts")
async def list_user_alerts(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(db_dependency),
):
    """Retrieve all air quality alert rules configured by the authenticated user."""
    try:
        query = text("""
            SELECT 
                a.id, a.user_id, a.alert_type, a.saved_location_id, 
                a.pollutant_code, a.threshold_value, a.is_enabled, 
                a.cooldown_minutes, a.last_triggered_at, a.created_at,
                sl.label as location_label
            FROM alerts a
            LEFT JOIN saved_locations sl ON a.saved_location_id = sl.id
            WHERE a.user_id = :user_id
            ORDER BY a.created_at DESC
        """)
        result = await db.execute(query, {"user_id": current_user["id"]})
        rows = result.mappings().all()

        alerts = [
            {
                "id": str(r["id"]),
                "alert_type": str(r["alert_type"]),
                "threshold_value": r["threshold_value"],
                "saved_location_id": str(r["saved_location_id"]) if r["saved_location_id"] else None,
                "location_label": r["location_label"],
                "pollutant_code": r["pollutant_code"],
                "is_enabled": r["is_enabled"],
                "cooldown_minutes": r["cooldown_minutes"],
                "last_triggered_at": r["last_triggered_at"].isoformat() if r["last_triggered_at"] else None,
                "created_at": r["created_at"].isoformat() if r["created_at"] else None,
            }
            for r in rows
        ]
        return ok(alerts)
    except Exception as e:
        logger.error(f"Error listing alerts: {e}", exc_info=True)
        return fail(f"Failed to fetch alerts: {str(e)}", status_code=500)


@router.post("/alerts")
async def create_or_update_alert(
    payload: AlertCreateRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(db_dependency),
):
    """Create or update a threshold alert trigger for the citizen."""
    try:
        existing_q = text("""
            SELECT id FROM alerts 
            WHERE user_id = :user_id 
              AND alert_type = CAST(:alert_type AS alert_type_enum)
              AND (saved_location_id = :loc_id OR (:loc_id IS NULL AND saved_location_id IS NULL))
            LIMIT 1
        """)
        existing = (await db.execute(existing_q, {
            "user_id": current_user["id"],
            "alert_type": payload.alert_type,
            "loc_id": payload.saved_location_id,
        })).first()

        if existing:
            update_q = text("""
                UPDATE alerts
                SET threshold_value = :thresh,
                    pollutant_code = :pollutant,
                    is_enabled = :is_enabled,
                    cooldown_minutes = :cooldown
                WHERE id = :id
                RETURNING id, threshold_value, is_enabled
            """)
            updated = (await db.execute(update_q, {
                "id": existing[0],
                "thresh": payload.threshold_value,
                "pollutant": payload.pollutant_code,
                "is_enabled": payload.is_enabled,
                "cooldown": payload.cooldown_minutes,
            })).mappings().first()
            await db.commit()
            return ok({"id": str(updated["id"]), "threshold_value": updated["threshold_value"], "action": "updated"})
        else:
            insert_q = text("""
                INSERT INTO alerts (
                    user_id, alert_type, saved_location_id, pollutant_code, 
                    threshold_value, is_enabled, cooldown_minutes
                ) VALUES (
                    :user_id, CAST(:alert_type AS alert_type_enum), :loc_id, :pollutant,
                    :thresh, :is_enabled, :cooldown
                )
                RETURNING id, threshold_value, is_enabled
            """)
            inserted = (await db.execute(insert_q, {
                "user_id": current_user["id"],
                "alert_type": payload.alert_type,
                "loc_id": payload.saved_location_id,
                "pollutant": payload.pollutant_code,
                "thresh": payload.threshold_value,
                "is_enabled": payload.is_enabled,
                "cooldown": payload.cooldown_minutes,
            })).mappings().first()
            await db.commit()
            return ok({"id": str(inserted["id"]), "threshold_value": inserted["threshold_value"], "action": "created"}, status_code=201)
    except Exception as e:
        await db.rollback()
        logger.error(f"Error creating alert: {e}", exc_info=True)
        return fail(f"Failed to configure alert: {str(e)}", status_code=500)


@router.delete("/alerts/{alert_id}")
async def delete_alert(
    alert_id: UUID,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(db_dependency),
):
    """Delete an alert configuration."""
    try:
        del_q = text("DELETE FROM alerts WHERE id = :id AND user_id = :user_id RETURNING id")
        res = await db.execute(del_q, {"id": alert_id, "user_id": current_user["id"]})
        if not res.first():
            return fail("Alert not found or unauthorized", status_code=404)
        await db.commit()
        return ok({"deleted": str(alert_id)})
    except Exception as e:
        await db.rollback()
        return fail(f"Failed to delete alert: {str(e)}", status_code=500)


@router.patch("/alerts/{alert_id}/toggle")
async def toggle_alert(
    alert_id: UUID,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(db_dependency),
):
    """Toggle enabled status of an alert rule."""
    try:
        toggle_q = text("""
            UPDATE alerts 
            SET is_enabled = NOT is_enabled 
            WHERE id = :id AND user_id = :user_id 
            RETURNING id, is_enabled
        """)
        res = (await db.execute(toggle_q, {"id": alert_id, "user_id": current_user["id"]})).mappings().first()
        if not res:
            return fail("Alert not found", status_code=404)
        await db.commit()
        return ok({"id": str(res["id"]), "is_enabled": res["is_enabled"]})
    except Exception as e:
        await db.rollback()
        return fail(f"Failed to toggle alert: {str(e)}", status_code=500)


@router.post("/users/push-token")
async def register_push_token(
    payload: PushTokenRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(db_dependency),
):
    """Register mobile device push notification token (FCM)."""
    try:
        upsert_q = text("""
            INSERT INTO notification_tokens (user_id, platform, token, is_active)
            VALUES (:user_id, :platform, :token, true)
            ON CONFLICT (user_id, token) 
            DO UPDATE SET platform = EXCLUDED.platform, is_active = true
            RETURNING id, platform, is_active
        """)
        res = (await db.execute(upsert_q, {
            "user_id": current_user["id"],
            "platform": payload.platform,
            "token": payload.token,
        })).mappings().first()
        await db.commit()
        return ok({"id": str(res["id"]), "platform": res["platform"], "is_active": res["is_active"]})
    except Exception as e:
        await db.rollback()
        logger.error(f"Error registering push token: {e}", exc_info=True)
        return fail(f"Failed to register token: {str(e)}", status_code=500)
