@echo off
title AirAware Pune - Real-Time Multi-Platform Server
echo ========================================================
echo   AirAware Pune - Environmental Intelligence Platform
echo   Real-time Air Quality, Safe Commute & Exposure Engine
echo ========================================================
echo.

cd /d "%~dp0backend"
echo [1/3] Checking Python virtual environment...
if not exist ".venv\Scripts\python.exe" (
    echo Virtual environment not found in backend\.venv. Creating...
    python -m venv .venv
    call .venv\Scripts\activate
    pip install -r requirements.txt
) else (
    call .venv\Scripts\activate
)

echo [2/3] Verifying Pune monitoring stations and live observations...
set PYTHONPATH=.
python app\services\populate_pune_stations.py

echo [3/3] Starting AirAware backend and web app server on http://localhost:8000 ...
start "" http://localhost:8000
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
pause
