import logging
import traceback
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.core.config import settings
from app.core.responses import ok, fail
from app.api.v1 import pune, admin, locations, users, alerts, exposure
from app.scheduler.jobs import start_scheduler

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("airaware")


@asynccontextmanager
async def lifespan(app: FastAPI):
    start_scheduler()
    async def _bg_startup_maintenance():
        try:
            from app.services.platform_maintenance_service import run_full_platform_maintenance
            logger.info("Running initial platform maintenance pass in background...")
            await run_full_platform_maintenance()
        except Exception as e:
            logger.warning("Startup platform maintenance warning: %s", e)
    import asyncio
    asyncio.create_task(_bg_startup_maintenance())
    yield


app = FastAPI(title="AIRAWare API & Pune Intelligence Platform", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if settings.ENVIRONMENT == "development" else settings.CORS_ALLOWED_ORIGINS.split(","),
    allow_credentials=settings.ENVIRONMENT != "development",
    allow_methods=["*"],
    allow_headers=["*"],
)

from fastapi.middleware.gzip import GZipMiddleware
from sqlalchemy import text
from app.core.db import get_session

app.add_middleware(GZipMiddleware, minimum_size=1000)

@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "SAMEORIGIN"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    return response

app.include_router(pune.router, prefix=settings.API_V1_PREFIX)
app.include_router(locations.router, prefix=settings.API_V1_PREFIX)
app.include_router(users.router, prefix=settings.API_V1_PREFIX)
app.include_router(admin.router, prefix=settings.API_V1_PREFIX)
app.include_router(alerts.router, prefix=settings.API_V1_PREFIX)
app.include_router(exposure.router, prefix=settings.API_V1_PREFIX)


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    full_trace = traceback.format_exc()
    logger.error("UNHANDLED EXCEPTION on %s %s:\n%s", request.method, request.url.path, full_trace)
    detail = str(exc) if settings.ENVIRONMENT == "development" else "Internal server error"
    return fail(detail, error_code="INTERNAL_ERROR", status_code=500)


@app.get("/health")
async def health():
    return ok({"status": "up", "environment": settings.ENVIRONMENT,
               "openaq_configured": settings.openaq_configured,
               "cpcb_configured": settings.cpcb_configured})


@app.get("/ready")
async def readiness_check():
    """Readiness probe for Kubernetes, Docker, and Cloud Load Balancers."""
    try:
        async with get_session() as session:
            await session.execute(text("SELECT 1"))
        return ok({"ready": True, "database": "connected"})
    except Exception as e:
        return fail(f"Database connectivity check failed: {e}", status_code=503)


@app.get("/")
async def root():
    """Mobile API Root Status Endpoint."""
    return ok({
        "service": "AirAware Pune Intelligence Platform",
        "version": "1.0.0",
        "target": "Mobile App API",
        "status": "online",
        "docs": "/docs",
    })