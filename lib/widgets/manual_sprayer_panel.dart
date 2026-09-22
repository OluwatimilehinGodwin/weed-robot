import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'neu_card.dart';

class ManualSprayerPanel extends StatelessWidget {
  final Widget sprayControl;
  final String railOrientation;
  final bool manualMode;
  final bool aimEnabled;
  final String unavailableReason;
  final VoidCallback onHorizontal;
  final VoidCallback onVertical;

  const ManualSprayerPanel({
    super.key,
    required this.sprayControl,
    required this.railOrientation,
    required this.manualMode,
    required this.aimEnabled,
    required this.unavailableReason,
    required this.onHorizontal,
    required this.onVertical,
  });

  @override
  Widget build(BuildContext context) {
    final orientation = railOrientation.trim().toLowerCase();

    final horizontal = orientation == 'horizontal';

    final vertical = orientation == 'vertical';

    final stateLabel = !manualMode
        ? 'MANUAL ONLY'
        : aimEnabled
            ? 'READY'
            : 'LOCKED';

    final stateColor = aimEnabled ? AppColors.green : AppColors.textSecondary;

    return NeuCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.tune_rounded,
                size: 21,
                color: AppColors.green,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Manual sprayer',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              _StatusBadge(
                label: stateLabel,
                color: stateColor,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Rail orientation',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Text(
                orientation.isEmpty ? 'UNKNOWN' : orientation.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final horizontalChoice = _OrientationChoice(
                title: 'HORIZONTAL',
                subtitle: 'WEEDS',
                icon: Icons.swap_horiz_rounded,
                selected: horizontal,
                enabled: aimEnabled,
                color: AppColors.green,
                onTap: horizontal ? null : onHorizontal,
              );

              final verticalChoice = _OrientationChoice(
                title: 'VERTICAL',
                subtitle: 'MAIZE',
                icon: Icons.swap_vert_rounded,
                selected: vertical,
                enabled: aimEnabled,
                color: AppColors.brown,
                onTap: vertical ? null : onVertical,
              );

              final stackChoices = constraints.maxWidth < 290 ||
                  MediaQuery.textScalerOf(
                        context,
                      ).scale(12) >
                      17;

              if (stackChoices) {
                return Column(
                  children: [
                    horizontalChoice,
                    const SizedBox(height: 8),
                    verticalChoice,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: horizontalChoice,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: verticalChoice,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 7),
          Text(
            aimEnabled ? 'Select the spray direction' : unavailableReason,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Divider(
            height: 1,
            color: Colors.black.withValues(
              alpha: 0.06,
            ),
          ),
          const SizedBox(height: 12),
          sprayControl,
        ],
      ),
    );
  }
}

class _OrientationChoice extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final Color color;
  final VoidCallback? onTap;

  const _OrientationChoice({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final interactive = enabled && onTap != null;

    return Semantics(
      button: true,
      selected: selected,
      enabled: interactive,
      label: '$title orientation for $subtitle',
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: enabled || selected ? 1 : 0.48,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: interactive ? onTap : null,
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(
                milliseconds: 200,
              ),
              constraints: const BoxConstraints(
                minHeight: 58,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 9,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? color.withValues(alpha: 0.12)
                    : Colors.black.withValues(
                        alpha: 0.025,
                      ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  width: selected ? 1.4 : 1,
                  color: selected
                      ? color.withValues(
                          alpha: 0.55,
                        )
                      : Colors.black.withValues(
                          alpha: 0.07,
                        ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: selected ? color : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: selected ? color : AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({
    required this.label,
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
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}
