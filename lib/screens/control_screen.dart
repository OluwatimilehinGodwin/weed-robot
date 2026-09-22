import 'package:flutter/material.dart';

import '../core/app_config.dart';
import '../theme/app_colors.dart';
import '../widgets/manual_sprayer_panel.dart';
import '../widgets/neu_card.dart';
import '../widgets/responsive_page.dart';

class ControlScreen extends StatelessWidget {
  final Widget sprayControl;
  final bool motionAllowed;
  final bool controlsVisible;
  final bool connected;
  final bool espConnected;
  final String mode;
  final String railOrientation;
  final bool aimAllowed;
  final String aimUnavailableReason;

  final void Function(String command) sendCommand;

  const ControlScreen({
    super.key,
    required this.sprayControl,
    required this.motionAllowed,
    required this.controlsVisible,
    required this.connected,
    required this.espConnected,
    required this.mode,
    required this.sendCommand,
    this.railOrientation = 'unknown',
    this.aimAllowed = false,
    this.aimUnavailableReason = 'Spray rail unavailable',
  });

  bool get _manualMode {
    return connected && mode.toLowerCase() == 'manual';
  }

  bool get _autoMode {
    return connected && mode.toLowerCase() == 'auto';
  }

  bool get _manualEnabled {
    return _manualMode && espConnected && motionAllowed && controlsVisible;
  }

  @override
  Widget build(BuildContext context) {
    return ResponsivePage(
      maxWidth: 900,
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildModePanel(),
          const SizedBox(height: 16),
          _buildControlWorkspace(),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _buildControlWorkspace() {
    final movementPanel = _buildManualControlPanel();

    final sprayerPanel = ManualSprayerPanel(
      sprayControl: sprayControl,
      railOrientation: railOrientation,
      manualMode: _manualMode,
      aimEnabled: _manualMode && aimAllowed && controlsVisible,
      unavailableReason:
          !_manualMode ? 'Manual mode only' : aimUnavailableReason,
      onHorizontal: () {
        sendCommand(
          RobotCommand.targetWeed,
        );
      },
      onVertical: () {
        sendCommand(
          RobotCommand.targetMaize,
        );
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackPanels = constraints.maxWidth < 680 ||
            MediaQuery.textScalerOf(
                  context,
                ).scale(14) >
                19;

        if (stackPanels) {
          return Column(
            children: [
              movementPanel,
              const SizedBox(height: 14),
              sprayerPanel,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 10,
              child: movementPanel,
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 12,
              child: sprayerPanel,
            ),
          ],
        );
      },
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
                'Control',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Operating mode and drive control',
                style: TextStyle(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _StatusPill(
          text: connected ? 'Connected' : 'Offline',
          active: connected,
        ),
      ],
    );
  }

  Widget _buildModePanel() {
    String stateText;
    IconData stateIcon;
    Color stateColor;

    if (!connected) {
      stateText = 'OFFLINE';
      stateIcon = Icons.cloud_off_outlined;
      stateColor = AppColors.textSecondary;
    } else if (_autoMode) {
      stateText = 'AUTO SETUP';
      stateIcon = Icons.smart_toy_outlined;
      stateColor = AppColors.green;
    } else {
      stateText = 'MANUAL';
      stateIcon = Icons.gamepad_outlined;
      stateColor = AppColors.brown;
    }

    return NeuCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: _PanelTitle(
                  icon: Icons.tune,
                  title: 'Operating Mode',
                ),
              ),
              _SmallChip(
                label: stateText,
                icon: stateIcon,
                color: stateColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final manualButton = _ModeButton(
                label: 'MANUAL',
                icon: Icons.gamepad_outlined,
                selected: _manualMode,
                enabled: connected,
                color: AppColors.brown,
                onPressed: () {
                  sendCommand(
                    RobotCommand.manualMode,
                  );
                },
              );

              final autoButton = _ModeButton(
                label: 'AUTO',
                icon: Icons.smart_toy_outlined,
                selected: _autoMode,
                enabled: connected,
                color: AppColors.green,
                onPressed: () {
                  sendCommand(
                    RobotCommand.autoMode,
                  );
                },
              );

              final stackButtons = constraints.maxWidth < 310 ||
                  MediaQuery.textScalerOf(
                        context,
                      ).scale(14) >
                      20;

              if (stackButtons) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    manualButton,
                    const SizedBox(height: 8),
                    autoButton,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: manualButton,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: autoButton,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildManualControlPanel() {
    return NeuCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: _PanelTitle(
                  icon: Icons.gamepad_outlined,
                  title: 'Movement',
                ),
              ),
              _SmallChip(
                label: _manualEnabled ? 'READY' : 'LOCKED',
                icon: _manualEnabled ? Icons.lock_open : Icons.lock_outline,
                color:
                    _manualEnabled ? AppColors.green : AppColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _EspStatus(
            connected: espConnected,
          ),
          const SizedBox(height: 12),
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _buildDirectionPad(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionPad() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HoldDirectionButton(
          icon: Icons.keyboard_arrow_up,
          enabled: _manualEnabled,
          onPressStart: () {
            sendCommand(
              RobotCommand.forward,
            );
          },
          onPressEnd: () {
            sendCommand(
              RobotCommand.stopMotion,
            );
          },
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HoldDirectionButton(
              icon: Icons.keyboard_arrow_left,
              enabled: _manualEnabled,
              onPressStart: () {
                sendCommand(
                  RobotCommand.left,
                );
              },
              onPressEnd: () {
                sendCommand(
                  RobotCommand.stopMotion,
                );
              },
            ),
            _HoldDirectionButton(
              icon: Icons.stop,
              enabled: connected,
              color: AppColors.brown,
              onPressStart: () {
                sendCommand(
                  RobotCommand.stopMotion,
                );
              },
              onPressEnd: () {},
            ),
            _HoldDirectionButton(
              icon: Icons.keyboard_arrow_right,
              enabled: _manualEnabled,
              onPressStart: () {
                sendCommand(
                  RobotCommand.right,
                );
              },
              onPressEnd: () {
                sendCommand(
                  RobotCommand.stopMotion,
                );
              },
            ),
          ],
        ),
        _HoldDirectionButton(
          icon: Icons.keyboard_arrow_down,
          enabled: _manualEnabled,
          onPressStart: () {
            sendCommand(
              RobotCommand.reverse,
            );
          },
          onPressEnd: () {
            sendCommand(
              RobotCommand.stopMotion,
            );
          },
        ),
      ],
    );
  }
}

class _EspStatus extends StatelessWidget {
  final bool connected;

  const _EspStatus({
    required this.connected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: connected
            ? AppColors.lightGreen
            : Colors.black.withValues(
                alpha: 0.04,
              ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            connected ? Icons.developer_board : Icons.developer_board_off,
            size: 18,
            color: connected ? AppColors.green : AppColors.textSecondary,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              connected ? 'ESP32 ready' : 'ESP32 unavailable',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: connected ? AppColors.green : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HoldDirectionButton extends StatefulWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressStart;
  final VoidCallback onPressEnd;
  final Color color;

  const _HoldDirectionButton({
    required this.icon,
    required this.enabled,
    required this.onPressStart,
    required this.onPressEnd,
    this.color = AppColors.green,
  });

  @override
  State<_HoldDirectionButton> createState() {
    return _HoldDirectionButtonState();
  }
}

class _HoldDirectionButtonState extends State<_HoldDirectionButton> {
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
  void didUpdateWidget(
    covariant _HoldDirectionButton oldWidget,
  ) {
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
      opacity: widget.enabled ? 1 : 0.32,
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
          scale: _pressed ? 0.94 : 1,
          duration: const Duration(
            milliseconds: 80,
          ),
          child: Container(
            width: 58,
            height: 58,
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: _pressed
                  ? Border.all(
                      color: widget.color,
                      width: 1.5,
                    )
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: _pressed ? 0.03 : 0.06,
                  ),
                  offset: _pressed ? const Offset(2, 2) : const Offset(5, 5),
                  blurRadius: _pressed ? 6 : 12,
                ),
              ],
            ),
            child: Icon(
              widget.icon,
              size: 28,
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _PanelTitle({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 21,
          color: AppColors.green,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String text;
  final bool active;

  const _StatusPill({
    required this.text,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: active ? AppColors.lightGreen : Colors.black12,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.circle,
            size: 8,
            color: active ? AppColors.green : AppColors.textSecondary,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
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
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.10,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final Color color;
  final VoidCallback onPressed;

  const _ModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: 44,
      ),
      child: selected
          ? ElevatedButton.icon(
              // Selected mode remains visible but
              // cannot be redundantly selected.
              onPressed: null,
              icon: Icon(
                icon,
                size: 18,
              ),
              label: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                ),
              ),
              style: ElevatedButton.styleFrom(
                disabledBackgroundColor: color,
                disabledForegroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
            )
          : OutlinedButton.icon(
              onPressed: enabled ? onPressed : null,
              icon: Icon(
                icon,
                size: 18,
              ),
              label: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(
                  color: enabled
                      ? color.withValues(
                          alpha: 0.35,
                        )
                      : Colors.black12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
            ),
    );
  }
}
