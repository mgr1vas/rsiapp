import 'package:flutter_test/flutter_test.dart';
import 'package:rsi/config/demo_routes.dart';
import 'package:rsi/services/hazard_db_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads the Naxos and Arta hazards together', () async {
    final hazards = await HazardDbService.initializeDatabase(
      forceReload: true,
    );
    final ids = hazards.map((hazard) => hazard.id).toSet();

    expect(ids, containsAll(['acc_1', 'arta_1', 'arta_10', 'pyli_1', 'pyli_14']));
    expect(ids, hasLength(hazards.length), reason: 'ids must be unique');
  });

  test('Pyli mock hazards lie between Pyli and Thebes', () async {
    final hazards = await HazardDbService.initializeDatabase(
      forceReload: true,
    );
    final pyli = hazards.where((hazard) => hazard.id.startsWith('pyli_'));

    expect(pyli.length, greaterThanOrEqualTo(12));

    for (final hazard in pyli) {
      expect(hazard.location.latitude, inInclusiveRange(38.20, 38.33));
      expect(hazard.location.longitude, inInclusiveRange(23.31, 23.51));
      expect(hazard.nearestArea, isNot(contains('Δημοτική Ενότητα')));
    }

    for (final demo in [DemoRoutes.pyliVillage, DemoRoutes.pyliToThiva]) {
      expect(demo.origin.latitude, inInclusiveRange(38.20, 38.33));
      expect(demo.destination.longitude, inInclusiveRange(23.31, 23.51));
    }
  });

  test('Arta mock hazards lie in central Arta near the demo route', () async {
    final hazards = await HazardDbService.initializeDatabase(
      forceReload: true,
    );
    final arta = hazards.where((hazard) => hazard.id.startsWith('arta_'));
    final demo = DemoRoutes.arta;

    expect(arta.length, greaterThanOrEqualTo(8));

    for (final hazard in arta) {
      expect(hazard.location.latitude, inInclusiveRange(39.14, 39.17));
      expect(hazard.location.longitude, inInclusiveRange(20.97, 21.00));
      expect(hazard.radiusMeters, greaterThan(0));
    }

    expect(demo.origin.latitude, inInclusiveRange(39.14, 39.17));
    expect(demo.destination.longitude, inInclusiveRange(20.97, 21.00));
  });
}
