import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/pune_providers.dart';
import '../services/exposure_tracker_service.dart';
import '../theme/app_theme.dart';
import '../theme/gradient_scaffold.dart';

class ExposureScreen extends ConsumerStatefulWidget {
  const ExposureScreen({super.key});

  @override
  ConsumerState<ExposureScreen> createState() => _ExposureScreenState();
}

class _ExposureScreenState extends ConsumerState<ExposureScreen> {
  String _activityMode = 'Walking'; // Walking, Running, Cycling, Driving

  // Route Exposure Calculator
  String _startLoc = 'Kothrud';
  String _endLoc = 'Hinjawadi Phase 1';
  String _commuteMode = 'car';
  Map<String, dynamic>? _routeResult;
  bool _calculatingRoute = false;

  Future<void> _toggleTracking() async {
    final tracker = ref.read(exposureTrackerProvider);
    final repo = ref.read(puneApiRepositoryProvider);

    if (tracker.state.isTracking) {
      final summary = await tracker.stopTracking(repository: repo);
      ref.invalidate(exposureSessionsProvider);
      if (mounted) {
        _showSessionSummary(summary);
      }
    } else {
      final success = await tracker.startTracking(
        activityMode: _activityMode,
        repository: repo,
      );
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required for outdoor exposure tracking.')),
        );
      }
    }
  }

  void _showSessionSummary(Map<String, dynamic> summary) {
    final avgAqi = summary['avg_aqi']?.toString() ?? '85';
    final peakAqi = summary['peak_aqi']?.toString() ?? '85';
    final dose = (summary['relative_exposure_score'] as num?)?.toStringAsFixed(1) ?? '0.0';
    final durSec = summary['duration_seconds'] as int? ?? 0;
    final distM = (summary['distance_meters'] as num?)?.toDouble() ?? 0.0;
    final mode = summary['activity_mode']?.toString() ?? _activityMode;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Exposure Session Complete', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Activity: $mode', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Duration: ${_formatDuration(durSec)} • Distance: ${(distM / 1000).toStringAsFixed(2)} km',
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.indigo.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.air_rounded, color: AppColors.violet),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$avgAqi AQI (Peak $peakAqi)', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
                        Text('Inhaled: $dose µg PM2.5', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.indigo),
            child: const Text('Save & Close', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }


  Future<void> _calculateCommute() async {
    setState(() => _calculatingRoute = true);
    try {
      final res = await ref.read(puneApiRepositoryProvider).calculateRouteExposure(
        startPoint: _startLoc,
        endPoint: _endLoc,
        mode: _commuteMode,
      );
      setState(() => _routeResult = res);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _calculatingRoute = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tracker = ref.watch(exposureTrackerProvider);
    final session = tracker.state;
    final isTracking = session.isTracking;
    final secondsElapsed = session.durationSeconds;
    final distanceMeters = session.distanceMeters;
    final currentSpeedKmh = session.currentSpeedKmh;
    final currentAqi = session.currentAqi;
    final currentStationName = session.currentStationName;
    final inhaledDoseUg = session.inhaledDoseUg;

    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Personal Exposure Intelligence'),
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
          children: [
            // 1. LIVE EXPOSURE STOPWATCH
            GlassCard(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  isTracking ? AppColors.indigo.withValues(alpha: 0.3) : AppColors.surfaceElevated,
                  AppColors.surface,
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Outdoor Exposure Tracker', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (isTracking ? AppColors.aqiGood : AppColors.textMuted).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isTracking ? 'RECORDING' : 'IDLE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: isTracking ? AppColors.aqiGood : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _formatDuration(secondsElapsed),
                    style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w800, letterSpacing: 2, color: Colors.white),
                  ),
                  if (isTracking) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.indigo.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                const Text('Distance', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                                const SizedBox(height: 2),
                                Text('${(distanceMeters / 1000).toStringAsFixed(2)} km',
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.white)),
                              ],
                            ),
                          ),
                          Container(width: 1, height: 24, color: AppColors.borderSubtle),
                          Expanded(
                            child: Column(
                              children: [
                                const Text('Speed', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                                const SizedBox(height: 2),
                                Text('${currentSpeedKmh.toStringAsFixed(1)} km/h',
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.violet)),
                              ],
                            ),
                          ),
                          Container(width: 1, height: 24, color: AppColors.borderSubtle),
                          Expanded(
                            child: Column(
                              children: [
                                const Text('Ambient AQI', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                                const SizedBox(height: 2),
                                Text('$currentAqi AQI',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      color: AppColors.colorForAqiCategory(currentAqi > 100 ? 'Moderate' : 'Satisfactory'),
                                    )),
                                Text(
                                  currentStationName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 9, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                          Container(width: 1, height: 24, color: AppColors.borderSubtle),
                          Expanded(
                            child: Column(
                              children: [
                                const Text('Inhaled Dose', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                                const SizedBox(height: 2),
                                Text('${inhaledDoseUg.toStringAsFixed(1)} µg',
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.aqiPoor)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),

                  // Activity mode selector
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: ['Walking', 'Running', 'Cycling', 'Driving'].map((mode) {
                      final sel = _activityMode == mode;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(mode, style: TextStyle(fontSize: 11, color: sel ? Colors.white : AppColors.textSecondary)),
                          selected: sel,
                          selectedColor: AppColors.indigo,
                          backgroundColor: AppColors.surfaceElevated,
                          onSelected: (val) {
                            if (!isTracking && val) setState(() => _activityMode = mode);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _toggleTracking,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isTracking ? AppColors.aqiPoor : AppColors.indigo,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    icon: Icon(isTracking ? Icons.stop_rounded : Icons.play_arrow_rounded, color: Colors.white),
                    label: Text(
                      isTracking ? 'Stop & Review Session' : 'Start Exposure Session',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 2. COMMUTE ROUTE EXPOSURE CALCULATOR
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pune Commute Exposure Calculator', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 4),
                  const Text('Simulate inhaled pollution along Pune transit corridors.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _startLoc,
                          isExpanded: true,
                          dropdownColor: AppColors.surfaceElevated,
                          decoration: const InputDecoration(labelText: 'From Locality', border: OutlineInputBorder()),
                          items: ['Kothrud', 'Aundh', 'Swargate', 'Deccan', 'Katraj', 'Shivajinagar'].map((l) {
                            return DropdownMenuItem(value: l, child: Text(l, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13)));
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _startLoc = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _endLoc,
                          isExpanded: true,
                          dropdownColor: AppColors.surfaceElevated,
                          decoration: const InputDecoration(labelText: 'To Locality', border: OutlineInputBorder()),
                          items: ['Hinjawadi Phase 1', 'Hinjawadi Phase 2', 'Kharadi IT Park', 'Magarpatta City', 'Viman Nagar', 'Bhosari MIDC'].map((l) {
                            return DropdownMenuItem(value: l, child: Text(l, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13)));
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _endLoc = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _commuteMode,
                    isExpanded: true,
                    dropdownColor: AppColors.surfaceElevated,
                    decoration: const InputDecoration(labelText: 'Commute Mode', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'car', child: Text('Car (AC Recirculation)', overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white))),
                      DropdownMenuItem(value: 'two_wheeler', child: Text('Two-Wheeler / Bike', overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white))),
                      DropdownMenuItem(value: 'metro', child: Text('Pune Metro', overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white))),
                      DropdownMenuItem(value: 'cycling', child: Text('Cycling', overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white))),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _commuteMode = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _calculatingRoute ? null : _calculateCommute,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.indigo,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _calculatingRoute
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Calculate Route Exposure', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                  ),

                  // Route Result
                  if (_routeResult != null) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.indigo.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '$_startLoc → $_endLoc',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text('${_routeResult!['average_aqi']} Avg AQI', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.violet)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _routeStat('Est. Duration', '${_routeResult!['duration_minutes']} min'),
                              _routeStat('Inhaled PM2.5', '${_routeResult!['estimated_pm25_inhaled_ug']} µg'),
                              _routeStat('Exposure Index', '${_routeResult!['exposure_score']}/100'),
                            ],
                          ),
                          if (_routeResult!['recommended_route'] != null) ...[
                            const Divider(height: 24, color: AppColors.borderSubtle),
                            Row(
                              children: [
                                const Icon(Icons.alt_route_rounded, color: AppColors.aqiGood, size: 16),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Alternative: ${_routeResult!['recommended_route']['name']}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.aqiGood),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Saves ${_routeResult!['recommended_route']['exposure_reduction_pct']}% inhaled particulate exposure.',
                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 3. RECENT EXPOSURE SESSIONS (from exposure_sessions table)
            Consumer(
              builder: (context, ref, _) {
                final historyAsync = ref.watch(exposureSessionsProvider);
                return GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Past Outdoor Sessions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          IconButton(
                            icon: const Icon(Icons.refresh_rounded, size: 18, color: AppColors.textMuted),
                            onPressed: () => ref.invalidate(exposureSessionsProvider),
                            tooltip: 'Refresh Sessions',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      historyAsync.when(
                        loading: () => const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: AppColors.indigo))),
                        error: (e, _) => const Text('Sign in to view session history', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                        data: (sessions) {
                          if (sessions.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: Text('No recorded outdoor sessions yet. Press Start above to track exposure.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                              ),
                            );
                          }
                          return Column(
                            children: sessions.map((s) {
                              final durSec = s['duration_seconds'] as int? ?? 0;
                              final avgAqi = (s['avg_aqi'] as num?)?.toStringAsFixed(0) ?? '80';
                              final dose = s['relative_exposure_score'] ?? 10;
                              final dateStr = s['started_at'] != null
                                  ? DateTime.tryParse(s['started_at'].toString())?.toLocal().toString().substring(0, 16) ?? ''
                                  : '';
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceElevated,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.directions_walk_rounded, color: AppColors.violet, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(dateStr, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                          Text('${_formatDuration(durSec)} duration • $avgAqi Avg AQI',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8)),
                                      child: Text('Dose: $dose', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.aqiSatisfactory)),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _routeStat(String label, String val) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
          const SizedBox(height: 2),
          Text(val, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
        ],
      ),
    );
  }
}
