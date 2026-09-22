import 'dart:async';
import 'dart:math' as math;

import '../core/app_config.dart';

import 'package:flutter/material.dart';

import '../models/lidar_point.dart';
import '../models/route_models.dart';
import '../services/route_service.dart';
import '../theme/app_colors.dart';
import '../widgets/neu_card.dart';
import '../widgets/responsive_page.dart';

enum FieldPanelMode { empty, recording, viewing }

class NavigationScreen extends StatefulWidget {
  final bool fluidOperational;
  final bool fluidRecoveryRequired;
  final bool controlsVisible;
  final bool connected;

  final String host;
  final int port;

  final bool espConnected;

  final String mode;
  final String autonomyState;

  final bool missionActive;
  final bool manualOverride;

  final String recordingPauseReason;

  final bool perceptionActive;
  final bool mappingActive;

  final bool lidarConnected;

  final List<LidarPoint> lidarPoints;

  final void Function(String command) sendCommand;

  const NavigationScreen({
    super.key,
    required this.fluidOperational,
    required this.fluidRecoveryRequired,
    required this.controlsVisible,
    required this.connected,
    required this.host,
    required this.port,
    required this.mode,
    required this.autonomyState,
    required this.missionActive,
    required this.espConnected,
    required this.manualOverride,
    required this.recordingPauseReason,
    required this.perceptionActive,
    required this.mappingActive,
    required this.lidarConnected,
    required this.lidarPoints,
    required this.sendCommand,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  List<RouteSummary> _routes = [];

  SavedRoute? _viewedRoute;
  SavedRoute? _liveRoute;

  int? _recordingRouteId;

  bool _loadingRoutes = false;
  bool _pollingLiveRoute = false;

  Timer? _liveRouteTimer;

  late RouteService _routeService;

  bool get _globalAuto {
    return widget.connected && widget.mode == 'auto';
  }

  bool get _teaching {
    return _recordingRouteId != null;
  }

  String get _pauseReason {
    return widget.recordingPauseReason.trim().toLowerCase();
  }

  String get _pauseChipLabel {
    switch (_pauseReason) {
      case 'dead_end':
        return 'DEAD END';

      case 'esp_offline':
        return 'ESP OFFLINE';

      case 'fluid_empty':
      case 'fluid_recovery_required':
      case 'water_empty':
        return widget.fluidRecoveryRequired
            ? 'REFILL CONFIRMATION'
            : 'FLUID EMPTY';

      case 'manual_reposition':
        return 'MANUAL';

      case 'interrupted':
        return 'INTERRUPTED';

      case 'safety_stop':
        return 'SAFETY STOP';

      case 'operator_stopped':
      case 'paused':
      default:
        return 'PAUSED';
    }
  }

  IconData get _pauseChipIcon {
    switch (_pauseReason) {
      case 'dead_end':
        return Icons.warning_amber_rounded;

      case 'esp_offline':
        return Icons.link_off;

      case 'fluid_empty':
      case 'fluid_recovery_required':
      case 'water_empty':
        return Icons.water_drop_outlined;

      case 'manual_reposition':
        return Icons.gamepad;

      case 'interrupted':
        return Icons.restart_alt;

      case 'safety_stop':
        return Icons.health_and_safety_outlined;

      default:
        return Icons.pause_circle_outline;
    }
  }

  String get _pauseDescription {
    switch (_pauseReason) {
      case 'dead_end':
        return 'Dead end detected. '
            'Reposition the robot if required, '
            'then resume, save or discard '
            'the field.';

      case 'esp_offline':
        return 'ESP32 communication was lost. '
            'The field recording is retained. '
            'Reconnect the ESP32 before '
            'resuming navigation.';

      case 'fluid_empty':
      case 'fluid_recovery_required':
      case 'water_empty':
        return 'Refill the tank and confirm recovery to resume.';

      case 'operator_stopped':
        return 'Teaching was paused by the '
            'operator. Resume, save or '
            'discard the field.';

      case 'manual_reposition':
        return 'Manual reposition is active. '
            'Spraying is disabled while the '
            'robot is positioned for the '
            'next row.';

      case 'interrupted':
        return 'An unfinished field recording '
            'was recovered after an '
            'interruption. Verify the robot '
            'position before resuming, or '
            'save or discard the field.';

      case 'safety_stop':
        return 'Teaching was paused by a '
            'safety condition. Resolve the '
            'condition before resuming.';

      case 'paused':
      default:
        return 'Field recording is paused. '
            'Resume, save or discard '
            'the field.';
    }
  }

  bool get _canStartTeaching {
    return _globalAuto &&
        widget.fluidOperational &&
        !widget.fluidRecoveryRequired &&
        widget.espConnected &&
        !widget.missionActive &&
        !widget.manualOverride &&
        !_teaching;
  }

  bool get _canBrowseFields {
    return widget.connected && !_teaching;
  }

  bool get _canFinishTeaching {
    return widget.connected && _teaching;
  }

  bool get _canDiscardTeaching {
    return widget.connected && _teaching;
  }

  bool get _canPauseTeaching {
    return widget.connected &&
        _teaching &&
        widget.missionActive &&
        !widget.manualOverride;
  }

  bool get _canResumeTeaching {
    return _globalAuto &&
        widget.espConnected &&
        _teaching &&
        !widget.missionActive &&
        !widget.manualOverride &&
        widget.fluidOperational &&
        !widget.fluidRecoveryRequired;
  }

  bool get _canEndRow {
    return _globalAuto &&
        widget.espConnected &&
        _teaching &&
        widget.missionActive &&
        !widget.manualOverride;
  }

  bool get _canDriveManually {
    return widget.controlsVisible &&
        widget.fluidOperational &&
        _globalAuto &&
        widget.espConnected &&
        _teaching &&
        widget.missionActive &&
        widget.manualOverride;
  }

  bool get _canStartNextRow {
    return _canDriveManually;
  }

  FieldPanelMode get _fieldMode {
    if (_recordingRouteId != null) {
      return FieldPanelMode.recording;
    }

    if (_viewedRoute != null) {
      return FieldPanelMode.viewing;
    }

    return FieldPanelMode.empty;
  }

  @override
  void initState() {
    super.initState();

    _routeService = RouteService(host: widget.host, port: widget.port);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.connected) {
        _recoverRecordingState();
      }
    });
  }

  @override
  void didUpdateWidget(NavigationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final addressChanged =
        widget.host != oldWidget.host || widget.port != oldWidget.port;

    if (addressChanged) {
      _routeService.close();

      _routeService = RouteService(host: widget.host, port: widget.port);

      _stopLiveRoutePolling();

      _routes = [];
      _viewedRoute = null;
      _liveRoute = null;
      _recordingRouteId = null;
    }

    if (!widget.connected && oldWidget.connected) {
      _stopLiveRoutePolling();

      // Retain the open recording
      // visually while offline.
      setState(() {});

      return;
    }

    if (widget.connected && (!oldWidget.connected || addressChanged)) {
      _recoverRecordingState();
    }
  }

  @override
  void dispose() {
    _stopLiveRoutePolling();

    _routeService.close();

    super.dispose();
  }

  void _startLiveRoutePolling() {
    _stopLiveRoutePolling();

    _refreshLiveRoute();

    _liveRouteTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshLiveRoute();
    });
  }

  void _stopLiveRoutePolling() {
    _liveRouteTimer?.cancel();

    _liveRouteTimer = null;
  }

  Future<void> _recoverRecordingState() async {
    if (!widget.connected) {
      return;
    }

    try {
      final recording = await _routeService.getRecordingRoute();

      if (!mounted) {
        return;
      }

      if (recording == null) {
        _stopLiveRoutePolling();

        setState(() {
          _recordingRouteId = null;

          _liveRoute = null;
        });

        return;
      }

      setState(() {
        _recordingRouteId = recording.summary.id;

        _liveRoute = recording;

        _viewedRoute = null;
      });

      _startLiveRoutePolling();
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Could not recover active '
        'field recording: $error',
      );
    }
  }

  Future<void> _refreshLiveRoute() async {
    final routeId = _recordingRouteId;

    if (routeId == null || _pollingLiveRoute || !widget.connected) {
      return;
    }

    _pollingLiveRoute = true;

    try {
      final route = await _routeService.getRoute(routeId);

      if (!mounted || _recordingRouteId != routeId) {
        return;
      }

      setState(() {
        _liveRoute = route;
      });
    } catch (_) {
      // A UI refresh failure must
      // never stop the robot mission.
    } finally {
      _pollingLiveRoute = false;
    }
  }

  Future<void> _refreshRoutes() async {
    if (!widget.connected) {
      return;
    }

    setState(() {
      _loadingRoutes = true;
    });

    try {
      final routes = await _routeService.getRoutes();

      int? recordingId;

      for (final route in routes) {
        if (route.recording) {
          recordingId = route.id;

          break;
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _routes = routes;

        _recordingRouteId = recordingId;

        if (recordingId == null) {
          _liveRoute = null;
        }
      });

      if (recordingId != null) {
        _startLiveRoutePolling();
      } else {
        _stopLiveRoutePolling();
      }
    } catch (error) {
      _showMessage(
        'Could not refresh '
        'recorded fields: $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingRoutes = false;
        });
      }
    }
  }

  Future<void> _switchLibraryToTeach() async {
    Navigator.of(context).pop();

    await Future<void>.delayed(const Duration(milliseconds: 150));

    if (!mounted) {
      return;
    }

    await _openTeachField();
  }

  Future<void> _startRecording(String fieldName) async {
    if (!_canStartTeaching) {
      if (!_globalAuto) {
        _showMessage('Select AUTO first.');
      } else if (!widget.espConnected) {
        _showMessage(
          'ESP32 must be connected '
          'before teaching.',
        );
      } else {
        _showMessage(
          'Teaching is not '
          'available right now.',
        );
      }

      return;
    }

    try {
      final existing = await _routeService.getRecordingRoute();

      if (existing != null) {
        if (!mounted) {
          return;
        }

        setState(() {
          _recordingRouteId = existing.summary.id;

          _liveRoute = existing;

          _viewedRoute = null;
        });

        Navigator.of(context).pop();

        _startLiveRoutePolling();

        _showMessage(
          'An unfinished field '
          'recording was recovered. '
          'Save, resume or discard '
          'it first.',
        );

        return;
      }

      final route = await _routeService.startRoute(fieldName);

      if (!mounted) {
        return;
      }

      setState(() {
        _recordingRouteId = route.summary.id;

        _liveRoute = route;

        _viewedRoute = null;
      });

      Navigator.of(context).pop();

      _startLiveRoutePolling();

      widget.sendCommand(RobotCommand.startMission);

      _showMessage(
        'Teaching "$fieldName" '
        'started.',
      );
    } catch (error) {
      await _recoverRecordingState();

      _showMessage(
        'Could not start field '
        'teaching: $error',
      );
    }
  }

  Future<void> _finishRecording() async {
    final routeId = _recordingRouteId;

    if (routeId == null) {
      return;
    }

    try {
      widget.sendCommand(RobotCommand.stopMission);

      await Future<void>.delayed(const Duration(milliseconds: 650));

      final savedRoute = await _routeService.finishRoute(routeId);

      if (!mounted) {
        return;
      }

      _stopLiveRoutePolling();

      setState(() {
        _recordingRouteId = null;

        _liveRoute = null;

        _viewedRoute = savedRoute;
      });

      await _refreshRoutes();

      _showMessage('Field recording saved.');
    } catch (error) {
      _showMessage(
        'Could not finish '
        'field recording: $error',
      );
    }
  }

  void _pauseTeaching() {
    if (!_canPauseTeaching) {
      return;
    }

    widget.sendCommand(RobotCommand.stopMission);

    _showMessage(
      'Navigation paused. '
      'The field recording '
      'remains open.',
    );
  }

  void _resumeTeaching() {
    if (!_teaching) {
      return;
    }

    if (!_globalAuto) {
      _showMessage(
        'Select AUTO before '
        'resuming teaching.',
      );

      return;
    }

    if (!widget.espConnected) {
      _showMessage(
        'ESP32 must reconnect '
        'before navigation '
        'can resume.',
      );

      return;
    }

    if (!widget.fluidOperational || widget.fluidRecoveryRequired) {
      _showMessage(
        'Refill the tank before '
        'resuming teaching.',
      );

      return;
    }

    widget.sendCommand(RobotCommand.startMission);

    _showMessage(
      'Teaching resume '
      'requested.',
    );
  }

  Future<void> _discardRecording() async {
    final routeId = _recordingRouteId;

    if (routeId == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Discard field recording?'),
          content: const Text(
            'All points recorded for '
            'this unfinished field '
            'will be permanently '
            'deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Discard'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      if (widget.connected) {
        widget.sendCommand(RobotCommand.stopMission);

        await Future<void>.delayed(const Duration(milliseconds: 300));
      }

      await _routeService.discardRoute(routeId);

      if (!mounted) {
        return;
      }

      _stopLiveRoutePolling();

      setState(() {
        _recordingRouteId = null;

        _liveRoute = null;
      });

      await _refreshRoutes();

      _showMessage(
        'Field recording '
        'discarded.',
      );
    } catch (error) {
      _showMessage(
        'Could not discard '
        'field recording: $error',
      );
    }
  }

  Future<void> _viewRoute(RouteSummary summary) async {
    try {
      final route = await _routeService.getRoute(summary.id);

      if (!mounted) {
        return;
      }

      setState(() {
        _viewedRoute = route;
      });

      Navigator.of(context).pop();

      _showMessage(
        'Viewing '
        '${summary.name}.',
      );
    } catch (error) {
      _showMessage(
        'Could not open field: '
        '$error',
      );
    }
  }

  Future<void> _deleteRoute(RouteSummary route) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete recorded field?'),
          content: Text(
            'Permanently delete '
            '"${route.name}"?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _routeService.deleteRoute(route.id);

      if (!mounted) {
        return;
      }

      if (_viewedRoute?.summary.id == route.id) {
        setState(() {
          _viewedRoute = null;
        });
      }

      await _refreshRoutes();

      _showMessage('${route.name} deleted.');
    } catch (error) {
      _showMessage(
        'Could not delete field: '
        '$error',
      );
    }
  }

  Future<void> _endOfRow() async {
    if (!_canEndRow) {
      return;
    }

    final routeId = _recordingRouteId;

    if (routeId == null) {
      return;
    }

    widget.sendCommand(RobotCommand.manualOverride);

    try {
      await _routeService.addEvent(routeId, RouteEvent.rowEnd);

      await _routeService.addEvent(routeId, RouteEvent.manualControlStarted);
    } catch (_) {
      _showMessage(
        'Manual override started, '
        'but the row event could '
        'not be saved.',
      );
    }
  }

  Future<void> _startNextRow() async {
    if (!_canStartNextRow) {
      return;
    }

    final routeId = _recordingRouteId;

    if (routeId == null) {
      return;
    }

    widget.sendCommand('auto');

    try {
      await _routeService.addEvent(routeId, RouteEvent.nextRowStarted);
    } catch (_) {
      _showMessage(
        'AUTO resumed, but the '
        'next-row event could '
        'not be saved.',
      );
    }
  }

  Future<void> _showAdaptiveModal({
    required Widget child,
    double tabletWidth = 720,
  }) async {
    final width = MediaQuery.sizeOf(context).width;

    final isTablet = width >= 700;

    if (isTablet) {
      await showDialog(
        context: context,
        builder: (context) {
          return Dialog(
            insetPadding: const EdgeInsets.all(32),
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: tabletWidth,
                maxHeight: MediaQuery.sizeOf(context).height * 0.82,
              ),
              child: child,
            ),
          );
        },
      );

      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        final screenHeight = MediaQuery.sizeOf(context).height;

        return SafeArea(
          top: false,
          child: SizedBox(height: screenHeight * 0.82, child: child),
        );
      },
    );
  }

  Future<void> _openSavedFields() async {
    if (!_canBrowseFields) {
      _showMessage(
        'Finish the current '
        'teaching session first.',
      );

      return;
    }

    await _refreshRoutes();

    if (!mounted) {
      return;
    }

    await _showAdaptiveModal(
      child: _SavedFieldsModal(
        routes: _routes,
        loading: _loadingRoutes,
        onView: _viewRoute,
        onDelete: _deleteRoute,
        onTeach: _switchLibraryToTeach,
      ),
    );
  }

  Future<void> _openTeachField() async {
    if (!_canStartTeaching) {
      if (!_globalAuto) {
        _showMessage(
          'Select AUTO before '
          'teaching a new field.',
        );
      } else if (!widget.espConnected) {
        _showMessage(
          'ESP32 must be connected '
          'before teaching.',
        );
      } else {
        _showMessage(
          'Teaching is not '
          'available right now.',
        );
      }

      return;
    }

    await _showAdaptiveModal(
      tabletWidth: 560,
      child: _TeachFieldModal(onStart: _startRecording),
    );
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ResponsivePage(
      maxWidth: 900,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          _buildEnvironmentPanel(),
          const SizedBox(height: 22),
          _buildFieldPanel(),
          const SizedBox(height: 22),
          _buildOperatorPanel(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Navigation',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Field teaching & '
                'local awareness',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _StatusPill(
          text: widget.connected ? 'Connected' : 'Offline',
          active: widget.connected,
        ),
      ],
    );
  }

  Widget _buildEnvironmentPanel() {
    final perceptionOn = widget.connected && widget.perceptionActive;

    final lidarLive = widget.connected && widget.lidarConnected;

    String statusLabel;
    IconData statusIcon;
    Color statusColor;

    if (!widget.connected) {
      statusLabel = 'STANDBY';

      statusIcon = Icons.pause_circle_outline;

      statusColor = AppColors.textSecondary;
    } else if (lidarLive) {
      statusLabel = 'LIDAR LIVE';

      statusIcon = Icons.radar;

      statusColor = AppColors.green;
    } else if (widget.mappingActive) {
      statusLabel = 'TEACHING';

      statusIcon = Icons.route_outlined;

      statusColor = AppColors.green;
    } else {
      statusLabel = 'STANDBY';

      statusIcon = Icons.pause_circle_outline;

      statusColor = AppColors.textSecondary;
    }

    return NeuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: _PanelTitle(
                  icon: Icons.radar,
                  title: 'Local Environment',
                ),
              ),
              _SmallChip(
                label: statusLabel,
                icon: statusIcon,
                color: statusColor,
              ),
            ],
          ),
          const SizedBox(height: 16),
          AspectRatio(
            aspectRatio: 1.55,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.lightGreen,
                borderRadius: BorderRadius.circular(22),
              ),
              clipBehavior: Clip.antiAlias,
              child: lidarLive && widget.lidarPoints.isNotEmpty
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        CustomPaint(
                          painter: _LidarPainter(points: widget.lidarPoints),
                          child: const SizedBox.expand(),
                        ),
                        Positioned(
                          left: 12,
                          bottom: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surface.withValues(alpha: 0.90),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              '${widget.lidarPoints.length} points',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          lidarLive ? Icons.radar : Icons.radar_outlined,
                          size: 58,
                          color: lidarLive
                              ? AppColors.green
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          lidarLive
                              ? 'Waiting for scan points'
                              : 'LiDAR standby',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: lidarLive
                                ? AppColors.green
                                : AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          perceptionOn
                              ? 'Perception active'
                              : 'Local obstacle view',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldPanel() {
    return NeuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: _PanelTitle(
                  icon: Icons.map_outlined,
                  title: 'Recorded Field',
                ),
              ),
              _buildFieldStateChip(),
            ],
          ),
          const SizedBox(height: 15),
          AspectRatio(aspectRatio: 1.30, child: _buildFieldVisual()),
          const SizedBox(height: 16),
          _buildFieldMetadata(),
          const SizedBox(height: 16),
          _buildFieldActions(),
        ],
      ),
    );
  }

  Widget _buildFieldStateChip() {
    if (_fieldMode == FieldPanelMode.recording) {
      if (!widget.connected) {
        return const _SmallChip(
          label: 'OFFLINE',
          icon: Icons.cloud_off,
          color: AppColors.textSecondary,
        );
      }

      if (widget.manualOverride) {
        return const _SmallChip(
          label: 'MANUAL',
          icon: Icons.gamepad,
          color: AppColors.brown,
        );
      }

      if (widget.missionActive) {
        return const _SmallChip(
          label: 'RECORDING',
          icon: Icons.fiber_manual_record,
          color: Colors.red,
        );
      }

      return _SmallChip(
        label: _pauseChipLabel,
        icon: _pauseChipIcon,
        color: AppColors.brown,
      );
    }

    if (_fieldMode == FieldPanelMode.viewing) {
      return const _SmallChip(
        label: 'RECORDED',
        icon: Icons.check_circle_outline,
        color: AppColors.green,
      );
    }

    return const _SmallChip(
      label: 'NO FIELD',
      icon: Icons.map_outlined,
      color: AppColors.textSecondary,
    );
  }

  Widget _buildFieldVisual() {
    final route =
        _fieldMode == FieldPanelMode.recording ? _liveRoute : _viewedRoute;

    if (route != null && route.points.isNotEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.lightGreen,
          borderRadius: BorderRadius.circular(22),
        ),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          painter: _RoutePainter(points: route.points),
          child: const SizedBox.expand(),
        ),
      );
    }

    if (_fieldMode == FieldPanelMode.recording) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.lightGreen,
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.route, size: 72, color: Color(0x443E7B50)),
            SizedBox(height: 12),
            Text(
              'Teaching field',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 5),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'The estimated path '
                'will appear as POSE '
                'samples are recorded.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.map_outlined, size: 62, color: AppColors.green),
          const SizedBox(height: 14),
          const Text(
            'No field selected',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _globalAuto
                  ? 'Teach a new field '
                      'or view a recording'
                  : 'Recorded fields can '
                      'be viewed at any time',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldMetadata() {
    if (_fieldMode == FieldPanelMode.recording && _liveRoute != null) {
      final metrics = _MapMetrics.fromPoints(_liveRoute!.points);

      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _InfoChip(
            icon: Icons.straighten,
            text: 'Approx. ${metrics.lengthM.toStringAsFixed(2)} m long',
          ),
          _InfoChip(
            icon: Icons.swap_horiz,
            text: 'Approx. ${metrics.widthM.toStringAsFixed(2)} m wide',
          ),
          _InfoChip(
            icon: Icons.route,
            text: '${metrics.distanceM.toStringAsFixed(2)} m travelled',
          ),
          _InfoChip(
            icon: Icons.location_on_outlined,
            text: '${_liveRoute!.points.length} points',
          ),
        ],
      );
    }

    if (_viewedRoute != null) {
      final summary = _viewedRoute!.summary;

      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _InfoChip(
            icon: Icons.straighten,
            text:
                'Approx. ${summary.approximateLengthM.toStringAsFixed(2)} m long',
          ),
          _InfoChip(
            icon: Icons.swap_horiz,
            text:
                'Approx. ${summary.approximateWidthM.toStringAsFixed(2)} m wide',
          ),
          _InfoChip(
            icon: Icons.route,
            text: '${summary.totalDistanceM.toStringAsFixed(2)} m travelled',
          ),
          _InfoChip(icon: Icons.grass, text: '${summary.rowCount} rows'),
        ],
      );
    }

    return const Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _InfoChip(icon: Icons.save_outlined, text: 'Teach & save'),
        _InfoChip(icon: Icons.visibility_outlined, text: 'View recordings'),
        _InfoChip(icon: Icons.straighten, text: 'Approx. dimensions'),
      ],
    );
  }

  Widget _buildFieldActions() {
    switch (_fieldMode) {
      case FieldPanelMode.empty:
        return Row(
          children: [
            Expanded(
              child: _PrimaryButton(
                label: 'Teach New Field',
                icon: Icons.add_road,
                enabled: _canStartTeaching,
                onPressed: _openTeachField,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SecondaryButton(
                label: 'Recorded Fields',
                icon: Icons.folder_open,
                enabled: _canBrowseFields,
                onPressed: _openSavedFields,
              ),
            ),
          ],
        );

      case FieldPanelMode.recording:
        return Column(
          children: [
            if (!widget.missionActive &&
                widget.connected &&
                !widget.manualOverride)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_pauseChipIcon, color: AppColors.brown),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _pauseDescription,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (widget.missionActive && !widget.manualOverride)
              SizedBox(
                width: double.infinity,
                child: _SecondaryButton(
                  label: 'Pause Navigation',
                  icon: Icons.pause,
                  enabled: _canPauseTeaching,
                  onPressed: _pauseTeaching,
                ),
              ),
            if (!widget.missionActive && !widget.manualOverride)
              SizedBox(
                width: double.infinity,
                child: _PrimaryButton(
                  label: 'Resume Teaching',
                  icon: Icons.play_arrow,
                  enabled: _canResumeTeaching,
                  onPressed: _resumeTeaching,
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _PrimaryButton(
                    label: 'Save Field',
                    icon: Icons.save_outlined,
                    enabled: _canFinishTeaching,
                    color: AppColors.brown,
                    onPressed: _finishRecording,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SecondaryButton(
                    label: 'Discard',
                    icon: Icons.delete_outline,
                    enabled: _canDiscardTeaching,
                    onPressed: _discardRecording,
                  ),
                ),
              ],
            ),
          ],
        );

      case FieldPanelMode.viewing:
        return Row(
          children: [
            Expanded(
              child: _SecondaryButton(
                label: 'Recorded Fields',
                icon: Icons.folder_open,
                enabled: widget.connected,
                onPressed: _openSavedFields,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PrimaryButton(
                label: 'Teach New Field',
                icon: Icons.add_road,
                enabled: _canStartTeaching,
                onPressed: _openTeachField,
              ),
            ),
          ],
        );
    }
  }

  Widget _buildOperatorPanel() {
    final statusText = !_teaching
        ? 'No active teaching session'
        : !widget.connected
            ? 'Recording retained - '
                'Pi connection unavailable'
            : widget.manualOverride
                ? _pauseDescription
                : widget.missionActive
                    ? 'Autonomous field teaching'
                    : _pauseDescription;

    return NeuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: _PanelTitle(
                  icon: Icons.gamepad_outlined,
                  title: 'Operator Override',
                ),
              ),
              _SmallChip(
                label: widget.manualOverride ? 'MANUAL OVERRIDE' : 'LOCKED',
                icon:
                    widget.manualOverride ? Icons.gamepad : Icons.lock_outline,
                color: widget.manualOverride
                    ? AppColors.brown
                    : AppColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            statusText,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          Center(child: _buildDirectionPad()),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _PrimaryButton(
                  label: 'End of Row',
                  icon: Icons.u_turn_right,
                  color: AppColors.brown,
                  enabled: _canEndRow,
                  onPressed: _endOfRow,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PrimaryButton(
                  label: 'Start Next Row',
                  icon: Icons.double_arrow,
                  enabled: _canStartNextRow,
                  onPressed: _startNextRow,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionPad() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DirectionButton(
          icon: Icons.keyboard_arrow_up,
          enabled: _canDriveManually,
          onPressStart: () {
            widget.sendCommand(RobotCommand.forward);
          },
          onPressEnd: () {
            widget.sendCommand(RobotCommand.stopMotion);
          },
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DirectionButton(
              icon: Icons.keyboard_arrow_left,
              enabled: _canDriveManually,
              onPressStart: () {
                widget.sendCommand(RobotCommand.left);
              },
              onPressEnd: () {
                widget.sendCommand(RobotCommand.stopMotion);
              },
            ),
            _DirectionButton(
              icon: Icons.stop,
              enabled: widget.connected,
              color: AppColors.brown,
              onPressStart: () {
                widget.sendCommand(RobotCommand.stopMotion);
              },
              onPressEnd: () {},
            ),
            _DirectionButton(
              icon: Icons.keyboard_arrow_right,
              enabled: _canDriveManually,
              onPressStart: () {
                widget.sendCommand(RobotCommand.right);
              },
              onPressEnd: () {
                widget.sendCommand(RobotCommand.stopMotion);
              },
            ),
          ],
        ),
        _DirectionButton(
          icon: Icons.keyboard_arrow_down,
          enabled: _canDriveManually,
          onPressStart: () {
            widget.sendCommand(RobotCommand.reverse);
          },
          onPressEnd: () {
            widget.sendCommand(RobotCommand.stopMotion);
          },
        ),
      ],
    );
  }
}

// ======================================================================
// SAVED FIELDS
// ======================================================================

class _SavedFieldsModal extends StatelessWidget {
  final VoidCallback onTeach;

  final List<RouteSummary> routes;

  final bool loading;

  final Future<void> Function(RouteSummary route) onView;

  final Future<void> Function(RouteSummary route) onDelete;

  const _SavedFieldsModal({
    required this.routes,
    required this.loading,
    required this.onView,
    required this.onDelete,
    required this.onTeach,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Recorded Fields',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Saved field maps can '
              'be viewed or deleted.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: _PrimaryButton(
              label: 'Teach New Field',
              icon: Icons.add_road,
              enabled: true,
              onPressed: onTeach,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Divider(color: Colors.black.withValues(alpha: 0.08)),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'RECORDED FIELDS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: Divider(color: Colors.black.withValues(alpha: 0.08)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.green),
                  )
                : routes.isEmpty
                    ? const Center(
                        child: Text(
                          'No recorded '
                          'fields yet.',
                        ),
                      )
                    : ListView.separated(
                        itemCount: routes.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final route = routes[index];

                          return _SavedFieldTile(
                            route: route,
                            onView: () {
                              onView(route);
                            },
                            onDelete: () {
                              onDelete(route);
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _SavedFieldTile extends StatelessWidget {
  final RouteSummary route;

  final VoidCallback onView;
  final VoidCallback onDelete;

  const _SavedFieldTile({
    required this.route,
    required this.onView,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            offset: const Offset(4, 6),
            blurRadius: 14,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.map_outlined, color: AppColors.green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      route.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Approx. '
                      '${route.approximateLengthM.toStringAsFixed(2)} × '
                      '${route.approximateWidthM.toStringAsFixed(2)} m'
                      ' • '
                      '${route.totalDistanceM.toStringAsFixed(1)} m travelled',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'delete') {
                    onDelete();
                  }
                },
                itemBuilder: (context) {
                  return const [
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline),
                          SizedBox(width: 8),
                          Text('Delete'),
                        ],
                      ),
                    ),
                  ];
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: _PrimaryButton(
              label: 'View Field',
              icon: Icons.visibility_outlined,
              enabled: true,
              onPressed: onView,
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// TEACH FIELD
// ======================================================================

class _TeachFieldModal extends StatefulWidget {
  final Future<void> Function(String fieldName) onStart;

  const _TeachFieldModal({required this.onStart});

  @override
  State<_TeachFieldModal> createState() => _TeachFieldModalState();
}

class _TeachFieldModalState extends State<_TeachFieldModal> {
  final TextEditingController _controller = TextEditingController();

  bool _starting = false;

  @override
  void dispose() {
    _controller.dispose();

    super.dispose();
  }

  Future<void> _start() async {
    final name = _controller.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a field name.')));

      return;
    }

    setState(() {
      _starting = true;
    });

    await widget.onStart(name);

    if (mounted) {
      setState(() {
        _starting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Teach New Field',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'The robot will navigate '
            'autonomously while its '
            'estimated field path is '
            'recorded.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Field name',
              hintText: 'Example: Test Field',
              prefixIcon: Icon(Icons.edit_road),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.lightGreen,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: AppColors.green),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Field dimensions are '
                    'estimated from the '
                    'recorded robot motion. '
                    'LiDAR and ultrasonic '
                    'navigation remain active '
                    'during teaching.',
                    style: TextStyle(height: 1.45),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: _PrimaryButton(
              label: _starting ? 'Starting...' : 'Start Autonomous Teaching',
              icon: Icons.fiber_manual_record,
              enabled: !_starting,
              onPressed: _start,
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// MAP METRICS
// ======================================================================

class _MapMetrics {
  final double lengthM;
  final double widthM;
  final double distanceM;

  const _MapMetrics({
    required this.lengthM,
    required this.widthM,
    required this.distanceM,
  });

  factory _MapMetrics.fromPoints(List<RoutePoint> points) {
    if (points.isEmpty) {
      return const _MapMetrics(lengthM: 0.0, widthM: 0.0, distanceM: 0.0);
    }

    var minX = points.first.xCm;

    var maxX = points.first.xCm;

    var minY = points.first.yCm;

    var maxY = points.first.yCm;

    var distanceCm = points.first.distanceCm;

    for (final point in points) {
      minX = math.min(minX, point.xCm);

      maxX = math.max(maxX, point.xCm);

      minY = math.min(minY, point.yCm);

      maxY = math.max(maxY, point.yCm);

      distanceCm = math.max(distanceCm, point.distanceCm);
    }

    return _MapMetrics(
      lengthM: (maxX - minX) / 100.0,
      widthM: (maxY - minY) / 100.0,
      distanceM: distanceCm / 100.0,
    );
  }
}

// ======================================================================
// SHARED UI
// ======================================================================

class _PanelTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _PanelTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.green),
        const SizedBox(width: 9),
        Flexible(
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String text;
  final bool active;

  const _StatusPill({required this.text, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: active ? AppColors.lightGreen : Colors.black12,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.circle,
            size: 9,
            color: active ? AppColors.green : AppColors.textSecondary,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: active ? AppColors.green : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _SmallChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.green),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool enabled;

  final VoidCallback onPressed;

  final Color color;

  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
    this.color = AppColors.green,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 19),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.black12,
          disabledForegroundColor: AppColors.textSecondary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool enabled;

  final VoidCallback onPressed;

  const _SecondaryButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 19),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.green,
          side: BorderSide(
            color: enabled
                ? AppColors.green.withValues(alpha: 0.35)
                : Colors.black12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
    );
  }
}

class _DirectionButton extends StatefulWidget {
  final IconData icon;

  final bool enabled;

  final VoidCallback onPressStart;

  final VoidCallback onPressEnd;

  final Color color;

  const _DirectionButton({
    required this.icon,
    required this.enabled,
    required this.onPressStart,
    required this.onPressEnd,
    this.color = AppColors.green,
  });

  @override
  State<_DirectionButton> createState() => _DirectionButtonState();
}

class _DirectionButtonState extends State<_DirectionButton> {
  bool _pressed = false;

  void _startPress() {
    if (!widget.enabled || _pressed) {
      return;
    }

    setState(() {
      _pressed = true;
    });

    widget.onPressStart();
  }

  void _endPress() {
    if (!_pressed) {
      return;
    }

    setState(() {
      _pressed = false;
    });

    widget.onPressEnd();
  }

  @override
  void didUpdateWidget(covariant _DirectionButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!widget.enabled && _pressed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pressed) {
          _endPress();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: widget.enabled ? 1.0 : 0.32,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.enabled
            ? (_) {
                _startPress();
              }
            : null,
        onTapUp: widget.enabled
            ? (_) {
                _endPress();
              }
            : null,
        onTapCancel: widget.enabled ? _endPress : null,
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 80),
          child: Container(
            width: 62,
            height: 62,
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(19),
              border:
                  _pressed ? Border.all(color: widget.color, width: 1.5) : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _pressed ? 0.03 : 0.06),
                  offset: _pressed ? const Offset(2, 2) : const Offset(5, 5),
                  blurRadius: _pressed ? 6 : 12,
                ),
              ],
            ),
            child: Icon(widget.icon, size: 29, color: widget.color),
          ),
        ),
      ),
    );
  }
}

// ======================================================================
// LIDAR
// ======================================================================

class _LidarPainter extends CustomPainter {
  final List<LidarPoint> points;

  const _LidarPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    const maxRangeM = 3.0;

    final radius = math.min(size.width, size.height) * 0.43;

    final gridPaint = Paint()
      ..color = AppColors.green.withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final fraction in [1 / 3, 2 / 3, 1.0]) {
      canvas.drawCircle(center, radius * fraction, gridPaint);
    }

    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      gridPaint,
    );

    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      gridPaint,
    );

    final pointPaint = Paint()
      ..color = AppColors.green
      ..style = PaintingStyle.fill;

    final scale = radius / maxRangeM;

    for (final point in points) {
      final distanceM = point.distanceMm / 1000.0;

      if (distanceM <= 0 || distanceM > maxRangeM) {
        continue;
      }

      final screenPoint = Offset(
        center.dx + point.yM * scale,
        center.dy - point.xM * scale,
      );

      canvas.drawCircle(screenPoint, 2.2, pointPaint);
    }

    final robotPaint = Paint()
      ..color = AppColors.brown
      ..style = PaintingStyle.fill;

    final robotBody = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 18, height: 28),
      const Radius.circular(6),
    );

    canvas.drawRRect(robotBody, robotPaint);

    final headingPaint = Paint()
      ..color = AppColors.brown
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(center, Offset(center.dx, center.dy - 22), headingPaint);
  }

  @override
  bool shouldRepaint(covariant _LidarPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}

// ======================================================================
// DIMENSIONALLY SCALED ROUTE MAP
// ======================================================================

class _RoutePainter extends CustomPainter {
  final List<RoutePoint> points;

  const _RoutePainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) {
      return;
    }

    const padding = 30.0;

    var minX = points.first.xCm;

    var maxX = points.first.xCm;

    var minY = points.first.yCm;

    var maxY = points.first.yCm;

    for (final point in points) {
      minX = math.min(minX, point.xCm);

      maxX = math.max(maxX, point.xCm);

      minY = math.min(minY, point.yCm);

      maxY = math.max(maxY, point.yCm);
    }

    var forwardSpan = maxX - minX;

    var lateralSpan = maxY - minY;

    forwardSpan = math.max(forwardSpan, 50.0);

    lateralSpan = math.max(lateralSpan, 50.0);

    final availableWidth = size.width - padding * 2;

    final availableHeight = size.height - padding * 2;

    final scale = math.min(
      availableWidth / lateralSpan,
      availableHeight / forwardSpan,
    );

    final centerXcm = (minX + maxX) / 2;

    final centerYcm = (minY + maxY) / 2;

    final screenCenter = Offset(size.width / 2, size.height / 2);

    Offset convert(RoutePoint point) {
      return Offset(
        screenCenter.dx + (point.yCm - centerYcm) * scale,
        screenCenter.dy - (point.xCm - centerXcm) * scale,
      );
    }

    final gridPaint = Paint()
      ..color = AppColors.green.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    const gridCm = 100.0;

    final leftCm = centerYcm - availableWidth / scale / 2;

    final rightCm = centerYcm + availableWidth / scale / 2;

    final bottomCm = centerXcm - availableHeight / scale / 2;

    final topCm = centerXcm + availableHeight / scale / 2;

    var gridY = (leftCm / gridCm).floor() * gridCm;

    while (gridY <= rightCm) {
      final screenX = screenCenter.dx + (gridY - centerYcm) * scale;

      canvas.drawLine(
        Offset(screenX, padding),
        Offset(screenX, size.height - padding),
        gridPaint,
      );

      gridY += gridCm;
    }

    var gridX = (bottomCm / gridCm).floor() * gridCm;

    while (gridX <= topCm) {
      final screenY = screenCenter.dy - (gridX - centerXcm) * scale;

      canvas.drawLine(
        Offset(padding, screenY),
        Offset(size.width - padding, screenY),
        gridPaint,
      );

      gridX += gridCm;
    }

    final boundaryPaint = Paint()
      ..color = AppColors.green.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final physicalWidthPx = (maxY - minY) * scale;

    final physicalHeightPx = (maxX - minX) * scale;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: screenCenter,
          width: math.max(physicalWidthPx, 6),
          height: math.max(physicalHeightPx, 6),
        ),
        const Radius.circular(8),
      ),
      boundaryPaint,
    );

    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];

      final current = points[i];

      final manual = current.mode.toUpperCase() == 'MANUAL' ||
          previous.mode.toUpperCase() == 'MANUAL';

      final segmentPaint = Paint()
        ..color = manual ? AppColors.brown : AppColors.green
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(convert(previous), convert(current), segmentPaint);
    }

    final first = convert(points.first);

    final last = convert(points.last);

    canvas.drawCircle(first, 7, Paint()..color = AppColors.green);

    canvas.drawCircle(last, 7, Paint()..color = AppColors.brown);

    final heading = points.last.headingDeg * math.pi / 180.0;

    const arrowLength = 20.0;

    final arrowEnd = Offset(
      last.dx + arrowLength * math.sin(heading),
      last.dy - arrowLength * math.cos(heading),
    );

    canvas.drawLine(
      last,
      arrowEnd,
      Paint()
        ..color = AppColors.brown
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) {
    return oldDelegate.points != points;
  }
}
