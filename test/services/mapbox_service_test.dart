import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rsi/services/mapbox_service.dart';

void main() {
  // Shaped like real Search Box API responses.
  final response = {
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [20.99451589, 39.14798613],
        },
        'properties': {
          'name': 'Γενικό Νοσοκομείο Άρτας',
          'feature_type': 'poi',
          'place_formatted': '471 31 Άρτα, Ελλάδα',
          'coordinates': {
            'latitude': 39.14798613,
            'longitude': 20.99451589,
            'routable_points': [
              {'name': 'POI', 'latitude': 39.147838, 'longitude': 20.994677},
            ],
          },
          'distance': 1575,
        },
      },
      {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [22.41068, 39.63637],
        },
        'properties': {
          'name': 'Σκουφά 10',
          'feature_type': 'address',
          'place_formatted': '412 22 Λάρισα, Ελλάδα',
          'coordinates': {'latitude': 39.63637, 'longitude': 22.41068},
        },
      },
      {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [20.98, 39.15],
        },
        'properties': {'name': '', 'feature_type': 'street'},
      },
      {
        'type': 'Feature',
        'properties': {'name': 'No coordinates'},
      },
    ],
  };

  test('reads names, places and types, skipping incomplete entries', () {
    final results = MapboxService.parseFeatures(response);

    expect(results, hasLength(2));
    expect(results[0].name, 'Γενικό Νοσοκομείο Άρτας');
    expect(results[0].featureType, 'poi');
    expect(results[0].distanceMeters, 1575);
    expect(results[1].featureType, 'address');
    expect(results[1].distanceMeters, isNull);
  });

  test('navigates to the entrance point when there is one', () {
    final results = MapboxService.parseFeatures(response);

    expect(results[0].location, const LatLng(39.147838, 20.994677));
    expect(results[1].location, const LatLng(39.63637, 22.41068));
  });

  test('shows the town without postcode or country', () {
    final results = MapboxService.parseFeatures(response);

    expect(results[1].town, 'Λάρισα');
    expect(results[1].displayName, 'Σκουφά 10, Λάρισα');
    // The name already says which town.
    expect(results[0].displayName, 'Γενικό Νοσοκομείο Άρτας');
  });

  test('copes with unexpected responses', () {
    expect(MapboxService.parseFeatures('oops'), isEmpty);
    expect(MapboxService.parseFeatures({'features': 'none'}), isEmpty);
  });
}
