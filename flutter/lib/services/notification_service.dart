import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';



class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  // Notification cooldown management to prevent spamming the user
  DateTime? _lastAlertTimestamp;
  int? _lastAlertAqi;
  static const Duration _cooldownDuration = Duration(minutes: 30);

  static const String _alertChannelId = 'airaware_alerts';
  static const String _alertChannelName = 'AirAware Pollution Alerts';
  static const String _alertChannelDescription =
      'Real-time alerts when ambient AQI crosses critical health thresholds in Pune';

  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    try {
      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          debugPrint('[NotificationService] Notification clicked with payload: ${response.payload}');
        },
      );

      if (Platform.isAndroid) {
        final androidImpl = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        if (androidImpl != null) {
          await androidImpl.requestNotificationsPermission();
          await androidImpl.createNotificationChannel(
            const AndroidNotificationChannel(
              _alertChannelId,
              _alertChannelName,
              description: _alertChannelDescription,
              importance: Importance.high,
              enableVibration: true,
              playSound: true,
            ),
          );
        }
      }

      _isInitialized = true;
      debugPrint('[NotificationService] Initialized successfully.');
    } catch (e) {
      debugPrint('[NotificationService] Initialization error: $e');
    }
  }

  Future<void> showAqiAlert({
    required String title,
    required String body,
    int? aqi,
    String? payload,
  }) async {
    if (!_isInitialized) await initialize();

    final androidDetails = AndroidNotificationDetails(
      _alertChannelId,
      _alertChannelName,
      channelDescription: _alertChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFF6366F1), // Indigo brand color
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: aqi != null ? 'Pune AQI: $aqi' : 'Pune Air Alert',
      ),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      final id = DateTime.now().millisecondsSinceEpoch.remainder(100000);
      await _plugin.show(
        id,
        title,
        body,
        notificationDetails,
        payload: payload,
      );
      debugPrint('[NotificationService] Push alert delivered: $title');
    } catch (e) {
      debugPrint('[NotificationService] Failed to show notification: $e');
    }
  }

  /// Evaluates whether current AQI exceeds user-configured threshold with cooldown deduplication
  Future<void> checkThresholdAndNotify({
    required int currentAqi,
    required double thresholdAqi,
    required String stationName,
    String? dominantPollutant,
  }) async {
    if (currentAqi < thresholdAqi) return;

    final now = DateTime.now();
    final inCooldown = _lastAlertTimestamp != null &&
        now.difference(_lastAlertTimestamp!) < _cooldownDuration;

    // Trigger only if outside cooldown OR if AQI surged by >= 50 points higher than previous alert
    if (inCooldown && _lastAlertAqi != null && (currentAqi - _lastAlertAqi!) < 50) {
      debugPrint('[NotificationService] Alert suppressed by cooldown ($currentAqi AQI)');
      return;
    }

    _lastAlertTimestamp = now;
    _lastAlertAqi = currentAqi;

    final pollutantText = dominantPollutant != null ? ' (Dominant: $dominantPollutant)' : '';
    await showAqiAlert(
      title: '⚠️ Air Quality Alert: $stationName ($currentAqi AQI)',
      body:
          'Pollution level at $stationName is $currentAqi AQI$pollutantText, exceeding your saved safety threshold of ${thresholdAqi.round()} AQI. Consider wearing an N95 mask outdoors.',
      aqi: currentAqi,
      payload: 'station_alert',
    );
  }
}
