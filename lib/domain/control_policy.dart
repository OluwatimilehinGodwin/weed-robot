import '../models/robot_status.dart';

class ControlPolicy {
  final RobotStatus status;
  final bool fresh;

  const ControlPolicy(
    this.status, {
    required this.fresh,
  });

  bool get hardwareReady => fresh && status.espConnected;

  bool get supported => status.controlProtocolVersion >= 2;

  bool get manual => status.mode == 'manual' && !status.manualOverride;

  bool get canToggleSensor =>
      hardwareReady && supported && manual && status.espNavMode == 'MANUAL';

  bool get fluidReady =>
      status.fluidOperational &&
      (!status.fluidSensorEnabled ||
          (status.fluidAvailable && !status.fluidRecoveryRequired));

  bool get canSpray =>
      canToggleSensor &&
      fluidReady &&
      !status.autoInhibited &&
      status.servoReady &&
      status.railSettled;

  bool get canAimSprayer =>
      canToggleSensor && status.servoReady && status.railSettled;

  bool get canMove =>
      hardwareReady &&
      fluidReady &&
      (manual || status.manualOverride) &&
      status.espNavMode == 'MANUAL';
  bool get canRecover =>
      supported &&
      hardwareReady &&
      status.fluidSensorEnabled &&
      status.fluidAvailable &&
      status.fluidRecoveryRequired;

  String get sprayUnavailableReason {
    if (!fresh) {
      return 'Robot offline';
    }

    if (!status.espConnected) {
      return 'ESP32 unavailable';
    }

    if (!supported) {
      return 'Controller update required';
    }

    if (!manual) {
      return 'Manual mode only';
    }

    if (status.fluidRecoveryRequired && status.fluidSensorEnabled) {
      return 'Refill confirmation required';
    }

    if (!status.fluidOperational) {
      return 'Fluid unavailable';
    }

    if (status.autoInhibited) {
      return 'Safety interlock active';
    }

    if (!status.servoReady || !status.railSettled) {
      return 'Sprayer positioning';
    }

    return 'Waiting for manual mode';
  }

  String get aimUnavailableReason {
    if (!fresh) {
      return 'Robot offline';
    }

    if (!status.espConnected) {
      return 'ESP32 unavailable';
    }

    if (!supported) {
      return 'Controller update required';
    }

    if (!manual) {
      return 'Manual mode only';
    }

    if (status.espNavMode != 'MANUAL') {
      return 'ESP32 is not in manual mode';
    }

    if (!status.servoReady) {
      return 'Servo unavailable';
    }

    if (!status.railSettled) {
      return 'Rail is still positioning';
    }

    return 'Spray rail unavailable';
  }
}
