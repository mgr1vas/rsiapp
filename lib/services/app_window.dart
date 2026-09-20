import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Control over the app's own window on Android: sending it to the
/// background and the small picture-in-picture window during navigation.
class AppWindow {
  AppWindow._();

  static const MethodChannel _channel = MethodChannel(
    'com.roadsafetyinsights.app/window',
  );

  /// True while the app is shown in the small picture-in-picture window.
  static final ValueNotifier<bool> pictureInPicture = ValueNotifier(false);

  static bool _listening = false;

  /// Starts listening for the window entering or leaving picture-in-picture.
  static void initialize() {
    if (_listening) return;
    _listening = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pictureInPictureChanged') {
        pictureInPicture.value = call.arguments == true;
      }
    });
  }

  /// While enabled, leaving the app (home, recents, back) shrinks it into a
  /// floating picture-in-picture window instead of hiding it.
  static Future<void> setAutoPictureInPicture(bool enabled) async {
    initialize();

    try {
      await _channel.invokeMethod<bool>(
        'setAutoPictureInPicture',
        {'enabled': enabled},
      );
    } on MissingPluginException {
      // iOS: not supported.
    } on PlatformException catch (error) {
      debugPrint('RSI could not set up picture-in-picture: $error');
    }
  }

  /// Leaves the app without closing it: into picture-in-picture when that
  /// is enabled, otherwise to the background like the home button.
  static Future<void> moveToBackground() async {
    try {
      await _channel.invokeMethod<bool>('moveToBackground');
    } on MissingPluginException {
      // iOS has no equivalent; apps there are never closed by "back".
    } on PlatformException catch (error) {
      debugPrint('RSI could not move the app to the background: $error');
    }
  }
}
