import 'dart:math' as math;

import '../../models/hazard_model.dart';
import '../../services/osrm_service.dart';
import '../geo/route_progress.dart';

class UpcomingManeuver {
  const UpcomingManeuver({required this.step, required this.distanceMeters});

  final NavigationStep step;
  final double distanceMeters;
}

class UpcomingHazard {
  const UpcomingHazard({required this.hazard, required this.distanceMeters});

  final HazardFeature hazard;
  final double distanceMeters;
}

typedef _Placed<T> = ({T item, double meters});

/// Turn instructions and hazard zones placed along a route once, so each
/// navigation update is a quick lookup instead of re-measuring the route.
class RouteGuidance {
  RouteGuidance._(this._steps, this._hazards);

  factory RouteGuidance.build({
    required RouteProgress route,
    required List<NavigationStep> steps,
    required List<HazardFeature> hazards,
  }) {
    final placedSteps = [
      for (final step in steps)
        (item: step, meters: route.snap(step.location).metersAlong),
    ]..sort((a, b) => a.meters.compareTo(b.meters));

    final placedHazards = <_Placed<HazardFeature>>[];
    for (final hazard in hazards) {
      final snap = route.snap(hazard.location);
      if (snap.offsetMeters > hazard.radiusMeters + hazardBufferMeters) {
        continue;
      }
      placedHazards.add((item: hazard, meters: snap.metersAlong));
    }
    placedHazards.sort((a, b) => a.meters.compareTo(b.meters));

    return RouteGuidance._(placedSteps, placedHazards);
  }

  /// Hazards this far outside their own radius still count as on the route.
  static const double hazardBufferMeters = 50;

  /// A maneuver closer than this is treated as already done.
  static const double _maneuverPassedMeters = 8;

  /// A hazard stays relevant until the driver is this far past it.
  static const double hazardPassedMeters = 30;

  final List<_Placed<NavigationStep>> _steps;
  final List<_Placed<HazardFeature>> _hazards;

  /// How far ahead a hazard is announced: at least 300 m, more for wide zones.
  static double warningDistanceFor(HazardFeature hazard) {
    return math.max(300.0, math.min(800.0, hazard.radiusMeters + 250));
  }

  UpcomingManeuver? nextManeuver(double driverMeters) {
    for (final placed in _steps) {
      final ahead = placed.meters - driverMeters;
      if (ahead >= _maneuverPassedMeters) {
        return UpcomingManeuver(step: placed.item, distanceMeters: ahead);
      }
    }
    return null;
  }

  /// The closest hazard within its warning distance that has not been
  /// announced yet, or null.
  UpcomingHazard? hazardToAnnounce(
    double driverMeters,
    Set<String> announcedKeys,
  ) {
    for (final placed in _hazards) {
      if (announcedKeys.contains(placed.item.stableKey)) continue;

      final ahead = placed.meters - driverMeters;
      if (ahead < -hazardPassedMeters) continue;
      if (ahead > warningDistanceFor(placed.item)) continue;

      return UpcomingHazard(
        hazard: placed.item,
        distanceMeters: math.max(0, ahead),
      );
    }
    return null;
  }

  /// Distance from the driver to [hazard] along the route (negative once
  /// passed), or null if the hazard is not on this route.
  double? distanceToHazard(HazardFeature hazard, double driverMeters) {
    for (final placed in _hazards) {
      if (placed.item.stableKey == hazard.stableKey) {
        return placed.meters - driverMeters;
      }
    }
    return null;
  }
}
