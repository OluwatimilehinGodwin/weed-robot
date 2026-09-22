class RobotStatus {
  final String fluidState;
  final bool fluidSensorEnabled;
  final bool fluidAvailable;
  final bool fluidOperational;
  final bool fluidRecoveryRequired;
  final bool fluidRecoveryPopupRequired;
  final bool railSettled;
  final bool manualSprayRequested;
  final int controlProtocolVersion;

  final bool running;
  final bool streaming;

  final int weedCount;
  final double fps;

  final String mode;
  final String autonomyState;

  final bool missionActive;
  final bool manualOverride;

  final bool perceptionActive;
  final bool mappingActive;

  final bool teachingStarted;
  final int recordingPointCount;

  final int? recordingRouteId;

  final String sprayTarget;
  final String railOrientation;

  final bool servoReady;

  final bool targetDetected;
  final double targetConfidence;

  final String tankState;

  final bool tankInterlockEnabled;
  final bool waterAvailable;

  final bool pumpOn;
  final bool autoInhibited;

  final bool espConnected;

  final String espNavMode;

  final bool espLidarHealthy;
  final bool espDeadEnd;

  final double espPoseXM;
  final double espPoseYM;

  final double espPoseHeadingDeg;
  final double espPoseDistanceM;

  const RobotStatus({
    this.fluidState = 'checking',
    this.fluidSensorEnabled = true,
    this.fluidAvailable = false,
    this.fluidOperational = false,
    this.fluidRecoveryRequired = false,
    this.fluidRecoveryPopupRequired = false,
    this.railSettled = false,
    this.manualSprayRequested = false,
    this.controlProtocolVersion = 0,
    this.running = false,
    this.streaming = false,
    this.weedCount = 0,
    this.fps = 0.0,
    this.mode = 'manual',
    this.autonomyState = 'manual',
    this.missionActive = false,
    this.manualOverride = false,
    this.perceptionActive = false,
    this.mappingActive = false,
    this.teachingStarted = false,
    this.recordingPointCount = 0,
    this.recordingRouteId,
    this.sprayTarget = 'weed',
    this.railOrientation = 'horizontal',
    this.servoReady = false,
    this.targetDetected = false,
    this.targetConfidence = 0.0,
    this.tankState = 'checking',
    this.tankInterlockEnabled = true,
    this.waterAvailable = false,
    this.pumpOn = false,
    this.autoInhibited = false,
    this.espConnected = false,
    this.espNavMode = 'STOP',
    this.espLidarHealthy = false,
    this.espDeadEnd = false,
    this.espPoseXM = 0.0,
    this.espPoseYM = 0.0,
    this.espPoseHeadingDeg = 0.0,
    this.espPoseDistanceM = 0.0,
  });

  factory RobotStatus.fromTelemetry(
    Map<String, dynamic> data,
    RobotStatus previous,
  ) {
    return RobotStatus(
      fluidState: _string(data, 'fluid_state', previous.fluidState),
      fluidSensorEnabled: _bool(
        data,
        'fluid_level_sensor_enabled',
        previous.fluidSensorEnabled,
      ),
      fluidAvailable: _bool(data, 'fluid_available', previous.fluidAvailable),
      fluidOperational: _bool(
        data,
        'fluid_operational',
        previous.fluidOperational,
      ),
      fluidRecoveryRequired: _bool(
        data,
        'fluid_recovery_required',
        previous.fluidRecoveryRequired,
      ),
      fluidRecoveryPopupRequired: _bool(
        data,
        'fluid_recovery_popup_required',
        previous.fluidRecoveryPopupRequired,
      ),
      railSettled: _bool(data, 'rail_settled', previous.railSettled),
      manualSprayRequested: _bool(
        data,
        'manual_spray_requested',
        previous.manualSprayRequested,
      ),
      controlProtocolVersion: _int(
        data,
        'control_protocol_version',
        previous.controlProtocolVersion,
      ),
      running: _bool(data, 'running', previous.running),
      streaming: _bool(data, 'streaming', previous.streaming),
      weedCount: _int(data, 'weed_count', previous.weedCount),
      fps: _double(data, 'fps', previous.fps),
      mode: _string(data, 'mode', previous.mode),
      autonomyState: _string(data, 'autonomy_state', previous.autonomyState),
      missionActive: _bool(data, 'mission_active', previous.missionActive),
      manualOverride: _bool(data, 'manual_override', previous.manualOverride),
      perceptionActive: _bool(
        data,
        'perception_active',
        previous.perceptionActive,
      ),
      mappingActive: _bool(data, 'mapping_active', previous.mappingActive),
      teachingStarted: _bool(
        data,
        'teaching_started',
        previous.teachingStarted,
      ),
      recordingPointCount: _int(
        data,
        'recording_point_count',
        previous.recordingPointCount,
      ),
      recordingRouteId: _nullableInt(
        data,
        'recording_route_id',
        previous.recordingRouteId,
      ),
      sprayTarget: _string(data, 'spray_target', previous.sprayTarget),
      railOrientation: _string(
        data,
        'rail_orientation',
        previous.railOrientation,
      ),
      servoReady: _bool(data, 'servo_ready', previous.servoReady),
      targetDetected: _bool(data, 'target_detected', previous.targetDetected),
      targetConfidence: _double(
        data,
        'target_confidence',
        previous.targetConfidence,
      ),
      tankState: _string(data, 'tank_state', previous.tankState),
      tankInterlockEnabled: _bool(
        data,
        'tank_interlock_enabled',
        previous.tankInterlockEnabled,
      ),
      waterAvailable: _bool(data, 'water_available', previous.waterAvailable),
      pumpOn: _bool(data, 'pump_on', previous.pumpOn),
      autoInhibited: _bool(data, 'auto_inhibited', previous.autoInhibited),
      espConnected: _bool(
        data,
        'esp_peer_alive',
        _bool(data, 'esp_uart_connected', previous.espConnected),
      ),
      espNavMode: _string(data, 'esp_nav_mode', previous.espNavMode),
      espLidarHealthy: _bool(
        data,
        'esp_lidar_healthy',
        previous.espLidarHealthy,
      ),
      espDeadEnd: _bool(data, 'esp_dead_end', previous.espDeadEnd),
      espPoseXM: _double(data, 'esp_pose_x_m', previous.espPoseXM),
      espPoseYM: _double(data, 'esp_pose_y_m', previous.espPoseYM),
      espPoseHeadingDeg: _double(
        data,
        'esp_pose_heading_deg',
        previous.espPoseHeadingDeg,
      ),
      espPoseDistanceM: _double(
        data,
        'esp_pose_distance_m',
        previous.espPoseDistanceM,
      ),
    );
  }

  static bool _bool(Map<String, dynamic> data, String key, bool fallback) {
    final value = data[key];

    return value is bool ? value : fallback;
  }

  static int _int(Map<String, dynamic> data, String key, int fallback) {
    final value = data[key];

    return value is num && value.isFinite ? value.toInt() : fallback;
  }

  static int? _nullableInt(
    Map<String, dynamic> data,
    String key,
    int? fallback,
  ) {
    if (!data.containsKey(key)) {
      return fallback;
    }

    final value = data[key];

    if (value == null) {
      return null;
    }

    return value is num && value.isFinite ? value.toInt() : fallback;
  }

  static double _double(
    Map<String, dynamic> data,
    String key,
    double fallback,
  ) {
    final value = data[key];

    return value is num && value.isFinite ? value.toDouble() : fallback;
  }

  static String _string(
    Map<String, dynamic> data,
    String key,
    String fallback,
  ) {
    final value = data[key];

    return value is String ? value : fallback;
  }
}
