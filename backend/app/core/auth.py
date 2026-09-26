"""
Validates the bearer token Flutter sends (the Supabase session access_token)
by asking Supabase's own Auth API who it belongs to — this is the safest
approach since it means we never need Supabase's JWT signing secret on the
backend, only the anon key, and revoked/expired tokens are rejected by
Supabase itself rather than by our own (easier to get wrong) JWT logic.
"""
from __future__ import annotations

from fastapi import Depends, Header, HTTPException
from sqlalchemy import text
from supabase import create_client, Client

from app.core.config import settings
from app.core.db import get_session

_supabase_client: Client | None = None


def _client() -> Client:
    global _supabase_client
    if _supabase_client is None:
        _supabase_client = create_client(settings.SUPABASE_URL, settings.SUPABASE_ANON_KEY)
    return _supabase_client


async def get_current_user(authorization: str = Header(default="")):
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.removeprefix("Bearer ").strip()

    try:
        user_resp = _client().auth.get_user(token)
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"Invalid session: {e}")

    if not user_resp or not user_resp.user:
        raise HTTPException(status_code=401, detail="Invalid or expired session")

    return {"id": user_resp.user.id, "email": user_resp.user.email}


async def require_admin(current_user: dict = Depends(get_current_user)) -> dict:
    """FastAPI dependency: use as `Depends(require_admin)` on any admin-only route.
    It resolves get_current_user internally, then enforces role='admin'."""
    async with get_session() as session:
        row = (await session.execute(
            text("select role from profiles where id = :id"), {"id": current_user["id"]}
        )).first()
    if not row or row[0] != "admin":
        raise HTTPException(status_code=403, detail="Admin role required")
    return current_user
