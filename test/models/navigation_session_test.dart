import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rsi/models/navigation_session.dart';
import 'package:rsi/services/app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final savedAt = DateTime(2026, 9, 14, 12, 30);

  final session = NavigationSession(
    originName: 'Γεφύρι της Άρτας',
    origin: const LatLng(39.152424, 20.975914),
    destinationName: 'Γενικό Νοσοκομείο Άρτας',
    destination: const LatLng(39.147838, 20.994677),
    simulate: true,
    simulationMultiplier: 5,
    metersAlong: 1234.5,
    savedAt: savedAt,
  );

  test('survives saving and loading', () {
    final restored = NavigationSession.tryDecode(session.encode());

    expect(restored, isNotNull);
    expect(restored!.originName, session.originName);
    expect(restored.origin, session.origin);
    expect(restored.destinationName, session.destinationName);
    expect(restored.destination, session.destination);
    expect(restored.simulate, isTrue);
    expect(restored.simulationMultiplier, 5);
    expect(restored.metersAlong, 1234.5);
    expect(restored.savedAt, savedAt);
  });

  test('ignores missing or damaged data', () {
    expect(NavigationSession.tryDecode(null), isNull);
    expect(NavigationSession.tryDecode(''), isNull);
    expect(NavigationSession.tryDecode('not json'), isNull);
    expect(NavigationSession.tryDecode('[1, 2]'), isNull);
    expect(
      NavigationSession.tryDecode('{"origin": [39, 20], "simulate": true}'),
      isNull,
    );
    expect(
      NavigationSession.tryDecode(
        session.encode().replaceFirst('39.152424', '139.152424'),
      ),
      isNull,
    );
  });

  test('is only resumed for a few hours', () {
    expect(session.isFresh(savedAt.add(const Duration(hours: 1))), isTrue);
    expect(session.isFresh(savedAt.add(const Duration(hours: 4))), isFalse);
  });

  test('updates progress without changing the trip', () {
    final later = savedAt.add(const Duration(minutes: 2));
    final updated = session.withProgress(2000, later);

    expect(updated.metersAlong, 2000);
    expect(updated.savedAt, later);
    expect(updated.destination, session.destination);
  });

  test('is stored in and cleared from device preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await AppPreferences.load();

    expect(preferences.navigationSession, isNull);

    await preferences.saveNavigationSession(session);
    expect(preferences.navigationSession?.metersAlong, 1234.5);

    await preferences.clearNavigationSession();
    expect(preferences.navigationSession, isNull);
  });
}
