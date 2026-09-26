"""
Indian National Air Quality Index (NAQI) calculator — CPCB methodology.

Reference: CPCB "National Air Quality Index" technical document
(https://cpcb.nic.in/National-Air-Quality-Index/), breakpoint table
reproduced below. This is the standard used across India's own AQI
dashboards — we do NOT invent our own scale, and we do NOT blindly
average pollutant concentrations together (spec section 9).

Method:
  1. For each pollutant with a valid concentration, compute a sub-index
     via linear interpolation within its CPCB breakpoint band.
  2. Overall AQI = max(sub-indices) — CPCB's own "worst pollutant governs"
     rule, not an average.
  3. dominant_pollutant = the pollutant whose sub-index equals the max.
  4. If fewer than one usable pollutant sub-index exists, AQI cannot be
     computed — caller must treat as unavailable, never a guess.

NOTE ON AVERAGING PERIODS: CPCB uses 24-hr averages for PM2.5/PM10/SO2/NO2/NH3
and 8-hr averages for CO/O3. Phase 3 (aggregation service) is responsible for
feeding this function pre-averaged values over the correct window; this
module only does the breakpoint math and takes whatever value it's given.
"""
from __future__ import annotations

from dataclasses import dataclass

# (pollutant_code, breakpoints: list of (BPLow, BPHigh, ILow, IHigh))
_BREAKPOINTS: dict[str, list[tuple[float, float, int, int]]] = {
    "pm25": [
        (0, 30, 0, 50), (31, 60, 51, 100), (61, 90, 101, 200),
        (91, 120, 201, 300), (121, 250, 301, 400), (251, 500, 401, 500),
    ],
    "pm10": [
        (0, 50, 0, 50), (51, 100, 51, 100), (101, 250, 101, 200),
        (251, 350, 201, 300), (351, 430, 301, 400), (431, 700, 401, 500),
    ],
    "no2": [
        (0, 40, 0, 50), (41, 80, 51, 100), (81, 180, 101, 200),
        (181, 280, 201, 300), (281, 400, 301, 400), (401, 700, 401, 500),
    ],
    "o3": [
        (0, 50, 0, 50), (51, 100, 51, 100), (101, 168, 101, 200),
        (169, 208, 201, 300), (209, 748, 301, 400), (749, 1200, 401, 500),
    ],
    "co": [  # mg/m3
        (0, 1.0, 0, 50), (1.1, 2.0, 51, 100), (2.1, 10, 101, 200),
        (10.1, 17, 201, 300), (17.1, 34, 301, 400), (34.1, 60, 401, 500),
    ],
    "so2": [
        (0, 40, 0, 50), (41, 80, 51, 100), (81, 380, 101, 200),
        (381, 800, 201, 300), (801, 1600, 301, 400), (1601, 2600, 401, 500),
    ],
    "nh3": [
        (0, 200, 0, 50), (201, 400, 51, 100), (401, 800, 101, 200),
        (801, 1200, 201, 300), (1201, 1800, 301, 400), (1801, 3000, 401, 500),
    ],
}

_CATEGORY_BANDS = [
    (0, 50, "Good"), (51, 100, "Satisfactory"), (101, 200, "Moderate"),
    (201, 300, "Poor"), (301, 400, "Very Poor"), (401, 500, "Severe"),
]


def _sub_index(pollutant_code: str, concentration: float) -> float | None:
    bands = _BREAKPOINTS.get(pollutant_code)
    if bands is None or concentration is None or concentration < 0:
        return None
    for bp_low, bp_high, i_low, i_high in bands:
        if bp_low <= concentration <= bp_high:
            return ((i_high - i_low) / (bp_high - bp_low)) * (concentration - bp_low) + i_low
    # Above the top of the table: clamp to the top band's upper index rather
    # than extrapolating indefinitely (CPCB's own dashboards do the same).
    if concentration > bands[-1][1]:
        return float(bands[-1][3])
    return None


def _category_for(aqi_value: float) -> str:
    for lo, hi, label in _CATEGORY_BANDS:
        if lo <= aqi_value <= hi:
            return label
    return "Severe"


@dataclass
class AqiResult:
    aqi_value: int
    aqi_category: str
    dominant_pollutant: str
    standard: str
    sub_indices: dict[str, float]


def calculate_aqi(pollutant_concentrations: dict[str, float]) -> AqiResult | None:
    """
    pollutant_concentrations: e.g. {'pm25': 68.0, 'pm10': 140.0, 'no2': 35.0}
    Returns None if no pollutant produced a usable sub-index — caller must
    surface this as "AQI unavailable", never guess a number.
    """
    sub_indices: dict[str, float] = {}
    for code, value in pollutant_concentrations.items():
        si = _sub_index(code, value)
        if si is not None:
            sub_indices[code] = si

    if not sub_indices:
        return None

    dominant = max(sub_indices, key=sub_indices.get)
    aqi_value = round(sub_indices[dominant])
    return AqiResult(
        aqi_value=aqi_value,
        aqi_category=_category_for(aqi_value),
        dominant_pollutant=dominant,
        standard="CPCB-NAQI",
        sub_indices=sub_indices,
    )
