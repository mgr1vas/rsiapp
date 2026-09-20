import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import 'accident_map_layer.dart';

/// Draws the active route as a blue line with a white edge. While driving,
/// the part already travelled is trimmed away so the line always starts
/// right at the car, without redrawing the whole route.
class RouteLineLayer {
  static const String sourceId = 'rsi-route';
  static const String casingLayerId = 'rsi-route-casing';
  static const String lineLayerId = 'rsi-route-line';

  static const int _lineColor = 0xFF1A73E8;
  static const int _casingColor = 0xFFFFFFFF;

  /// Trim changes smaller than this (0.05% of the route) are not visible.
  static const double _minTrimStep = 0.0005;

  List<ll.LatLng> _points = const [];
  double _travelledFraction = 0;
  bool _updatingTrim = false;

  /// Shows [points] as the route, untrimmed.
  Future<void> show(mapbox.MapboxMap map, List<ll.LatLng> points) async {
    _points = List.unmodifiable(points);
    _travelledFraction = 0;
    await restore(map);
  }

  /// Draws the current route again, e.g. after the map style reloads.
  Future<void> restore(mapbox.MapboxMap map) {
    return _oneAtATime(() => _restoreNow(map));
  }

  /// Runs map changes one after another. A style reload and the app
  /// resuming can both redraw the route at the same moment, and overlapping
  /// remove/add steps would leave it half drawn.
  Future<void> _oneAtATime(Future<void> Function() change) {
    final next = _pendingChange.then((_) => change());
    _pendingChange = next.catchError((Object _) {});
    return next;
  }

  Future<void> _pendingChange = Future<void>.value();

  Future<void> _restoreNow(mapbox.MapboxMap map) async {
    try {
      await _removeFrom(map);
      if (_points.length < 2) return;

      final style = map.style;

      await style.addSource(
        mapbox.GeoJsonSource(
          id: sourceId,
          data: jsonEncode(_toGeoJson(_points)),
          // Needed for trimming the line by how much has been driven.
          lineMetrics: true,
        ),
      );

      // Below the accident points so they stay visible and tappable.
      final accidentsShown =
          await style.styleLayerExists(AccidentMapLayer.clusterLayerId);

      final line = _lineLayer(
        id: lineLayerId,
        color: _lineColor,
        widths: const [11, 4, 14, 6.5, 17, 9],
      );

      if (accidentsShown) {
        await style.addLayerAt(
          line,
          mapbox.LayerPosition(below: AccidentMapLayer.clusterLayerId),
        );
      } else {
        await style.addLayer(line);
      }

      await style.addLayerAt(
        _lineLayer(
          id: casingLayerId,
          color: _casingColor,
          widths: const [11, 6.5, 14, 10, 17, 14],
        ),
        mapbox.LayerPosition(below: lineLayerId),
      );
    } catch (error) {
      debugPrint('RSI could not draw the route: $error');
    }
  }

  /// Draws the route again only if the map lost it, e.g. when Android
  /// rebuilt the map while the app was in the background.
  Future<void> restoreIfMissing(mapbox.MapboxMap map) {
    return _oneAtATime(() async {
      if (_points.length < 2) return;

      try {
        if (await map.style.styleSourceExists(sourceId)) return;
      } catch (error) {
        debugPrint('RSI could not check the route on the map: $error');
        return;
      }

      await _restoreNow(map);
    });
  }

  /// Hides the first [fraction] (0 to 1) of the route, the part driven.
  Future<void> setTravelledFraction(
    mapbox.MapboxMap map,
    double fraction, {
    bool force = false,
  }) async {
    final clamped = fraction.clamp(0.0, 1.0);
    final unchanged = (clamped - _travelledFraction).abs() < _minTrimStep;
    if (_points.length < 2 || _updatingTrim || (unchanged && !force)) return;

    _travelledFraction = clamped;
    _updatingTrim = true;

    try {
      for (final layerId in const [casingLayerId, lineLayerId]) {
        await map.style.setStyleLayerProperty(
          layerId,
          'line-trim-offset',
          [0.0, clamped],
        );
      }
    } catch (error) {
      debugPrint('RSI could not update the route progress: $error');
    } finally {
      _updatingTrim = false;
    }
  }

  /// Removes the route from the map.
  Future<void> clear(mapbox.MapboxMap map) {
    _points = const [];
    _travelledFraction = 0;

    return _oneAtATime(() async {
      try {
        await _removeFrom(map);
      } catch (error) {
        debugPrint('RSI could not remove the route: $error');
      }
    });
  }

  mapbox.LineLayer _lineLayer({
    required String id,
    required int color,
    required List<double> widths,
  }) {
    return mapbox.LineLayer(
      id: id,
      sourceId: sourceId,
      lineColor: color,
      // Pairs of zoom level and width: thinner zoomed out, wider close in.
      lineWidthExpression: [
        'interpolate',
        ['linear'],
        ['zoom'],
        ...widths,
      ],
      lineCap: mapbox.LineCap.ROUND,
      lineJoin: mapbox.LineJoin.ROUND,
      lineTrimOffset: [0.0, _travelledFraction],
    );
  }

  static Future<void> _removeFrom(mapbox.MapboxMap map) async {
    final style = map.style;

    for (final layerId in const [lineLayerId, casingLayerId]) {
      if (await style.styleLayerExists(layerId)) {
        await style.removeStyleLayer(layerId);
      }
    }

    if (await style.styleSourceExists(sourceId)) {
      await style.removeStyleSource(sourceId);
    }
  }

  static Map<String, Object> _toGeoJson(List<ll.LatLng> points) {
    return {
      'type': 'Feature',
      'properties': const <String, Object>{},
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          for (final point in points) [point.longitude, point.latitude],
        ],
      },
    };
  }
}
