import 'package:latlong2/latlong.dart';

/// A ready-made trip that passes the bundled mock hazards, for trying out
/// navigation alerts in simulation without searching for places.
class DemoRoute {
  const DemoRoute({
    required this.label,
    required this.originName,
    required this.origin,
    required this.destinationName,
    required this.destination,
  });

  final String label;
  final String originName;
  final LatLng origin;
  final String destinationName;
  final LatLng destination;
}

class DemoRoutes {
  DemoRoutes._();

  /// Turn off for store builds with `--dart-define=RSI_DEMO_ROUTES=false`.
  static const bool enabled = bool.fromEnvironment(
    'RSI_DEMO_ROUTES',
    defaultValue: true,
  );

  /// Across central Arta, from the old bridge to the General Hospital, past
  /// the mock hazards in `assets/data/arta_hazards.geojson`.
  static final DemoRoute arta = DemoRoute(
    label: 'Δοκιμαστική διαδρομή: Άρτα',
    originName: 'Γεφύρι της Άρτας',
    origin: const LatLng(39.152424, 20.975914),
    destinationName: 'Γενικό Νοσοκομείο Άρτας',
    destination: const LatLng(39.147838, 20.994677),
  );

  /// A short country-road drive from Pyli (Boeotia) to the Zoodochos Pigi
  /// monastery, past the village mock hazards.
  static final DemoRoute pyliVillage = DemoRoute(
    label: 'Δοκιμαστική διαδρομή: Πύλη',
    originName: 'Πύλη Βοιωτίας',
    origin: const LatLng(38.213364, 23.496732),
    destinationName: 'Ι.Μ. Ζωοδόχου Πηγής, Πύλη',
    destination: const LatLng(38.214965, 23.469484),
  );

  /// About 26 km from Pyli to central Thebes on regional roads and the EO3,
  /// for longer runs at higher simulation speeds.
  static final DemoRoute pyliToThiva = DemoRoute(
    label: 'Δοκιμαστική διαδρομή: Πύλη → Θήβα',
    originName: 'Πύλη Βοιωτίας',
    origin: const LatLng(38.213364, 23.496732),
    destinationName: 'Θήβα (κέντρο)',
    destination: const LatLng(38.31922, 23.317957),
  );

  static final List<DemoRoute> all = [arta, pyliVillage, pyliToThiva];
}
