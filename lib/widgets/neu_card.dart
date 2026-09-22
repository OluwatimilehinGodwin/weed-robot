import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class NeuCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  const NeuCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.borderRadius = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            offset: const Offset(7, 7),
            blurRadius: 18,
          ),
          const BoxShadow(
            color: Colors.white,
            offset: Offset(-7, -7),
            blurRadius: 18,
          ),
        ],
      ),
      child: child,
    );
  }
}
