import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/pune_providers.dart';
import '../theme/app_theme.dart';
import '../theme/gradient_scaffold.dart';

class ExposureScreen extends ConsumerStatefulWidget {
  const ExposureScreen({super.key});

  @override
  ConsumerState<ExposureScreen> createState() => _ExposureScreenState();
}

class _ExposureScreenState extends ConsumerState<ExposureScreen> {
  // Exposure Stopwatch & Live Tracking
  bool _isTracking = false;
  int _secondsElapsed = 0;
  Timer? _timer;
  StreamSubscription<Position>? _positionStream;
  Position? _lastPosition;
  double _distanceMeters = 0.0;
  double _currentSpeedKmh = 0.0;
  int _currentAqi = 85;
  String _currentStationName = 'Pune Sensor';
  double _inhaledDoseUg = 0.0;
  final List<int> _sampledAqis = [];

  String? _activeSessionId;
  String _activityMode = 'Walking'; // Walking, Running, Cycling, Driving

  // Route Exposure Calculator
  String _startLoc = 'Kothrud';
  String _endLoc = 'Hinjawadi Phase 1';
  String _commuteMode = 'car';
  Map<String, dynamic>? _routeResult;
  bool _calculatingRoute = false;

  @override
  void dispose() {
    _timer?.cancel();
    _positionStream?.cancel();
    super.dispose();
  }

  Future<void> _toggleTracking() async {
    if (_isTracking) {
      _timer?.cancel();
      await _positionStream?.cancel();
      _positionStream = null;
      setState(() => _isTracking = false);

      Map<String, dynamic>? finishData;
      if (_activeSessionId != null) {
        try {
          finishData = await ref.read(puneApiRepositoryProvider).finishExposureSession(_activeSessionId!);
        } catch (e) {
          debugPrint('[Exposure] Error finishing session on backend: $e');
        }

        // Direct Supabase fallback update if needed
        try {
          final sb = Supabase.instance.client;
          if (sb.auth.currentSession != null) {
            final avgAqi = _sampledAqis.isNotEmpty
                ? (_sampledAqis.reduce((a, b) => a + b) / _sampledAqis.length).round()
                : _currentAqi;
            final peakAqi = _sampledAqis.isNotEmpty
                ? _sampledAqis.reduce((a, b) => a > b ? a : b)
                : _currentAqi;
            await sb.from('exposure_sessions').update({
              'ended_at': DateTime.now().toUtc().toIso8601String(),
              'duration_seconds': _secondsElapsed,
              'avg_aqi': avgAqi,
              'peak_aqi': peakAqi,
              'relative_exposure_score': (_inhaledDoseUg / 5.0).clamp(1.0, 100.0).round(),
            }).eq('id', _activeSessionId!);
          }
        } catch (e) {
          debugPrint('[Exposure] Supabase direct session finish error: $e');
        }

        ref.invalidate(exposureSessionsProvider);
      }

      _showSessionSummary(finishData);
      _activeSessionId = null;
    } else {
      // Permission check
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permission is required for outdoor exposure tracking.')),
            );
          }
          return;
        }
      }
      if (perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enable location permission in device settings.')),
          );
        }
        return;
      }

      // Reset tracking metrics
      setState(() {
        _isTracking = true;
        _secondsElapsed = 0;
        _distanceMeters = 0.0;
        _currentSpeedKmh = 0.0;
        _inhaledDoseUg = 0.0;
        _lastPosition = null;
        _sampledAqis.clear();
      });

      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (mounted) setState(() => _secondsElapsed++);
      });

      // Start backend/Supabase exposure session
      try {
        _activeSessionId = await ref.read(puneApiRepositoryProvider).startExposureSession(activityMode: _activityMode);
      } catch (e) {
        debugPrint('[Exposure] Backend start session failed: $e');
      }

      // If backend was unreachable, start direct Supabase session
      if (_activeSessionId == null) {
        try {
          final sb = Supabase.instance.client;
          final user = sb.auth.currentUser;
          if (user != null) {
            final res = await sb.from('exposure_sessions').insert({
              'user_id': user.id,
              'started_at': DateTime.now().toUtc().toIso8601String(),
            }).select('id').single();
            _activeSessionId = res['id']?.toString();
          }
        } catch (e) {
          debugPrint('[Exposure] Direct Supabase session creation error: $e');
        }
      }

      // Android foreground service settings
      final locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 4),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'AirAware Exposure Tracker Active',
          notificationText: 'Tracking outdoor route and Pune air intake in real time...',
          enableWakeLock: true,
        ),
      );

      _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((pos) {
        if (!mounted || !_isTracking) return;

        double deltaMeters = 0.0;
        if (_lastPosition != null) {
          deltaMeters = Geolocator.distanceBetween(
            _lastPosition!.latitude,
            _lastPosition!.longitude,
            pos.latitude,
            pos.longitude,
          );
        }
        _lastPosition = pos;

        // Speed in km/h
        final speedKmh = (pos.speed * 3.6).clamp(0.0, 140.0);

        // Find nearest station from stationsProvider
        final stations = ref.read(stationsProvider).valueOrNull ?? [];
        int nearestAqi = 85;
        String nearestName = 'Pune Center';
        if (stations.isNotEmpty) {
          double minD = double.infinity;
          for (final s in stations) {
            final d = Geolocator.distanceBetween(pos.latitude, pos.longitude, s.latitude, s.longitude);
            if (d < minD) {
              minD = d;
              nearestAqi = s.aqiValue ?? 85;
              nearestName = s.name;
            }
          }
        }
        _sampledAqis.add(nearestAqi);

        // Calculate ventilation rate (m^3/hr) based on activity and persona
        double ventRate = 1.2;
        if (_activityMode == 'Running') {
          ventRate = 3.0;
        } else if (_activityMode == 'Cycling') {
          ventRate = 2.4;
        } else if (_activityMode == 'Driving') {
          ventRate = 0.6;
        }

        final persona = ref.read(activeHealthPersonaProvider);
        if (persona.contains('Athlete')) {
          ventRate *= 1.2;
        }
        if (persona.contains('Child')) {
          ventRate *= 0.8;
        }


        // Inhaled particulate PM2.5 mass estimation:
        // PM2.5 concentration approx ~ aqi * 0.6 ug/m^3
        final pm25ugM3 = (nearestAqi * 0.6).clamp(10.0, 450.0);
        // Dosage for 4 seconds interval:
        final incrementalDose = (ventRate / 3600.0) * 4.0 * pm25ugM3;

        setState(() {
          _distanceMeters += deltaMeters;
          _currentSpeedKmh = speedKmh;
          _currentAqi = nearestAqi;
          _currentStationName = nearestName;
          _inhaledDoseUg += incrementalDose;
        });

        // Record breadcrumb point
        if (_activeSessionId != null) {
          ref.read(puneApiRepositoryProvider).addExposurePoint(
            sessionId: _activeSessionId!,
            latitude: pos.latitude,
            longitude: pos.longitude,
          );
        }
      });
    }
  }

  void _showSessionSummary([Map<String, dynamic>? finishData]) {
    final avgAqi = finishData?['avg_aqi']?.toString() ??
        (_sampledAqis.isNotEmpty
            ? (_sampledAqis.reduce((a, b) => a + b) / _sampledAqis.length).round().toString()
            : '$_currentAqi');
    final peakAqi = finishData?['peak_aqi']?.toString() ??
        (_sampledAqis.isNotEmpty
            ? _sampledAqis.reduce((a, b) => a > b ? a : b).toString()
            : '$_currentAqi');
    final doseScore = finishData?['relative_exposure_score']?.toString() ??
        (_inhaledDoseUg / 5.0).clamp(1.0, 100.0).round().toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Exposure Session Complete', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Activity: $_activityMode', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Duration: ${_formatDuration(_secondsElapsed)} • Distance: ${(_distanceMeters / 1000).toStringAsFixed(2)} km',
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
                        Text('Inhaled: ${_inhaledDoseUg.toStringAsFixed(1)} µg PM2.5', style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8)),
                    child: Text('Dose: $doseScore/100', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.aqiSatisfactory)),
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
                  _isTracking ? AppColors.indigo.withValues(alpha: 0.3) : AppColors.surfaceElevated,
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
                          color: (_isTracking ? AppColors.aqiGood : AppColors.textMuted).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _isTracking ? 'RECORDING' : 'IDLE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: _isTracking ? AppColors.aqiGood : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _formatDuration(_secondsElapsed),
                    style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w800, letterSpacing: 2, color: Colors.white),
                  ),
                  if (_isTracking) ...[
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
                                Text('${(_distanceMeters / 1000).toStringAsFixed(2)} km',
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
                                Text('${_currentSpeedKmh.toStringAsFixed(1)} km/h',
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
                                Text('$_currentAqi AQI',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      color: AppColors.colorForAqiCategory(_currentAqi > 100 ? 'Moderate' : 'Satisfactory'),
                                    )),
                                Text(
                                  _currentStationName,
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
                                Text('${_inhaledDoseUg.toStringAsFixed(1)} µg',
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
                            if (!_isTracking && val) setState(() => _activityMode = mode);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _toggleTracking,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isTracking ? AppColors.aqiPoor : AppColors.indigo,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    icon: Icon(_isTracking ? Icons.stop_rounded : Icons.play_arrow_rounded, color: Colors.white),
                    label: Text(
                      _isTracking ? 'Stop & Review Session' : 'Start Exposure Session',
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
