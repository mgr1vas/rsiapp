import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rsi/core/geo/route_progress.dart';
import 'package:rsi/core/navigation/route_guidance.dart';
import 'package:rsi/core/navigation/simulation_clock.dart';
import 'package:rsi/models/hazard_model.dart';
import 'package:rsi/services/osrm_service.dart';

HazardFeature _hazard(String id, LatLng location, double radius) {
  return HazardFeature(
    id: id,
    hazardType: 'Test hazard',
    locationDescription: '',
    nearestArea: '',
    severity: '',
    date: '',
    weatherFactor: '',
    totalAccidents: 1,
    recentAccidents: 0,
    radiusMeters: radius,
    location: location,
  );
}

void main() {
  group('RouteGuidance', () {
    // Due east, about 173 m per segment, 520 m in total.
    final route = RouteProgress(const [
      LatLng(39.0, 21.000),
      LatLng(39.0, 21.002),
      LatLng(39.0, 21.004),
      LatLng(39.0, 21.006),
    ]);

    const steps = [
      NavigationStep(
        instruction: 'Ξεκινήστε',
        distanceMeters: 173,
        location: LatLng(39.0, 21.000),
      ),
      NavigationStep(
        instruction: 'Στρίψτε δεξιά',
        distanceMeters: 347,
        location: LatLng(39.0, 21.002),
      ),
      NavigationStep(
        instruction: 'Φτάσατε',
        distanceMeters: 0,
        location: LatLng(39.0, 21.006),
      ),
    ];

    // ~347 m along, warned from 400 m.
    final nearHazard = _hazard('near', const LatLng(39.0003, 21.004), 150);
    // ~477 m along, warned from 450 m.
    final farHazard = _hazard('far', const LatLng(39.0, 21.0055), 200);
    // More than a kilometre north of the road.
    final offRoute = _hazard('off', const LatLng(39.01, 21.003), 100);

    final guidance = RouteGuidance.build(
      route: route,
      steps: steps,
      hazards: [farHazard, offRoute, nearHazard],
    );

    test('next maneuver skips the start and ones just passed', () {
      final fromStart = guidance.nextManeuver(0);
      expect(fromStart?.step.instruction, 'Στρίψτε δεξιά');
      expect(fromStart?.distanceMeters, closeTo(173, 2));

      final atTurn = guidance.nextManeuver(170);
      expect(atTurn?.step.instruction, 'Φτάσατε');

      expect(guidance.nextManeuver(route.totalMeters), isNull);
    });

    test('announces the closest hazard within its warning distance', () {
      final announced = guidance.hazardToAnnounce(0, {});

      expect(announced?.hazard.id, 'near');
      expect(announced?.distanceMeters, closeTo(347, 3));
    });

    test('moves on to the next hazard once one was announced', () {
      expect(guidance.hazardToAnnounce(0, {'near'}), isNull);
      expect(guidance.hazardToAnnounce(100, {'near'})?.hazard.id, 'far');
    });

    test('drops hazards the driver has passed', () {
      expect(guidance.hazardToAnnounce(400, {})?.hazard.id, 'far');
    });

    test('ignores hazards away from the route', () {
      expect(guidance.distanceToHazard(offRoute, 0), isNull);
      expect(guidance.distanceToHazard(nearHazard, 300), closeTo(47, 3));
    });
  });

  group('SimulationClock', () {
    final start = DateTime(2026, 9, 14, 12);

    test('advances at the chosen multiple of town speed', () {
      final clock = SimulationClock.start(
        fromMeters: 100,
        multiplier: 5,
        now: start,
      );

      final after = clock.metersAt(start.add(const Duration(seconds: 2)));

      expect(after, closeTo(100 + 2 * 5 * 50 / 3.6, 1e-6));
    });

    test('never goes backwards before it started', () {
      final clock = SimulationClock.start(
        fromMeters: 100,
        multiplier: 5,
        now: start,
      );

      expect(clock.metersAt(start.subtract(const Duration(seconds: 1))), 100);
    });

    test('treats a zero multiplier as normal speed', () {
      final clock = SimulationClock.start(
        fromMeters: 0,
        multiplier: 0,
        now: start,
      );

      expect(
        clock.metersAt(start.add(const Duration(seconds: 36))),
        closeTo(500, 1e-6),
      );
    });
  });
}
