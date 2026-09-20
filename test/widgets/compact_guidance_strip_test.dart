import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsi/widgets/compact_guidance_strip.dart';

Widget _inSmallWindow(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 180, child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the next turn and its distance', (tester) async {
    await tester.pumpWidget(
      _inSmallWindow(
        const CompactGuidanceStrip(
          maneuverIcon: Icons.turn_right_rounded,
          distanceMeters: 250,
        ),
      ),
    );

    expect(find.text('250 m'), findsOneWidget);
    expect(find.byIcon(Icons.turn_right_rounded), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('switches to the hazard warning when one is ahead', (tester) async {
    await tester.pumpWidget(
      _inSmallWindow(
        const CompactGuidanceStrip(
          maneuverIcon: Icons.turn_right_rounded,
          distanceMeters: 250,
          showsHazard: true,
          hazardDistanceMeters: 1200,
        ),
      ),
    );

    expect(find.text('1.2 km'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('says when a new route is being worked out', (tester) async {
    await tester.pumpWidget(
      _inSmallWindow(
        const CompactGuidanceStrip(
          maneuverIcon: Icons.turn_right_rounded,
          distanceMeters: 250,
          isOffRoute: true,
        ),
      ),
    );

    expect(find.text('Εκτός διαδρομής'), findsOneWidget);
    expect(find.text('250 m'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a hazard still comes first when off the route', (tester) async {
    await tester.pumpWidget(
      _inSmallWindow(
        const CompactGuidanceStrip(
          maneuverIcon: Icons.turn_right_rounded,
          distanceMeters: 250,
          isOffRoute: true,
          showsHazard: true,
          hazardDistanceMeters: 400,
        ),
      ),
    );

    expect(find.text('400 m'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });
}
