import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';

class MapboxSearchResult {
  const MapboxSearchResult({
    required this.name,
    required this.location,
    this.placeFormatted = '',
    this.featureType = '',
    this.distanceMeters,
  });

  /// Street address, place or business name, e.g. "Σκουφά 10".
  final String name;

  /// Where to navigate to: the entrance or roadside point when Mapbox knows
  /// it, so routes end at the door rather than the middle of a building.
  final LatLng location;

  /// Town, postcode and country, e.g. "471 31 Άρτα, Ελλάδα".
  final String placeFormatted;

  /// Mapbox feature type: poi, address, street, place, locality…
  final String featureType;

  /// Distance from the user, when their location was known.
  final double? distanceMeters;

  static final RegExp _leadingPostcode = RegExp(r'^\d{3}\s?\d{2}\s+');

  /// The town without postcode or country, e.g. "Άρτα".
  String get town {
    final firstPart = placeFormatted.split(',').first.trim();
    return firstPart.replaceFirst(_leadingPostcode, '').trim();
  }

  /// Name plus town for the route fields, e.g. "Σκουφά 10, Άρτα".
  String get displayName {
    final place = town;
    if (place.isEmpty || name.contains(place)) return name;
    return '$name, $place';
  }
}

/// Place search and address lookup with the Mapbox Search Box API, which
/// covers businesses and landmarks as well as streets and addresses.
class MapboxService {
  MapboxService._();

  static const String _baseUrl = 'https://api.mapbox.com/search/searchbox/v1';
  static const Duration _timeout = Duration(seconds: 10);

  static Future<List<MapboxSearchResult>> searchPlaces(
    String query, {
    LatLng? userLocation,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.length < 2) return const [];

    final uri = Uri.parse('$_baseUrl/forward').replace(
      queryParameters: {
        'q': cleanQuery,
        'access_token': AppConfig.mapboxAccessToken,
        'country': 'gr',
        'language': 'el',
        'limit': '10',
        'types': 'poi,address,street,place,locality,neighborhood',
        if (userLocation != null)
          'proximity': '${userLocation.longitude},${userLocation.latitude}',
      },
    );

    final decoded = await _getJson(uri);
    return decoded == null ? const [] : parseFeatures(decoded);
  }

  /// The address at [point], named for display but keeping [point] itself
  /// as the location, since that is exactly where the user pointed.
  static Future<MapboxSearchResult?> reverseGeocode(LatLng point) async {
    final uri = Uri.parse('$_baseUrl/reverse').replace(
      queryParameters: {
        'longitude': '${point.longitude}',
        'latitude': '${point.latitude}',
        'access_token': AppConfig.mapboxAccessToken,
        'language': 'el',
        'limit': '1',
        'types': 'address,street,poi',
      },
    );

    final decoded = await _getJson(uri);
    if (decoded == null) return null;

    final results = parseFeatures(decoded);
    if (results.isEmpty) return null;

    final nearest = results.first;
    return MapboxSearchResult(
      name: nearest.name,
      location: point,
      placeFormatted: nearest.placeFormatted,
      featureType: nearest.featureType,
    );
  }

  /// Turns a Search Box response into results, skipping any entry without
  /// a name or coordinates.
  @visibleForTesting
  static List<MapboxSearchResult> parseFeatures(Object decoded) {
    if (decoded is! Map) return const [];
    final features = decoded['features'];
    if (features is! List) return const [];

    final results = <MapboxSearchResult>[];

    for (final feature in features) {
      if (feature is! Map) continue;
      final properties = feature['properties'];
      if (properties is! Map) continue;

      final name = '${properties['name'] ?? ''}'.trim();
      final location = _navigableLocation(properties['coordinates']) ??
          _geometryLocation(feature['geometry']);
      if (name.isEmpty || location == null) continue;

      final distance = properties['distance'];

      results.add(
        MapboxSearchResult(
          name: name,
          location: location,
          placeFormatted: '${properties['place_formatted'] ?? ''}'.trim(),
          featureType: '${properties['feature_type'] ?? ''}',
          distanceMeters: distance is num ? distance.toDouble() : null,
        ),
      );
    }

    return results;
  }

  static LatLng? _navigableLocation(Object? coordinates) {
    if (coordinates is! Map) return null;

    final routablePoints = coordinates['routable_points'];
    if (routablePoints is List && routablePoints.isNotEmpty) {
      final entrance = _latLng(routablePoints.first);
      if (entrance != null) return entrance;
    }

    return _latLng(coordinates);
  }

  static LatLng? _latLng(Object? value) {
    if (value is! Map) return null;
    final latitude = value['latitude'];
    final longitude = value['longitude'];
    if (latitude is! num || longitude is! num) return null;
    return LatLng(latitude.toDouble(), longitude.toDouble());
  }

  static LatLng? _geometryLocation(Object? geometry) {
    if (geometry is! Map) return null;
    final coordinates = geometry['coordinates'];
    if (coordinates is! List || coordinates.length < 2) return null;
    final longitude = coordinates[0];
    final latitude = coordinates[1];
    if (latitude is! num || longitude is! num) return null;
    return LatLng(latitude.toDouble(), longitude.toDouble());
  }

  static Future<Object?> _getJson(Uri uri) async {
    try {
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) {
        debugPrint('RSI place search failed: HTTP ${response.statusCode}');
        return null;
      }
      return jsonDecode(response.body);
    } on TimeoutException {
      debugPrint('RSI place search timed out.');
    } catch (error) {
      debugPrint('RSI place search error: $error');
    }
    return null;
  }
}
