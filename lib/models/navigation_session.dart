import 'dart:convert';

import 'package:latlong2/latlong.dart';

/// A trip in progress, saved so navigation can carry on if Android closes
/// the app while the driver is using another one.
class NavigationSession {
  const NavigationSession({
    required this.originName,
    required this.origin,
    required this.destinationName,
    required this.destination,
    required this.simulate,
    required this.simulationMultiplier,
    required this.metersAlong,
    required this.savedAt,
  });

  /// Older sessions are not resumed; the driver has most likely finished.
  static const Duration maxAge = Duration(hours: 3);

  final String originName;
  final LatLng origin;
  final String destinationName;
  final LatLng destination;
  final bool simulate;
  final int simulationMultiplier;

  /// How far along the route the driver had got.
  final double metersAlong;
  final DateTime savedAt;

  bool isFresh(DateTime now) => now.difference(savedAt) <= maxAge;

  NavigationSession withProgress(double meters, DateTime now) {
    return NavigationSession(
      originName: originName,
      origin: origin,
      destinationName: destinationName,
      destination: destination,
      simulate: simulate,
      simulationMultiplier: simulationMultiplier,
      metersAlong: meters,
      savedAt: now,
    );
  }

  String encode() {
    return jsonEncode({
      'originName': originName,
      'origin': [origin.latitude, origin.longitude],
      'destinationName': destinationName,
      'destination': [destination.latitude, destination.longitude],
      'simulate': simulate,
      'simulationMultiplier': simulationMultiplier,
      'metersAlong': metersAlong,
      'savedAt': savedAt.toIso8601String(),
    });
  }

  /// Reads a saved session, or null if [raw] is missing or damaged.
  static NavigationSession? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;

    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;

      final origin = _latLng(json['origin']);
      final destination = _latLng(json['destination']);
      final savedAt = DateTime.tryParse('${json['savedAt']}');
      final multiplier = json['simulationMultiplier'];
      final meters = json['metersAlong'];

      if (origin == null ||
          destination == null ||
          savedAt == null ||
          multiplier is! int ||
          meters is! num ||
          json['simulate'] is! bool) {
        return null;
      }

      return NavigationSession(
        originName: '${json['originName'] ?? ''}',
        origin: origin,
        destinationName: '${json['destinationName'] ?? ''}',
        destination: destination,
        simulate: json['simulate'] as bool,
        simulationMultiplier: multiplier,
        metersAlong: meters.toDouble(),
        savedAt: savedAt,
      );
    } on FormatException {
      return null;
    }
  }

  static LatLng? _latLng(Object? value) {
    if (value is! List || value.length != 2) return null;
    final latitude = value[0];
    final longitude = value[1];
    if (latitude is! num || longitude is! num) return null;
    if (latitude.abs() > 90 || longitude.abs() > 180) return null;
    return LatLng(latitude.toDouble(), longitude.toDouble());
  }
}
