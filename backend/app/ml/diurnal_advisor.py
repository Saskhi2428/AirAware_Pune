from typing import Dict, Any, List

def get_pune_activity_advisor(current_aqi: float, current_hour: int) -> Dict[str, Any]:
    """
    Provides practical, health-aligned Pune outdoor activity guidance
    based on local diurnal pollution rhythms.
    """
    # Pune specific optimal windows:
    # Early morning: 05:30 AM to 07:15 AM (Before morning inversion/traffic peak)
    # Late afternoon: 03:00 PM to 05:00 PM (Highest convective boundary layer)
    # Avoid: 08:30 AM to 10:30 AM & 07:00 PM to 09:30 PM

    recommendations = []

    if current_aqi <= 50:
        outdoor_safe = True
        mask_needed = False
        guidance = "Air quality is pristine! Ideal conditions for running, cycling, and outdoor recreation across all Pune gardens and hills (ARAI, Taljai, Vetal Tekdi)."
    elif current_aqi <= 100:
        outdoor_safe = True
        mask_needed = False
        guidance = "Air quality is satisfactory. Safe for normal outdoor activities. Prefer greener zones away from major arterials."
    elif current_aqi <= 200:
        outdoor_safe = False
        mask_needed = True
        guidance = "Moderate air pollution. People with asthma or respiratory sensitivities should avoid intense cardio near high-traffic chowks."
    else:
        outdoor_safe = False
        mask_needed = True
        guidance = "Poor air quality. Limit strenuous outdoor exercise. N95 mask recommended for active commuters."

    return {
        "current_air_quality": "Safe" if outdoor_safe else "Caution",
        "mask_recommended": mask_needed,
        "activity_guidance": guidance,
        "optimal_windows": [
            {
                "activity": "Morning Walk / Running / Tekdi Hike",
                "recommended_time": "05:30 AM - 07:00 AM",
                "why": "Cleanest boundary layer before morning traffic sets in.",
                "rating": "Best"
            },
            {
                "activity": "Afternoon Outdoor Sports",
                "recommended_time": "03:30 PM - 05:00 PM",
                "why": "Maximum convective mixing clears low-level exhaust.",
                "rating": "Good"
            },
            {
                "activity": "Commute & Errands Window",
                "recommended_time": "Avoid 08:30 AM - 10:30 AM and 07:00 PM - 09:00 PM",
                "why": "Peak vehicle congestion sharply elevates localized PM2.5 & NO2.",
                "rating": "Avoid Peak"
            }
        ],
        "vulnerable_groups_advice": {
            "children": "Safe for standard play unless AQI exceeds 150.",
            "elderly": "Prefer morning walks in green spaces (Empress Garden, Sarasbaug, Tekdi) before 7:30 AM.",
            "athletes": "Shift high-intensity workouts away from highways and transit corridors."
        }
    }
