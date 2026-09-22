import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/neu_card.dart';
import '../widgets/responsive_page.dart';

class GuideScreen extends StatelessWidget {
  const GuideScreen({
    super.key,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return const ResponsivePage(
      maxWidth: 900,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Operator Guide',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(
            height: 4,
          ),
          Text(
            'Normal operating workflow '
            'and safety states',
            style: TextStyle(
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(
            height: 24,
          ),
          _GuideCard(
            icon: Icons.power_settings_new,
            title: 'Start-up',
            steps: [
              'Connect the app to '
                  'the Raspberry Pi.',
              'The software session '
                  'starts in MANUAL.',
              'Verify the ESP32, '
                  'spray rail and tank '
                  'status before AUTO.',
            ],
          ),
          SizedBox(
            height: 16,
          ),
          _GuideCard(
            icon: Icons.gamepad_outlined,
            title: 'Manual operation',
            steps: [
              'Select MANUAL on '
                  'the Control page.',
              'Hold a direction '
                  'button to move.',
              'Releasing the button '
                  'sends a stop command.',
            ],
          ),
          SizedBox(
            height: 16,
          ),
          _GuideCard(
            icon: Icons.route_outlined,
            title: 'Autonomous operation',
            steps: [
              'Select AUTO. The robot '
                  'remains stationary '
                  'in setup.',
              'Teach a route or load '
                  'a saved route in '
                  'Navigation.',
              'Start the mission '
                  'explicitly after '
                  'the route is ready.',
            ],
          ),
          SizedBox(
            height: 16,
          ),
          _GuideCard(
            icon: Icons.water_drop_outlined,
            title: 'Tank safety',
            steps: [
              'A dry indication stops '
                  'the pump immediately.',
              'A confirmed empty tank '
                  'inhibits autonomous '
                  'operation.',
              'After refill, AUTO must '
                  'be restarted explicitly.',
            ],
          ),
          SizedBox(
            height: 16,
          ),
          _GuideCard(
            icon: Icons.warning_amber_rounded,
            title: 'Emergency stop',
            steps: [
              'Use the physical '
                  'emergency stop for '
                  'an unsafe condition.',
              'Do not rely on the app '
                  'as the only emergency '
                  'stopping layer.',
            ],
          ),
          SizedBox(
            height: 24,
          ),
        ],
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> steps;

  const _GuideCard({
    required this.icon,
    required this.title,
    required this.steps,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return NeuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: AppColors.green,
              ),
              const SizedBox(
                width: 10,
              ),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 14,
          ),
          for (var index = 0; index < steps.length; index++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    '${index + 1}.',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.green,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    steps[index],
                    style: const TextStyle(
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            if (index != steps.length - 1)
              const SizedBox(
                height: 9,
              ),
          ],
        ],
      ),
    );
  }
}
