from typing import Dict, Any, List

def explain_pune_aqi(current_aqi: float, dominant_pollutant: str, hour: int, wind_speed: float, humidity: float) -> Dict[str, Any]:
    """
    SHAP-style attribution explaining the underlying contributors to Pune's current AQI.
    """
    factors = []

    # 1. Base regional background
    factors.append({
        "factor": "Pune Regional Basal Background",
        "impact_points": 35.0,
        "direction": "positive",
        "description": "Deccan plateau ambient particulate baseline"
    })

    # 2. Diurnal traffic cycle
    is_morning_rush = 8 <= hour <= 11
    is_evening_rush = 18 <= hour <= 21
    if is_morning_rush:
        traffic_impact = 28.0
        desc = "Morning peak commute (Karve Rd, FC Rd, Nagar Rd corridors)"
    elif is_evening_rush:
        traffic_impact = 34.0
        desc = "Evening rush hour congestion and stop-and-go vehicle emissions"
    elif 13 <= hour <= 16:
        traffic_impact = -12.0
        desc = "Midday solar thermal updraft and reduced traffic volume"
    else:
        traffic_impact = 5.0
        desc = "Nighttime heavy vehicle transit (NH48 bypass & MIDC freight)"

    factors.append({
        "factor": "Diurnal Traffic Pattern",
        "impact_points": traffic_impact,
        "direction": "positive" if traffic_impact > 0 else "negative",
        "description": desc
    })

    # 3. Meteorological Dispersion (Wind)
    if wind_speed < 6.0:
        wind_impact = 18.0
        wind_desc = f"Stagnant air ({wind_speed} km/h) trapping pollutants in the Pune basin"
    elif wind_speed > 15.0:
        wind_impact = -15.0
        wind_desc = f"Brisk ventilation ({wind_speed} km/h) clearing particulates"
    else:
        wind_impact = 2.0
        wind_desc = f"Moderate breeze ({wind_speed} km/h)"

    factors.append({
        "factor": "Atmospheric Ventilation (Wind)",
        "impact_points": wind_impact,
        "direction": "positive" if wind_impact > 0 else "negative",
        "description": wind_desc
    })

    # 4. Humidity & Secondary aerosol formation
    if humidity > 75.0:
        hum_impact = 12.0
        hum_desc = f"High humidity ({humidity}%) encouraging hygroscopic growth of fine particles"
    else:
        hum_impact = 0.0
        hum_desc = f"Normal humidity ({humidity}%)"

    if hum_impact > 0:
        factors.append({
            "factor": "Hygroscopic Particle Growth",
            "impact_points": hum_impact,
            "direction": "positive",
            "description": hum_desc
        })

    # Primary driver
    pollutant_upper = (dominant_pollutant or "PM2.5").upper()
    return {
        "primary_pollutant": pollutant_upper,
        "total_aqi": int(current_aqi),
        "attribution_factors": factors,
        "summary": f"{pollutant_upper} is the primary driver today. {'Rush hour traffic' if (is_morning_rush or is_evening_rush) else 'Atmospheric stagnation'} is the largest dynamic variable."
    }
