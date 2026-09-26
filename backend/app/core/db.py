"""
Async SQLAlchemy engine pointed at Supabase's Postgres (DATABASE_URL).
We use SQLAlchemy Core (raw `text()` queries) rather than the ORM here,
since the schema is managed by hand-written migrations (migrations/*.sql),
not by ORM models — this avoids two sources of truth for the schema.
"""
from __future__ import annotations

import socket
from contextlib import asynccontextmanager

from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker

from app.core.config import settings

# ---------------------------------------------------------------------------
# WINDOWS IPv4-ONLY DNS WORKAROUND
#
# On some Windows machines (common with campus/hostel networks, VPN clients,
# or certain virtual network adapters), the system has a broken or partial
# IPv6 stack. Python's asyncio resolves hostnames with a dual-stack query
# (both A and AAAA records in one call) via socket.getaddrinfo(). If the
# IPv6 half of that query fails, Windows returns WSAENODATA / error 11003
# ("getaddrinfo failed") for the ENTIRE lookup — even though a plain IPv4-only
# lookup (which is what `nslookup` does by default) succeeds fine.
#
# This monkeypatch forces every DNS lookup in this process to ask for IPv4
# (AF_INET) addresses only, sidestepping the broken IPv6 path entirely.
# This is safe: Supabase's pooler is reachable over IPv4, which is exactly
# what `nslookup` already confirmed above.
# ---------------------------------------------------------------------------
_original_getaddrinfo = socket.getaddrinfo


def _ipv4_only_getaddrinfo(host, port, family=0, type=0, proto=0, flags=0):
    try:
        return _original_getaddrinfo(host, port, socket.AF_INET, type, proto, flags)
    except Exception:
        return _original_getaddrinfo(host, port, family, type, proto, flags)


socket.getaddrinfo = _ipv4_only_getaddrinfo

# Supabase's connection string uses postgresql://; asyncpg driver needs postgresql+asyncpg://
_db_url = settings.DATABASE_URL.replace("postgresql://", "postgresql+asyncpg://", 1)

# IMPORTANT: if DATABASE_URL points at Supabase's connection POOLER
# (port 6543, host contains "pooler.supabase.com"), it runs PgBouncer in
# transaction mode, which does not support asyncpg's server-side prepared
# statements. Without disabling them, every query fails with something like
# "DuplicatePreparedStatementError" or a generic connection error — which is
# exactly the kind of unhandled crash that used to surface to Flutter as a
# raw "Internal Server Error" text body. statement_cache_size=0 disables
# asyncpg's prepared-statement cache so it works against the pooler too.
# If you're on the direct connection (port 5432), this setting is harmless.
_connect_args = {"statement_cache_size": 0} if "pooler" in _db_url else {}

engine = create_async_engine(
    _db_url,
    pool_size=20,
    max_overflow=15,
    pool_timeout=10,
    pool_pre_ping=True,
    connect_args=_connect_args,
)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)


@asynccontextmanager
async def get_session():
    async with SessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()


async def db_dependency():
    async with SessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()