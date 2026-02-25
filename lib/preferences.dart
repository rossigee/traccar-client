import 'dart:io';
import 'dart:math';

import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';

class Preferences {
  static Future<void>? _initFuture;
  static late SharedPreferencesWithCache instance;

  static const String id = 'id';
  static const String url = 'url';
  static const String accuracy = 'accuracy';
  static const String distance = 'distance';
  static const String interval = 'interval';
  static const String angle = 'angle';
  static const String heartbeat = 'heartbeat';
  static const String fastestInterval = 'fastest_interval';
  static const String buffer = 'buffer';
  static const String wakelock = 'wakelock';
  static const String stopDetection = 'stop_detection';
  static const String password = 'password';
  static const String firebase = 'firebase';
  static const String scheduleStart = 'schedule_start';
  static const String scheduleStop = 'schedule_stop';
  static const String scheduleEntry = 'schedule_entry';
  static const String scheduleEnabled = 'schedule_enabled';

  static const String lastTimestamp = 'lastTimestamp';
  static const String lastLatitude = 'lastLatitude';
  static const String lastLongitude = 'lastLongitude';
  static const String lastHeading = 'lastHeading';

  static Future<void> init() async {
    _initFuture ??= _createInstance();
    await _initFuture;
  }

  static Future<void> _createInstance() async {
    instance = await SharedPreferencesWithCache.create(
      sharedPreferencesOptions: Platform.isAndroid
          ? SharedPreferencesAsyncAndroidOptions(
              backend: SharedPreferencesAndroidBackendLibrary.SharedPreferences,
            )
          : SharedPreferencesOptions(),
      cacheOptions: SharedPreferencesWithCacheOptions(
        allowList: {
          id,
          url,
          accuracy,
          distance,
          interval,
          angle,
          heartbeat,
          fastestInterval,
          buffer,
          wakelock,
          stopDetection,
          password,
          firebase,
          scheduleStart,
          scheduleStop,
          scheduleEntry,
          scheduleEnabled,
          lastTimestamp,
          lastLatitude,
          lastLongitude,
          lastHeading,
          'device_id_preference',
          'server_url_preference',
          'accuracy_preference',
          'frequency_preference',
          'distance_preference',
          'buffer_preference',
        },
      ),
    );
    if (instance.getString(id) == null) {
      await instance.setString(
        id,
        (Random().nextInt(90000000) + 10000000).toString(),
      );
      await instance.setString(url, 'http://demo.traccar.org:5055');
      await instance.setString(accuracy, 'medium');
      await instance.setInt(interval, 300);
      await instance.setInt(distance, 75);
      await instance.setBool(buffer, true);
      await instance.setBool(stopDetection, true);
      await instance.setInt(fastestInterval, 30);
      await instance.setBool(firebase, true);
      await instance.setBool(scheduleEnabled, false);
    }
    await _ensureScheduleEntry();
  }

  static Future<void> _ensureScheduleEntry() async {
    final hasSchedule = instance.getBool(scheduleEnabled) ?? false;
    if (!hasSchedule) {
      return;
    }

    final entry = instance.getString(scheduleEntry);
    if (entry != null && entry.trim().isNotEmpty) {
      return;
    }

    final start = instance.getString(scheduleStart) ?? '08:00';
    final stop = instance.getString(scheduleStop) ?? '17:00';
    await instance.setString(scheduleEntry, '1-7 $start-$stop');
  }

  static bg.Config geolocationConfig() {
    final isHighestAccuracy = instance.getString(accuracy) == 'highest';
    final locationUpdateInterval = (instance.getInt(interval) ?? 0) * 1000;
    final fastestLocationUpdateInterval =
        (instance.getInt(fastestInterval) ?? 30) * 1000;
    final heartbeatInterval = instance.getInt(heartbeat) ?? 0;
    return bg.Config(
      isMoving: true,
      geolocation: bg.GeoConfig(
        desiredAccuracy: switch (instance.getString(accuracy)) {
          'highest' =>
            Platform.isIOS
                ? bg.DesiredAccuracy.navigation
                : bg.DesiredAccuracy.high,
          'high' => bg.DesiredAccuracy.high,
          'low' => bg.DesiredAccuracy.low,
          _ => bg.DesiredAccuracy.medium,
        },
        distanceFilter: isHighestAccuracy
            ? 0
            : instance.getInt(distance)?.toDouble(),
        locationUpdateInterval: Platform.isAndroid
            ? (isHighestAccuracy
                  ? 0
                  : (locationUpdateInterval > 0
                        ? locationUpdateInterval
                        : null))
            : null,
        fastestLocationUpdateInterval: Platform.isAndroid
            ? (isHighestAccuracy ? 0 : fastestLocationUpdateInterval)
            : null,
        disableElasticity: true,
        pausesLocationUpdatesAutomatically: Platform.isIOS
            ? !(isHighestAccuracy || instance.getBool(stopDetection) == false)
            : null,
        showsBackgroundLocationIndicator: Platform.isIOS ? false : null,
      ),
      app: bg.AppConfig(
        enableHeadless: Platform.isAndroid ? true : null,
        stopOnTerminate: false,
        startOnBoot: Platform.isAndroid ? true : null,
        heartbeatInterval: heartbeatInterval > 0
            ? heartbeatInterval.toDouble()
            : null,
        preventSuspend: Platform.isIOS ? (heartbeatInterval > 0) : null,
        backgroundPermissionRationale: Platform.isAndroid
            ? bg.PermissionRationale(
                title:
                    'Allow {applicationName} to access this device\'s location in the background',
                message:
                    'For reliable tracking, please enable {backgroundPermissionOptionLabel} location access.',
                positiveAction: 'Change to {backgroundPermissionOptionLabel}',
                negativeAction: 'Cancel',
              )
            : null,
        notification: Platform.isAndroid
            ? bg.Notification(
                smallIcon: 'drawable/ic_stat_notify',
                priority: bg.NotificationPriority.low,
              )
            : null,
      ),
      http: bg.HttpConfig(
        autoSync: true,
        autoSyncThreshold: 1,
        batchSync: false,
        url: _formatUrl(instance.getString(url)),
        params: {'device_id': instance.getString(id)},
      ),
      logger: const bg.LoggerConfig(
        logLevel: bg.LogLevel.verbose,
        logMaxDays: 1,
      ),
      activity: bg.ActivityConfig(
        disableStopDetection: instance.getBool(stopDetection) == false,
      ),
      persistence: bg.PersistenceConfig(
        maxRecordsToPersist: instance.getBool(buffer) != false ? -1 : 1,
        locationTemplate: _locationTemplate(),
      ),
    );
  }

  static String? _formatUrl(String? url) {
    if (url == null) return null;
    final uri = Uri.parse(url);
    if (uri.path.isEmpty && !url.endsWith('/')) return '$url/';
    return url;
  }

  static String _locationTemplate() {
    return '''{
      "timestamp": "<%= timestamp %>",
      "device_id": "<%= device.id %>",
      "coords": {
        "latitude": <%= latitude %>,
        "longitude": <%= longitude %>,
        "accuracy": <%= accuracy %>,
        "speed": <%= speed %>,
        "heading": <%= heading %>,
        "altitude": <%= altitude %>
      },
      "is_moving": <%= is_moving %>,
      "odometer": <%= odometer %>,
      "event": "<%= event %>",
      "battery": {
        "level": <%= battery.level %>,
        "is_charging": <%= battery.is_charging %>
      },
      "activity": {
        "type": "<%= activity.type %>"
      },
      "extras": {}
    }'''
        .split('\n')
        .map((line) => line.trimLeft())
        .join();
  }
}
