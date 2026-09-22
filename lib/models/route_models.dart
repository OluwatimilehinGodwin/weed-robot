class RouteSummary {
  final int id;
  final String name;
  final String createdAt;
  final String status;

  final double fieldWidthCm;
  final double fieldHeightCm;

  final int rowCount;

  final double totalDistanceCm;
  final int pointCount;

  final bool recording;

  const RouteSummary({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.status,
    required this.fieldWidthCm,
    required this.fieldHeightCm,
    required this.rowCount,
    required this.totalDistanceCm,
    required this.pointCount,
    required this.recording,
  });

  double get approximateWidthM {
    return fieldWidthCm / 100.0;
  }

  double get approximateLengthM {
    return fieldHeightCm / 100.0;
  }

  double get totalDistanceM {
    return totalDistanceCm / 100.0;
  }

  factory RouteSummary.fromJson(
    Map<String, dynamic> json,
  ) {
    return RouteSummary(
      id: (json['id'] as num).toInt(),
      name: json['name']?.toString() ?? 'Unnamed Field',
      createdAt: json['created_at']?.toString() ?? '',
      status: json['status']?.toString() ?? 'unknown',
      fieldWidthCm: (json['field_width_cm'] as num?)?.toDouble() ?? 0.0,
      fieldHeightCm: (json['field_height_cm'] as num?)?.toDouble() ?? 0.0,
      rowCount: (json['row_count'] as num?)?.toInt() ?? 0,
      totalDistanceCm: (json['total_distance_cm'] as num?)?.toDouble() ?? 0.0,
      pointCount: (json['point_count'] as num?)?.toInt() ?? 0,
      recording: json['recording'] == true,
    );
  }
}

class RoutePoint {
  final int seq;

  final double xCm;
  final double yCm;

  final double headingDeg;
  final double velocityCmS;

  final String mode;

  final int timestampMs;
  final double distanceCm;

  const RoutePoint({
    required this.seq,
    required this.xCm,
    required this.yCm,
    required this.headingDeg,
    required this.velocityCmS,
    required this.mode,
    required this.timestampMs,
    required this.distanceCm,
  });

  factory RoutePoint.fromJson(
    Map<String, dynamic> json,
  ) {
    return RoutePoint(
      seq: (json['seq'] as num).toInt(),
      xCm: (json['x_cm'] as num).toDouble(),
      yCm: (json['y_cm'] as num).toDouble(),
      headingDeg: (json['heading_deg'] as num?)?.toDouble() ?? 0.0,
      velocityCmS: (json['velocity_cm_s'] as num?)?.toDouble() ?? 0.0,
      mode: json['mode']?.toString() ?? 'AUTO',
      timestampMs: (json['timestamp_ms'] as num?)?.toInt() ?? 0,
      distanceCm: (json['distance_cm'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class SavedRoute {
  final RouteSummary summary;

  final List<RoutePoint> points;

  const SavedRoute({
    required this.summary,
    required this.points,
  });

  factory SavedRoute.fromJson(
    Map<String, dynamic> json,
  ) {
    final pointData = json['points'] as List? ?? [];

    return SavedRoute(
      summary: RouteSummary.fromJson(
        json,
      ),
      points: pointData
          .map(
            (point) => RoutePoint.fromJson(
              Map<String, dynamic>.from(
                point,
              ),
            ),
          )
          .toList(),
    );
  }
}
