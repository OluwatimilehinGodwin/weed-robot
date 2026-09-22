import 'package:flutter/material.dart';

import '../application/robot_controller.dart';

class FluidRecoveryDialog extends StatelessWidget {
  final RobotController controller;
  const FluidRecoveryDialog({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => StreamBuilder<void>(
    stream: controller.changes,
    builder: (context, _) {
      final recovered =
          !controller.status.fluidRecoveryRequired &&
          controller.fresh &&
          !controller.recovering;
      final status = controller.status;
      final message = recovered
          ? 'Recovery confirmed.'
          : !controller.policy.canRecover
          ? 'Waiting for fluid and robot connection.'
          : status.mode == 'auto' && status.teachingStarted
          ? 'Resume the paused operation?'
          : status.mode == 'manual'
          ? 'Restore manual controls? Sprayer stays off.'
          : 'Restore operation controls?';
      return PopScope(
        canPop: !controller.recovering,
        child: AlertDialog(
          title: Text(recovered ? 'Fluid restored' : 'Refill detected'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: controller.recovering
                  ? null
                  : () => Navigator.of(context).pop(),
              child: Text(recovered ? 'Done' : 'Not now'),
            ),
            if (!recovered)
              FilledButton(
                onPressed: controller.policy.canRecover && !controller.busy
                    ? controller.resumeFluid
                    : null,
                child: Text(controller.recovering ? 'Resuming…' : 'Resume'),
              ),
          ],
        ),
      );
    },
  );
}
