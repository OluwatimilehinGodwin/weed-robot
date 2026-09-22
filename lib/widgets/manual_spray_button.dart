import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class ManualSprayButton extends StatelessWidget {
  final bool online;
  final bool pumpOn;
  final bool requested;
  final bool pending;
  final bool stopping;
  final bool manual;
  final bool available;
  final String unavailableReason;
  final VoidCallback? onPressed;

  const ManualSprayButton({
    super.key,
    required this.online,
    required this.pumpOn,
    required this.requested,
    required this.pending,
    required this.stopping,
    required this.manual,
    required this.available,
    required this.unavailableReason,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final active = pumpOn || requested;
    final enabled = onPressed != null;

    final stateLabel = pending
        ? (stopping ? 'STOPPING' : 'STARTING')
        : pumpOn
            ? 'ON'
            : requested
                ? 'REQUESTED'
                : 'OFF';

    final detail = !manual
        ? 'Manual mode only'
        : !online
            ? 'ESP32 unavailable'
            : pending
                ? (stopping ? 'Stopping pump…' : 'Starting pump…')
                : active
                    ? 'Tap to turn off'
                    : available
                        ? 'Tap to turn on'
                        : unavailableReason;

    final accent = active ? AppColors.green : AppColors.brown;

    return Semantics(
      button: true,
      enabled: enabled,
      toggled: pumpOn,
      liveRegion: true,
      label: 'Manual sprayer $stateLabel',
      child: AnimatedOpacity(
        duration: const Duration(
          milliseconds: 180,
        ),
        opacity: enabled || active ? 1 : 0.55,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(
                milliseconds: 220,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: active
                    ? AppColors.lightGreen
                    : Colors.black.withValues(
                        alpha: 0.025,
                      ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: active
                      ? AppColors.green.withValues(
                          alpha: 0.35,
                        )
                      : Colors.black.withValues(
                          alpha: 0.07,
                        ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: accent.withValues(
                        alpha: 0.12,
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: pending
                        ? Padding(
                            padding: const EdgeInsets.all(11),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: accent,
                            ),
                          )
                        : Icon(
                            active
                                ? Icons.water_drop
                                : Icons.water_drop_outlined,
                            color: accent,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sprayer',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  AnimatedContainer(
                    duration: const Duration(
                      milliseconds: 220,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(
                        alpha: 0.12,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      stateLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
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
