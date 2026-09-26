from datetime import datetime, timezone
from typing import Any

from fastapi.responses import JSONResponse


def ok(data: Any = None, message: str | None = None, status_code: int = 200) -> JSONResponse:
    return JSONResponse(status_code=status_code, content={
        "success": True,
        "data": data,
        "message": message,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    })


def fail(message: str, error_code: str = "ERROR", status_code: int = 400) -> JSONResponse:
    return JSONResponse(status_code=status_code, content={
        "success": False,
        "data": None,
        "message": message,
        "error_code": error_code,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    })
