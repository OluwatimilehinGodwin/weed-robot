class AppConfig {
  static const defaultHost = '192.168.1.50';

  static const defaultPort = 8000;

  static const requestTimeout = Duration(seconds: 4);
}

class RobotCommand {
  static const sprayOn = 'manual_spray_on';
  static const sprayOff = 'manual_spray_off';
  static const sprayKeepalive = 'manual_spray_keepalive';
  static const sensorEnable = 'fluid_sensor_enable';
  static const sensorBypass = 'fluid_sensor_bypass';
  static const fluidResume = 'fluid_resume';
  static const startDetection = 'start';

  static const stopDetection = 'stop';

  static const manualMode = 'mode_manual';

  static const autoMode = 'mode_auto';

  static const manualOverride = 'manual_override';

  static const startMission = 'start_mission';

  static const stopMission = 'stop_mission';

  static const forward = 'forward';

  static const reverse = 'reverse';

  static const left = 'left';

  static const right = 'right';

  static const stopMotion = 'motion_stop';

  static const targetWeed = 'target_weed';

  static const targetMaize = 'target_maize';
}

class RouteEvent {
  static const rowEnd = 'ROW_END';

  static const manualControlStarted = 'MANUAL_CONTROL_STARTED';

  static const nextRowStarted = 'NEXT_ROW_STARTED';
}
