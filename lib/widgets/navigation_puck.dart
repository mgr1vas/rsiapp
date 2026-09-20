import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The car arrow shown while the map follows the driver. It is drawn by
/// Flutter at the fixed spot the camera keeps the car on, so it never lags
/// behind the moving map the way a map marker would.
class NavigationPuck extends StatelessWidget {
  const NavigationPuck({super.key, required this.rotationDegrees});

  static const double size = 46;

  /// Arrow direction relative to the top of the screen.
  final ValueListenable<double> rotationDegrees;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: rotationDegrees,
      builder: (context, degrees, child) {
        return Transform.rotate(
          angle: degrees * math.pi / 180,
          child: child,
        );
      },
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.navigation_rounded,
          color: Color(0xFF1A73E8),
          size: 32,
        ),
      ),
    );
  }
}
