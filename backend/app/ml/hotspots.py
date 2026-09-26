import math
import numpy as np
from typing import List, Dict, Any
from sklearn.cluster import DBSCAN

def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (math.sin(dlat / 2) ** 2 +
         math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) *
         math.sin(dlon / 2) ** 2)
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

def detect_pune_hotspots(stations: List[Dict[str, Any]], aqi_threshold: float = 90.0) -> List[Dict[str, Any]]:
    """
    Detect spatial pollution clusters across Pune using DBSCAN on high-AQI stations.
    Returns clustered geographical hotspots with severity metrics and human-readable names.
    """
    if not stations:
        return []

    # Filter stations with AQI above threshold or top elevated stations
    elevated = [s for s in stations if (s.get("aqi_value") or 0) >= aqi_threshold]
    if len(elevated) < 2:
        # If threshold is too high, lower to top 50th percentile to detect relative hotspots
        all_aqis = [s.get("aqi_value") or 50 for s in stations]
        median_aqi = float(np.median(all_aqis))
        elevated = [s for s in stations if (s.get("aqi_value") or 0) >= median_aqi]

    if len(elevated) < 2:
        return []

    # Coordinates in radians for Haversine metric in DBSCAN
    coords = np.array([[math.radians(s["latitude"]), math.radians(s["longitude"])] for s in elevated])

    # Epsilon: 6 km radius (~6 / 6371.0 radians)
    kms_per_radian = 6371.0
    epsilon = 6.0 / kms_per_radian

    db = DBSCAN(eps=epsilon, min_samples=2, metric="haversine")
    labels = db.fit_predict(coords)

    hotspots = []
    unique_labels = set(labels)

    for cluster_id in unique_labels:
        if cluster_id == -1:
            # Noise points
            continue

        cluster_stations = [elevated[i] for i, l in enumerate(labels) if l == cluster_id]
        if not cluster_stations:
            continue

        center_lat = sum(s["latitude"] for s in cluster_stations) / len(cluster_stations)
        center_lng = sum(s["longitude"] for s in cluster_stations) / len(cluster_stations)

        # Max distance from center to define cluster radius
        radius_km = max(haversine_km(center_lat, center_lng, s["latitude"], s["longitude"]) for s in cluster_stations)
        radius_km = max(radius_km, 1.5)  # minimum 1.5km display radius

        aqi_vals = [s.get("aqi_value") or 50 for s in cluster_stations]
        peak_aqi = max(aqi_vals)
        mean_aqi = round(sum(aqi_vals) / len(aqi_vals), 1)

        # Determine dominant area name
        areas = [s.get("area") or s.get("name") for s in cluster_stations]
        cluster_name = f"{areas[0]} - {areas[-1]} Corridor" if len(areas) > 1 else areas[0]

        severity = "Severe" if peak_aqi > 200 else ("Very Poor" if peak_aqi > 150 else "Moderate Hotspot")

        hotspots.append({
            "cluster_id": int(cluster_id),
            "name": cluster_name,
            "center": {"latitude": round(center_lat, 5), "longitude": round(center_lng, 5)},
            "radius_km": round(radius_km, 2),
            "station_count": len(cluster_stations),
            "peak_aqi": peak_aqi,
            "average_aqi": mean_aqi, 
            "severity": severity,
            "stations_included": [
                {"id": str(s.get("id")), "name": s.get("name"), "area": s.get("area"), "aqi": s.get("aqi_value")}
                for s in cluster_stations
            ],
            "recommendation": (
                "Avoid heavy exertion in this industrial/traffic corridor."
                if peak_aqi > 150 else "Sensitive groups should reduce prolonged outdoor exposure."
            )
        })

    # Sort hotspots by peak AQI descending
    hotspots.sort(key=lambda x: x["peak_aqi"], reverse=True)
    return hotspots
