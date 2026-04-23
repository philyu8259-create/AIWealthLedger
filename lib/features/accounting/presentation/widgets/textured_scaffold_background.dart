import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class TexturedScaffoldBackground extends StatelessWidget {
  const TexturedScaffoldBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(color: colors.background),
          ),
        ),
        if (!isDark) ...[
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: AppColors.ambientGradients,
                  stops: [0.0, 0.42, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            top: -110,
            right: -50,
            child: _AmbientGlow(
              size: 360,
              color: AppColors.primary.withValues(alpha: 0.065),
            ),
          ),
          Positioned(
            top: 170,
            left: -100,
            child: _AmbientGlow(
              size: 280,
              color: const Color(0xFFA7B3FF).withValues(alpha: 0.045),
            ),
          ),
          Positioned(
            bottom: -120,
            right: -40,
            child: _AmbientGlow(
              size: 300,
              color: const Color(0xFFDEE5FF).withValues(alpha: 0.22),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.42),
                      Colors.transparent,
                      AppColors.primary.withValues(alpha: 0.018),
                    ],
                    stops: const [0.0, 0.28, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ] else ...[
          Positioned(
            top: -80,
            right: -30,
            child: _AmbientGlow(
              size: 280,
              color: AppColors.primary.withValues(alpha: 0.12),
            ),
          ),
        ],
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _NoisePainter(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.018)
                    : const Color(0xFF8B93A7).withValues(alpha: 0.024),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, Colors.transparent]),
        ),
      ),
    );
  }
}

class _NoisePainter extends CustomPainter {
  const _NoisePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const step = 18.0;
    for (double x = 0; x < size.width + step; x += step) {
      for (double y = 0; y < size.height + step; y += step) {
        final seed =
            ((x / step).floor() * 73856093) ^ ((y / step).floor() * 19349663);
        final rand = math.Random(seed);
        final dx = x + rand.nextDouble() * step;
        final dy = y + rand.nextDouble() * step;
        final radius = 0.35 + rand.nextDouble() * 0.45;
        canvas.drawCircle(Offset(dx, dy), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NoisePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
