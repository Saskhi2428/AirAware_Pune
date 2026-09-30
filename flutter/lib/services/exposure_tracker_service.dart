import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/station.dart';
import '../providers/pune_providers.dart';
import '../repositories/pune_api_repository.dart';

class ExposureSessionData {
  final bool isTracking;
  final String? sessionId;
  final DateTime? startTime;
  final int durationSeconds;
  final String activityMode;
  final double distanceMeters;
  final double currentSpeedKmh;
  final int currentAqi;
  final String currentStationName;
  final double inhaledDoseUg;
  final List<int> sampledAqis;
  final Position? lastPosition;

  const ExposureSessionData({
    this.isTracking = false,
    this.sessionId,
    this.startTime,
    this.durationSeconds = 0,
    this.activityMode = 'Walking',
    this.distanceMeters = 0.0,
    this.currentSpeedKmh = 0.0,
    this.currentAqi = 85,
    this.currentStationName = 'Pune Sensor',
    this.inhaledDoseUg = 0.0,
    this.sampledAqis = const [],
    this.lastPosition,
  });

  ExposureSessionData copyWith({
    bool? isTracking,
    String? sessionId,
    DateTime? startTime,
    int? durationSeconds,
    String? activityMode,
    double? distanceMeters,
    double? currentSpeedKmh,
    int? currentAqi,
    String? currentStationName,
    double? inhaledDoseUg,
    List<int>? sampledAqis,
    Position? lastPosition,
  }) {
    return ExposureSessionData(
      isTracking: isTracking ?? this.isTracking,
      sessionId: sessionId ?? this.sessionId,
      startTime: startTime ?? this.startTime,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      activityMode: activityMode ?? this.activityMode,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      currentSpeedKmh: currentSpeedKmh ?? this.currentSpeedKmh,
      currentAqi: currentAqi ?? this.currentAqi,
      currentStationName: currentStationName ?? this.currentStationName,
      inhaledDoseUg: inhaledDoseUg ?? this.inhaledDoseUg,
      sampledAqis: sampledAqis ?? this.sampledAqis,
      lastPosition: lastPosition ?? this.lastPosition,
    );
  }
}

class ExposureTrackerService extends ChangeNotifier {
  ExposureTrackerService._();
  static final ExposureTrackerService instance = ExposureTrackerService._();

  ExposureSessionData _state = const ExposureSessionData();
  ExposureSessionData get state => _state;

  bool get isTracking => _state.isTracking;
  int get durationSeconds => _state.durationSeconds;
  String get activityMode => _state.activityMode;
  double get distanceMeters => _state.distanceMeters;
  double get currentSpeedKmh => _state.currentSpeedKmh;
  int get currentAqi => _state.currentAqi;
  String get currentStationName => _state.currentStationName;
  double get inhaledDoseUg => _state.inhaledDoseUg;
  List<int> get sampledAqis => _state.sampledAqis;

  String get elapsedTimeString {
    final m = (_state.durationSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_state.durationSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Timer? _timer;
  StreamSubscription<Position>? _positionStream;
  List<Station> _cachedStations = [];
  bool _initialized = false;

  static const String _prefActiveKey = 'exposure_active';
  static const String _prefSessionIdKey = 'exposure_session_id';
  static const String _prefStartTimeKey = 'exposure_start_time';
  static const String _prefModeKey = 'exposure_mode';
  static const String _prefDistanceKey = 'exposure_distance';
  static const String _prefDoseKey = 'exposure_dose';
  static const String _prefPastSessionsKey = 'past_exposure_sessions';

  Future<void> initialize(List<Station> stations) async {
    _cachedStations = stations;
    if (_initialized) return;
    _initialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final isActive = prefs.getBool(_prefActiveKey) ?? false;
      if (isActive) {
        final startIso = prefs.getString(_prefStartTimeKey);
        final startTime = startIso != null ? DateTime.tryParse(startIso) : null;
        final mode = prefs.getString(_prefModeKey) ?? 'Walking';
        final dist = prefs.getDouble(_prefDistanceKey) ?? 0.0;
        final dose = prefs.getDouble(_prefDoseKey) ?? 0.0;
        final sid = prefs.getString(_prefSessionIdKey);

        if (startTime != null) {
          final elapsed = DateTime.now().difference(startTime).inSeconds;
          _state = _state.copyWith(
            isTracking: true,
            sessionId: sid,
            startTime: startTime,
            durationSeconds: max(0, elapsed),
            activityMode: mode,
            distanceMeters: dist,
            inhaledDoseUg: dose,
          );
          _startTimerAndGps();
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[ExposureTrackerService] Init error: $e');
    }
  }

  void updateCachedStations(List<Station> stations) {
    _cachedStations = stations;
  }

  Future<bool> startTracking({
    required String activityMode,
    required PuneApiRepository repository,
  }) async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) return false;
    }
    if (perm == LocationPermission.deniedForever) return false;

    final now = DateTime.now();
    String? sid;

    // Try backend start session
    try {
      sid = await repository.startExposureSession(activityMode: activityMode);
    } catch (_) {}

    // Fallback to Supabase direct
    if (sid == null) {
      try {
        final sb = Supabase.instance.client;
        final user = sb.auth.currentUser;
        if (user != null) {
          final res = await sb.from('exposure_sessions').insert({
            'user_id': user.id,
            'started_at': now.toUtc().toIso8601String(),
          }).select('id').single();
          sid = res['id']?.toString();
        }
      } catch (_) {}
    }
    sid ??= 'exp-${now.millisecondsSinceEpoch}';

    _state = ExposureSessionData(
      isTracking: true,
      sessionId: sid,
      startTime: now,
      durationSeconds: 0,
      activityMode: activityMode,
      distanceMeters: 0.0,
      currentSpeedKmh: 0.0,
      inhaledDoseUg: 0.0,
      sampledAqis: [],
      currentAqi: _cachedStations.isNotEmpty ? (_cachedStations.first.aqiValue ?? 85) : 85,
      currentStationName: _cachedStations.isNotEmpty ? _cachedStations.first.name : 'Pune Sensor',
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefActiveKey, true);
    await prefs.setString(_prefSessionIdKey, sid);
    await prefs.setString(_prefStartTimeKey, now.toIso8601String());
    await prefs.setString(_prefModeKey, activityMode);
    await prefs.setDouble(_prefDistanceKey, 0.0);
    await prefs.setDouble(_prefDoseKey, 0.0);

    _startTimerAndGps();
    notifyListeners();
    return true;
  }

  void _startTimerAndGps() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_state.startTime != null) {
        final elapsed = DateTime.now().difference(_state.startTime!).inSeconds;
        _state = _state.copyWith(durationSeconds: max(0, elapsed));
        notifyListeners();
      }
    });

    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 4),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: "AirAware Exposure Tracker Active",
          notificationText: "Tracking outdoor route and inhaling exposure in real-time...",
          enableWakeLock: true,
          color: Color(0xFF6366F1),
        ),
      ),
    ).listen((pos) {
      _processGpsFix(pos);
    }, onError: (err) {
      debugPrint('[ExposureTrackerService] GPS error: $err');
    });
  }

  void _processGpsFix(Position pos) {
    double addedDist = 0.0;
    if (_state.lastPosition != null) {
      addedDist = Geolocator.distanceBetween(
        _state.lastPosition!.latitude,
        _state.lastPosition!.longitude,
        pos.latitude,
        pos.longitude,
      );
    }

    final newDist = _state.distanceMeters + addedDist;
    final speedKmh = pos.speed >= 0 ? (pos.speed * 3.6) : 0.0;

    // Find nearest station
    Station? nearest;
    double minDist = double.infinity;
    for (final s in _cachedStations) {
      final d = Geolocator.distanceBetween(pos.latitude, pos.longitude, s.latitude, s.longitude);
      if (d < minDist) {
        minDist = d;
        nearest = s;
      }
    }

    final aqi = nearest?.aqiValue ?? _state.currentAqi;
    final stName = nearest?.name ?? _state.currentStationName;

    // Minute ventilation rate Ve based on activity (m3/min)
    double ve = 0.015; // default walking
    final mode = _state.activityMode.toLowerCase();
    if (mode.contains('run')) {
      ve = 0.035;
    } else if (mode.contains('cycl')) {
      ve = 0.030;
    } else if (mode.contains('driv') || mode.contains('car')) {
      ve = 0.008;
    }

    // Inhaled PM2.5 dosage math (ug) = PM2.5 (ug/m3) * Ve (m3/min) * dt (min)
    final pm25Concentration = (aqi * 0.6).clamp(5.0, 500.0);
    const dtMinutes = 4.0 / 60.0; // 4 seconds interval
    final deltaDose = pm25Concentration * ve * dtMinutes;
    final newDose = _state.inhaledDoseUg + deltaDose;

    final updatedSamples = List<int>.from(_state.sampledAqis)..add(aqi);

    _state = _state.copyWith(
      distanceMeters: newDist,
      currentSpeedKmh: speedKmh,
      lastPosition: pos,
      currentAqi: aqi,
      currentStationName: stName,
      inhaledDoseUg: newDose,
      sampledAqis: updatedSamples,
    );

    // Save incremental state to SharedPreferences
    SharedPreferences.getInstance().then((prefs) {
      prefs.setDouble(_prefDistanceKey, newDist);
      prefs.setDouble(_prefDoseKey, newDose);
    });

    notifyListeners();
  }

  Future<Map<String, dynamic>> stopTracking({
    required PuneApiRepository repository,
  }) async {
    _timer?.cancel();
    _timer = null;
    await _positionStream?.cancel();
    _positionStream = null;

    final session = _state;
    final now = DateTime.now();

    final avgAqi = session.sampledAqis.isNotEmpty
        ? (session.sampledAqis.reduce((a, b) => a + b) / session.sampledAqis.length).round()
        : session.currentAqi;
    final peakAqi = session.sampledAqis.isNotEmpty
        ? session.sampledAqis.reduce((a, b) => a > b ? a : b)
        : session.currentAqi;

    final summary = {
      'id': session.sessionId ?? 'exp-${now.millisecondsSinceEpoch}',
      'started_at': (session.startTime ?? now).toIso8601String(),
      'ended_at': now.toIso8601String(),
      'duration_seconds': session.durationSeconds,
      'distance_meters': session.distanceMeters,
      'activity_mode': session.activityMode,
      'avg_aqi': avgAqi,
      'peak_aqi': peakAqi,
      'relative_exposure_score': session.inhaledDoseUg,
      'station_name': session.currentStationName,
    };

    // 1. Finish backend session if online
    if (session.sessionId != null) {
      try {
        await repository.finishExposureSession(session.sessionId!);
      } catch (_) {}

      // 2. Direct Supabase update
      try {
        final sb = Supabase.instance.client;
        if (sb.auth.currentSession != null) {
          await sb.from('exposure_sessions').update({
            'ended_at': now.toUtc().toIso8601String(),
            'duration_seconds': session.durationSeconds,
            'avg_aqi': avgAqi,
            'peak_aqi': peakAqi,
            'relative_exposure_score': session.inhaledDoseUg,
          }).eq('id', session.sessionId!);
        }
      } catch (e) {
        debugPrint('[ExposureTrackerService] Supabase session update error: $e');
      }
    }

    // 3. Persist locally to SharedPreferences so Past Sessions ALWAYS shows real history!
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefActiveKey, false);
      await prefs.remove(_prefSessionIdKey);
      await prefs.remove(_prefStartTimeKey);

      final existingJson = prefs.getStringList(_prefPastSessionsKey) ?? [];
      existingJson.insert(0, jsonEncode(summary));
      // Keep up to 50 past sessions locally
      if (existingJson.length > 50) {
        existingJson.removeRange(50, existingJson.length);
      }
      await prefs.setStringList(_prefPastSessionsKey, existingJson);
    } catch (e) {
      debugPrint('[ExposureTrackerService] Save past session local error: $e');
    }

    _state = const ExposureSessionData();
    notifyListeners();
    return summary;
  }

  Future<List<Map<String, dynamic>>> getPastSessions({
    required PuneApiRepository repository,
  }) async {
    final list = <Map<String, dynamic>>[];

    // 1. Load locally persisted sessions
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedStrings = prefs.getStringList(_prefPastSessionsKey) ?? [];
      for (final str in savedStrings) {
        try {
          final decoded = jsonDecode(str);
          if (decoded is Map<String, dynamic>) {
            list.add(decoded);
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[ExposureTrackerService] Local past sessions load error: $e');
    }

    // 2. Query Supabase direct if authenticated and merge
    try {
      final sb = Supabase.instance.client;
      final user = sb.auth.currentUser;
      if (user != null) {
        final rows = await sb
            .from('exposure_sessions')
            .select()
            .eq('user_id', user.id)
            .order('started_at', ascending: false)
            .limit(30);

        final seenIds = list.map((e) => e['id']?.toString()).toSet();
        for (final r in rows) {
          final map = Map<String, dynamic>.from(r);
          if (!seenIds.contains(map['id']?.toString())) {
            list.add(map);
          }
        }
      }
    } catch (e) {
      debugPrint('[ExposureTrackerService] Supabase past sessions load error: $e');
    }

    // 3. Fallback to repository backend if available
    if (list.isEmpty) {
      try {
        final backendSessions = await repository.getExposureSessions();
        list.addAll(backendSessions);
      } catch (_) {}
    }

    // Sort by started_at descending
    list.sort((a, b) {
      final aDate = DateTime.tryParse(a['started_at']?.toString() ?? '') ?? DateTime(2000);
      final bDate = DateTime.tryParse(b['ended_at']?.toString() ?? b['started_at']?.toString() ?? '') ?? DateTime(2000);
      return bDate.compareTo(aDate);
    });

    return list;
  }
}

/// Global Riverpod Provider for Exposure Tracking
final exposureTrackerProvider = ChangeNotifierProvider<ExposureTrackerService>((ref) {
  final service = ExposureTrackerService.instance;
  final stations = ref.watch(stationsProvider).valueOrNull ?? [];
  service.initialize(stations);
  return service;
});
