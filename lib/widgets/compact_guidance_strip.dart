import 'package:flutter/material.dart';

import '../core/format/navigation_labels.dart';

/// The next turn, or a hazard warning, squeezed into one line for the small
/// picture-in-picture window.
class CompactGuidanceStrip extends StatelessWidget {
  const CompactGuidanceStrip({
    super.key,
    required this.maneuverIcon,
    required this.distanceMeters,
    this.hazardDistanceMeters,
    this.showsHazard = false,
    this.isOffRoute = false,
  });

  final IconData maneuverIcon;
  final double distanceMeters;
  final bool showsHazard;
  final double? hazardDistanceMeters;

  /// The car has left the route, so the turn ahead is no longer the one to
  /// follow and a new route is on its way.
  final bool isOffRoute;

  static const Color _hazardColor = Color(0xFFE8710A);
  static const Color _offRouteColor = Color(0xFF5F6368);
  static const Color _routeColor = Color(0xFF1A73E8);

  @override
  Widget build(BuildContext context) {
    // A hazard still matters most: it is about to be driven into, whichever
    // road the car is on.
    final showsOffRoute = isOffRoute && !showsHazard;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: showsHazard
            ? _hazardColor
            : showsOffRoute
                ? _offRouteColor
                : _routeColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            showsHazard
                ? Icons.warning_amber_rounded
                : showsOffRoute
                    ? Icons.alt_route_rounded
                    : maneuverIcon,
            color: Colors.white,
            size: 22,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              showsOffRoute
                  ? 'Εκτός διαδρομής'
                  : formatDistance(
                      showsHazard ? hazardDistanceMeters ?? 0 : distanceMeters,
                    ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: showsOffRoute ? 13 : 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
