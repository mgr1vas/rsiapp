/// A short distance for navigation: "850 m", "1.2 km", "12 km".
String formatDistance(double meters) {
  if (meters >= 1000) {
    final digits = meters >= 10000 ? 0 : 1;
    return '${(meters / 1000).toStringAsFixed(digits)} km';
  }
  return '${meters.round()} m';
}

/// A trip length: "12 min", "1 hr", "1 hr 5 min".
String formatDuration(double minutes) {
  final total = minutes.round();
  if (total < 60) return '$total min';
  final hours = total ~/ 60;
  final remaining = total % 60;
  return remaining == 0 ? '$hours hr' : '$hours hr $remaining min';
}

/// Clock time [minutes] from [now], e.g. "14:05".
String formatArrivalTime(double minutes, {DateTime? now}) {
  final arrival = (now ?? DateTime.now()).add(
    Duration(minutes: minutes.round()),
  );
  final hour = arrival.hour.toString().padLeft(2, '0');
  final minute = arrival.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
