import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Compass direction from [from] to [to], in degrees clockwise from north.
double bearingBetween(LatLng from, LatLng to) {
  final lat1 = from.latitude * math.pi / 180;
  final lat2 = to.latitude * math.pi / 180;
  final dLon = (to.longitude - from.longitude) * math.pi / 180;

  final y = math.sin(dLon) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// Turns [from] towards [to] by [factor] (0 to 1), the shorter way round,
/// so a heading of 350° eases to 10° through north instead of spinning back.
double lerpBearing(double from, double to, double factor) {
  final delta = ((to - from + 540) % 360) - 180;
  return (from + delta * factor.clamp(0.0, 1.0) + 360) % 360;
}
