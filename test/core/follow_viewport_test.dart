import 'package:flutter_test/flutter_test.dart';
import 'package:rsi/core/navigation/follow_viewport.dart';

void main() {
  test('keeps the full-screen phone layout unchanged', () {
    // A Pixel 9 map is 923 dp tall.
    final phone = FollowViewport.forHeight(923);
    expect(phone.top, closeTo(150, 0.5));
    expect(phone.bottom, closeTo(240, 0.5));

    // Taller screens never get bigger gaps than a phone.
    final tablet = FollowViewport.forHeight(1280);
    expect(tablet.top, 150);
    expect(tablet.bottom, 240);
  });

  test('scales the gaps down with shorter maps', () {
    for (final height in [700.0, 450.0, 411.0, 250.0]) {
      final viewport = FollowViewport.forHeight(height);
      final car = viewport.carCenterY(height);

      expect(viewport.top + viewport.bottom, lessThan(height * 0.5));
      expect(car, greaterThan(viewport.top));
      expect(car, lessThan(height - viewport.bottom));
    }
  });

  test('puts the car in the same place relative to the map at any size', () {
    final large = FollowViewport.forHeight(900);
    final small = FollowViewport.forHeight(450);

    expect(
      small.carCenterY(450) / 450,
      closeTo(large.carCenterY(900) / 900, 0.01),
    );
  });

  test('picture-in-picture keeps the car low in the window', () {
    const height = 300.0;
    final compact = FollowViewport.forHeight(height, compact: true);
    final regular = FollowViewport.forHeight(height);

    expect(compact.carCenterY(height), greaterThan(regular.carCenterY(height)));
    expect(compact.carCenterY(height) / height, closeTo(0.625, 0.001));
  });

  test('copes with a map that has no height yet', () {
    final viewport = FollowViewport.forHeight(0);

    expect(viewport.top, 0);
    expect(viewport.bottom, 0);
    expect(viewport.carCenterY(0), 0);
  });
}
