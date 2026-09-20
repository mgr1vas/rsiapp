import 'package:flutter_test/flutter_test.dart';
import 'package:rsi/core/navigation/off_route_detector.dart';

void main() {
  final start = DateTime(2026, 9, 20, 10);

  /// Feeds [offsets] one second apart and returns the last verdict.
  RouteFix feed(
    OffRouteDetector detector,
    List<double> offsets, {
    DateTime? from,
  }) {
    var verdict = RouteFix.onRoute;
    final base = from ?? start;

    for (var i = 0; i < offsets.length; i++) {
      verdict = detector.update(
        offsetMeters: offsets[i],
        now: base.add(Duration(seconds: i)),
      );
    }

    return verdict;
  }

  /// One more fix well off the route, at [at].
  RouteFix fixAt(OffRouteDetector detector, DateTime at) =>
      detector.update(offsetMeters: 80, now: at);

  test('stays on route while the car is near the line', () {
    final detector = OffRouteDetector();

    expect(feed(detector, [0, 12, 30, 49, 5]), RouteFix.onRoute);
  });

  test('ignores a single fix thrown off by poor GPS', () {
    final detector = OffRouteDetector();

    expect(feed(detector, [5, 120, 8, 4]), RouteFix.onRoute);
  });

  test('asks for a reroute after three fixes off the route', () {
    final detector = OffRouteDetector();

    expect(
      feed(detector, [5, 80]),
      RouteFix.drifting,
      reason: 'two fixes off the route is not yet enough',
    );
    expect(feed(detector, [80, 90], from: start.add(const Duration(seconds: 2))),
        RouteFix.reroute);
  });

  test('counts only consecutive fixes', () {
    final detector = OffRouteDetector();

    expect(feed(detector, [80, 80, 10, 80, 80]), RouteFix.drifting);
  });

  test('asks once, then waits out the cooldown before asking again', () {
    final detector = OffRouteDetector();
    expect(feed(detector, [80, 80, 80]), RouteFix.reroute);

    // Still off the route, but a request is already on its way.
    expect(fixAt(detector, start.add(const Duration(seconds: 3))),
        RouteFix.drifting);
    expect(fixAt(detector, start.add(const Duration(seconds: 13))),
        RouteFix.drifting);

    expect(fixAt(detector, start.add(const Duration(seconds: 14))),
        RouteFix.reroute);
  });

  test('backs off further each time a reroute fails', () {
    final detector = OffRouteDetector();
    expect(feed(detector, [80, 80, 80]), RouteFix.reroute);

    detector.recordRerouteFailed(start.add(const Duration(seconds: 2)));
    // 4s backoff: too early at 5s, allowed at 6s.
    expect(fixAt(detector, start.add(const Duration(seconds: 5))),
        RouteFix.drifting);
    expect(fixAt(detector, start.add(const Duration(seconds: 6))),
        RouteFix.reroute);

    detector.recordRerouteFailed(start.add(const Duration(seconds: 10)));
    // 8s backoff now, so 17s in is still too early.
    expect(fixAt(detector, start.add(const Duration(seconds: 17))),
        RouteFix.drifting);
    expect(fixAt(detector, start.add(const Duration(seconds: 18))),
        RouteFix.reroute);
  });

  test('caps the backoff so it keeps retrying', () {
    final detector = OffRouteDetector();
    var at = start;

    for (var i = 0; i < 10; i++) {
      at = at.add(const Duration(minutes: 1));
      detector.recordRerouteFailed(at);
    }

    feed(detector, [80, 80], from: at);
    expect(
      fixAt(detector, at.add(OffRouteDetector.maxRetryDelay)),
      RouteFix.reroute,
    );
  });

  test('a new route clears the backoff and the off-route run', () {
    final detector = OffRouteDetector();
    expect(feed(detector, [80, 80, 80]), RouteFix.reroute);
    detector.recordRerouteFailed(start.add(const Duration(seconds: 2)));

    detector.reset();

    expect(
      feed(detector, [80, 80], from: start.add(const Duration(seconds: 3))),
      RouteFix.drifting,
      reason: 'the run of off-route fixes starts again from zero',
    );
    expect(
      feed(detector, [80], from: start.add(const Duration(seconds: 5))),
      RouteFix.reroute,
      reason: 'and the failure backoff no longer holds it back',
    );
  });

  test('coming back onto the route stops the reroute', () {
    final detector = OffRouteDetector();

    expect(feed(detector, [80, 80]), RouteFix.drifting);
    expect(feed(detector, [4], from: start.add(const Duration(seconds: 2))),
        RouteFix.onRoute);
  });
}
