import 'package:flutter/material.dart';

import '../models/robot_status.dart';
import '../theme/app_colors.dart';

class FluidSensorTile extends StatelessWidget {
  final RobotStatus status;
  final bool online;
  final bool pending;
  final VoidCallback? onToggle;
  const FluidSensorTile({
    super.key,
    required this.status,
    required this.online,
    required this.pending,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    String label;
    IconData icon;
    Color color;
    if (!online) {
      label = 'Unavailable';
      icon = Icons.sensors_off;
      color = AppColors.textSecondary;
    } else if (!status.fluidSensorEnabled) {
      label = 'Bypassed';
      icon = Icons.sensors_off;
      color = AppColors.brown;
    } else if (status.fluidRecoveryRequired && status.fluidAvailable) {
      label = 'Refill ready';
      icon = Icons.water_drop;
      color = AppColors.brown;
    } else if (status.fluidState == 'empty_confirmed') {
      label = 'Empty';
      icon = Icons.water_drop_outlined;
      color = AppColors.danger;
    } else if (status.fluidOperational) {
      label = 'Fluid available';
      icon = Icons.water_drop;
      color = AppColors.green;
    } else {
      label = 'Checking level';
      icon = Icons.hourglass_top;
      color = AppColors.textSecondary;
    }
    final action = status.fluidSensorEnabled
        ? 'Bypass level sensor'
        : 'Enable level sensor';
    return Semantics(
      button: true,
      enabled: onToggle != null,
      toggled: status.fluidSensorEnabled,
      label: 'Level sensor, $label',
      child: Tooltip(
        message: onToggle == null
            ? 'Sensor control requires manual mode'
            : action,
        child: TextButton(
          onPressed: pending ? null : onToggle,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            foregroundColor: color,
            minimumSize: const Size(48, 110),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'LEVEL SENSOR',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: pending
                    ? const SizedBox(
                        key: ValueKey('pending'),
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(icon, key: ValueKey(label), size: 28, color: color),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (online)
                Text(
                  status.fluidSensorEnabled ? 'Sensor on' : 'Sensor off',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
