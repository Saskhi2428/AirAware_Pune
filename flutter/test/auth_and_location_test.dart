import 'package:flutter_test/flutter_test.dart';
import 'package:airaware/models/station.dart';
import 'package:airaware/theme/app_theme.dart';
import 'package:airaware/repositories/pune_api_repository.dart';

void main() {
  group('CPCB AQI Category & Theme Tests', () {
    test('Color mapping conforms to official Indian CPCB NAQI standards', () {
      expect(AppColors.colorForAqiCategory('Good'), AppColors.aqiGood);
      expect(AppColors.colorForAqiCategory('Satisfactory'), AppColors.aqiSatisfactory);
      expect(AppColors.colorForAqiCategory('Moderate'), AppColors.aqiModerate);
      expect(AppColors.colorForAqiCategory('Poor'), AppColors.aqiPoor);
      expect(AppColors.colorForAqiCategory('Very Poor'), AppColors.aqiVeryPoor);
      expect(AppColors.colorForAqiCategory('Severe'), AppColors.aqiSevere);
    });

    test('Case-insensitive category resolution', () {
      expect(AppColors.colorForAqiCategory('good'), AppColors.aqiGood);
      expect(AppColors.colorForAqiCategory('moderate'), AppColors.aqiModerate);
      expect(AppColors.colorForAqiCategory('severe'), AppColors.aqiSevere);
    });
  });

  group('Station Model Tests', () {
    test('Station parses CPCB real-time payload correctly', () {
      final json = {
        'id': 'st-shivajinagar',
        'name': 'Shivajinagar, Pune - CPCB',
        'area': 'Shivajinagar',
        'latitude': 18.5314,
        'longitude': 73.8446,
        'station_type': 'CAAQMS',
        'is_active': true,
        'aqi_value': 88,
        'aqi_category': 'Satisfactory',
        'dominant_pollutant': 'PM2.5',
      };

      final station = Station.fromJson(json);
      expect(station.id, 'st-shivajinagar');
      expect(station.name, 'Shivajinagar, Pune - CPCB');
      expect(station.area, 'Shivajinagar');
      expect(station.latitude, 18.5314);
      expect(station.longitude, 73.8446);
      expect(station.aqiValue, 88);
      expect(station.aqiCategory, 'Satisfactory');
      expect(station.dominantPollutant, 'PM2.5');
      expect(station.hasCurrentAqi, isTrue);
    });
  });

  group('PuneApiRepository Auth & Saved Locations Privacy Tests', () {
    test('fetchSavedLocations returns empty list for unauthenticated requests without throwing', () async {
      final repo = PuneApiRepository();
      // Supabase is unauthenticated in headless unit test environment
      final places = await repo.fetchSavedLocations();
      expect(places, isEmpty);
    });

    test('fetchDataHealth returns healthy diagnostic structure', () async {
      final repo = PuneApiRepository();
      final health = await repo.fetchDataHealth();
      expect(health, contains('status'));
      expect(health, contains('region'));
      expect(health['status'], 'Healthy');
      expect(health['region'], contains('Pune'));
    });

    test('askAiAssistant provides verified environmental intelligence guidance', () async {
      final repo = PuneApiRepository();
      final resp = await repo.askAiAssistant('Can I go for a run in Pashan?');
      expect(resp, contains('answer'));
      expect(resp, contains('current_aqi'));
      expect(resp, contains('category'));
      expect(resp, contains('key_recommendations'));
      expect(resp['key_recommendations'], isA<List>());
    });

    test('fetchCitizenReports returns community incidents list', () async {
      final repo = PuneApiRepository();
      final reports = await repo.fetchCitizenReports();
      expect(reports, isA<List>());
    });

    test('fetchUserProfile returns guest profile map for unauthenticated environment', () async {
      final repo = PuneApiRepository();
      final profile = await repo.fetchUserProfile();
      expect(profile, contains('id'));
      expect(profile, contains('full_name'));
      expect(profile, contains('role'));
      expect(profile, contains('notification_prefs'));
      expect(profile['notification_prefs'], isA<Map>());
    });

    test('updateProfileName throws Exception when user is unauthenticated', () async {
      final repo = PuneApiRepository();
      expect(() => repo.updateProfileName('New Name'), throwsA(isA<Exception>()));
    });
  });
}
