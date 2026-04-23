import 'dart:ui';

import 'package:flutter/material.dart';

class AiScannerHud extends StatefulWidget {
  const AiScannerHud({
    super.key,
    required this.imageChild,
    required this.title,
    this.subtitle,
  });

  final Widget imageChild;
  final String title;
  final String? subtitle;

  @override
  State<AiScannerHud> createState() => _AiScannerHudState();
}

class _AiScannerHudState extends State<AiScannerHud>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scanController;

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final frameWidth = size.width.clamp(280.0, 360.0) - 32;
    final frameHeight = frameWidth * 1.48;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: widget.imageChild),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
              child: Container(color: Colors.black.withValues(alpha: 0.18)),
            ),
          ),
          _ScannerMask(frameWidth: frameWidth, frameHeight: frameHeight),
          Center(
            child: SizedBox(
              width: frameWidth,
              height: frameHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.05),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(painter: _ScannerBracketPainter()),
                  ),
                  AnimatedBuilder(
                    animation: _scanController,
                    builder: (context, _) {
                      return Positioned(
                        top: _scanController.value * (frameHeight - 12),
                        left: 14,
                        right: 14,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: const Color(0xFF6B4DFF),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFFB61FFF,
                                ).withValues(alpha: 0.85),
                                blurRadius: 16,
                                spreadRadius: 3,
                              ),
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.8),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 72,
            child: Column(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                if (widget.subtitle case final subtitle?) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerMask extends StatelessWidget {
  const _ScannerMask({required this.frameWidth, required this.frameHeight});

  final double frameWidth;
  final double frameHeight;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final frameLeft = (constraints.maxWidth - frameWidth) / 2;
          final frameTop = (constraints.maxHeight - frameHeight) / 2;
          final frameRight = frameLeft + frameWidth;
          final frameBottom = frameTop + frameHeight;
          final maskColor = Colors.black.withValues(alpha: 0.58);

          return Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                height: frameTop,
                child: ColoredBox(color: maskColor),
              ),
              Positioned(
                left: 0,
                top: frameBottom,
                right: 0,
                bottom: 0,
                child: ColoredBox(color: maskColor),
              ),
              Positioned(
                left: 0,
                top: frameTop,
                width: frameLeft,
                height: frameHeight,
                child: ColoredBox(color: maskColor),
              ),
              Positioned(
                left: frameRight,
                top: frameTop,
                right: 0,
                height: frameHeight,
                child: ColoredBox(color: maskColor),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ScannerBracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF6B4DFF)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const length = 34.0;
    const radius = 24.0;

    canvas.drawPath(
      Path()
        ..moveTo(0, length)
        ..lineTo(0, radius)
        ..quadraticBezierTo(0, 0, radius, 0)
        ..lineTo(length, 0),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width - length, 0)
        ..lineTo(size.width - radius, 0)
        ..quadraticBezierTo(size.width, 0, size.width, radius)
        ..lineTo(size.width, length),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height - length)
        ..lineTo(0, size.height - radius)
        ..quadraticBezierTo(0, size.height, radius, size.height)
        ..lineTo(length, size.height),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width - length, size.height)
        ..lineTo(size.width - radius, size.height)
        ..quadraticBezierTo(
          size.width,
          size.height,
          size.width,
          size.height - radius,
        )
        ..lineTo(size.width, size.height - length),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
