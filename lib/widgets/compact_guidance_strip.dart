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
  });

  final IconData maneuverIcon;
  final double distanceMeters;
  final bool showsHazard;
  final double? hazardDistanceMeters;

  @override
  Widget build(BuildContext context) {
    final distance = showsHazard ? hazardDistanceMeters ?? 0 : distanceMeters;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: showsHazard ? const Color(0xFFE8710A) : const Color(0xFF1A73E8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            showsHazard ? Icons.warning_amber_rounded : maneuverIcon,
            color: Colors.white,
            size: 22,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              formatDistance(distance),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
