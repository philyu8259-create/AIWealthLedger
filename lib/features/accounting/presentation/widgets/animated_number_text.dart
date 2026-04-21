import 'package:flutter/material.dart';

/// 高级数字滚动动效组件
class AnimatedNumberText extends StatelessWidget {
  final double value;
  final String Function(double) formatter;
  final TextStyle style;
  final Duration duration;

  const AnimatedNumberText({
    super.key,
    required this.value,
    required this.formatter,
    required this.style,
    this.duration = const Duration(milliseconds: 600),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, currentValue, child) {
        return Text(
          formatter(currentValue),
          style: style,
        );
      },
    );
  }
}
