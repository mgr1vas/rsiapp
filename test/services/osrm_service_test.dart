import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rsi/services/osrm_service.dart';

void main() {
  const start = LatLng(39.16, 20.98);
  const end = LatLng(39.14, 20.99);

  group('route url', () {
    test('asks for the full geometry and the turn steps', () {
      final url = OsrmService.routeUrl(start: start, end: end);

      expect(url.path, endsWith('/route/v1/driving/20.98,39.16;20.99,39.14'));
      expect(url.queryParameters['overview'], 'full');
      expect(url.queryParameters['geometries'], 'geojson');
      expect(url.queryParameters['steps'], 'true');
    });

    test('leaves out bearings when the heading is unknown', () {
      final url = OsrmService.routeUrl(start: start, end: end);

      expect(url.queryParameters.containsKey('bearings'), isFalse);
    });

    test('holds the route to the way the car is pointing', () {
      final url = OsrmService.routeUrl(start: start, end: end, startBearing: 92.4);

      // One entry per coordinate; the destination may be approached any way.
      expect(url.queryParameters['bearings'], '92,45;');
    });

    test('wraps the heading into 0-359 degrees', () {
      expect(
        OsrmService.routeUrl(start: start, end: end, startBearing: -90)
            .queryParameters['bearings'],
        '270,45;',
      );
      expect(
        OsrmService.routeUrl(start: start, end: end, startBearing: 361)
            .queryParameters['bearings'],
        '1,45;',
      );
      expect(
        OsrmService.routeUrl(start: start, end: end, startBearing: 359.8)
            .queryParameters['bearings'],
        '0,45;',
      );
    });
  });
}
