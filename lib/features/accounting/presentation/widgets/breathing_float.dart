import 'package:flutter/material.dart';

class BreathingFloat extends StatefulWidget {
  final Widget child;
  final double distance;
  final Duration duration;

  const BreathingFloat({
    super.key,
    required this.child,
    this.distance = 8,
    this.duration = const Duration(seconds: 2),
  });

  @override
  State<BreathingFloat> createState() => _BreathingFloatState();
}

class _BreathingFloatState extends State<BreathingFloat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat(reverse: true);
    _offset = Tween<double>(begin: -widget.distance, end: widget.distance)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offset,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _offset.value),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
