class LidarPoint {
  final double angleDeg;
  final double distanceMm;
  final double xM;
  final double yM;
  final int intensity;

  const LidarPoint({
    required this.angleDeg,
    required this.distanceMm,
    required this.xM,
    required this.yM,
    required this.intensity,
  });

  factory LidarPoint.fromJson(
    Map<String, dynamic> json,
  ) {
    return LidarPoint(
      angleDeg: (json['angle_deg'] as num?)?.toDouble() ?? 0,
      distanceMm: (json['distance_mm'] as num?)?.toDouble() ?? 0,
      xM: (json['x_m'] as num?)?.toDouble() ?? 0,
      yM: (json['y_m'] as num?)?.toDouble() ?? 0,
      intensity: (json['intensity'] as num?)?.toInt() ?? 0,
    );
  }
}
