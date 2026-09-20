import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../config/demo_routes.dart';
import '../core/format/navigation_labels.dart';
import '../core/geo/bearing.dart';
import '../core/geo/route_progress.dart';
import '../core/navigation/follow_viewport.dart';
import '../core/navigation/route_guidance.dart';
import '../core/navigation/simulation_clock.dart';
import '../map/accident_map_layer.dart';
import '../map/road_risk_map_layer.dart';
import '../map/route_line_layer.dart';
import '../models/hazard_model.dart';
import '../models/navigation_session.dart';
import '../providers/accidents_provider.dart';
import '../providers/app_setup_provider.dart';
import '../providers/clock_provider.dart';
import '../providers/location_provider.dart';
import '../providers/map_filter_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/road_risk_provider.dart';
import '../services/app_window.dart';
import '../services/background_navigation_service.dart';
import '../services/hazard_db_service.dart';
import '../services/location_service.dart';
import '../services/mapbox_service.dart';
import '../services/navigation_alerts.dart';
import '../services/osrm_service.dart';
import '../widgets/accidents/accident_details_sheet.dart';
import '../widgets/compact_guidance_strip.dart';
import '../widgets/map_compass_button.dart';
import '../widgets/map_filter/map_filter_sheet.dart';
import '../widgets/navigation_bottom_bar.dart';
import '../widgets/navigation_puck.dart';
import '../widgets/place_suggestion_tile.dart';
import '../widgets/rentals/rentals_sheet.dart';
import '../widgets/road_risk/road_risk_details_sheet.dart';
import '../widgets/route_summary_sheet.dart';
import '../widgets/safety_alert_card.dart';
import '../widgets/turn_by_turn_panel.dart';

class LiveTrackingScreen extends ConsumerStatefulWidget {
  const LiveTrackingScreen({super.key});

  @override
  ConsumerState<LiveTrackingScreen> createState() =>
      _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends ConsumerState<LiveTrackingScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const Color _mapsBlue = Color(0xFF1A73E8);
  static const Color _textPrimary = Color(0xFF202124);
  static const Color _textSecondary = Color(0xFF5F6368);
  static const ll.Distance _distance = ll.Distance();

  static const double _followZoom = 17.2;

  /// A slightly wider view in the small picture-in-picture window.
  static const double _pictureInPictureZoom = 16;

  /// How often turn instructions, hazards and the saved trip are updated.
  /// A timer rather than screen frames, so it keeps running while another
  /// app is open.
  static const Duration _guidanceInterval = Duration(milliseconds: 200);
  static const Duration _sessionSaveInterval = Duration(seconds: 5);
  static const Duration _backgroundNotificationInterval = Duration(seconds: 1);

  /// GPS fixes further than this from the route are drawn where they are
  /// instead of on the route line.
  static const double _maxSnapMeters = 35;
  static const double _arrivalMeters = 18;

  /// Share of the remaining turn applied each frame, to smooth the heading.
  static const double _headingSmoothing = 0.18;

  static const String _yourLocation = 'Your location';

  // Must stay one instance: MapWidget re-applies its viewport whenever it
  // receives a different object, which would snap the camera back here on
  // every rebuild.
  static final mapbox.CameraViewportState _initialViewport =
      mapbox.CameraViewportState(
    center: mapbox.Point(
      coordinates: mapbox.Position(23.7275, 37.9838),
    ),
    zoom: 12.5,
  );

  mapbox.MapboxMap? _map;
  mapbox.CircleAnnotationManager? _hazardManager;
  mapbox.CircleAnnotationManager? _destinationManager;
  mapbox.CircleAnnotationManager? _vehicleManager;
  mapbox.CircleAnnotation? _vehicleAnnotation;
  final RouteLineLayer _routeLayer = RouteLineLayer();

  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  final FocusNode _originFocus = FocusNode();
  final FocusNode _destinationFocus = FocusNode();

  Timer? _searchDebouncer;
  Timer? _guidanceTimer;

  /// Moves the camera and car arrow on every screen frame while navigating.
  late final Ticker _frameTicker = createTicker(_onFrame);

  List<MapboxSearchResult> _suggestions = [];
  MapboxSearchResult? _selectedOrigin;
  MapboxSearchResult? _selectedDestination;

  ll.LatLng? _currentGpsPosition;
  double _lastHeading = 0;

  bool _plannerExpanded = false;
  bool _searchingOrigin = false;
  bool _isSearching = false;
  bool _isCalculatingRoute = false;
  bool _cameraFollowing = true;
  bool _is3d = true;
  bool _simulationMode = true;
  bool _arrivalPending = false;
  bool _hasCenteredOnUser = false;
  bool _resumeChecked = false;

  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  /// During navigation: true keeps the map north-up instead of following
  /// the driving direction. Toggled by tapping the compass.
  bool _navigationNorthUp = false;

  /// Live map bearing, for the compass needle without rebuilding the map.
  final ValueNotifier<double> _mapBearing = ValueNotifier<double>(0);

  /// Car arrow direction on screen, updated every frame without rebuilds.
  final ValueNotifier<double> _puckRotation = ValueNotifier<double>(0);

  late final AccidentMapLayer _accidentLayer = AccidentMapLayer(
    onAccidentTap: (accident) {
      if (mounted) showAccidentDetailsSheet(context, accident);
    },
  );

  late final RoadRiskMapLayer _roadRiskLayer = RoadRiskMapLayer(
    onSegmentTap: (assessment) {
      if (mounted) showRoadRiskDetailsSheet(context, assessment);
    },
  );

  // The active route, measured once when it is calculated.
  RouteProgress? _routeProgress;
  RouteGuidance? _guidance;
  ll.LatLng? _routeStart;

  // Driving progress.
  SimulationClock? _simulationClock;
  double _driverMeters = 0;
  ll.LatLng? _vehiclePosition;
  double _displayHeading = 0;

  // Live GPS: the car is eased from where it was drawn to each new fix over
  // the time between fixes, instead of jumping once a second.
  bool _liveOnRoute = true;
  double _liveFromMeters = 0;
  double _liveToMeters = 0;
  ll.LatLng? _liveFromPosition;
  ll.LatLng? _liveToPosition;
  DateTime? _liveFixAt;
  Duration _liveFixInterval = const Duration(seconds: 1);

  bool _cameraBusy = false;
  DateTime? _cameraEaseUntil;

  /// Space kept clear above and below the car, sized to the map on every
  /// layout so split screen and picture-in-picture place the car correctly.
  FollowViewport _followViewport = FollowViewport.forHeight(800);
  DateTime? _lastSessionSave;
  DateTime? _lastBackgroundNotification;

  final Set<String> _shownHazardIds = {};

  double _remainingDistanceKm = 0;
  double _remainingDurationMinutes = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppWindow.initialize();
    AppWindow.pictureInPicture.addListener(_onPictureInPictureChanged);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    HazardDbService.initializeDatabase();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppWindow.pictureInPicture.removeListener(_onPictureInPictureChanged);
    _frameTicker.dispose();
    _searchDebouncer?.cancel();
    _guidanceTimer?.cancel();
    _originController.dispose();
    _destinationController.dispose();
    _originFocus.dispose();
    _destinationFocus.dispose();
    _mapBearing.dispose();
    _puckRotation.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (!ref.read(navigationProvider).isNavigating) return;

    if (state == AppLifecycleState.resumed) {
      // Android may have rebuilt the map while the app was hidden.
      final map = _map;
      if (map != null) unawaited(_routeLayer.restoreIfMissing(map));
      _cameraEaseUntil = null;
      unawaited(NavigationAlerts.clearHazard());
    } else {
      _lastBackgroundNotification = null;
      _updateBackgroundNotification(DateTime.now());
    }
  }

  /// The small floating window can't be touched to pan the map, so while
  /// floating the camera always follows the car.
  void _onPictureInPictureChanged() {
    if (!mounted) return;

    final floating = AppWindow.pictureInPicture.value;
    final navigating = ref.read(navigationProvider).isNavigating;

    setState(() {
      if (floating && navigating) _cameraFollowing = true;
    });

    if (floating) {
      FocusManager.instance.primaryFocus?.unfocus();
      if (navigating) unawaited(_removeVehicleMarker());
    }
    _cameraEaseUntil = null;
  }

  Future<void> _onMapCreated(mapbox.MapboxMap map) async {
    _map = map;

    // Keep the Mapbox logo and attribution visible above the rentals sheet.
    final ornamentMarginBottom =
        RentalsSheet.peekHeight + MediaQuery.paddingOf(context).bottom + 8;

    await _map?.compass.updateSettings(
      mapbox.CompassSettings(enabled: false),
    );
    await _map?.scaleBar.updateSettings(
      mapbox.ScaleBarSettings(enabled: false),
    );
    await _map?.attribution.updateSettings(
      mapbox.AttributionSettings(
        marginBottom: ornamentMarginBottom,
        marginLeft: 8,
      ),
    );
    await _map?.logo.updateSettings(
      mapbox.LogoSettings(
        marginBottom: ornamentMarginBottom,
        marginLeft: 8,
      ),
    );
    await _map?.location.updateSettings(
      mapbox.LocationComponentSettings(
        enabled: false,
      ),
    );

    // Created in drawing order: hazards, then destination, then the car.
    _hazardManager =
        await _map?.annotations.createCircleAnnotationManager();
    _destinationManager =
        await _map?.annotations.createCircleAnnotationManager();
    _vehicleManager =
        await _map?.annotations.createCircleAnnotationManager();

    // Android can rebuild the map while the app is in the background; the
    // new map starts empty, so put the route's markers back. The old car
    // marker belonged to the previous map and is recreated on next update.
    _vehicleAnnotation = null;
    final activeRoute = ref.read(navigationProvider).activeRouteDetails;
    if (activeRoute != null) {
      await _drawHazards(activeRoute.dbHazards);
      await _drawDestination(_selectedDestination?.location);
    }

    map.addInteraction(
      mapbox.LongTapInteraction.onMap(_pickDestinationOnMap),
      interactionID: 'rsi-pick-destination',
    );

    final position = _currentGpsPosition;
    if (position != null) {
      _centerOnFirstFix(position);
    }
  }

  void _onSearchChanged(String query, {required bool origin}) {
    _searchDebouncer?.cancel();
    _searchingOrigin = origin;

    _searchDebouncer = Timer(const Duration(milliseconds: 280), () async {
      final clean = query.trim();
      if (clean.isEmpty || clean == _yourLocation) {
        if (!mounted) return;
        setState(() => _suggestions = []);
        return;
      }

      setState(() => _isSearching = true);
      final results = await MapboxService.searchPlaces(
        clean,
        userLocation: _currentGpsPosition,
      );
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _isSearching = false;
      });
    });
  }

  void _selectSuggestion(MapboxSearchResult result) {
    FocusScope.of(context).unfocus();

    setState(() {
      _suggestions = [];
      if (_searchingOrigin) {
        _selectedOrigin = result;
        _originController.text = result.displayName;
      } else {
        _selectedDestination = result;
        _destinationController.text = result.displayName;
      }
    });

    if (_selectedDestination != null) {
      _calculateRoute();
    }
  }

  void _swapOriginDestination() {
    final currentLocationResult = _currentGpsPosition == null
        ? null
        : MapboxSearchResult(
            name: _yourLocation,
            location: _currentGpsPosition!,
          );

    final effectiveOrigin = _selectedOrigin ?? currentLocationResult;
    final previousDestination = _selectedDestination;

    if (effectiveOrigin == null || previousDestination == null) return;

    setState(() {
      _selectedOrigin = previousDestination;
      _selectedDestination = effectiveOrigin;
      _originController.text = previousDestination.displayName;
      _destinationController.text = effectiveOrigin.displayName;
    });

    _calculateRoute();
  }

  /// Long press on the map: route to exactly that spot, named with the
  /// nearest address. More precise than search where house numbers are
  /// missing from the map data.
  Future<void> _pickDestinationOnMap(
    mapbox.MapContentGestureContext gesture,
  ) async {
    if (ref.read(navigationProvider).isNavigating) return;

    final coordinates = gesture.point.coordinates;
    final point = ll.LatLng(
      coordinates.lat.toDouble(),
      coordinates.lng.toDouble(),
    );

    HapticFeedback.selectionClick();
    unawaited(_drawDestination(point));

    final place = await MapboxService.reverseGeocode(point);
    if (!mounted) return;

    final destination = place ??
        MapboxSearchResult(
          name: 'Σημείο στον χάρτη (${point.latitude.toStringAsFixed(5)}, '
              '${point.longitude.toStringAsFixed(5)})',
          location: point,
        );

    setState(() {
      _selectedDestination = destination;
      _destinationController.text = destination.displayName;
      _suggestions = [];
    });

    final calculated = await _calculateRoute();
    if (!calculated && mounted) {
      setState(() {
        _plannerExpanded = true;
        _searchingOrigin = true;
      });
    }
  }

  Future<void> _startDemoRoute(DemoRoute demo) async {
    FocusScope.of(context).unfocus();

    setState(() {
      _selectedOrigin = MapboxSearchResult(
        name: demo.originName,
        location: demo.origin,
      );
      _selectedDestination = MapboxSearchResult(
        name: demo.destinationName,
        location: demo.destination,
      );
      _originController.text = demo.originName;
      _destinationController.text = demo.destinationName;
      _simulationMode = true;
      _suggestions = [];
    });

    await _calculateRoute();
  }

  /// Fetches and draws the route; returns whether one is ready to drive.
  Future<bool> _calculateRoute({bool showOverview = true}) async {
    final start = _selectedOrigin?.location ?? _currentGpsPosition;
    final end = _selectedDestination?.location;
    if (end == null) return false;

    if (start == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a starting point or turn on location.'),
        ),
      );
      return false;
    }

    setState(() {
      _isCalculatingRoute = true;
      _suggestions = [];
    });

    final details = await OsrmService.fetchRouteDetails(
      start: start,
      end: end,
    );

    if (!mounted) return false;
    setState(() => _isCalculatingRoute = false);

    if (details == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not calculate this route.')),
      );
      return false;
    }

    ref.read(navigationProvider.notifier).setRoute(details);

    final progress = RouteProgress(details.polyline);
    _routeStart = start;
    _routeProgress = progress;
    _guidance = RouteGuidance.build(
      route: progress,
      steps: details.steps,
      hazards: details.dbHazards,
    );

    setState(() {
      _plannerExpanded = false;
      _remainingDistanceKm = details.distanceKm;
      _remainingDurationMinutes = details.durationMinutes;
    });

    final map = _map;
    if (map != null) await _routeLayer.show(map, details.polyline);
    await _drawHazards(details.dbHazards);
    await _drawDestination(end);
    if (showOverview) await _showRouteOverview(details.polyline);

    return true;
  }

  Future<void> _showRouteOverview(List<ll.LatLng> route) async {
    final map = _map;
    if (map == null || route.length < 2) return;

    final points = route
        .map(
          (p) => mapbox.Point(
            coordinates: mapbox.Position(p.longitude, p.latitude),
          ),
        )
        .toList();

    final camera = await map.cameraForCoordinatesPadding(
      points,
      mapbox.CameraOptions(bearing: 0, pitch: 0),
      mapbox.MbxEdgeInsets(
        top: 150,
        left: 44,
        bottom: 310,
        right: 44,
      ),
      16,
      null,
    );

    await map.easeTo(
      camera,
      mapbox.MapAnimationOptions(duration: 650),
    );
  }

  Future<void> _drawHazards(List<HazardFeature> hazards) async {
    final manager = _hazardManager;
    if (manager == null) return;

    await manager.deleteAll();

    for (final hazard in hazards) {
      final point = mapbox.Point(
        coordinates: mapbox.Position(
          hazard.location.longitude,
          hazard.location.latitude,
        ),
      );

      await manager.create(
        mapbox.CircleAnnotationOptions(
          geometry: point,
          circleRadius: 17,
          circleColor: const Color(0xFFF29900).toARGB32(),
          circleOpacity: 0.18,
          circleStrokeColor: const Color(0xFFF29900).toARGB32(),
          circleStrokeWidth: 1.5,
        ),
      );

      await manager.create(
        mapbox.CircleAnnotationOptions(
          geometry: point,
          circleRadius: 7,
          circleColor: const Color(0xFFF29900).toARGB32(),
          circleOpacity: 1,
          circleStrokeColor: Colors.white.toARGB32(),
          circleStrokeWidth: 2.5,
        ),
      );
    }
  }

  Future<void> _drawDestination(ll.LatLng? destination) async {
    final manager = _destinationManager;
    if (manager == null) return;

    await manager.deleteAll();
    if (destination == null) return;

    await manager.create(
      mapbox.CircleAnnotationOptions(
        geometry: mapbox.Point(
          coordinates: mapbox.Position(
            destination.longitude,
            destination.latitude,
          ),
        ),
        circleRadius: 8,
        circleColor: const Color(0xFFEA4335).toARGB32(),
        circleStrokeColor: Colors.white.toARGB32(),
        circleStrokeWidth: 3,
      ),
    );
  }

  /// The map's own car marker, used whenever the camera is not following
  /// the car (while following, the Flutter arrow is shown instead).
  Future<void> _updateVehicleMarker(ll.LatLng position) async {
    final manager = _vehicleManager;
    if (manager == null || _showsNavigationPuck) return;

    if (_vehicleAnnotation == null) {
      _vehicleAnnotation = await manager.create(
        mapbox.CircleAnnotationOptions(
          geometry: mapbox.Point(
            coordinates: mapbox.Position(
              position.longitude,
              position.latitude,
            ),
          ),
          circleRadius: 7,
          circleColor: _mapsBlue.toARGB32(),
          circleStrokeColor: Colors.white.toARGB32(),
          circleStrokeWidth: 2.5,
          circleOpacity: 1,
        ),
      );
      // Following may have resumed while the marker was being created.
      if (_showsNavigationPuck) await _removeVehicleMarker();
      return;
    }

    _vehicleAnnotation!.geometry = mapbox.Point(
      coordinates: mapbox.Position(position.longitude, position.latitude),
    );
    await manager.update(_vehicleAnnotation!);
  }

  Future<void> _removeVehicleMarker() async {
    _vehicleAnnotation = null;
    await _vehicleManager?.deleteAll();
  }

  bool get _showsNavigationPuck =>
      _cameraFollowing && ref.read(navigationProvider).isNavigating;

  /// Compass tap: turns the map back to north. While navigating it switches
  /// between north-up and following the driving direction.
  void _onCompassTap() {
    if (ref.read(navigationProvider).isNavigating) {
      setState(() => _navigationNorthUp = !_navigationNorthUp);

      if (!_navigationNorthUp) {
        _recenter();
        return;
      }
    }

    _map?.easeTo(
      mapbox.CameraOptions(bearing: 0),
      mapbox.MapAnimationOptions(duration: 300),
    );
  }

  mapbox.CameraOptions _followCamera(ll.LatLng position, double heading) {
    final northUp =
        _navigationNorthUp && ref.read(navigationProvider).isNavigating;

    return mapbox.CameraOptions(
      center: mapbox.Point(
        coordinates: mapbox.Position(position.longitude, position.latitude),
      ),
      zoom: AppWindow.pictureInPicture.value
          ? _pictureInPictureZoom
          : _followZoom,
      pitch: _is3d ? 58 : 0,
      bearing: northUp ? 0 : heading,
      padding: mapbox.MbxEdgeInsets(
        top: _followViewport.top,
        left: 0,
        bottom: _followViewport.bottom,
        right: 0,
      ),
    );
  }

  /// Animated move onto the car, e.g. when starting or re-centring.
  Future<void> _followDriver(ll.LatLng position, double heading) async {
    if (!_cameraFollowing || _map == null) return;

    // Let the animation finish before per-frame camera updates take over.
    _cameraEaseUntil = DateTime.now().add(const Duration(milliseconds: 350));

    await _map!.easeTo(
      _followCamera(position, heading),
      mapbox.MapAnimationOptions(duration: 300),
    );
  }

  Future<void> _startNavigation({double resumeMeters = 0}) async {
    final nav = ref.read(navigationProvider);
    final route = nav.activeRouteDetails;
    final progress = _routeProgress;
    if (route == null || progress == null || route.polyline.isEmpty) return;

    _guidanceTimer?.cancel();
    _shownHazardIds.clear();
    _arrivalPending = false;
    _lastSessionSave = null;

    final now = DateTime.now();
    final gps = _currentGpsPosition;
    final ll.LatLng start;

    if (_simulationMode) {
      final startMeters = resumeMeters.clamp(0.0, progress.totalMeters);
      _simulationClock = SimulationClock.start(
        fromMeters: startMeters,
        multiplier: nav.simulationMultiplier,
        now: now,
      );
      _driverMeters = startMeters;
      start = progress.positionAt(startMeters);
    } else {
      final snap = gps == null ? null : progress.snap(gps);
      _simulationClock = null;
      _driverMeters = snap?.metersAlong ?? 0;
      _liveOnRoute = snap == null || snap.offsetMeters <= _maxSnapMeters;
      start = gps ?? progress.positionAt(0);
      _liveFromMeters = _driverMeters;
      _liveToMeters = _driverMeters;
      _liveFromPosition = start;
      _liveToPosition = start;
      _liveFixAt = now;
    }

    _vehiclePosition = start;
    _displayHeading = progress.headingAt(_driverMeters);

    ref.read(navigationProvider.notifier).startNavigation(
          simulate: _simulationMode,
          startPos: start,
        );

    setState(() {
      _cameraFollowing = true;
      _plannerExpanded = false;
      _remainingDistanceKm = route.distanceKm;
      _remainingDurationMinutes = route.durationMinutes;
    });

    await _removeVehicleMarker();

    final map = _map;
    if (map != null) {
      unawaited(
        _routeLayer.setTravelledFraction(
          map,
          progress.fractionAt(_driverMeters),
          force: true,
        ),
      );
    }

    unawaited(_followDriver(start, _displayHeading));

    _guidanceTimer = Timer.periodic(
      _guidanceInterval,
      (_) => _onGuidanceTick(),
    );
    if (!_frameTicker.isActive) _frameTicker.start();

    _saveSessionProgress(now, force: true);
    unawaited(_startBackgroundSupport());
    // Leaving the app during the trip floats it in a small window.
    unawaited(AppWindow.setAutoPictureInPicture(true));
  }

  /// Notification permission for hazard alerts, and the foreground service
  /// that keeps navigation going while another app is open.
  Future<void> _startBackgroundSupport() async {
    await NavigationAlerts.requestPermission();
    final started = await BackgroundNavigationService.start();

    if (started || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Allow location access to keep navigating and get hazard alerts '
          'while using other apps.',
        ),
      ),
    );
  }

  /// Where the car is drawn at [now]: exact for simulation, eased between
  /// fixes for live GPS.
  double _displayMetersAt(DateTime now) {
    final clock = _simulationClock;
    if (clock != null) return clock.metersAt(now);

    return _liveFromMeters +
        (_liveToMeters - _liveFromMeters) * _liveEaseAt(now);
  }

  double _liveEaseAt(DateTime now) {
    final fixAt = _liveFixAt;
    if (fixAt == null) return 1;

    final t = now.difference(fixAt).inMicroseconds /
        _liveFixInterval.inMicroseconds;
    return t.clamp(0.0, 1.0);
  }

  ll.LatLng? _liveDrawnPosition(DateTime now) {
    final from = _liveFromPosition;
    final to = _liveToPosition;
    if (from == null || to == null) return to;

    final t = _liveEaseAt(now);
    return ll.LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
  }

  /// Runs every screen frame while navigating: moves the car and camera
  /// smoothly and trims the route line behind the car.
  void _onFrame(Duration _) {
    final map = _map;
    final route = _routeProgress;
    if (map == null ||
        route == null ||
        !ref.read(navigationProvider).isNavigating) {
      return;
    }

    final now = DateTime.now();
    final ll.LatLng position;
    final double targetHeading;

    if (_simulationClock != null || _liveOnRoute) {
      final meters = math.min(_displayMetersAt(now), route.totalMeters);
      position = route.positionAt(meters);
      targetHeading = route.headingAt(meters);
      unawaited(_routeLayer.setTravelledFraction(map, route.fractionAt(meters)));
    } else {
      final drawn = _liveDrawnPosition(now);
      if (drawn == null) return;
      position = drawn;
      targetHeading = _lastHeading;
    }

    _displayHeading = lerpBearing(
      _displayHeading,
      targetHeading,
      _headingSmoothing,
    );
    // With the map turned to the driving direction the arrow points up.
    _puckRotation.value = _navigationNorthUp ? _displayHeading : 0;

    if (!_cameraFollowing) return;

    final easeUntil = _cameraEaseUntil;
    if (easeUntil != null && now.isBefore(easeUntil)) return;

    unawaited(_moveCamera(map, position));
  }

  Future<void> _moveCamera(mapbox.MapboxMap map, ll.LatLng position) async {
    // Skip frames while the previous move is still being applied, rather
    // than queueing up camera changes.
    if (_cameraBusy) return;
    _cameraBusy = true;

    try {
      await map.setCamera(_followCamera(position, _displayHeading));
    } catch (error) {
      debugPrint('RSI could not move the camera: $error');
    } finally {
      _cameraBusy = false;
    }
  }

  void _onLiveFix(ll.LatLng position) {
    final route = _routeProgress;
    if (route == null) return;

    final now = DateTime.now();
    final previousFixAt = _liveFixAt;
    final snap = route.snap(position, nearMeters: _liveToMeters);

    // Ease on from wherever the car is currently drawn.
    _liveFromMeters = _displayMetersAt(now);
    _liveFromPosition = _liveDrawnPosition(now) ?? position;
    _liveToMeters = snap.metersAlong;
    _liveToPosition = position;
    _liveOnRoute = snap.offsetMeters <= _maxSnapMeters;

    if (previousFixAt != null) {
      final gap = now.difference(previousFixAt);
      _liveFixInterval = gap < const Duration(milliseconds: 300)
          ? const Duration(milliseconds: 300)
          : gap > const Duration(seconds: 2)
              ? const Duration(seconds: 2)
              : gap;
    }
    _liveFixAt = now;
  }

  /// Runs a few times a second, also in the background: progress, turn
  /// instructions, hazard alerts, notification text and the saved trip.
  void _onGuidanceTick() {
    final nav = ref.read(navigationProvider);
    final route = _routeProgress;
    final guidance = _guidance;
    if (!mounted ||
        !nav.isNavigating ||
        route == null ||
        guidance == null ||
        _arrivalPending) {
      return;
    }

    final now = DateTime.now();
    final meters = math.min(
      _simulationClock?.metersAt(now) ?? _liveToMeters,
      route.totalMeters,
    );
    _driverMeters = meters;
    _vehiclePosition = _simulationClock != null || _liveOnRoute
        ? route.positionAt(meters)
        : (_liveToPosition ?? route.positionAt(meters));

    final remainingMeters = route.totalMeters - meters;
    _updateRemaining(nav, remainingMeters);

    if (remainingMeters <= _arrivalMeters) {
      _completeArrival();
      return;
    }

    _updateManeuver(guidance, meters);
    _updateHazardAlert(guidance, meters);

    final vehicle = _vehiclePosition;
    if (!_cameraFollowing &&
        vehicle != null &&
        _lifecycle == AppLifecycleState.resumed) {
      unawaited(_updateVehicleMarker(vehicle));
    }

    _updateBackgroundNotification(now);
    _saveSessionProgress(now);
  }

  void _updateRemaining(NavigationState nav, double remainingMeters) {
    final route = nav.activeRouteDetails;
    final progress = _routeProgress;
    if (route == null || progress == null) return;

    final share =
        (remainingMeters / math.max(1.0, progress.totalMeters)).clamp(0.0, 1.0);
    final km = remainingMeters / 1000;
    final minutes = route.durationMinutes * share;

    // Rebuild only when the numbers on screen change.
    final changed = (km * 10).round() != (_remainingDistanceKm * 10).round() ||
        minutes.round() != _remainingDurationMinutes.round();

    if (!changed) {
      _remainingDistanceKm = km;
      _remainingDurationMinutes = minutes;
      return;
    }

    setState(() {
      _remainingDistanceKm = km;
      _remainingDurationMinutes = minutes;
    });
  }

  void _updateManeuver(RouteGuidance guidance, double meters) {
    final next = guidance.nextManeuver(meters);
    if (next == null) return;

    // Rounded to what the panel shows, so it only updates when that changes.
    final distance = next.distanceMeters >= 1000
        ? (next.distanceMeters / 100).round() * 100.0
        : (next.distanceMeters / 10).round() * 10.0;

    final nav = ref.read(navigationProvider);
    if (nav.currentTurnInstruction == next.step.instruction &&
        nav.distanceToNextTurnMeters == distance) {
      return;
    }

    ref.read(navigationProvider.notifier).updateTurnInstruction(
          next.step.instruction,
          distance,
        );
  }

  void _updateHazardAlert(RouteGuidance guidance, double meters) {
    final nav = ref.read(navigationProvider);
    final notifier = ref.read(navigationProvider.notifier);
    final active = nav.activeApproachingHazard;

    if (active != null) {
      final ahead = guidance.distanceToHazard(active, meters);

      // The alert stays up until the driver is past the hazard.
      if (ahead == null || ahead < -RouteGuidance.hazardPassedMeters) {
        notifier.updateApproachingHazard(null);
        unawaited(NavigationAlerts.clearHazard());
        return;
      }

      final shown = math.max(0.0, (ahead / 10).round() * 10.0);
      if (shown != nav.activeHazardDistanceMeters) {
        notifier.updateApproachingHazard(active, distanceAheadMeters: shown);
      }
      return;
    }

    final upcoming = guidance.hazardToAnnounce(meters, _shownHazardIds);
    if (upcoming == null) return;

    _shownHazardIds.add(upcoming.hazard.stableKey);
    notifier.updateApproachingHazard(
      upcoming.hazard,
      distanceAheadMeters: upcoming.distanceMeters,
    );
    HapticFeedback.heavyImpact();

    // On screen the alert card shows it; elsewhere a heads-up notification.
    if (_lifecycle != AppLifecycleState.resumed) {
      unawaited(
        NavigationAlerts.showHazard(upcoming.hazard, upcoming.distanceMeters),
      );
    }
  }

  /// Shows the next instruction in the ongoing notification while the app
  /// is in the background.
  void _updateBackgroundNotification(DateTime now) {
    if (_lifecycle == AppLifecycleState.resumed) return;

    final last = _lastBackgroundNotification;
    if (last != null &&
        now.difference(last) < _backgroundNotificationInterval) {
      return;
    }
    _lastBackgroundNotification = now;

    final nav = ref.read(navigationProvider);
    final hazard = nav.activeApproachingHazard;

    BackgroundNavigationService.updateNotification(
      title: '${formatDistance(nav.distanceToNextTurnMeters)} · '
          '${nav.currentTurnInstruction}',
      content: hazard != null
          ? 'Προσοχή: ${hazard.hazardType}'
          : 'Άφιξη ${formatArrivalTime(_remainingDurationMinutes)} · '
              '${_remainingDistanceKm.toStringAsFixed(1)} km',
    );
  }

  void _saveSessionProgress(DateTime now, {bool force = false}) {
    final last = _lastSessionSave;
    if (!force && last != null && now.difference(last) < _sessionSaveInterval) {
      return;
    }

    final destination = _selectedDestination;
    final start = _routeStart;
    if (destination == null || start == null) return;

    _lastSessionSave = now;

    final session = NavigationSession(
      originName: _selectedOrigin?.displayName ?? _yourLocation,
      origin: start,
      destinationName: destination.displayName,
      destination: destination.location,
      simulate: _simulationClock != null,
      simulationMultiplier: ref.read(navigationProvider).simulationMultiplier,
      metersAlong: _driverMeters,
      savedAt: now,
    );

    unawaited(_writeSession(session));
  }

  Future<void> _writeSession(NavigationSession? session) async {
    try {
      final preferences = ref.read(appPreferencesProvider);
      if (session == null) {
        await preferences.clearNavigationSession();
      } else {
        await preferences.saveNavigationSession(session);
      }
    } catch (error) {
      debugPrint('RSI could not save the navigation session: $error');
    }
  }

  /// Carries on a trip that was cut off, e.g. when Android closed the app
  /// while another one was in use. Runs once, after the map is ready.
  Future<void> _resumeSavedNavigation() async {
    if (_resumeChecked) return;
    _resumeChecked = true;

    final session = ref.read(appPreferencesProvider).navigationSession;

    if (session == null || !session.isFresh(DateTime.now())) {
      if (session != null) await _writeSession(null);
      await BackgroundNavigationService.stopIfRunning();
      return;
    }

    if (!mounted || ref.read(navigationProvider).isNavigating) return;

    setState(() {
      _selectedOrigin = MapboxSearchResult(
        name: session.originName,
        location: session.origin,
      );
      _selectedDestination = MapboxSearchResult(
        name: session.destinationName,
        location: session.destination,
      );
      _originController.text = session.originName;
      _destinationController.text = session.destinationName;
      _simulationMode = session.simulate;
    });
    ref
        .read(navigationProvider.notifier)
        .updateSimulationMultiplier(session.simulationMultiplier);

    final calculated = await _calculateRoute(showOverview: false);
    if (!calculated || !mounted) return;

    await _startNavigation(
      resumeMeters: session.simulate ? session.metersAlong : 0,
    );
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Συνέχεια πλοήγησης προς ${session.destinationName}'),
      ),
    );
  }

  void _completeArrival() {
    if (_arrivalPending) return;
    _arrivalPending = true;
    _guidanceTimer?.cancel();
    unawaited(_writeSession(null));

    ref.read(navigationProvider.notifier).updateTurnInstruction(
          'Φτάσατε στον προορισμό σας',
          0,
        );

    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _arrivalPending) _stopNavigation();
    });
  }

  void _stopNavigation() {
    _guidanceTimer?.cancel();
    _frameTicker.stop();
    _shownHazardIds.clear();
    _arrivalPending = false;
    _simulationClock = null;
    _cameraEaseUntil = null;

    unawaited(_writeSession(null));
    unawaited(NavigationAlerts.clearHazard());
    BackgroundNavigationService.stop();
    unawaited(AppWindow.setAutoPictureInPicture(false));

    ref.read(navigationProvider.notifier).stopNavigation();

    setState(() {
      _cameraFollowing = true;
    });

    final map = _map;
    if (map != null) {
      unawaited(_routeLayer.setTravelledFraction(map, 0, force: true));
    }

    final route = ref.read(navigationProvider).activeRouteDetails;
    if (route != null) {
      _showRouteOverview(route.polyline);
    }

    final gps = _currentGpsPosition;
    if (gps != null) unawaited(_updateVehicleMarker(gps));
  }

  void _toggleNavigationMode() {
    setState(() => _simulationMode = !_simulationMode);
  }

  void _recenter() {
    final nav = ref.read(navigationProvider);
    final position = nav.isNavigating
        ? (_vehiclePosition ?? nav.activeVehiclePosition)
        : _currentGpsPosition;

    if (position == null) {
      if (!ref.read(appSetupProvider).useDeviceLocation) {
        _enableDeviceLocation();
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Finding your location. Make sure location is turned on.',
          ),
        ),
      );
      return;
    }

    setState(() => _cameraFollowing = true);
    if (nav.isNavigating) unawaited(_removeVehicleMarker());

    // Follow the driving direction while navigating (unless north-up is
    // chosen); when browsing keep the map's current rotation.
    _followDriver(
      position,
      nav.isNavigating ? _displayHeading : _mapBearing.value,
    );
  }

  /// Asks for location access when the user skipped it during onboarding
  /// and later taps the location button.
  Future<void> _enableDeviceLocation() async {
    final granted = await LocationService.checkAndRequestPermissions();

    if (!mounted) return;

    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location is off. Allow location access for Road Safety Insights '
            'in your phone settings.',
          ),
        ),
      );
      return;
    }

    await ref.read(appSetupProvider.notifier).setUseDeviceLocation(true);
  }

  /// Road lines are thin, so taps this close to a line still select it.
  static const double _roadTapRadiusDp = 20;

  /// Converts a tap radius in logical pixels to the map's screen units.
  /// Mapbox on Android measures in physical pixels; iOS uses points.
  double _mapTapRadius(double logicalPixels) {
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    return isAndroid
        ? logicalPixels * MediaQuery.devicePixelRatioOf(context)
        : logicalPixels;
  }

  /// Shows road risk levels and recorded accidents once the map style has
  /// loaded. Road lines go first so accident points draw on top of them.
  Future<void> _addSafetyLayers() async {
    final map = _map;
    if (map == null) return;

    try {
      final assessments = await ref.read(roadRiskProvider.future);
      if (!mounted) return;
      await _roadRiskLayer.addTo(
        map,
        assessments,
        tapRadius: _mapTapRadius(_roadTapRadiusDp),
      );
    } catch (error) {
      debugPrint('RSI could not show road risk levels: $error');
    }

    try {
      final catalog = await ref.read(accidentCatalogProvider.future);
      if (!mounted) return;
      await _accidentLayer.addTo(map, catalog);
    } catch (error) {
      debugPrint('RSI could not show accident points: $error');
    }

    await _applyMapFilter();

    // A style reload removes the route too; put it back under the accidents.
    await _routeLayer.restore(map);

    if (mounted && ref.read(appSetupProvider).onboardingCompleted) {
      await _resumeSavedNavigation();
    }
  }

  /// Shows only the accidents and roads that match the map filters.
  Future<void> _applyMapFilter() async {
    final map = _map;
    if (map == null) return;

    final filter = ref.read(mapFilterProvider);
    final now = ref.read(clockProvider)();

    try {
      final catalog = await ref.read(accidentCatalogProvider.future);
      final assessments = await ref.read(roadRiskProvider.future);
      if (!mounted) return;

      await _accidentLayer.update(
        map,
        visible: filter.showAccidents,
        accidents: catalog.accidents.where(
          (accident) => filter.includesAccident(accident, now),
        ),
      );
      await _roadRiskLayer.update(
        map,
        visible: filter.showRoadRisk,
        assessments: assessments.where(filter.includesRoad),
      );
    } catch (error) {
      debugPrint('RSI could not apply map filters: $error');
    }
  }

  /// Moves the map from its default view to the user once, on the first fix.
  void _centerOnFirstFix(ll.LatLng position) {
    final map = _map;

    if (_hasCenteredOnUser || map == null) return;
    if (ref.read(navigationProvider).activeRouteDetails != null) return;

    _hasCenteredOnUser = true;

    map.easeTo(
      mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(position.longitude, position.latitude),
        ),
        zoom: 15,
        bearing: 0,
        pitch: 0,
      ),
      mapbox.MapAnimationOptions(duration: 600),
    );
  }

  IconData _maneuverIcon(String instruction) {
    final text = instruction.toLowerCase();
    if (text.contains('left') || text.contains('αριστερ')) {
      return Icons.turn_left_rounded;
    }
    if (text.contains('right') || text.contains('δεξ')) {
      return Icons.turn_right_rounded;
    }
    if (text.contains('roundabout') || text.contains('κυκλ')) {
      return Icons.roundabout_right_rounded;
    }
    if (text.contains('arriv') || text.contains('φτά')) {
      return Icons.flag_rounded;
    }
    if (text.contains('u-turn') || text.contains('αναστροφ')) {
      return Icons.u_turn_left_rounded;
    }
    return Icons.straight_rounded;
  }

  Widget _mapButton({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
    String? label,
  }) {
    return Material(
      color: active ? _mapsBlue : Colors.white,
      elevation: 4,
      shadowColor: const Color(0x33000000),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: label == null ? 12 : 14,
            vertical: 11,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 21,
                color: active ? Colors.white : _textSecondary,
              ),
              if (label != null) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: active ? Colors.white : _textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _collapsedSearchBar() {
    final hasRoute = ref.watch(navigationProvider).activeRouteDetails != null;
    final title = _selectedDestination?.displayName;
    final activeFilters = ref.watch(
      mapFilterProvider.select((filter) => filter.activeCount),
    );

    return Material(
      color: Colors.white,
      elevation: 7,
      shadowColor: const Color(0x26000000),
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: () {
          setState(() {
            _plannerExpanded = true;
            _searchingOrigin = false;
          });
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) _destinationFocus.requestFocus();
          });
        },
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Menu',
                // The State's context sits above this screen's Scaffold, so
                // it reaches the HomeShell scaffold that owns the drawer.
                onPressed: () => Scaffold.maybeOf(context)?.openDrawer(),
                icon: const Icon(Icons.menu_rounded),
                color: _textPrimary,
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Text(
                  hasRoute && title != null ? title : 'Where to?',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: title == null ? _textSecondary : _textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Material(
                color: const Color(0xFFE8F0FE),
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Map filters',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => showMapFilterSheet(context),
                  color: _mapsBlue,
                  icon: Badge(
                    isLabelVisible: activeFilters > 0,
                    label: Text('$activeFilters'),
                    child: const Icon(Icons.tune_rounded, size: 20),
                  ),
                ),
              ),
              const SizedBox(width: 9),
            ],
          ),
        ),
      ),
    );
  }

  Widget _plannerCard() {
    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: const Color(0x26000000),
      borderRadius: BorderRadius.circular(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 10, 10),
            child: Row(
              children: [
                IconButton(
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    setState(() {
                      _plannerExpanded = false;
                      _suggestions = [];
                    });
                  },
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: _textPrimary,
                ),
                const SizedBox(width: 2),
                Column(
                  children: [
                    const Icon(Icons.my_location_rounded, color: _mapsBlue, size: 17),
                    Container(
                      width: 2,
                      height: 25,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: const Color(0xFFDADCE0),
                    ),
                    const Icon(Icons.location_on_rounded, color: Color(0xFFEA4335), size: 20),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    children: [
                      _routeTextField(
                        controller: _originController,
                        focusNode: _originFocus,
                        hint: _yourLocation,
                        origin: true,
                      ),
                      const Divider(height: 1, color: Color(0xFFE8EAED)),
                      _routeTextField(
                        controller: _destinationController,
                        focusNode: _destinationFocus,
                        hint: 'Choose destination',
                        origin: false,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _swapOriginDestination,
                  icon: const Icon(Icons.swap_vert_rounded),
                  color: _textSecondary,
                ),
              ],
            ),
          ),
          if (_isSearching || _isCalculatingRoute)
            const LinearProgressIndicator(
              minHeight: 2,
              color: _mapsBlue,
              backgroundColor: Color(0xFFE8EAED),
            ),
          if (_suggestions.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: _suggestions.length,
                separatorBuilder: (_, _) => const Divider(
                  height: 1,
                  indent: 58,
                  color: Color(0xFFF1F3F4),
                ),
                itemBuilder: (context, index) {
                  final suggestion = _suggestions[index];
                  return PlaceSuggestionTile(
                    result: suggestion,
                    onTap: () => _selectSuggestion(suggestion),
                  );
                },
              ),
            )
          else if (!_isSearching)
            _plannerHints(),
        ],
      ),
    );
  }

  /// Tips under the route fields: long press for an exact spot, and the
  /// demo trips for testing alerts.
  Widget _plannerHints() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.touch_app_outlined, size: 16, color: _textSecondary),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Πατήστε παρατεταμένα στον χάρτη για ακριβές σημείο.',
                  style: TextStyle(color: _textSecondary, fontSize: 12.5),
                ),
              ),
            ],
          ),
          if (DemoRoutes.enabled) ...[
            const SizedBox(height: 10),
            const Text(
              'Δοκιμή ειδοποιήσεων (προσομοίωση)',
              style: TextStyle(
                color: _textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final demo in DemoRoutes.all)
                  ActionChip(
                    avatar: const Icon(
                      Icons.play_circle_outline_rounded,
                      size: 18,
                      color: _mapsBlue,
                    ),
                    label: Text(demo.label),
                    onPressed: () => _startDemoRoute(demo),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _routeTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required bool origin,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      maxLines: 1,
      style: const TextStyle(
        color: _textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF80868B)),
        border: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
      onTap: () => setState(() => _searchingOrigin = origin),
      onChanged: (value) => _onSearchChanged(value, origin: origin),
    );
  }

  void _onLocation(AsyncValue<ll.LatLng> next) {
    if (next.hasError) {
      debugPrint('RSI location stream error: ${next.error}');
    }

    next.whenData((position) {
      final previousPosition = _currentGpsPosition;
      if (previousPosition != null) {
        final moved = _distance.as(
          ll.LengthUnit.Meter,
          previousPosition,
          position,
        );
        if (moved > 1.5) {
          _lastHeading = bearingBetween(previousPosition, position);
        }
      }

      _currentGpsPosition = position;

      if (_originController.text.isEmpty && _selectedOrigin == null) {
        _originController.text = _yourLocation;
      }

      final nav = ref.read(navigationProvider);

      if (!nav.isNavigating) {
        _updateVehicleMarker(position);
        _centerOnFirstFix(position);
        return;
      }

      if (!nav.isSimulating) _onLiveFix(position);
    });
  }

  @override
  Widget build(BuildContext context) {
    final nav = ref.watch(navigationProvider);
    final safeTop = MediaQuery.paddingOf(context).top;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    // In the floating window only the map, car and next turn are shown.
    final floating = AppWindow.pictureInPicture.value;

    ref.listen(mapFilterProvider, (_, _) => _applyMapFilter());
    ref.listen<AsyncValue<ll.LatLng>>(
      locationStreamProvider,
      (_, next) => _onLocation(next),
    );

    return PopScope(
      // Back while navigating hides the app instead of closing it, so the
      // trip carries on in the background.
      canPop: !nav.isNavigating,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(AppWindow.moveToBackground());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F3F4),
        body: LayoutBuilder(
          builder: (context, constraints) {
            _followViewport = FollowViewport.forHeight(
              constraints.maxHeight,
              compact: floating,
            );

            return Stack(
            children: [
              Listener(
                onPointerDown: (_) {
                  if (nav.isNavigating && _cameraFollowing) {
                    setState(() => _cameraFollowing = false);
                    final vehicle = _vehiclePosition;
                    if (vehicle != null) unawaited(_updateVehicleMarker(vehicle));
                  }
                },
                child: mapbox.MapWidget(
                  key: const ValueKey('rsi-map'),
                  onMapCreated: _onMapCreated,
                  styleUri: mapbox.MapboxStyles.STANDARD,
                  viewport: _initialViewport,
                  onStyleLoadedListener: (_) => _addSafetyLayers(),
                  onCameraChangeListener: (event) {
                    _mapBearing.value = event.cameraState.bearing;
                  },
                ),
              ),

              if (nav.isNavigating && _cameraFollowing)
                Positioned(
                  left: constraints.maxWidth / 2 - NavigationPuck.size / 2,
                  // The centre of the area the camera keeps the car in.
                  top: _followViewport.carCenterY(constraints.maxHeight) -
                      NavigationPuck.size / 2,
                  child: IgnorePointer(
                    child: NavigationPuck(rotationDegrees: _puckRotation),
                  ),
                ),

              if (!nav.isNavigating && !floating)
                Positioned(
                  top: safeTop + 10,
                  left: 14,
                  right: 14,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _plannerExpanded
                        ? _plannerCard()
                        : _collapsedSearchBar(),
                  ),
                ),

              if (nav.isNavigating && floating)
                Positioned(
                  top: 6,
                  left: 6,
                  right: 6,
                  child: CompactGuidanceStrip(
                    maneuverIcon: _maneuverIcon(nav.currentTurnInstruction),
                    distanceMeters: nav.distanceToNextTurnMeters,
                    showsHazard: nav.activeApproachingHazard != null,
                    hazardDistanceMeters: nav.activeHazardDistanceMeters,
                  ),
                ),

              if (nav.isNavigating && !floating)
                Positioned(
                  top: safeTop + 10,
                  left: 12,
                  right: 12,
                  child: Column(
                    children: [
                      TurnByTurnPanel(
                        instruction: nav.currentTurnInstruction,
                        distanceMeters: nav.distanceToNextTurnMeters,
                        maneuverIcon: _maneuverIcon(nav.currentTurnInstruction),
                      ),
                      if (nav.activeApproachingHazard != null) ...[
                        const SizedBox(height: 10),
                        SafetyAlertCard(
                          hazard: nav.activeApproachingHazard!,
                          distanceAheadMeters: nav.activeHazardDistanceMeters,
                        ),
                      ],
                    ],
                  ),
                ),

              if (!floating)
              Positioned(
                right: 14,
                bottom: nav.isNavigating
                    ? 114 + safeBottom
                    : nav.activeRouteDetails != null
                        ? 232 + safeBottom
                        : _plannerExpanded
                            ? 28 + safeBottom
                            : RentalsSheet.peekHeight + 16 + safeBottom,
                child: Column(
                  children: [
                    if (nav.isNavigating) ...[
                      _mapButton(
                        icon: _is3d ? Icons.view_in_ar_rounded : Icons.map_outlined,
                        onTap: () {
                          setState(() => _is3d = !_is3d);
                          _recenter();
                        },
                        active: _is3d,
                      ),
                      const SizedBox(height: 10),
                    ],
                    MapCompassButton(
                      bearing: _mapBearing,
                      tooltip: !nav.isNavigating
                          ? 'Reset map to north'
                          : _navigationNorthUp
                              ? 'Follow driving direction'
                              : 'Keep north up',
                      onTap: _onCompassTap,
                    ),
                    const SizedBox(height: 10),
                    _mapButton(
                      icon: Icons.my_location_rounded,
                      onTap: _recenter,
                      active: _cameraFollowing,
                    ),
                  ],
                ),
              ),

              if (!floating &&
                  !nav.isNavigating &&
                  nav.activeRouteDetails != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: RouteSummarySheet(
                    routeDetails: nav.activeRouteDetails!,
                    simulationMultiplier: nav.simulationMultiplier,
                    formattedDuration: formatDuration(
                      nav.activeRouteDetails!.durationMinutes,
                    ),
                    onSimulationSpeedChanged: (value) {
                      if (value != null) {
                        ref
                            .read(navigationProvider.notifier)
                            .updateSimulationMultiplier(value);
                      }
                    },
                    onStartNavigation: () => _startNavigation(),
                  ),
                ),

              if (!floating &&
                  !nav.isNavigating &&
                  nav.activeRouteDetails != null)
                Positioned(
                  left: 14,
                  bottom: 218 + safeBottom,
                  child: _mapButton(
                    icon: _simulationMode
                        ? Icons.speed_rounded
                        : Icons.gps_fixed_rounded,
                    label: _simulationMode ? 'Simulation' : 'Live GPS',
                    active: _simulationMode,
                    onTap: _toggleNavigationMode,
                  ),
                ),

              if (nav.isNavigating && !floating)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: NavigationBottomBar(
                    remainingMinutes: _remainingDurationMinutes,
                    remainingKm: _remainingDistanceKm,
                    onOverview: () {
                      final route = nav.activeRouteDetails;
                      if (route != null) _showRouteOverview(route.polyline);
                      setState(() => _cameraFollowing = false);
                      final vehicle = _vehiclePosition;
                      if (vehicle != null) {
                        unawaited(_updateVehicleMarker(vehicle));
                      }
                    },
                    onEnd: _stopNavigation,
                  ),
                ),

              if (!floating &&
                  !nav.isNavigating &&
                  nav.activeRouteDetails == null &&
                  !_plannerExpanded)
                Positioned.fill(
                  child: RentalsSheet(
                    // Keeps the search bar visible above the expanded sheet.
                    topClearance: safeTop + 78,
                  ),
                ),
            ],
          );
          },
        ),
      ),
    );
  }
}
