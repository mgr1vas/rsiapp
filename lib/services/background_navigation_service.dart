import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onBackgroundStart,
      autoStart: false,
      isForegroundMode: true,
      // No custom notificationChannelId: the plugin only creates its default
      // channel itself. A custom id needs a channel created by the app first,
      // otherwise Android kills the app with "Bad notification for
      // startForeground" as soon as the service starts.
      initialNotificationTitle: 'Πλοήγηση RSI',
      initialNotificationContent: 'Η πλοήγηση είναι ενεργή',
      // Keeps GPS updates and the navigation logic running while another
      // app is on screen. Must match the type in AndroidManifest.xml.
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onBackgroundStart,
      onBackground: onIosBackground,
    ),
  );
}

/// Keeps navigation alive while the app is in the background, with an
/// ongoing notification showing the next instruction.
class BackgroundNavigationService {
  BackgroundNavigationService._();

  static String? _lastTitle;
  static String? _lastContent;

  /// Starts the foreground service. Android only allows a location service
  /// once location access is granted; without it, starting would crash the
  /// app, so navigation then only runs while the app is open.
  static Future<bool> start() async {
    try {
      final permission = await Geolocator.checkPermission();
      final granted = permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
      if (!granted) return false;

      _lastTitle = null;
      _lastContent = null;
      return await FlutterBackgroundService().startService();
    } catch (error) {
      debugPrint('RSI could not start background navigation: $error');
      return false;
    }
  }

  static void stop() {
    FlutterBackgroundService().invoke('stopService');
  }

  /// Stops a service left over from an earlier run. The plugin restarts its
  /// service after the app is swiped away, which would otherwise keep showing
  /// "navigation active" with nothing navigating.
  static Future<void> stopIfRunning() async {
    try {
      if (await FlutterBackgroundService().isRunning()) stop();
    } catch (error) {
      debugPrint('RSI could not check background navigation: $error');
    }
  }

  /// Updates the ongoing notification; repeated identical text is skipped.
  static void updateNotification({
    required String title,
    required String content,
  }) {
    if (title == _lastTitle && content == _lastContent) return;
    _lastTitle = title;
    _lastContent = content;

    FlutterBackgroundService().invoke('updateNotification', {
      'title': title,
      'content': content,
    });
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onBackgroundStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  service.on('updateNotification').listen((event) {
    if (service is! AndroidServiceInstance || event == null) return;

    final title = event['title'];
    final content = event['content'];
    if (title is! String || content is! String) return;

    service.setForegroundNotificationInfo(title: title, content: content);
  });
}
