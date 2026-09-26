class PollutantReading {
  final String code; // pm25, pm10, no2, so2, o3, co, nh3
  final double value;
  final String unit;
  final DateTime observedAt;
  final int? qualityScore;
  final String? qualityFlag;

  PollutantReading({
    required this.code,
    required this.value,
    required this.unit,
    required this.observedAt,
    this.qualityScore,
    this.qualityFlag,
  });

  factory PollutantReading.fromJson(Map<String, dynamic> json) {
    return PollutantReading(
      code: json['code'] as String,
      value: (json['value'] as num).toDouble(),
      unit: json['unit'] as String? ?? '',
      observedAt: DateTime.parse(json['observed_at'] as String),
      qualityScore: json['quality_score'] != null ? (json['quality_score'] as num).toInt() : null,
      qualityFlag: json['quality_flag'] as String?,
    );
  }

  String get displayName {
    const names = {
      'pm25': 'PM2.5', 'pm10': 'PM10', 'no2': 'NO2',
      'so2': 'SO2', 'o3': 'O3', 'co': 'CO', 'nh3': 'NH3',
    };
    return names[code] ?? code.toUpperCase();
  }
}
