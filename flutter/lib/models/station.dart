/// Mirrors the backend's `monitoring_stations` + latest `aqi_computations`
/// row, as returned by GET /api/v1/pune/stations and /pune/map.
class Station {
  final String id;
  final String name;
  final String? area;
  final String locationType; // measured_station | mapped_station | estimated | modelled
  final double latitude;
  final double longitude;
  final String health; // healthy | warning | offline | unknown
  final DateTime? lastObservationAt;
  final String freshness; // fresh | delayed | stale | unavailable
  final int? aqiValue;
  final String? aqiCategory;
  final String? dominantPollutant;

  Station({
    required this.id,
    required this.name,
    this.area,
    required this.locationType,
    required this.latitude,
    required this.longitude,
    required this.health,
    this.lastObservationAt,
    required this.freshness,
    this.aqiValue,
    this.aqiCategory,
    this.dominantPollutant,
  });

  factory Station.fromJson(Map<String, dynamic> json) {
    return Station(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Unnamed station',
      area: json['area'] as String?,
      locationType: json['location_type'] as String? ?? 'estimated',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      health: json['health'] as String? ?? 'unknown',
      lastObservationAt: json['last_observation_at'] != null
          ? DateTime.tryParse(json['last_observation_at'] as String)
          : null,
      freshness: json['freshness'] as String? ?? 'unavailable',
      aqiValue: json['aqi_value'] != null ? (json['aqi_value'] as num).toInt() : null,
      aqiCategory: json['aqi_category'] as String?,
      dominantPollutant: json['dominant_pollutant'] as String?,
    );
  }

  bool get hasCurrentAqi => aqiValue != null;

  /// Human label matching spec's "never claim measured for estimated data" rule.
  String get locationTypeLabel {
    switch (locationType) {
      case 'measured_station':
        return 'Directly measured';
      case 'mapped_station':
        return 'Mapped station reading';
      case 'estimated':
        return 'Nearest-station estimate';
      case 'modelled':
        return 'Model-derived estimate';
      default:
        return 'Unknown';
    }
  }
}
