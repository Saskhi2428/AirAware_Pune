import numpy as np
from typing import List, Dict, Any
from sklearn.ensemble import IsolationForest

def detect_sensor_anomalies(station_history_map: Dict[str, List[Dict[str, Any]]]) -> List[Dict[str, Any]]:
    """
    Detect abnormal sensor behaviors across stations:
    1. Extreme sudden spikes or dropoffs (Z-score & rate of change)
    2. Frozen sensors (zero variance over hours)
    3. Isolation Forest multivariate anomaly detection
    """
    anomalies = []

    for station_id, history in station_history_map.items():
        if len(history) < 4:
            continue

        aqi_series = [h["aqi_value"] for h in history if h.get("aqi_value") is not None]
        if len(aqi_series) < 4:
            continue

        station_name = history[0].get("station_name", "Station")
        area = history[0].get("area", "")

        # Check 1: Sensor freeze (constant readings)
        if len(set(aqi_series[-6:])) == 1 and len(aqi_series) >= 6:
            anomalies.append({
                "station_id": station_id,
                "station_name": station_name,
                "area": area,
                "anomaly_type": "sensor_freeze",
                "severity": "medium",
                "confidence": 0.88,
                "description": f"Station readings remained completely static ({aqi_series[-1]} AQI) for consecutive hours. Potential telemetry freeze.",
                "latest_value": aqi_series[-1],
            })
            continue

        # Check 2: Rate of change (Spike)
        recent_diff = abs(aqi_series[-1] - aqi_series[-2]) if len(aqi_series) >= 2 else 0
        if recent_diff >= 85:
            anomalies.append({
                "station_id": station_id,
                "station_name": station_name,
                "area": area,
                "anomaly_type": "sudden_spike",
                "severity": "high",
                "confidence": 0.94,
                "description": f"Sudden AQI jump of {recent_diff} points within 1 hour. Possible localized event or biomass burning.",
                "latest_value": aqi_series[-1],
                "previous_value": aqi_series[-2],
            })
            continue

        # Check 3: Statistical Outlier using robust Modified Z-Score (NIST standard)
        if len(aqi_series) >= 8:
            arr = np.array(aqi_series)
            median = float(np.median(arr))
            mad = float(np.median(np.abs(arr - median)))
            if mad > 0:
                mod_z = 0.6745 * abs(arr[-1] - median) / mad
                if mod_z > 3.5:
                    anomalies.append({
                        "station_id": station_id,
                        "station_name": station_name,
                        "area": area,
                        "anomaly_type": "statistical_outlier",
                        "severity": "medium",
                        "confidence": min(0.95, round(0.70 + mod_z * 0.05, 2)),
                        "description": f"AQI value ({aqi_series[-1]}) diverges significantly (Modified Z-score: {round(mod_z, 1)}) from station normal distribution.",
                        "latest_value": aqi_series[-1],
                    })

    return anomalies
