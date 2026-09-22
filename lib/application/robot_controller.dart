import 'dart:async';

import '../core/app_config.dart';
import '../domain/control_policy.dart';
import '../domain/robot_transport.dart';
import '../models/lidar_point.dart';
import '../models/robot_status.dart';

class _PendingCommand {
  final String id;
  final String command;
  final bool Function(RobotStatus) confirmed;
  final DateTime deadline;
  bool acknowledged = false;
  _PendingCommand(this.id, this.command, this.confirmed, this.deadline);
}

/// Owns operator intent; hardware telemetry remains authoritative.
class RobotController {
  final _changes = StreamController<void>.broadcast(sync: true);
  Stream<void> get changes => _changes.stream;
  void _notify() {
    if (!_disposed) _changes.add(null);
  }

  final RobotTransport transport;
  final DateTime Function() clock;
  late final StreamSubscription<Map<String, dynamic>> _messages;
  late final StreamSubscription<bool> _connections;
  late final Timer _watchdog;
  Timer? _sprayLease;
  Timer? _motionLease;
  String? _motionCommand;
  _PendingCommand? _pending;
  DateTime? _lastTelemetry;
  bool _fresh = false;
  bool _disposed = false;
  bool _ownsSpray = false;
  int _requestSequence = 0;
  bool recoveryPrompted = false;

  RobotStatus status = const RobotStatus();
  bool connected = false;
  bool lidarConnected = false;
  List<LidarPoint> lidarPoints = const [];
  String recordingPauseReason = '';
  String host = AppConfig.defaultHost;
  int port = AppConfig.defaultPort;
  String lastMessage = 'Not connected.';
  String? notice;
  int noticeRevision = 0;

  RobotController({required this.transport, DateTime Function()? clock})
      : clock = clock ?? DateTime.now {
    _messages = transport.messages.listen(_receive);
    _connections = transport.connections.listen(_connectionChanged);
    _watchdog = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _tick(),
    );
  }

  bool get fresh => connected && _fresh;
  ControlPolicy get policy => ControlPolicy(status, fresh: fresh);
  bool get busy => _pending != null;
  bool get sprayBusy =>
      _pending?.command == RobotCommand.sprayOn ||
      _pending?.command == RobotCommand.sprayOff;
  bool get sprayStopping => _pending?.command == RobotCommand.sprayOff;
  bool get sensorBusy =>
      _pending?.command == RobotCommand.sensorEnable ||
      _pending?.command == RobotCommand.sensorBypass;
  bool get recovering => _pending?.command == RobotCommand.fluidResume;
  bool get shouldPromptRecovery => policy.canRecover && !recoveryPrompted;
  String get videoUrl => Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: '/video_feed',
      ).toString();

  Future<void> connect(String newHost, int newPort) async {
    stopOperatorOutputs();
    host = newHost.trim();
    port = newPort;
    await transport.connect(host: host, port: port);
  }

  Future<void> disconnect() async {
    stopOperatorOutputs();
    await transport.disconnect();
  }

  void _connectionChanged(bool value) {
    connected = value;
    _fresh = false;
    _lastTelemetry = null;
    _pending = null;
    _stopLease();
    _motionLease?.cancel();
    _motionLease = null;
    _motionCommand = null;
    status = const RobotStatus();
    lidarPoints = const [];
    lidarConnected = false;
    recoveryPrompted = false;
    lastMessage = value ? 'Waiting for robot status' : 'Disconnected';
    _notify();
  }

  void _receive(Map<String, dynamic> data) {
    if (_disposed) return;
    final type = data['type'];
    if (type == 'status' || type == 'telemetry') {
      if (data['mode'] is! String ||
          data['esp_peer_alive'] is! bool ||
          data['fluid_operational'] is! bool ||
          data['pump_on'] is! bool) return;
      _lastTelemetry = clock();
      _fresh = true;
      status = RobotStatus.fromTelemetry(data, status);
      recordingPauseReason =
          data['recording_pause_reason']?.toString() ?? recordingPauseReason;
      if (data['lidar_connected'] is bool)
        lidarConnected = data['lidar_connected'] as bool;
      if (!status.fluidRecoveryRequired) recoveryPrompted = false;
      _completeIfConfirmed();
      if (!policy.canMove && _motionCommand != null) stopMotion();
      if (_ownsSpray &&
          (!policy.canSpray ||
              (!status.manualSprayRequested &&
                  _pending?.command != RobotCommand.sprayOn))) {
        _stopLease();
        transport.sendCommand(RobotCommand.sprayOff);
      }
    } else if (type == 'lidar') {
      lidarConnected = data['lidar_connected'] == true;
      final points = <LidarPoint>[];
      final incoming = data['lidar_points'];
      if (incoming is List) {
        for (final point in incoming) {
          if (point is Map<String, dynamic>) {
            try {
              points.add(LidarPoint.fromJson(point));
            } on TypeError {
              /* Skip malformed samples. */
            }
          }
        }
      }
      lidarPoints = List.unmodifiable(points);
    } else {
      final pending = _pending;
      final matching = pending != null && data['request_id'] == pending.id;
      if (data['request_id'] != null && !matching) return;
      if (type == 'error') {
        if (matching) {
          _pending = null;
          if (pending.command == RobotCommand.sprayOn) {
            _stopLease();
            transport.sendCommand(RobotCommand.sprayOff);
          }
        }
        _report(data['message']?.toString() ?? 'Command failed');
      } else if (type == 'ack') {
        lastMessage = data['message']?.toString() ?? '';
        if (matching) {
          pending.acknowledged = true;
          _completeIfConfirmed();
        } else if (lastMessage.isNotEmpty) {
          _report(lastMessage);
        }
      }
    }
    _notify();
  }

  void _completeIfConfirmed() {
    final pending = _pending;
    if (pending != null && pending.acknowledged && pending.confirmed(status)) {
      _pending = null;
    }
  }

  void _tick() {
    if (_disposed) return;
    final now = clock();
    if (_fresh &&
        _lastTelemetry != null &&
        now.difference(_lastTelemetry!) > const Duration(milliseconds: 1500)) {
      _fresh = false;
      stopOperatorOutputs();
      _report('Robot status lost');
      _notify();
    }
    final pending = _pending;
    if (pending != null && !now.isBefore(pending.deadline)) {
      _pending = null;
      if (pending.command == RobotCommand.sprayOn) {
        _stopLease();
        transport.sendCommand(RobotCommand.sprayOff);
      }
      _report('Command not confirmed. Check robot status.');
      _notify();
    }
  }

  void _report(String message) {
    lastMessage = message;
    notice = message;
    noticeRevision++;
  }

  void send(String command) {
    if (!connected) {
      _report(
        'Connect to the Raspberry Pi first',
      );
      _notify();
      return;
    }

    final moving = {
      RobotCommand.forward,
      RobotCommand.reverse,
      RobotCommand.left,
      RobotCommand.right,
    }.contains(command);

    final changingSprayTarget = command == RobotCommand.targetWeed ||
        command == RobotCommand.targetMaize;

    if (moving && !policy.canMove) {
      return;
    }

    if (changingSprayTarget && !policy.canAimSprayer) {
      _report(
        policy.aimUnavailableReason,
      );
      _notify();
      return;
    }

    if (command == RobotCommand.autoMode) {
      if (!fresh) {
        _report(
          'AUTO unavailable: '
          'waiting for fresh robot status',
        );
        _notify();
        return;
      }

      if (!status.espConnected) {
        _report(
          'AUTO unavailable: '
          'ESP32 not connected',
        );
        _notify();
        return;
      }
    }

    if (command == RobotCommand.manualMode ||
        command == RobotCommand.autoMode ||
        changingSprayTarget) {
      stopOperatorOutputs();
    }

    if (command == RobotCommand.stopMotion) {
      stopMotion();
      return;
    }

    if (moving) {
      _motionCommand = command;

      _motionLease ??= Timer.periodic(
        const Duration(milliseconds: 250),
        (_) {
          if (policy.canMove && _motionCommand != null) {
            transport.sendCommand(
              _motionCommand!,
            );
          } else {
            stopMotion();
          }
        },
      );
    }

    transport.sendCommand(command);
  }

  void _request(String command, bool Function(RobotStatus) confirmed) {
    final id = '${++_requestSequence}';
    _pending = _PendingCommand(
      id,
      command,
      confirmed,
      clock().add(const Duration(seconds: 4)),
    );
    if (!transport.sendCommand(command, requestId: id)) {
      _pending = null;
      _stopLease();
      _report('Robot disconnected');
    }
    _notify();
  }

  void toggleSpray() {
    // OFF remains available during an in-flight ON request.
    if (status.pumpOn || status.manualSprayRequested || _ownsSpray) {
      _stopLease();
      if (connected)
        _request(
          RobotCommand.sprayOff,
          (s) => !s.pumpOn && !s.manualSprayRequested,
        );
      return;
    }
    if (!policy.canSpray || busy) return;
    _ownsSpray = true;
    _sprayLease = Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (_ownsSpray && policy.canSpray)
        transport.sendCommand(RobotCommand.sprayKeepalive);
    });
    _request(RobotCommand.sprayOn, (s) => s.pumpOn && s.manualSprayRequested);
  }

  void toggleSensor() {
    if (!policy.canToggleSensor || busy) return;
    stopOperatorOutputs();
    final enable = !status.fluidSensorEnabled;
    _request(
      enable ? RobotCommand.sensorEnable : RobotCommand.sensorBypass,
      (s) => s.fluidSensorEnabled == enable,
    );
  }

  void resumeFluid() {
    if (!policy.canRecover || busy) return;
    _request(
      RobotCommand.fluidResume,
      (s) => !s.fluidRecoveryRequired && s.fluidOperational,
    );
  }

  void stopMotion() {
    _motionLease?.cancel();
    _motionLease = null;
    _motionCommand = null;
    if (connected) transport.sendCommand(RobotCommand.stopMotion);
  }

  void _stopLease() {
    _ownsSpray = false;
    _sprayLease?.cancel();
    _sprayLease = null;
  }

  void stopOperatorOutputs() {
    stopMotion();
    _stopLease();
    if (sprayBusy) _pending = null;
    if (connected) {
      transport.sendCommand(RobotCommand.sprayOff);
    }
  }

  void dispose() {
    stopOperatorOutputs();
    _disposed = true;
    _watchdog.cancel();
    unawaited(_messages.cancel());
    unawaited(_connections.cancel());
    transport.dispose();
    unawaited(_changes.close());
  }
}
