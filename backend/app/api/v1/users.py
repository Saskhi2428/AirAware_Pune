from __future__ import annotations
from datetime import datetime, timezone
from typing import Optional, Any, Dict
import json

from fastapi import APIRouter, Depends, HTTPException, Body
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import get_current_user
from app.core.db import db_dependency
from app.core.responses import ok, fail

router = APIRouter(prefix="/users", tags=["users"])


class ProfileUpdate(BaseModel):
    full_name: Optional[str] = None
    role: Optional[str] = Field(None, description="user, researcher, or admin")
    home_location_id: Optional[str] = None
    college_location_id: Optional[str] = None
    office_location_id: Optional[str] = None
    notification_prefs: Optional[Dict[str, Any]] = None


class PreferencesUpdate(BaseModel):
    units: Optional[str] = "metric"
    theme: Optional[str] = "dark"


@router.get("/profile")
async def get_user_profile(
    user: dict = Depends(get_current_user),
    session: AsyncSession = Depends(db_dependency),
):
    """Retrieve the current user profile or create a default one if first login."""
    uid = user["id"]
    email = user.get("email", "")

    # Check if profile exists
    row = (await session.execute(text("""
        select p.id, p.full_name, p.role, p.notification_prefs, p.created_at,
               p.home_location_id, p.college_location_id, p.office_location_id,
               hl.label as home_label, hl.latitude as home_lat, hl.longitude as home_lng,
               cl.label as college_label, cl.latitude as college_lat, cl.longitude as college_lng,
               ol.label as office_label, ol.latitude as office_lat, ol.longitude as office_lng
        from profiles p
        left join saved_locations hl on hl.id = p.home_location_id
        left join saved_locations cl on cl.id = p.college_location_id
        left join saved_locations ol on ol.id = p.office_location_id
        where p.id = :uid
    """), {"uid": uid})).mappings().first()

    if not row:
        default_name = email.split("@")[0].replace(".", " ").title() if email else "AirAware User"
        default_prefs = json.dumps({
            "daily_digest": True,
            "spike_alerts": True,
            "threshold_aqi": 150,
            "fcm_token": None,
        })
        await session.execute(text("""
            insert into profiles (id, full_name, role, notification_prefs)
            values (:uid, :name, 'user'::user_role_enum, :prefs::jsonb)
            on conflict (id) do nothing
        """), {"uid": uid, "name": default_name, "prefs": default_prefs})
        await session.commit()

        row = (await session.execute(text("""
            select p.id, p.full_name, p.role, p.notification_prefs, p.created_at,
                   p.home_location_id, p.college_location_id, p.office_location_id,
                   hl.label as home_label, hl.latitude as home_lat, hl.longitude as home_lng,
                   cl.label as college_label, cl.latitude as college_lat, cl.longitude as college_lng,
                   ol.label as office_label, ol.latitude as office_lat, ol.longitude as office_lng
            from profiles p
            left join saved_locations hl on hl.id = p.home_location_id
            left join saved_locations cl on cl.id = p.college_location_id
            left join saved_locations ol on ol.id = p.office_location_id
            where p.id = :uid
        """), {"uid": uid})).mappings().first()

    profile_data = dict(row)
    profile_data["email"] = email

    profile_data["home"] = {
        "id": str(row["home_location_id"]) if row["home_location_id"] else None,
        "label": row["home_label"],
        "lat": row["home_lat"],
        "lng": row["home_lng"],
    } if row["home_location_id"] else None

    profile_data["college"] = {
        "id": str(row["college_location_id"]) if row["college_location_id"] else None,
        "label": row["college_label"],
        "lat": row["college_lat"],
        "lng": row["college_lng"],
    } if row["college_location_id"] else None

    profile_data["office"] = {
        "id": str(row["office_location_id"]) if row["office_location_id"] else None,
        "label": row["office_label"],
        "lat": row["office_lat"],
        "lng": row["office_lng"],
    } if row["office_location_id"] else None

    return ok(profile_data)


@router.patch("/profile")
async def update_user_profile(
    updates: ProfileUpdate,
    user: dict = Depends(get_current_user),
    session: AsyncSession = Depends(db_dependency),
):
    """Update profile fields (full name, notification preferences, role, saved place pointers)."""
    uid = user["id"]

    clauses = []
    params: Dict[str, Any] = {"uid": uid}

    if updates.full_name is not None:
        clauses.append("full_name = :full_name")
        params["full_name"] = updates.full_name

    if updates.role is not None and updates.role in ["user", "researcher", "admin"]:
        clauses.append("role = :role::user_role_enum")
        params["role"] = updates.role

    if updates.home_location_id is not None:
        clauses.append("home_location_id = :home_loc")
        params["home_loc"] = updates.home_location_id if updates.home_location_id != "" else None

    if updates.college_location_id is not None:
        clauses.append("college_location_id = :coll_loc")
        params["coll_loc"] = updates.college_location_id if updates.college_location_id != "" else None

    if updates.office_location_id is not None:
        clauses.append("office_location_id = :off_loc")
        params["off_loc"] = updates.office_location_id if updates.office_location_id != "" else None

    if updates.notification_prefs is not None:
        clauses.append("notification_prefs = :prefs::jsonb")
        params["prefs"] = json.dumps(updates.notification_prefs)

    if not clauses:
        return ok({"message": "No updates provided"})

    clauses.append("updated_at = now()")
    query = f"update profiles set {', '.join(clauses)} where id = :uid"

    await session.execute(text(query), params)
    await session.commit()

    return ok({"updated": True})


@router.get("/preferences")
async def get_user_preferences(
    user: dict = Depends(get_current_user),
    session: AsyncSession = Depends(db_dependency),
):
    """Get UI preferences (units, theme) for the user."""
    uid = user["id"]
    row = (await session.execute(text("""
        select units, theme, updated_at from user_preferences where user_id = :uid
    """), {"uid": uid})).mappings().first()

    if not row:
        return ok({"units": "metric", "theme": "dark"})
    return ok(dict(row))


@router.put("/preferences")
async def set_user_preferences(
    prefs: PreferencesUpdate,
    user: dict = Depends(get_current_user),
    session: AsyncSession = Depends(db_dependency),
):
    """Upsert UI preferences for the user."""
    uid = user["id"]
    await session.execute(text("""
        insert into user_preferences (user_id, units, theme, updated_at)
        values (:uid, :units, :theme, now())
        on conflict (user_id) do update
        set units = excluded.units, theme = excluded.theme, updated_at = now()
    """), {"uid": uid, "units": prefs.units or "metric", "theme": prefs.theme or "dark"})
    await session.commit()
    return ok({"units": prefs.units, "theme": prefs.theme})
