import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'bearing.dart';

/// Where a point lies relative to a route.
class RouteSnap {
  const RouteSnap({required this.metersAlong, required this.offsetMeters});

  /// Distance from the start of the route to the closest point on it.
  final double metersAlong;

  /// Straight-line distance between the point and the route.
  final double offsetMeters;
}

/// A route line measured once, so positions and distances along it can be
/// looked up cheaply many times a second while navigating.
class RouteProgress {
  RouteProgress(List<LatLng> points)
      : points = List.unmodifiable(points),
        _cumulative = _measure(points);

  // Unrounded: the default rounds each segment to whole metres, which adds
  // up over hundreds of short segments and makes movement uneven.
  static const Distance _distance = Distance(roundResult: false);
  static const double _earthRadiusMeters = 6371000.0;

  /// A nearby match further off the route than this is treated as the wrong
  /// part of the route (e.g. a road that loops back), so the whole route is
  /// searched instead.
  static const double _maxLocalOffsetMeters = 60;

  final List<LatLng> points;
  final List<double> _cumulative;

  double get totalMeters => _cumulative.isEmpty ? 0 : _cumulative.last;

  static List<double> _measure(List<LatLng> points) {
    final cumulative = <double>[];
    var total = 0.0;

    for (var i = 0; i < points.length; i++) {
      if (i > 0) {
        total += _distance.as(LengthUnit.Meter, points[i - 1], points[i]);
      }
      cumulative.add(total);
    }

    return cumulative;
  }

  /// Share of the route covered after [meters], from 0 to 1.
  double fractionAt(double meters) {
    if (totalMeters <= 0) return 0;
    return (meters / totalMeters).clamp(0.0, 1.0);
  }

  /// The point [meters] from the start, clamped to the route's ends.
  LatLng positionAt(double meters) {
    if (points.isEmpty) {
      throw StateError('Cannot find a position on an empty route.');
    }
    if (points.length == 1) return points.first;

    final clamped = meters.clamp(0.0, totalMeters);
    final index = _segmentAt(clamped);
    final start = points[index];
    final end = points[index + 1];
    final segmentLength = _cumulative[index + 1] - _cumulative[index];
    final t = segmentLength <= 0
        ? 0.0
        : (clamped - _cumulative[index]) / segmentLength;

    return LatLng(
      start.latitude + (end.latitude - start.latitude) * t,
      start.longitude + (end.longitude - start.longitude) * t,
    );
  }

  /// Driving direction at [meters], measured across a short stretch of road
  /// so a corner turns the heading gradually instead of snapping.
  double headingAt(
    double meters, {
    double behindMeters = 4,
    double aheadMeters = 14,
  }) {
    if (points.length < 2) return 0;

    final span = behindMeters + aheadMeters;
    final start = totalMeters <= span
        ? 0.0
        : (meters - behindMeters).clamp(0.0, totalMeters - span);
    final end = math.min(totalMeters, start + span);

    return bearingBetween(positionAt(start), positionAt(end));
  }

  /// Finds where [point] lies along the route.
  ///
  /// Pass [nearMeters] (the last known position) to search only the nearby
  /// stretch, which is faster and avoids jumping to another part of a route
  /// that passes the same spot twice.
  RouteSnap snap(
    LatLng point, {
    double? nearMeters,
    double windowMeters = 300,
  }) {
    if (points.isEmpty) {
      return const RouteSnap(metersAlong: 0, offsetMeters: double.infinity);
    }
    if (points.length == 1) {
      return RouteSnap(
        metersAlong: 0,
        offsetMeters: _distance.as(LengthUnit.Meter, point, points.first),
      );
    }

    if (nearMeters != null) {
      final local = _snapBetween(
        point,
        _segmentAt(math.max(0, nearMeters - windowMeters)),
        _segmentAt(math.min(totalMeters, nearMeters + windowMeters)),
      );
      if (local.offsetMeters <= _maxLocalOffsetMeters) return local;
    }

    return _snapBetween(point, 0, points.length - 2);
  }

  /// Index of the segment containing [meters] along the route.
  int _segmentAt(double meters) {
    var low = 0;
    var high = points.length - 2;

    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (_cumulative[mid] <= meters) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }

    return low;
  }

  RouteSnap _snapBetween(LatLng point, int firstSegment, int lastSegment) {
    // Flat projection around the point; accurate over the few hundred
    // metres a single route segment spans.
    final cosLatitude = math.cos(point.latitude * math.pi / 180);
    double x(LatLng p) =>
        p.longitude * math.pi / 180 * _earthRadiusMeters * cosLatitude;
    double y(LatLng p) => p.latitude * math.pi / 180 * _earthRadiusMeters;

    final px = x(point);
    final py = y(point);

    var bestOffset = double.infinity;
    var bestAlong = 0.0;

    for (var i = firstSegment; i <= lastSegment; i++) {
      final ax = x(points[i]);
      final ay = y(points[i]);
      final abX = x(points[i + 1]) - ax;
      final abY = y(points[i + 1]) - ay;
      final lengthSquared = abX * abX + abY * abY;

      final t = lengthSquared == 0
          ? 0.0
          : (((px - ax) * abX + (py - ay) * abY) / lengthSquared)
              .clamp(0.0, 1.0);

      final dx = px - (ax + abX * t);
      final dy = py - (ay + abY * t);
      final offset = math.sqrt(dx * dx + dy * dy);

      if (offset < bestOffset) {
        bestOffset = offset;
        bestAlong =
            _cumulative[i] + (_cumulative[i + 1] - _cumulative[i]) * t;
      }
    }

    return RouteSnap(metersAlong: bestAlong, offsetMeters: bestOffset);
  }
}
