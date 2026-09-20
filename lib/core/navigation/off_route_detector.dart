import 'dart:math' as math;

/// What the latest GPS fix says about the driver following the route.
enum RouteFix {
  /// On the route, or close enough that GPS noise explains the difference.
  onRoute,

  /// Away from the route, but not (yet) worth asking for a new one: either
  /// too few fixes to be sure, or a request has just gone out.
  drifting,

  /// Away from the route long enough that a new one should be fetched.
  reroute,
}

/// Decides when the driver has left the route and a new one is needed.
///
/// A single fix is never enough: phones report positions tens of metres out
/// in towns and under trees, and one bad fix should not throw away the
/// route. Only a run of fixes clearly off the line counts as a wrong turn.
class OffRouteDetector {
  OffRouteDetector({
    this.thresholdMeters = 50,
    this.requiredFixes = 3,
    this.cooldown = const Duration(seconds: 12),
  });

  /// How far off the line a fix has to be to count as off the route.
  final double thresholdMeters;

  /// How many of those fixes in a row are needed before rerouting.
  final int requiredFixes;

  /// How long to wait after asking for a route before asking again, so one
  /// missed turn does not fire a request on every fix.
  final Duration cooldown;

  /// The first wait after a failed attempt; it doubles from there.
  static const Duration firstRetryDelay = Duration(seconds: 4);

  /// Failures stop stretching the wait beyond this, so a trip that starts
  /// out of signal still recovers quickly once the signal returns.
  static const Duration maxRetryDelay = Duration(seconds: 30);

  int _offRouteFixes = 0;
  int _failures = 0;
  DateTime? _lastAttemptAt;

  /// Whether the last fix was away from the route, regardless of whether
  /// that is enough to reroute yet.
  bool get isOffRoute => _offRouteFixes > 0;

  /// Reports how far the newest fix landed from the route.
  RouteFix update({required double offsetMeters, required DateTime now}) {
    if (offsetMeters <= thresholdMeters) {
      _offRouteFixes = 0;
      return RouteFix.onRoute;
    }

    _offRouteFixes++;
    if (_offRouteFixes < requiredFixes) return RouteFix.drifting;
    if (!_mayAttemptAt(now)) return RouteFix.drifting;

    _lastAttemptAt = now;
    return RouteFix.reroute;
  }

  /// Call when a reroute request came back empty, so the next attempt waits
  /// longer instead of hammering a dead connection.
  void recordRerouteFailed(DateTime now) {
    _failures++;
    _lastAttemptAt = now;
  }

  /// Call once a new route is being followed.
  void reset() {
    _offRouteFixes = 0;
    _failures = 0;
    _lastAttemptAt = null;
  }

  bool _mayAttemptAt(DateTime now) {
    final last = _lastAttemptAt;
    if (last == null) return true;

    return now.difference(last) >= _waitAfterLastAttempt;
  }

  Duration get _waitAfterLastAttempt {
    if (_failures == 0) return cooldown;

    final doubled = firstRetryDelay * math.pow(2, _failures - 1).toDouble();
    return doubled > maxRetryDelay ? maxRetryDelay : doubled;
  }
}
