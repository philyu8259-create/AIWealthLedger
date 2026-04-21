import 'package:flutter/material.dart';

const aiPrimaryGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [
    Color(0xFF5A42F4),
    Color(0xFF7D31FF),
    Color(0xFFB61FFF),
  ],
  stops: [0.0, 0.46, 1.0],
);

class AiSparklesIcon extends StatelessWidget {
  const AiSparklesIcon({
    super.key,
    required this.size,
    required this.color,
    this.accentColor,
    this.strokeWidthFactor = 0.115,
  });

  final double size;
  final Color color;
  final Color? accentColor;
  final double strokeWidthFactor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _AiSparklesPainter(
        color: color,
        accentColor: accentColor ?? color,
        strokeWidthFactor: strokeWidthFactor,
      ),
    );
  }
}

class _AiSparklesPainter extends CustomPainter {
  const _AiSparklesPainter({
    required this.color,
    required this.accentColor,
    required this.strokeWidthFactor,
  });

  final Color color;
  final Color accentColor;
  final double strokeWidthFactor;

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * strokeWidthFactor
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final main = Path()
      ..moveTo(size.width * 0.47, size.height * 0.08)
      ..quadraticBezierTo(
        size.width * 0.53,
        size.height * 0.28,
        size.width * 0.76,
        size.height * 0.41,
      )
      ..quadraticBezierTo(
        size.width * 0.54,
        size.height * 0.52,
        size.width * 0.48,
        size.height * 0.93,
      )
      ..quadraticBezierTo(
        size.width * 0.40,
        size.height * 0.69,
        size.width * 0.16,
        size.height * 0.56,
      )
      ..quadraticBezierTo(
        size.width * 0.37,
        size.height * 0.46,
        size.width * 0.47,
        size.height * 0.08,
      );
    canvas.drawPath(main, strokePaint);

    final tinySparkle = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * (strokeWidthFactor * 0.74)
      ..strokeCap = StrokeCap.round;

    final smallCenter = Offset(size.width * 0.80, size.height * 0.18);
    final smallArm = size.width * 0.10;
    canvas.drawLine(
      Offset(smallCenter.dx - smallArm, smallCenter.dy),
      Offset(smallCenter.dx + smallArm, smallCenter.dy),
      tinySparkle,
    );
    canvas.drawLine(
      Offset(smallCenter.dx, smallCenter.dy - smallArm),
      Offset(smallCenter.dx, smallCenter.dy + smallArm),
      tinySparkle,
    );

    final dotPaint = Paint()..color = accentColor;
    canvas.drawCircle(
      Offset(size.width * 0.19, size.height * 0.78),
      size.width * 0.072,
      dotPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _AiSparklesPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.strokeWidthFactor != strokeWidthFactor;
  }
}
