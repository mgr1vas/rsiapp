import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rsi/core/geo/bearing.dart';
import 'package:rsi/core/geo/route_progress.dart';

void main() {
  // Three points heading due east, about 86.7 m apart.
  final eastward = RouteProgress(const [
    LatLng(39.0, 21.000),
    LatLng(39.0, 21.001),
    LatLng(39.0, 21.002),
  ]);

  test('measures the whole route', () {
    expect(eastward.totalMeters, closeTo(173.3, 1));
  });

  test('finds positions part-way along a segment', () {
    final quarter = eastward.positionAt(eastward.totalMeters / 4);

    expect(quarter.latitude, closeTo(39.0, 1e-9));
    expect(quarter.longitude, closeTo(21.0005, 1e-6));
  });

  test('clamps positions to the ends of the route', () {
    expect(eastward.positionAt(-50), eastward.points.first);
    expect(eastward.positionAt(1e6), eastward.points.last);
  });

  test('reports share of the route covered', () {
    expect(eastward.fractionAt(0), 0);
    expect(eastward.fractionAt(eastward.totalMeters / 2), closeTo(0.5, 1e-9));
    expect(eastward.fractionAt(1e6), 1);
  });

  test('heading follows the road, including at the very end', () {
    expect(eastward.headingAt(40), closeTo(90, 0.5));
    expect(eastward.headingAt(eastward.totalMeters), closeTo(90, 0.5));
  });

  test('heading turns gradually through a corner', () {
    final corner = RouteProgress(const [
      LatLng(39.0, 21.000),
      LatLng(39.0, 21.001),
      LatLng(39.001, 21.001),
    ]);
    final cornerMeters = corner.snap(const LatLng(39.0, 21.001)).metersAlong;

    final heading = corner.headingAt(cornerMeters);

    expect(heading, greaterThan(5));
    expect(heading, lessThan(85));
    expect(corner.headingAt(cornerMeters + 40), closeTo(0, 0.5));
  });

  test('snaps a nearby point onto the route', () {
    final snap = eastward.snap(const LatLng(39.00018, 21.001));

    expect(snap.offsetMeters, closeTo(20, 1));
    expect(snap.metersAlong, closeTo(86.7, 2));
  });

  test('stays on the nearby part of a route that doubles back', () {
    // Out east, a few metres north, then back west along the same road.
    final outAndBack = RouteProgress(const [
      LatLng(39.0, 21.000),
      LatLng(39.0, 21.002),
      LatLng(39.00005, 21.002),
      LatLng(39.00005, 21.000),
    ]);
    const point = LatLng(39.00002, 21.0005);

    final outward = outAndBack.snap(point);
    final returning = outAndBack.snap(
      point,
      nearMeters: 308,
      windowMeters: 100,
    );

    expect(outward.metersAlong, lessThan(173));
    expect(returning.metersAlong, greaterThan(178));
  });

  group('bearing', () {
    test('points east and north', () {
      expect(
        bearingBetween(const LatLng(39, 21), const LatLng(39, 21.01)),
        closeTo(90, 0.1),
      );
      expect(
        bearingBetween(const LatLng(39, 21), const LatLng(39.01, 21)),
        closeTo(0, 0.1),
      );
    });

    test('eases the short way round through north', () {
      expect(lerpBearing(350, 10, 0.5), closeTo(0, 1e-9));
      expect(lerpBearing(10, 350, 0.5), closeTo(0, 1e-9));
      expect(lerpBearing(0, 90, 2), closeTo(90, 1e-9));
    });
  });
}
