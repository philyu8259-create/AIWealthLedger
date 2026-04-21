import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PressFeedback extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedOpacity;
  final Duration duration;
  final HitTestBehavior behavior;
  final bool enableHaptic;

  const PressFeedback({
    super.key,
    required this.child,
    this.onTap,
    this.pressedOpacity = 0.9,
    this.duration = const Duration(milliseconds: 100),
    this.behavior = HitTestBehavior.deferToChild,
    this.enableHaptic = false,
  });

  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<PressFeedback> {
  bool _isPressed = false;

  bool get _enabled => widget.onTap != null;

  void _setPressed(bool value) {
    if (!_enabled || _isPressed == value) return;
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return widget.child;

    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: () {
        if (widget.enableHaptic) {
          HapticFeedback.lightImpact();
        }
        widget.onTap?.call();
      },
      child: AnimatedOpacity(
        duration: widget.duration,
        opacity: _isPressed ? widget.pressedOpacity : 1.0,
        child: widget.child,
      ),
    );
  }
}
