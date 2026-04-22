import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum HapticType { light, medium, heavy, selection, success, none }

class PressFeedback extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedOpacity;
  final Duration duration;
  final HitTestBehavior behavior;
  final bool enableHaptic;
  final HapticType hapticType;
  final double scaleFactor;

  const PressFeedback({
    super.key,
    required this.child,
    this.onTap,
    this.pressedOpacity = 0.9,
    this.duration = const Duration(milliseconds: 150),
    this.behavior = HitTestBehavior.deferToChild,
    this.enableHaptic = false,
    this.hapticType = HapticType.light,
    this.scaleFactor = 0.96,
  });

  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<PressFeedback>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _scaleAnimation;

  bool get _enabled => widget.onTap != null;
  HapticType get _effectiveHapticType =>
      widget.enableHaptic ? HapticType.light : widget.hapticType;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _scaleAnimation = _buildScaleAnimation();
  }

  @override
  void didUpdateWidget(covariant PressFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (oldWidget.scaleFactor != widget.scaleFactor) {
      _scaleAnimation = _buildScaleAnimation();
    }
  }

  void _triggerHaptic() {
    switch (_effectiveHapticType) {
      case HapticType.light:
        HapticFeedback.lightImpact();
        break;
      case HapticType.medium:
        HapticFeedback.mediumImpact();
        break;
      case HapticType.heavy:
        HapticFeedback.heavyImpact();
        break;
      case HapticType.selection:
        HapticFeedback.selectionClick();
        break;
      case HapticType.success:
        HapticFeedback.lightImpact();
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) HapticFeedback.mediumImpact();
        });
        break;
      case HapticType.none:
        break;
    }
  }

  Animation<double> _buildScaleAnimation() {
    return Tween<double>(begin: 1.0, end: widget.scaleFactor).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return widget.child;

    final opacityAnimation =
        Tween<double>(begin: 1.0, end: widget.pressedOpacity).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
        );

    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        _triggerHaptic();
        widget.onTap?.call();
      },
      onTapCancel: () => _controller.reverse(),
      child: FadeTransition(
        opacity: opacityAnimation,
        child: ScaleTransition(scale: _scaleAnimation, child: widget.child),
      ),
    );
  }
}
