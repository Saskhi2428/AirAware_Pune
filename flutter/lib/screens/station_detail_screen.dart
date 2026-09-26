import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/pollutant_reading.dart';
import '../models/station.dart';
import '../providers/pune_providers.dart';
import '../theme/app_theme.dart';
import '../theme/gradient_scaffold.dart';

final _stationDetailProvider = FutureProvider.family.autoDispose((ref, String stationId) {
  return ref.watch(puneApiRepositoryProvider).fetchStationDetails(stationId);
});

class StationDetailScreen extends ConsumerStatefulWidget {
  final String stationId;
  const StationDetailScreen({super.key, required this.stationId});

  @override
  ConsumerState<StationDetailScreen> createState() => _StationDetailScreenState();
}

class _StationDetailScreenState extends ConsumerState<StationDetailScreen> {
  String _selectedRange = '24H';
  final Set<String> _compareStationIds = {};

  // Indian NAAQS 24-hr standards for pollutants
  static const Map<String, double> naaqsLimits = {
    'pm25': 60.0,
    'pm10': 100.0,
    'no2': 80.0,
    'so2': 80.0,
    'co': 2.0,
    'o3': 100.0,
    'nh3': 400.0,
  };

  void _shareReport(Station station) {
    final areaStr = station.area != null ? ' (${station.area})' : '';
    final obsStr = station.lastObservationAt != null
        ? DateFormat('dd MMM yyyy, hh:mm a').format(station.lastObservationAt!.toLocal())
        : 'Real-time telemetry';
    final aqiStr = station.hasCurrentAqi ? '${station.aqiValue}' : 'Awaiting Telemetry';
    final catStr = station.aqiCategory ?? 'Normal';
    final domStr = (station.dominantPollutant ?? 'PM2.5').toUpperCase();
    final advisory = _healthAdvisory(station.aqiValue ?? 80);

    Share.share(
      '🌿 AirSense Pune — Station Air Intelligence\n\n'
      '📍 Station: ${station.name}$areaStr\n'
      '📊 Current AQI: $aqiStr ($catStr)\n'
      '🔬 Dominant Pollutant: $domStr\n'
      '🩺 Health Advisory: $advisory\n'
      '🕒 Verified: $obsStr\n\n'
      'Live Pune Air Intelligence • CPCB NAQI Standard 🇮🇳\n'
      'Track real-time Pune air quality on AirSense.',
      subject: 'AirSense Pune: ${station.name} ($aqiStr AQI)',
    );
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(_stationDetailProvider(widget.stationId));
    final historyAsync = ref.watch(stationHistoryProvider(
      (stationId: widget.stationId, range: _selectedRange.toLowerCase()),
    ));
    final allStations = ref.watch(stationsProvider).valueOrNull ?? [];

    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Station Intelligence'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share air quality report',
            onPressed: () {
              final currentStation = detailAsync.valueOrNull?.station;
              if (currentStation != null) {
                _shareReport(currentStation);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Awaiting station telemetry before sharing.')),
                );
              }
            },
          ),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.indigo)),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: GlassCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.aqiVeryPoor),
                  const SizedBox(height: 12),
                  Text('Could not load station: $err',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.indigo,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => ref.refresh(_stationDetailProvider(widget.stationId)),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
        data: (result) {
          final station = result.station;
          final pollutants = result.pollutants;
          final aqiColor = AppColors.colorForAqiCategory(station.aqiCategory);

          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                // 1. Station Title & Live Verification Badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(station.name, style: Theme.of(context).textTheme.headlineMedium),
                          if (station.area != null) ...[
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 8,
                              runSpacing: 2,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textMuted),
                                    const SizedBox(width: 3),
                                    Text(station.area!, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                                  ],
                                ),
                                Text(
                                  '${station.latitude.toStringAsFixed(4)}°N, ${station.longitude.toStringAsFixed(4)}°E',
                                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.aqiGood.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.aqiGood.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: AppColors.aqiGood,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'LIVE SENSOR',
                            style: TextStyle(
                              color: AppColors.aqiGood,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 2. Hero AQI Card with CPCB standard styling
                GlassCard(
                  gradient: LinearGradient(
                    colors: [aqiColor.withValues(alpha: 0.22), AppColors.surface],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: aqiColor.withValues(alpha: 0.18),
                              border: Border.all(color: aqiColor.withValues(alpha: 0.5), width: 3),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              station.hasCurrentAqi ? '${station.aqiValue}' : '—',
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w900,
                                color: aqiColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  station.aqiCategory ?? 'Air Quality Index',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 20,
                                    color: aqiColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Primary Pollutant: ${(station.dominantPollutant ?? "PM2.5").toUpperCase()}',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Status: ${station.freshness.toUpperCase()} • CPCB NAQI Standard',
                                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 18, color: aqiColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _healthAdvisory(station.aqiValue ?? 80),
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 3. Interactive Historical AQI Curve with Time Range Selector
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Historical Trend', style: Theme.of(context).textTheme.titleLarge),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: ['24H', '3D', '7D', '30D'].map((range) {
                          final isSel = _selectedRange == range;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedRange = range),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSel ? AppColors.indigo : Colors.transparent,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Text(
                                range,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isSel ? Colors.white : AppColors.textMuted,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Historical Chart Card
                GlassCard(
                  child: historyAsync.when(
                    loading: () => const SizedBox(
                      height: 200,
                      child: Center(child: CircularProgressIndicator(color: AppColors.indigo)),
                    ),
                    error: (e, _) => const SizedBox(
                      height: 200,
                      child: Center(
                        child: Text('Historical trend temporarily unavailable',
                            style: TextStyle(color: AppColors.textMuted)),
                      ),
                    ),
                    data: (histData) {
                      if (histData.isEmpty) {
                        return const SizedBox(
                          height: 200,
                          child: Center(
                            child: Text('Awaiting historical telemetry for this horizon',
                                style: TextStyle(color: AppColors.textMuted)),
                          ),
                        );
                      }

                      final values = histData.map((e) => (e['aqi_value'] as num).toDouble()).toList();
                      final minAqi = values.reduce((a, b) => a < b ? a : b).toInt();
                      final maxAqi = values.reduce((a, b) => a > b ? a : b).toInt();
                      final avgAqi = (values.reduce((a, b) => a + b) / values.length).round();

                      // Trend determination
                      final firstHalf = values.take(values.length ~/ 2);
                      final secondHalf = values.skip(values.length ~/ 2);
                      final avg1 = firstHalf.isNotEmpty ? firstHalf.reduce((a, b) => a + b) / firstHalf.length : avgAqi.toDouble();
                      final avg2 = secondHalf.isNotEmpty ? secondHalf.reduce((a, b) => a + b) / secondHalf.length : avgAqi.toDouble();
                      final trendStr = avg2 < avg1 - 3
                          ? 'Improving \u{1F4C9}'
                          : (avg2 > avg1 + 3 ? 'Worsening \u{1F4C8}' : 'Stable \u{27A1}\u{FE0F}');

                      final spots = <FlSpot>[];
                      for (int i = 0; i < histData.length; i++) {
                        final val = (histData[i]['aqi_value'] as num).toDouble();
                        spots.add(FlSpot(i.toDouble(), val));
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Summary Stats Row
                          Row(
                            children: [
                              Expanded(child: _metricPill('Min', '$minAqi', AppColors.aqiGood)),
                              const SizedBox(width: 6),
                              Expanded(child: _metricPill('Avg', '$avgAqi', AppColors.indigo)),
                              const SizedBox(width: 6),
                              Expanded(child: _metricPill('Max', '$maxAqi', AppColors.aqiVeryPoor)),
                              const SizedBox(width: 6),
                              Expanded(child: _metricPill('Trend', trendStr, AppColors.textPrimary)),
                            ],
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            height: 180,
                            child: LineChart(
                              LineChartData(
                                gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: false,
                                  horizontalInterval: 50,
                                  getDrawingHorizontalLine: (val) => const FlLine(
                                    color: AppColors.borderSubtle,
                                    strokeWidth: 1,
                                    dashArray: [4, 4],
                                  ),
                                ),
                                titlesData: FlTitlesData(
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 32,
                                      interval: 50,
                                      getTitlesWidget: (v, meta) => Text(
                                        '${v.toInt()}',
                                        style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                                      ),
                                    ),
                                  ),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 22,
                                      interval: (spots.length / 4).clamp(1.0, 10.0),
                                      getTitlesWidget: (v, meta) {
                                        final idx = v.toInt();
                                        if (idx >= 0 && idx < histData.length) {
                                          final dt = DateTime.tryParse(histData[idx]['computed_for'] as String);
                                          if (dt != null) {
                                            return Text(
                                              _selectedRange == '24H'
                                                  ? DateFormat('HH:mm').format(dt.toLocal())
                                                  : DateFormat('d MMM').format(dt.toLocal()),
                                              style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
                                            );
                                          }
                                        }
                                        return const SizedBox();
                                      },
                                    ),
                                  ),
                                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                ),
                                borderData: FlBorderData(show: false),
                                minX: 0,
                                maxX: (spots.length - 1).clamp(0, 500).toDouble(),
                                minY: (minAqi - 15).clamp(0, 500).toDouble(),
                                maxY: (maxAqi + 25).toDouble(),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: spots,
                                    isCurved: true,
                                    curveSmoothness: 0.25,
                                    color: aqiColor,
                                    barWidth: 3,
                                    isStrokeCapRound: true,
                                    dotData: const FlDotData(show: false),
                                    belowBarData: BarAreaData(
                                      show: true,
                                      gradient: LinearGradient(
                                        colors: [
                                          aqiColor.withValues(alpha: 0.35),
                                          aqiColor.withValues(alpha: 0.0),
                                        ],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                    ),
                                  ),
                                ],
                                lineTouchData: LineTouchData(
                                  touchTooltipData: LineTouchTooltipData(
                                    getTooltipColor: (_) => AppColors.surfaceElevated,
                                    getTooltipItems: (touchedSpots) {
                                      return touchedSpots.map((barSpot) {
                                        final idx = barSpot.x.toInt();
                                        String timeStr = '';
                                        if (idx >= 0 && idx < histData.length) {
                                          final dt = DateTime.tryParse(histData[idx]['computed_for'] as String);
                                          if (dt != null) {
                                            timeStr = DateFormat('h:mm a').format(dt.toLocal());
                                          }
                                        }
                                        return LineTooltipItem(
                                          'AQI ${barSpot.y.toInt()}\n$timeStr',
                                          TextStyle(color: aqiColor, fontWeight: FontWeight.w700),
                                        );
                                      }).toList();
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),

                // 4. Pollutants Breakdown vs NAAQS National Standards
                Text('Pollutant Concentrations', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                const Text(
                  'Relative to Indian National Ambient Air Quality Standards (CPCB NAAQS 24-hr limit)',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 12),

                if (pollutants.isEmpty)
                  const GlassCard(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Pollutant sensor telemetry updating...',
                          style: TextStyle(color: AppColors.textMuted)),
                    ),
                  )
                else
                  ...pollutants.map((p) => _pollutantMeterCard(p)),

                const SizedBox(height: 24),

                // 5. Multi-Station Comparison Tool
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Station Comparison Tool', style: Theme.of(context).textTheme.titleLarge),
                    if (_compareStationIds.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() => _compareStationIds.clear()),
                        child: const Text('Reset', style: TextStyle(color: AppColors.violet, fontSize: 12)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Compare live air quality across up to 3 Pune localities simultaneously:',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 12),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Quick-add suggestions
                      if (_compareStationIds.length < 2) ...[
                        const Text(
                          'Quick Add Locality:',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: allStations
                              .where((s) => s.id != widget.stationId && !_compareStationIds.contains(s.id))
                              .take(4)
                              .map((s) => ActionChip(
                                    label: Text(
                                      '+ ${s.area ?? s.name} (${s.aqiValue ?? "—"})',
                                      style: const TextStyle(fontSize: 11, color: AppColors.textPrimary),
                                    ),
                                    backgroundColor: AppColors.surfaceElevated,
                                    side: const BorderSide(color: AppColors.borderSubtle),
                                    onPressed: () {
                                      setState(() {
                                        if (_compareStationIds.length < 2) {
                                          _compareStationIds.add(s.id);
                                        }
                                      });
                                    },
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Station Selector Dropdown
                      if (_compareStationIds.length < 2) ...[
                        DropdownButtonFormField<String>(
                          value: null,
                          isExpanded: true,
                          dropdownColor: AppColors.surface,
                          hint: Text(
                            _compareStationIds.isEmpty
                                ? 'Select a Pune station to compare...'
                                : 'Add a 2nd station to compare (3 total)...',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                          ),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: AppColors.surfaceElevated,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          items: allStations
                              .where((s) => s.id != widget.stationId && !_compareStationIds.contains(s.id))
                              .map((s) => DropdownMenuItem(
                                    value: s.id,
                                    child: Text(
                                      '${s.name} • ${s.area ?? "Pune"} (AQI ${s.aqiValue ?? "—"})',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                if (_compareStationIds.length < 2) {
                                  _compareStationIds.add(val);
                                }
                              });
                            }
                          },
                        ),
                      ],

                      // Comparison Cards
                      if (_compareStationIds.isEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.compare_arrows_rounded, size: 18, color: AppColors.textMuted),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Choose up to 2 other Pune monitoring stations to compare side-by-side.',
                                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 16),
                        ...allStations
                            .where((s) => _compareStationIds.contains(s.id))
                            .map((other) => _buildComparisonItem(station, other)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 6. Data Source & Operational Transparency
                Text('Metadata & Transparency', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sourceRow(Icons.sensors_rounded, 'Measurement Standard', 'Direct CPCB / Open-Meteo High Resolution'),
                      const Divider(height: 18, color: AppColors.borderSubtle),
                      _sourceRow(Icons.location_searching_rounded, 'Location Type', station.locationTypeLabel),
                      const Divider(height: 18, color: AppColors.borderSubtle),
                      _sourceRow(
                        Icons.schedule_rounded,
                        'Last Verified Observation',
                        station.lastObservationAt != null
                            ? DateFormat('dd MMM yyyy, hh:mm a').format(station.lastObservationAt!.toLocal())
                            : 'Real-time feed active',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Action button: Navigate to route optimizer
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.navigation_rounded),
                    label: Flexible(
                      child: Text(
                        'Calculate Clean Route to ${station.area ?? station.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.indigo,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    onPressed: () {
                      context.push('/exposure', extra: station.name);
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _metricPill(String label, String val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
          const SizedBox(height: 2),
          Text(val, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _pollutantMeterCard(PollutantReading p) {
    final code = p.code.toLowerCase();
    final limit = naaqsLimits[code] ?? 100.0;
    final ratio = (p.value / limit).clamp(0.0, 2.5);
    final pct = (ratio * 100).round();

    Color meterColor = AppColors.aqiGood;
    String statusText = 'Safe (Within NAAQS limit)';
    if (ratio > 1.5) {
      meterColor = AppColors.aqiVeryPoor;
      statusText = 'Exceeded (Hazardous)';
    } else if (ratio > 1.0) {
      meterColor = AppColors.aqiModerate;
      statusText = 'Exceeded Standard';
    } else if (ratio > 0.75) {
      meterColor = AppColors.aqiModerate;
      statusText = 'Approaching Limit';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        p.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: meterColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(color: meterColor, fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${p.value.toStringAsFixed(1)} ${p.unit}',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: meterColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (ratio / 2.0).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: AppColors.surfaceElevated,
                valueColor: AlwaysStoppedAnimation<Color>(meterColor),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'NAAQS Limit: ${limit.toStringAsFixed(0)} ${p.unit}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$pct% of safe threshold',
                  style: TextStyle(color: meterColor, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonItem(Station curr, Station other) {
    final c1 = AppColors.colorForAqiCategory(curr.aqiCategory);
    final c2 = AppColors.colorForAqiCategory(other.aqiCategory);

    final currAqi = curr.aqiValue ?? 0;
    final otherAqi = other.aqiValue ?? 0;
    final diff = otherAqi - currAqi;

    String deltaText;
    Color deltaColor;
    if (diff > 0) {
      deltaText = '+$diff AQI Worse';
      deltaColor = AppColors.aqiPoor;
    } else if (diff < 0) {
      deltaText = '${diff.abs()} AQI Cleaner';
      deltaColor = AppColors.aqiGood;
    } else {
      deltaText = 'Equal AQI';
      deltaColor = AppColors.textMuted;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Left: Current Station
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.indigo.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('THIS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.violet)),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(curr.area ?? curr.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('AQI ${curr.aqiValue ?? "—"}',
                        style: TextStyle(color: c1, fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(curr.aqiCategory ?? '—',
                        style: TextStyle(color: c1, fontSize: 10, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),

              // Middle: Delta & VS
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: const Text('VS', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 10)),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: deltaColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      deltaText,
                      style: TextStyle(color: deltaColor, fontWeight: FontWeight.w700, fontSize: 9),
                    ),
                  ),
                ],
              ),

              // Right: Compared Station
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(other.area ?? other.name,
                              textAlign: TextAlign.end,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('AQI ${other.aqiValue ?? "—"}',
                        style: TextStyle(color: c2, fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(other.aqiCategory ?? '—',
                        style: TextStyle(color: c2, fontSize: 10, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.borderSubtle),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Dominant: ${(other.dominantPollutant ?? "PM2.5").toUpperCase()}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () => context.push('/station/${other.id}'),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text('View Details', style: TextStyle(color: AppColors.violet, fontWeight: FontWeight.w700, fontSize: 11)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => setState(() => _compareStationIds.remove(other.id)),
                    child: const Icon(Icons.close_rounded, size: 16, color: AppColors.textMuted),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sourceRow(IconData icon, String label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.indigo),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
          ),
        ],
      );

  String _healthAdvisory(int aqi) {
    if (aqi <= 50) {
      return 'Air quality is considered satisfactory, and air pollution poses little or no risk.';
    } else if (aqi <= 100) {
      return 'Air quality is acceptable. Sensitive individuals may experience mild respiratory symptoms.';
    } else if (aqi <= 200) {
      return 'Breathing discomfort to people with lungs, asthma and heart diseases.';
    } else if (aqi <= 300) {
      return 'Breathing discomfort to most people on prolonged exposure.';
    } else {
      return 'Respiratory illness on prolonged exposure. Avoid strenuous outdoor activities.';
    }
  }
}
