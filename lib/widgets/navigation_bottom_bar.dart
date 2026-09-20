import 'package:flutter/material.dart';

import '../core/format/navigation_labels.dart';

/// Arrival time, time and distance left, with route overview and end
/// buttons, shown at the bottom while navigating.
class NavigationBottomBar extends StatelessWidget {
  const NavigationBottomBar({
    super.key,
    required this.remainingMinutes,
    required this.remainingKm,
    required this.onOverview,
    required this.onEnd,
  });

  static const Color _textPrimary = Color(0xFF202124);
  static const Color _textSecondary = Color(0xFF5F6368);

  final double remainingMinutes;
  final double remainingKm;
  final VoidCallback onOverview;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        formatArrivalTime(remainingMinutes),
                        style: const TextStyle(
                          color: Color(0xFF188038),
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatDuration(remainingMinutes),
                        style: const TextStyle(
                          color: _textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${remainingKm.toStringAsFixed(1)} km remaining',
                    style: const TextStyle(
                      color: _textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Overview',
              onPressed: onOverview,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFF1F3F4),
                foregroundColor: _textPrimary,
              ),
              icon: const Icon(Icons.route_rounded),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'End navigation',
              onPressed: onEnd,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFEA4335),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
