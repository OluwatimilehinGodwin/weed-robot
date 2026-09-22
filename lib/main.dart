import 'dart:async';

import 'package:flutter/material.dart';

import 'application/robot_controller.dart';
import 'core/app_config.dart';
import 'screens/connection_screen.dart';
import 'screens/control_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/guide_screen.dart';
import 'screens/navigation_screen.dart';
import 'services/pi_socket_service.dart';
import 'theme/app_theme.dart';
import 'widgets/fluid_sensor_tile.dart';
import 'widgets/fluid_recovery_dialog.dart';
import 'widgets/manual_spray_button.dart';

void main() => runApp(const TimirexApp());

class TimirexApp extends StatelessWidget {
  const TimirexApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Timirex',
        theme: AppTheme.lightTheme,
        home: const RobotShell(),
      );
}

class RobotShell extends StatefulWidget {
  final RobotController? controller;
  const RobotShell({super.key, this.controller});
  @override
  State<RobotShell> createState() => _RobotShellState();
}

class _RobotShellState extends State<RobotShell> with WidgetsBindingObserver {
  late final RobotController robot;
  late final StreamSubscription<void> _robotSubscription;
  int _page = 0;
  int _noticeRevision = 0;
  bool _dialogOpen = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    robot = widget.controller ?? RobotController(transport: PiSocketService());
    _robotSubscription = robot.changes.listen((_) => _onRobotChanged());
    WidgetsBinding.instance.addObserver(this);
  }

  void _onRobotChanged() {
    if (!mounted) return;
    if (!_dialogOpen && _foreground && robot.shouldPromptRecovery) {
      _dialogOpen = true;
      robot.recoveryPrompted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showRecoveryDialog();
      });
    }
    if (_noticeRevision != robot.noticeRevision) {
      _noticeRevision = robot.noticeRevision;
      final message = robot.notice;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && message != null) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        }
      });
    }
  }

  Future<void> _showRecoveryDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FluidRecoveryDialog(controller: robot),
    );
    if (mounted) setState(() => _dialogOpen = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) robot.stopOperatorOutputs();
    if (mounted) setState(() {});
    if (_foreground) _onRobotChanged();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_robotSubscription.cancel());
    if (widget.controller == null) robot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<void>(
        stream: robot.changes,
        builder: (context, _) {
          final s = robot.status;
          final policy = robot.policy;
          final pages = [
            DashboardScreen(
              connected: robot.fresh,
              running: s.running,
              streaming: s.streaming,
              weedCount: s.weedCount,
              fps: s.fps,
              mode: s.mode,
              videoStreamUrl: robot.videoUrl,
              onStart: () => robot.send(RobotCommand.startDetection),
              onStop: () => robot.send(RobotCommand.stopDetection),
              sprayTarget: s.sprayTarget,
              railOrientation: s.railOrientation,
              servoReady: s.servoReady,
              fluidSensorTile: FluidSensorTile(
                status: s,
                online: policy.hardwareReady,
                pending: robot.sensorBusy,
                onToggle: policy.canToggleSensor && !robot.busy
                    ? robot.toggleSensor
                    : null,
              ),
            ),
            NavigationScreen(
              connected: robot.fresh,
              host: robot.host,
              port: robot.port,
              mode: s.mode,
              autonomyState: s.autonomyState,
              missionActive: s.missionActive,
              manualOverride: s.manualOverride,
              recordingPauseReason: robot.recordingPauseReason,
              perceptionActive: s.perceptionActive,
              mappingActive: s.mappingActive,
              espConnected: policy.hardwareReady,
              lidarConnected: robot.lidarConnected && robot.fresh,
              lidarPoints: robot.lidarPoints,
              sendCommand: robot.send,
              fluidOperational: s.fluidOperational,
              fluidRecoveryRequired:
                  s.fluidSensorEnabled && s.fluidRecoveryRequired,
              controlsVisible: _page == 1 && _foreground,
            ),
            ControlScreen(
              connected: robot.fresh,
              mode: s.mode,
              espConnected: policy.hardwareReady,
              motionAllowed: policy.canMove,
              controlsVisible: _page == 2 && _foreground,
              railOrientation: s.railOrientation,
              aimAllowed: policy.canAimSprayer,
              aimUnavailableReason: policy.aimUnavailableReason,
              sendCommand: robot.send,
              sprayControl: ManualSprayButton(
                online: policy.hardwareReady,
                pumpOn: robot.fresh && s.pumpOn,
                requested: robot.fresh && s.manualSprayRequested,
                pending: robot.sprayBusy,
                stopping: robot.sprayStopping,
                manual: policy.manual,
                available: policy.canSpray,
                unavailableReason: policy.sprayUnavailableReason,
                onPressed: robot.fresh &&
                        policy.manual &&
                        ((policy.canSpray && !robot.busy) ||
                            s.pumpOn ||
                            s.manualSprayRequested ||
                            robot.sprayBusy)
                    ? robot.toggleSpray
                    : null,
              ),
            ),
            ConnectionScreen(
              connected: robot.connected,
              initialHost: robot.host,
              initialPort: robot.port,
              lastMessage: robot.lastMessage,
              onConnect: robot.connect,
              onDisconnect: robot.disconnect,
            ),
            const GuideScreen(),
          ];
          return Scaffold(
            body: Column(
              children: [
                if (policy.canRecover && !_dialogOpen)
                  SafeArea(
                    bottom: false,
                    child: MaterialBanner(
                      content: const Text('Refill ready'),
                      actions: [
                        TextButton(
                          onPressed: () {
                            _dialogOpen = true;
                            robot.recoveryPrompted = true;
                            _showRecoveryDialog();
                          },
                          child: const Text('Resume'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: IndexedStack(index: _page, children: pages),
                ),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _page,
              labelBehavior: MediaQuery.sizeOf(context).width < 400
                  ? NavigationDestinationLabelBehavior.onlyShowSelected
                  : NavigationDestinationLabelBehavior.alwaysShow,
              onDestinationSelected: (index) {
                robot.stopMotion();
                setState(() => _page = index);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  label: 'Dashboard',
                ),
                NavigationDestination(
                  icon: Icon(Icons.route_outlined),
                  label: 'Navigation',
                ),
                NavigationDestination(
                  icon: Icon(Icons.gamepad_outlined),
                  label: 'Control',
                ),
                NavigationDestination(
                    icon: Icon(Icons.wifi), label: 'Connection'),
                NavigationDestination(
                  icon: Icon(Icons.help_outline),
                  label: 'Guide',
                ),
              ],
            ),
          );
        },
      );
}
