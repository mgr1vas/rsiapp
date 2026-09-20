import 'dart:math' as math;

/// Where the camera keeps the car while following it: the space left clear
/// above the car (for the turn panel) and below it (for the trip bar).
///
/// The gaps are a share of the map's height. Fixed pixel gaps only suit a
/// full phone screen; in split screen, landscape or the picture-in-picture
/// window they could fill the whole map and put the car in the wrong place.
class FollowViewport {
  const FollowViewport({required this.top, required this.bottom});

  factory FollowViewport.forHeight(double height, {bool compact = false}) {
    final mapHeight = math.max(0.0, height);

    if (compact) {
      // Picture-in-picture: a thin guidance strip above, nothing below, and
      // the car low in the window so more road ahead is visible.
      return FollowViewport(
        top: mapHeight * _compactTopShare,
        bottom: mapHeight * _compactBottomShare,
      );
    }

    return FollowViewport(
      top: math.min(_fullTop, mapHeight * _topShare),
      bottom: math.min(_fullBottom, mapHeight * _bottomShare),
    );
  }

  /// Gaps on a full-size phone screen (about 920 dp tall).
  static const double _fullTop = 150;
  static const double _fullBottom = 240;
  static const double _topShare = 0.1625;
  static const double _bottomShare = 0.26;

  static const double _compactTopShare = 0.30;
  static const double _compactBottomShare = 0.05;

  final double top;
  final double bottom;

  /// Distance from the top of the map to where the car is drawn.
  double carCenterY(double height) => top + (height - top - bottom) / 2;
}
