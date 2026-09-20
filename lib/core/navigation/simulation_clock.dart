import 'dart:math' as math;

/// Works out how far a simulated drive has got from the time elapsed, not
/// from counting timer ticks, so the car keeps a steady speed even when
/// frames are dropped or the app is in the background.
class SimulationClock {
  const SimulationClock({
    required this.startMeters,
    required this.metersPerSecond,
    required this.startedAt,
  });

  factory SimulationClock.start({
    required double fromMeters,
    required int multiplier,
    required DateTime now,
  }) {
    return SimulationClock(
      startMeters: fromMeters,
      metersPerSecond: baseMetersPerSecond * math.max(1, multiplier),
      startedAt: now,
    );
  }

  /// Town driving speed (50 km/h) used for the 1× simulation speed.
  static const double baseMetersPerSecond = 50 / 3.6;

  final double startMeters;
  final double metersPerSecond;
  final DateTime startedAt;

  /// Distance along the route reached at [now].
  double metersAt(DateTime now) {
    final seconds = now.difference(startedAt).inMicroseconds / 1e6;
    return startMeters + math.max(0, seconds) * metersPerSecond;
  }
}
