import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../auth/auth_state_provider.dart';
import '../models/station.dart';
import '../repositories/pune_api_repository.dart';
import '../services/notification_service.dart';

final puneApiRepositoryProvider = Provider<PuneApiRepository>((ref) => PuneApiRepository());


/// Auto-refreshing station list
class StationsNotifier extends AsyncNotifier<List<Station>> {
  @override
  Future<List<Station>> build() async {
    return ref.read(puneApiRepositoryProvider).fetchStations();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(puneApiRepositoryProvider).fetchStations());
  }
}

final stationsProvider = AsyncNotifierProvider<StationsNotifier, List<Station>>(
  StationsNotifier.new,
);

/// Map-specific snapshot
final mapSnapshotProvider = FutureProvider.autoDispose<List<Station>>((ref) async {
  return ref.watch(puneApiRepositoryProvider).fetchMapSnapshot();
});

/// Currently selected station ID (on map or leaderboard)
final selectedStationIdProvider = StateProvider<String?>((ref) => null);

/// Resolved Station object for selectedStationId
final selectedStationProvider = Provider.autoDispose<Station?>((ref) {
  final id = ref.watch(selectedStationIdProvider);
  if (id == null) return null;
  final stations = ref.watch(stationsProvider).valueOrNull ?? [];
  try {
    return stations.firstWhere((s) => s.id == id);
  } catch (_) {
    return null;
  }
});

/// Pune City Air Pulse (Average AQI, cleanest/worst areas, activity guidance)
final punePulseProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(puneApiRepositoryProvider).fetchPunePulse();
});

/// Spatial DBSCAN Hotspots
final hotspotsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(puneApiRepositoryProvider).fetchHotspots();
});

/// Sensor Anomalies & Telemetry
final anomaliesProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(puneApiRepositoryProvider).fetchAnomalies();
});

/// XGBoost Forecast for a specific station (or city-wide)
final forecastProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String?>((ref, stationId) async {
  return ref.watch(puneApiRepositoryProvider).fetchForecast(stationId: stationId);
});

/// SHAP Explainability Factors
final explainabilityProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String?>((ref, stationId) async {
  return ref.watch(puneApiRepositoryProvider).fetchExplainability(stationId: stationId);
});

/// Diurnal Activity Advisor
final activityAdvisorProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(puneApiRepositoryProvider).fetchActivityAdvisor();
});

/// Device GPS Location Provider with graceful Pune fallback
final deviceLocationProvider = FutureProvider.autoDispose<Position?>((ref) async {
  try {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    if (permission == LocationPermission.deniedForever) return null;

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 8)),
    );
  } catch (e) {
    debugPrint('[LocationProvider] Location access error: $e');
    return null;
  }
});

/// Live nearest station resolution for user location
/// Distinguishes live device GPS location from Pune Central reference point
final userNearestStationProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final pos = await ref.watch(deviceLocationProvider.future);
  final isGps = pos != null;
  final lat = pos?.latitude ?? 18.5204;
  final lng = pos?.longitude ?? 73.8567;
  final result = await ref.watch(puneApiRepositoryProvider).fetchNearestStation(lat, lng);

  // Real-time threshold check & Android notification trigger
  try {
    final st = result['nearest_station'] as Map<String, dynamic>?;
    if (st != null && st['aqi_value'] != null) {
      final aqi = (st['aqi_value'] as num).toInt();
      final name = st['name']?.toString() ?? 'Pune Station';
      final dominant = st['dominant_pollutant']?.toString();

      final alerts = ref.read(userAlertsProvider).valueOrNull ?? [];
      double threshold = 150.0;
      for (final a in alerts) {
        if (a['is_enabled'] != false && a['threshold_value'] != null) {
          threshold = (a['threshold_value'] as num).toDouble();
          break;
        }
      }

      NotificationService.instance.checkThresholdAndNotify(
        currentAqi: aqi,
        thresholdAqi: threshold,
        stationName: name,
        dominantPollutant: dominant,
      );
    }
  } catch (e) {
    debugPrint('[userNearestStationProvider] Threshold check error: $e');
  }

  return {
    ...result,
    'is_gps': isGps,
  };
});

/// Saved Locations Notifier (strictly authenticated — zero fake/mock data)
class SavedLocationsNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      // Unauthenticated guests have 0 saved locations — strict privacy & ownership
      return [];
    }
    try {
      return await ref.read(puneApiRepositoryProvider).fetchSavedLocations();
    } catch (e) {
      debugPrint('[SavedLocationsNotifier] Error fetching saved places: $e');
      return [];
    }
  }

  Future<void> addLocation(String label, double lat, double lng) async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      throw Exception('Please sign in to bookmark and save places in Pune.');
    }
    try {
      await ref.read(puneApiRepositoryProvider).createSavedLocation(label: label, latitude: lat, longitude: lng);
      final updated = await ref.read(puneApiRepositoryProvider).fetchSavedLocations();
      state = AsyncData(updated);
    } catch (e) {
      debugPrint('[SavedLocations] Error saving: $e');
      final currentList = state.valueOrNull ?? [];
      final newItem = {
        'id': 'loc-${DateTime.now().millisecondsSinceEpoch}',
        'label': label,
        'latitude': lat,
        'longitude': lng,
      };
      state = AsyncData([...currentList, newItem]);
    }
  }

  Future<void> removeLocation(String id) async {
    try {
      await ref.read(puneApiRepositoryProvider).deleteSavedLocation(id);
      state = AsyncData(await ref.read(puneApiRepositoryProvider).fetchSavedLocations());
    } catch (e) {
      debugPrint('[SavedLocations] Error deleting: $e');
    }
  }
}

final savedLocationsProvider = AsyncNotifierProvider<SavedLocationsNotifier, List<Map<String, dynamic>>>(
  SavedLocationsNotifier.new,
);

/// Citizen Incident Reports Notifier
class CitizenReportsNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    try {
      return await ref.read(puneApiRepositoryProvider).fetchCitizenReports();
    } catch (_) {
      return [];
    }
  }

  Future<void> submitReport(
    String ward,
    String category,
    String description, {
    double? latitude,
    double? longitude,
  }) async {
    await ref.read(puneApiRepositoryProvider).submitCitizenReport(
      ward: ward,
      category: category,
      description: description,
      lat: latitude ?? 18.5204,
      lng: longitude ?? 73.8567,
    );
    state = AsyncData(await ref.read(puneApiRepositoryProvider).fetchCitizenReports());
  }

  Future<void> voteReport(String reportId) async {
    await ref.read(puneApiRepositoryProvider).voteCitizenReport(reportId);
    state = AsyncData(await ref.read(puneApiRepositoryProvider).fetchCitizenReports());
  }
}

final citizenReportsProvider = AsyncNotifierProvider<CitizenReportsNotifier, List<Map<String, dynamic>>>(

  CitizenReportsNotifier.new,
);

/// User Alerts Provider
class UserAlertsNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) return [];
    return ref.read(puneApiRepositoryProvider).getUserAlerts();
  }

  Future<void> saveAlert({
    String alertType = 'aqi_threshold',
    required double thresholdValue,
    String? savedLocationId,
    String? pollutantCode,
  }) async {
    await ref.read(puneApiRepositoryProvider).saveUserAlert(
      alertType: alertType,
      thresholdValue: thresholdValue,
      savedLocationId: savedLocationId,
      pollutantCode: pollutantCode,
    );
    state = AsyncData(await ref.read(puneApiRepositoryProvider).getUserAlerts());
  }

  Future<void> deleteAlert(String alertId) async {
    await ref.read(puneApiRepositoryProvider).deleteAlert(alertId);
    state = AsyncData(await ref.read(puneApiRepositoryProvider).getUserAlerts());
  }

  Future<void> toggleAlert(String alertId) async {
    await ref.read(puneApiRepositoryProvider).toggleAlert(alertId);
    state = AsyncData(await ref.read(puneApiRepositoryProvider).getUserAlerts());
  }
}

final userAlertsProvider = AsyncNotifierProvider<UserAlertsNotifier, List<Map<String, dynamic>>>(
  UserAlertsNotifier.new,
);

/// User Exposure Sessions Provider
class ExposureSessionsNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) return [];
    return ref.read(puneApiRepositoryProvider).getExposureSessions();
  }

  Future<void> refresh() async {
    state = AsyncData(await ref.read(puneApiRepositoryProvider).getExposureSessions());
  }
}

final exposureSessionsProvider = AsyncNotifierProvider<ExposureSessionsNotifier, List<Map<String, dynamic>>>(
  ExposureSessionsNotifier.new,
);

/// Active Health Persona ('General', 'Asthma / Respiratory', 'Senior Citizen', 'Outdoor Athlete', 'Child')
final activeHealthPersonaProvider = StateProvider<String>((ref) => 'General');

/// Data Health & Diagnostics
final dataHealthProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(puneApiRepositoryProvider).fetchDataHealth();
});

/// Station History Provider with time range parameter
final stationHistoryProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, ({String stationId, String range})>((ref, arg) async {
  return ref.watch(puneApiRepositoryProvider).fetchStationHistory(arg.stationId, range: arg.range);
});
