import pytest
import pytest_asyncio
import httpx
from app.main import app

@pytest.mark.asyncio
async def test_pune_data_health():
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
        r = await client.get("/api/v1/pune/data-health")
        assert r.status_code == 200
        data = r.json()["data"]
        assert data["status"] == "Healthy"
        assert "Pune" in data["region"]
        assert data["telemetry_health"]["active_stations"] >= 25

@pytest.mark.asyncio
async def test_pune_citizen_reports_and_creation():
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
        # Fetch reports
        r = await client.get("/api/v1/pune/citizen-reports")
        assert r.status_code == 200
        reports = r.json()["data"]
        assert isinstance(reports, list)

        # Create report
        payload = {
            "ward": "Kothrud Paud Road",
            "category": "Garbage Burning",
            "description": "Smoke haze spotted along Paud canal path",
            "latitude": 18.5074,
            "longitude": 73.8077
        }
        rc = await client.post("/api/v1/pune/citizen-reports", json=payload)
        assert rc.status_code == 200
        new_rep = rc.json()["data"]
        assert new_rep["ward"] == "Kothrud Paud Road"
        assert new_rep["category"] == "Garbage Burning"

@pytest.mark.asyncio
async def test_pune_ai_assistant():
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
        payload = {"message": "Is it safe to run in Pashan this morning?"}
        r = await client.post("/api/v1/pune/assistant", json=payload)
        assert r.status_code == 200
        data = r.json()["data"]
        assert "answer" in data
        assert "current_aqi" in data
        assert "key_recommendations" in data
        assert isinstance(data["key_recommendations"], list)

@pytest.mark.asyncio
async def test_pune_stations_and_history():
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
        r = await client.get("/api/v1/pune/stations")
        assert r.status_code == 200
        stations = r.json()["data"]
        assert len(stations) >= 25
        sid = stations[0]["id"]

        rh = await client.get(f"/api/v1/pune/stations/{sid}/history?range=24h")
        assert rh.status_code == 200
        hist = rh.json()["data"]
        assert isinstance(hist, list)

@pytest.mark.asyncio
async def test_pune_pulse():
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
        r = await client.get("/api/v1/pune/pulse")
        assert r.status_code == 200
        data = r.json()["data"]
        assert "average_aqi" in data
        assert "cleanest_area" in data
        assert "most_polluted_area" in data

@pytest.mark.asyncio
async def test_pune_forecast():
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
        r = await client.get("/api/v1/pune/forecast")
        assert r.status_code == 200
        data = r.json()["data"]
        assert "milestones" in data
        assert "1h" in data["milestones"]
        assert "3h" in data["milestones"]
        assert "6h" in data["milestones"]
        assert "12h" in data["milestones"]
        assert "24h" in data["milestones"]
        assert len(data["hourly_forecast"]) == 24

@pytest.mark.asyncio
async def test_pune_explainability():
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
        r = await client.get("/api/v1/pune/explainability")
        assert r.status_code == 200
        data = r.json()["data"]
        assert "attribution_factors" in data
        assert len(data["attribution_factors"]) > 0
