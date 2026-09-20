import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/format/navigation_labels.dart';
import '../models/hazard_model.dart';

/// Heads-up notifications for hazards ahead, so the driver is still warned
/// while another app (music, calls, messages) is on screen.
class NavigationAlerts {
  NavigationAlerts._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'rsi_hazard_alerts';
  static const String _channelName = 'Προειδοποιήσεις κινδύνου';
  static const String _channelDescription =
      'Ειδοποιήσεις για επικίνδυνα σημεία στη διαδρομή κατά την πλοήγηση';
  static const int _hazardNotificationId = 4101;

  /// A hazard notification disappears on its own after this long.
  static const Duration _hazardTimeout = Duration(seconds: 20);

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _initialized = true;
    } catch (error) {
      debugPrint('RSI could not set up notifications: $error');
    }
  }

  /// Asks for permission to show notifications (Android 13+ and iOS).
  /// Returns whether hazard alerts can be shown.
  static Future<bool> requestPermission() async {
    await initialize();
    if (!_initialized) return false;

    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }

      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        return await ios.requestPermissions(alert: true, sound: true) ??
            false;
      }
    } catch (error) {
      debugPrint('RSI could not ask for notification permission: $error');
    }

    return false;
  }

  static Future<void> showHazard(
    HazardFeature hazard,
    double distanceMeters,
  ) async {
    await initialize();
    if (!_initialized) return;

    final area = hazard.nearestArea.trim();

    try {
      await _plugin.show(
        _hazardNotificationId,
        'Προσοχή σε ${formatDistance(distanceMeters)}: ${hazard.hazardType}',
        area.isEmpty ? 'Επικίνδυνο σημείο στη διαδρομή σας' : area,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.navigation,
            ticker: 'Προειδοποίηση κινδύνου',
            timeoutAfter: _hazardTimeout.inMilliseconds,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
      );
    } catch (error) {
      debugPrint('RSI could not show the hazard notification: $error');
    }
  }

  static Future<void> clearHazard() async {
    if (!_initialized) return;

    try {
      await _plugin.cancel(_hazardNotificationId);
    } catch (error) {
      debugPrint('RSI could not clear the hazard notification: $error');
    }
  }
}
