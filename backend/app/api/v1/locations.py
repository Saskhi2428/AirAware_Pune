import math
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, Query, HTTPException, Body
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import get_current_user
from app.core.db import db_dependency, get_session
from app.core.responses import ok, fail

router = APIRouter(prefix="/locations", tags=["locations"])

# Haversine distance calculator in kilometers
def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (math.sin(dlat / 2) ** 2 +
         math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) *
         math.sin(dlon / 2) ** 2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return r * c

# Known Pune localities reference database
PUNE_LOCALITIES = [
    {"name": "Shivajinagar", "lat": 18.5314, "lng": 73.8446, "area": "Central Pune"},
    {"name": "Kothrud", "lat": 18.5074, "lng": 73.8077, "area": "West Pune"},
    {"name": "Karve Road", "lat": 18.5012, "lng": 73.8166, "area": "West Pune"},
    {"name": "Deccan Gymkhana", "lat": 18.5173, "lng": 73.8415, "area": "Central Pune"},
    {"name": "SPPU / University Area", "lat": 18.5529, "lng": 73.8260, "area": "North-West Pune"},
    {"name": "Aundh", "lat": 18.5580, "lng": 73.8073, "area": "North-West Pune"},
    {"name": "Baner", "lat": 18.5590, "lng": 73.7868, "area": "West Pune"},
    {"name": "Balewadi", "lat": 18.5741, "lng": 73.7744, "area": "West Pune"},
    {"name": "Pashan", "lat": 18.5416, "lng": 73.8055, "area": "West Pune"},
    {"name": "Bavdhan", "lat": 18.5133, "lng": 73.7699, "area": "West Pune"},
    {"name": "Wakad", "lat": 18.5987, "lng": 73.7688, "area": "PCMC / West Pune"},
    {"name": "Bhumkar Chowk", "lat": 18.5991, "lng": 73.7548, "area": "PCMC / Hinjawadi Corridor"},
    {"name": "Hinjewadi / Hinjawadi Phase 1", "lat": 18.5913, "lng": 73.7389, "area": "IT Park Corridor"},
    {"name": "Hinjawadi Phase 2", "lat": 18.5835, "lng": 73.7142, "area": "IT Park Corridor"},
    {"name": "Hinjawadi Phase 3", "lat": 18.5752, "lng": 73.6912, "area": "IT Park Corridor"},
    {"name": "Hadapsar", "lat": 18.5089, "lng": 73.9260, "area": "East Pune"},
    {"name": "Magarpatta City", "lat": 18.5167, "lng": 73.9298, "area": "East Pune / IT Park"},
    {"name": "Kharadi", "lat": 18.5514, "lng": 73.9348, "area": "East Pune / IT Park"},
    {"name": "Viman Nagar", "lat": 18.5679, "lng": 73.9143, "area": "North-East Pune"},
    {"name": "Kalyani Nagar", "lat": 18.5463, "lng": 73.9033, "area": "East Pune"},
    {"name": "Koregaon Park", "lat": 18.5362, "lng": 73.8940, "area": "Central-East Pune"},
    {"name": "Yerawada", "lat": 18.5529, "lng": 73.8797, "area": "North-East Pune"},
    {"name": "Swargate", "lat": 18.5018, "lng": 73.8580, "area": "South-Central Pune"},
    {"name": "Camp / Pune Cantonment", "lat": 18.5135, "lng": 73.8821, "area": "Cantonment"},
    {"name": "Katraj", "lat": 18.4529, "lng": 73.8553, "area": "South Pune"},
    {"name": "Kondhwa", "lat": 18.4744, "lng": 73.8890, "area": "South-East Pune"},
    {"name": "Bibwewadi", "lat": 18.4735, "lng": 73.8611, "area": "South Pune"},
    {"name": "Pimpri", "lat": 18.6279, "lng": 73.8009, "area": "PCMC Central"},
    {"name": "Chinchwad", "lat": 18.6298, "lng": 73.7997, "area": "PCMC Central"},
    {"name": "Bhosari", "lat": 18.6401, "lng": 73.8490, "area": "PCMC Industrial MIDC"},
    {"name": "Akurdi", "lat": 18.6496, "lng": 73.7712, "area": "PCMC North"},
    {"name": "Nigdi", "lat": 18.6643, "lng": 73.7640, "area": "PCMC North"},
    {"name": "Alandi", "lat": 18.6775, "lng": 73.8967, "area": "North Pune Suburb"},
]


@router.get("/nearest-station")
async def get_nearest_station(
    lat: float = Query(..., description="Latitude"),
    lng: float = Query(..., description="Longitude"),
    session: AsyncSession = Depends(db_dependency),
):
    """Find the nearest active Pune monitoring station for a GPS point, calculating exact distance and real AQI."""
    stations = (await session.execute(text("""
        select s.id, s.name, s.area, s.location_type, s.latitude, s.longitude, s.health,
               a.aqi_value, a.aqi_category, a.dominant_pollutant, a.computed_for
        from monitoring_stations s
        left join lateral (
            select aqi_value, aqi_category, dominant_pollutant, computed_for
            from aqi_computations ac
            where ac.station_id = s.id
            order by computed_for desc limit 1
        ) a on true
        where s.is_active = true and a.aqi_value is not null
    """))).mappings().all()

    if not stations:
        return fail("No active monitoring stations found", error_code="NO_STATIONS", status_code=404)

    # Calculate distance to every station
    closest_station = None
    min_dist = float("inf")

    for st in stations:
        dist = haversine_km(lat, lng, st["latitude"], st["longitude"])
        if dist < min_dist:
            min_dist = dist
            closest_station = st

    is_direct_measure = min_dist <= 1.0

    return ok({
        "location": {"latitude": lat, "longitude": lng},
        "nearest_station": {
            "id": str(closest_station["id"]),
            "name": closest_station["name"],
            "area": closest_station["area"] or closest_station["name"].split(",")[0],
            "latitude": closest_station["latitude"],
            "longitude": closest_station["longitude"],
            "distance_km": round(min_dist, 2),
            "aqi_value": closest_station["aqi_value"],
            "aqi_category": closest_station["aqi_category"],
            "dominant_pollutant": (closest_station["dominant_pollutant"] or "pm25").upper(),
            "computed_for": closest_station["computed_for"].isoformat() if closest_station["computed_for"] else None,
            "station_health": closest_station["health"],
        },
        "data_classification": "measured_station" if is_direct_measure else "estimated_from_nearest",
        "transparency_note": (
            f"Direct measurement at {closest_station['name']}"
            if is_direct_measure else
            f"Estimated from nearest official station ({closest_station['area']}, {round(min_dist, 1)} km away)"
        ),
    })


@router.get("/search")
async def search_pune_localities(
    q: str = Query(..., min_length=1, description="Locality search term"),
    session: AsyncSession = Depends(db_dependency),
):
    """Search Pune neighborhoods and return nearest station with live air quality."""
    query = q.lower().strip()
    matches = [loc for loc in PUNE_LOCALITIES if query in loc["name"].lower() or query in loc["area"].lower()]

    if not matches:
        return ok([])

    stations = (await session.execute(text("""
        select s.id, s.name, s.area, s.latitude, s.longitude,
               a.aqi_value, a.aqi_category, a.dominant_pollutant
        from monitoring_stations s
        left join lateral (
            select aqi_value, aqi_category, dominant_pollutant
            from aqi_computations ac where ac.station_id = s.id order by computed_for desc limit 1
        ) a on true
        where s.is_active = true and a.aqi_value is not null
    """))).mappings().all()

    results = []
    for loc in matches[:10]:
        # Find nearest station
        nearest = None
        min_d = float("inf")
        for st in stations:
            d = haversine_km(loc["lat"], loc["lng"], st["latitude"], st["longitude"])
            if d < min_d:
                min_d = d
                nearest = st

        results.append({
            "locality": loc["name"],
            "area_region": loc["area"],
            "latitude": loc["lat"],
            "longitude": loc["lng"],
            "nearest_station": {
                "id": str(nearest["id"]) if nearest else None,
                "name": nearest["name"] if nearest else "Pune Central",
                "distance_km": round(min_d, 1) if nearest else 0,
                "aqi_value": nearest["aqi_value"] if nearest else 80,
                "aqi_category": nearest["aqi_category"] if nearest else "Satisfactory",
                "dominant_pollutant": (nearest["dominant_pollutant"] or "pm25").upper() if nearest else "PM2.5",
            }
        })

    return ok(results)


class SavedLocationCreate(BaseModel):
    label: str  # 'Home', 'College', 'Office', 'Custom'
    locality_name: Optional[str] = None
    latitude: float
    longitude: float


@router.get("/saved-locations")
async def list_saved_locations(
    user: dict = Depends(get_current_user),
    session: AsyncSession = Depends(db_dependency),
):
    """List saved locations for the authenticated user with live nearest-station AQI."""
    rows = (await session.execute(text("""
        select sl.id, sl.label, sl.latitude, sl.longitude, sl.nearest_station_id,
               s.name as station_name, s.area as station_area,
               a.aqi_value, a.aqi_category, a.dominant_pollutant
        from saved_locations sl
        left join monitoring_stations s on s.id = sl.nearest_station_id
        left join lateral (
            select aqi_value, aqi_category, dominant_pollutant
            from aqi_computations ac where ac.station_id = s.id order by computed_for desc limit 1
        ) a on true
        where sl.user_id = :uid
        order by sl.created_at asc
    """), {"uid": user["id"]})).mappings().all()

    return ok([{
        "id": str(r["id"]),
        "label": r["label"],
        "latitude": r["latitude"],
        "longitude": r["longitude"],
        "nearest_station_name": r["station_name"],
        "nearest_station_area": r["station_area"],
        "aqi_value": r["aqi_value"],
        "aqi_category": r["aqi_category"],
        "dominant_pollutant": (r["dominant_pollutant"] or "pm25").upper() if r["dominant_pollutant"] else "PM2.5",
    } for r in rows])


@router.post("/saved-locations")
async def create_saved_location(
    loc: SavedLocationCreate,
    user: dict = Depends(get_current_user),
    session: AsyncSession = Depends(db_dependency),
):
    """Save an important location (Home, College, Office, etc.) with nearest station mapping."""
    # Find nearest station
    stations = (await session.execute(text("select id, latitude, longitude from monitoring_stations where is_active=true"))).all()
    nearest_id = None
    min_dist = float("inf")
    for st_id, s_lat, s_lng in stations:
        d = haversine_km(loc.latitude, loc.longitude, s_lat, s_lng)
        if d < min_dist:
            min_dist = d
            nearest_id = st_id

    res = await session.execute(text("""
        insert into saved_locations (user_id, label, latitude, longitude, nearest_station_id)
        values (:uid, :lbl, :lat, :lng, :nid)
        returning id, label, latitude, longitude, nearest_station_id
    """), {
        "uid": user["id"],
        "lbl": loc.label,
        "lat": loc.latitude,
        "lng": loc.longitude,
        "nid": nearest_id,
    })
    await session.commit()
    row = dict(res.mappings().first())
    row["id"] = str(row["id"])
    if row.get("nearest_station_id"):
        row["nearest_station_id"] = str(row["nearest_station_id"])
    return ok(row)


@router.delete("/saved-locations/{location_id}")
async def delete_saved_location(
    location_id: str,
    user: dict = Depends(get_current_user),
    session: AsyncSession = Depends(db_dependency),
):
    """Delete a saved location."""
    await session.execute(text("""
        delete from saved_locations where id = :id and user_id = :uid
    """), {"id": location_id, "uid": user["id"]})
    await session.commit()
    return ok({"deleted": True, "id": location_id})
