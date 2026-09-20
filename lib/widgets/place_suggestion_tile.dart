import 'package:flutter/material.dart';

import '../core/format/navigation_labels.dart';
import '../services/mapbox_service.dart';

/// One search result: the place or address on the first line, the town
/// and postcode below it, and how far away it is.
class PlaceSuggestionTile extends StatelessWidget {
  const PlaceSuggestionTile({
    super.key,
    required this.result,
    required this.onTap,
  });

  static const Color _textPrimary = Color(0xFF202124);
  static const Color _textSecondary = Color(0xFF5F6368);

  final MapboxSearchResult result;
  final VoidCallback onTap;

  IconData get _icon {
    return switch (result.featureType) {
      'address' => Icons.home_outlined,
      'street' => Icons.add_road_rounded,
      'place' || 'locality' || 'neighborhood' => Icons.location_city_rounded,
      _ => Icons.place_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final distance = result.distanceMeters;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: Color(0xFFF1F3F4),
          shape: BoxShape.circle,
        ),
        child: Icon(_icon, size: 19, color: _textSecondary),
      ),
      title: Text(
        result.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: _textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: result.placeFormatted.isEmpty
          ? null
          : Text(
              result.placeFormatted,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _textSecondary, fontSize: 12.5),
            ),
      trailing: distance == null
          ? null
          : Text(
              formatDistance(distance),
              style: const TextStyle(
                color: _textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
      onTap: onTap,
    );
  }
}
