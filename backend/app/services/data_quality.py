"""
Validates a single raw observation before it is trusted enough to store.
Produces a 0-100 quality_score and a data_quality_enum classification.
Every check here is a real, checkable condition — nothing here is
decorative; a failing check actually excludes/downgrades the reading.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

# Rough plausible upper bounds per pollutant (µg/m3, mg/m3 for CO) — values
# above these are almost certainly sensor faults, not real air quality.
_PLAUSIBLE_MAX = {
    "pm25": 1000.0, "pm10": 1200.0, "no2": 700.0,
    "so2": 2000.0, "o3": 1200.0, "co": 60.0, "nh3": 3000.0,
}

STALE_AFTER = timedelta(hours=3)


@dataclass
class QualityCheckResult:
    passed: bool
    quality_score: int
    classification: str  # excellent|good|fair|poor|unavailable
    failed_checks: list[str]


def validate_observation(pollutant_code: str, value: float, observed_at: datetime) -> QualityCheckResult:
    failed: list[str] = []
    now = datetime.now(timezone.utc)

    if value is None:
        failed.append("missing_value")
    elif value < 0:
        failed.append("negative_value")
    elif value == 0:
        # Not necessarily wrong, but flagged for review rather than silently trusted
        failed.append("zero_value_flagged")

    max_plausible = _PLAUSIBLE_MAX.get(pollutant_code)
    if max_plausible and value is not None and value > max_plausible:
        failed.append("implausible_concentration")

    if observed_at is not None:
        if observed_at.tzinfo is None:
            observed_at = observed_at.replace(tzinfo=timezone.utc)
        if observed_at > now + timedelta(minutes=5):
            failed.append("future_timestamp")
        if now - observed_at > STALE_AFTER:
            failed.append("stale_observation")
    else:
        failed.append("missing_timestamp")

    hard_failures = {"missing_value", "negative_value", "implausible_concentration",
                      "future_timestamp", "missing_timestamp"}
    passed = not any(f in hard_failures for f in failed)

    # Score: start at 100, deduct per issue found (soft issues cost less)
    score = 100
    deductions = {
        "zero_value_flagged": 10, "stale_observation": 20,
        "implausible_concentration": 100, "negative_value": 100,
        "missing_value": 100, "future_timestamp": 100, "missing_timestamp": 100,
    }
    for f in failed:
        score -= deductions.get(f, 15)
    score = max(0, min(100, score))

    if not passed:
        classification = "unavailable"
    elif score >= 90:
        classification = "excellent"
    elif score >= 75:
        classification = "good"
    elif score >= 50:
        classification = "fair"
    else:
        classification = "poor"

    return QualityCheckResult(passed=passed, quality_score=score,
                               classification=classification, failed_checks=failed)
