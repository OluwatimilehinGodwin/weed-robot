import 'package:flutter/material.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';

import '../theme/app_colors.dart';
import '../widgets/neu_button.dart';
import '../widgets/neu_card.dart';
import '../widgets/responsive_page.dart';

class DashboardScreen extends StatelessWidget {
  final Widget fluidSensorTile;
  final String sprayTarget;
  final String railOrientation;
  final bool servoReady;
  final bool connected;
  final bool running;
  final bool streaming;
  final int weedCount;
  final double fps;
  final String mode;

  final String videoStreamUrl;

  final VoidCallback onStart;
  final VoidCallback onStop;

  // ==========================================================
  // SPRAY PANEL SIZE CONTROLS
  // ==========================================================
  //
  // These are the main values to change if you later want
  // the spray panel slightly tighter or roomier.
  //
  static const double _sprayOuterPadding = 14;
  static const double _sprayInnerPadding = 11;
  static const double _sprayHeaderGap = 10;

  const DashboardScreen({
    super.key,
    required this.fluidSensorTile,
    required this.connected,
    required this.running,
    required this.streaming,
    required this.weedCount,
    required this.fps,
    required this.mode,
    required this.videoStreamUrl,
    required this.onStart,
    required this.onStop,
    required this.sprayTarget,
    required this.railOrientation,
    required this.servoReady,
  });

  @override
  Widget build(BuildContext context) {
    return ResponsivePage(
      maxWidth: 900,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ==================================================
          // HEADER
          // ==================================================

          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Weed Robot',
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Smart field monitoring',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _ConnectionBadge(connected: connected),
            ],
          ),

          const SizedBox(height: 14),

          // ==================================================
          // COMPACT SPRAY SYSTEM
          // ==================================================
          _buildSpraySystemCard(),

          const SizedBox(height: 18),

          // ==================================================
          // LIVE VIDEO - ORIGINAL 4:3 SIZE
          // ==================================================
          _buildVideoPreview(context),

          const SizedBox(height: 22),

          // ==================================================
          // SYSTEM OVERVIEW
          // ==================================================
          const Text(
            'System overview',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  icon: Icons.grass,
                  value: weedCount.toString(),
                  label: 'Detections',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricCard(
                  icon: Icons.speed,
                  value: fps.toStringAsFixed(1),
                  label: 'FPS',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricCard(
                  icon: Icons.smart_toy_outlined,
                  value: mode.toUpperCase(),
                  label: 'Mode',
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ==================================================
          // DETECTOR CONTROL
          // ==================================================
          const Text(
            'Detection system',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: NeuButton(
                  label: running ? 'RUNNING' : 'START',
                  icon: Icons.play_arrow_rounded,
                  filled: true,
                  onTap: connected && !running ? onStart : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: NeuButton(
                  label: 'STOP',
                  icon: Icons.stop_rounded,
                  accentColor: AppColors.brown,
                  onTap: connected && running ? onStop : null,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          _DetectorStatus(
            connected: connected,
            running: running,
            streaming: streaming,
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ==========================================================
  // COMPACT SPRAY SYSTEM
  // ==========================================================

  Widget _buildSpraySystemCard() {
    final maizeSelected = sprayTarget.toLowerCase() == 'maize';

    final currentTarget = maizeSelected ? 'MAIZE' : 'WEEDS';

    final currentTargetIcon = maizeSelected ? Icons.eco_outlined : Icons.grass;

    final orientation = railOrientation.toUpperCase();

    return NeuCard(
      padding: const EdgeInsets.all(
        _sprayOuterPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.agriculture_outlined,
                size: 21,
                color: AppColors.green,
              ),
              SizedBox(width: 8),
              Text(
                'Spray System',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(
            height: _sprayHeaderGap,
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(
              _sprayInnerPadding,
            ),
            decoration: BoxDecoration(
              color: AppColors.lightGreen,
              borderRadius: BorderRadius.circular(18),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 11,
                    child: _buildTargetSection(
                      currentTarget: currentTarget,
                      currentTargetIcon: currentTargetIcon,
                      orientation: orientation,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 1,
                    color: AppColors.green.withValues(
                      alpha: 0.16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 9,
                    child: fluidSensorTile,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetSection({
    required String currentTarget,
    required IconData currentTargetIcon,
    required String orientation,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                currentTargetIcon,
                size: 22,
                color: AppColors.green,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CURRENT TARGET',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      currentTarget,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.green,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Container(
          height: 1,
          color: AppColors.green.withValues(
            alpha: 0.12,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'RAIL ORIENTATION',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 1),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            orientation,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.green,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _RailStatus(
          connected: connected,
          servoReady: servoReady,
        ),
      ],
    );
  }

  // ==========================================================
  // VIDEO PREVIEW
  // ==========================================================

  Widget _buildVideoPreview(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _openFullScreenVideo(context);
          },
          child: NeuCard(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: AspectRatio(
                // Keep the original dashboard camera proportion.
                aspectRatio: 4 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildVideoArea(),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: _ExpandButton(
                        onTap: () {
                          _openFullScreenVideo(context);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openFullScreenVideo(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          return _FullScreenVideoPage(
            connected: connected,
            running: running,
            streaming: streaming,
            videoStreamUrl: videoStreamUrl,
          );
        },
      ),
    );
  }

  // ==========================================================
  // VIDEO STATE MACHINE
  // ==========================================================

  Widget _buildVideoArea() {
    if (!connected) {
      return const _CameraMessage(
        icon: Icons.cloud_off_outlined,
        iconColor: AppColors.brown,
        title: 'Robot offline',
        subtitle: 'Connect to Raspberry Pi to view the field.',
      );
    }

    if (!running) {
      return const _CameraMessage(
        icon: Icons.videocam_off_outlined,
        iconColor: AppColors.brown,
        title: 'Detection stopped',
        subtitle: 'Switch to AUTO or start detection to view the field.',
      );
    }

    if (!streaming) {
      return Container(
        color: AppColors.surface,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.green,
              ),
            ),
            SizedBox(height: 15),
            Text(
              'Starting field vision',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 5),
            Text(
              'Pi camera and YOLO are preparing...',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Mjpeg(
          key: ValueKey(videoStreamUrl),
          isLive: true,
          stream: videoStreamUrl,
          fit: BoxFit.cover,
          timeout: const Duration(seconds: 10),
          loading: (context) {
            return Container(
              color: AppColors.surface,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.green,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Loading live stream...',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            );
          },
          error: (context, error, stackTrace) {
            return Container(
              color: AppColors.surface,
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 42,
                      color: AppColors.brown,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Stream unavailable',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.90),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 7, color: AppColors.green),
                SizedBox(width: 5),
                Text(
                  'LIVE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.green,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RailStatus extends StatelessWidget {
  final bool connected;
  final bool servoReady;

  const _RailStatus({
    required this.connected,
    required this.servoReady,
  });

  @override
  Widget build(BuildContext context) {
    final ready = connected && servoReady;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: ready
            ? AppColors.green.withValues(
                alpha: 0.09,
              )
            : Colors.black.withValues(
                alpha: 0.035,
              ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ready
                ? Icons.check_circle_outline_rounded
                : Icons.motion_photos_off_outlined,
            size: 14,
            color: ready ? AppColors.green : AppColors.textSecondary,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              ready ? 'SERVO READY' : 'SERVO UNAVAILABLE',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: ready ? AppColors.green : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// FULL-SCREEN VIDEO
// ============================================================

class _FullScreenVideoPage extends StatelessWidget {
  final bool connected;
  final bool running;
  final bool streaming;
  final String videoStreamUrl;

  const _FullScreenVideoPage({
    required this.connected,
    required this.running,
    required this.streaming,
    required this.videoStreamUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildFullScreenContent(),
            Positioned(
              top: 12,
              left: 12,
              child: Material(
                color: Colors.black.withValues(alpha: 0.55),
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                ),
              ),
            ),
            if (connected && running && streaming)
              Positioned(
                top: 17,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 8, color: AppColors.green),
                      SizedBox(width: 6),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullScreenContent() {
    if (!connected) {
      return const _FullScreenMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Robot offline',
        subtitle: 'Connect to Raspberry Pi to view the field.',
      );
    }

    if (!running) {
      return const _FullScreenMessage(
        icon: Icons.videocam_off_outlined,
        title: 'Detection stopped',
        subtitle: 'Start field perception to view the live feed.',
      );
    }

    if (!streaming) {
      return const _FullScreenMessage(
        icon: Icons.hourglass_top_rounded,
        title: 'Starting field vision',
        subtitle: 'Pi camera and YOLO are preparing...',
        loading: true,
      );
    }

    return Center(
      child: Mjpeg(
        key: ValueKey('fullscreen-$videoStreamUrl'),
        isLive: true,
        stream: videoStreamUrl,
        fit: BoxFit.contain,
        timeout: const Duration(seconds: 10),
        loading: (context) {
          return const _FullScreenMessage(
            icon: Icons.videocam_outlined,
            title: 'Loading live stream',
            subtitle: 'Waiting for the Raspberry Pi video feed...',
            loading: true,
          );
        },
        error: (context, error, stackTrace) {
          return _FullScreenMessage(
            icon: Icons.warning_amber_rounded,
            title: 'Stream unavailable',
            subtitle: error.toString(),
          );
        },
      ),
    );
  }
}

// ============================================================
// TANK GAUGE

// ============================================================
// EXPAND BUTTON
// ============================================================

class _ExpandButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ExpandButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 38,
          height: 38,
          child: Icon(Icons.fullscreen, size: 22, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

// ============================================================
// CONNECTION BADGE
// ============================================================

class _ConnectionBadge extends StatelessWidget {
  final bool connected;

  const _ConnectionBadge({required this.connected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: connected ? AppColors.lightGreen : AppColors.lightBrown,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: connected ? AppColors.success : AppColors.brown,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            connected ? 'Connected' : 'Offline',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: connected ? AppColors.green : AppColors.brown,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// METRIC CARD
// ============================================================

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _MetricCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return NeuCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
      child: Column(
        children: [
          Icon(icon, color: AppColors.green, size: 20),
          const SizedBox(height: 7),
          FittedBox(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// CAMERA MESSAGE
// ============================================================

class _CameraMessage extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _CameraMessage({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 44, color: iconColor),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// FULL-SCREEN MESSAGE
// ============================================================

class _FullScreenMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool loading;

  const _FullScreenMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const CircularProgressIndicator(color: AppColors.green)
            else
              Icon(icon, size: 54, color: Colors.white70),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// DETECTOR STATUS
// ============================================================

class _DetectorStatus extends StatelessWidget {
  final bool connected;
  final bool running;
  final bool streaming;

  const _DetectorStatus({
    required this.connected,
    required this.running,
    required this.streaming,
  });

  @override
  Widget build(BuildContext context) {
    String message;
    IconData icon;
    Color color;

    if (!connected) {
      message = 'Waiting for Raspberry Pi connection';
      icon = Icons.link_off;
      color = AppColors.brown;
    } else if (!running) {
      message = 'Field vision system stopped';
      icon = Icons.pause_circle_outline;
      color = AppColors.brown;
    } else if (!streaming) {
      message = 'Camera and detection system starting';
      icon = Icons.hourglass_top_rounded;
      color = AppColors.green;
    } else {
      message = 'Field vision system active';
      icon = Icons.check_circle_outline;
      color = AppColors.green;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
