import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_string_keys.dart';
import '../../../../l10n/app_strings.dart';

class VoicePulseButton extends StatefulWidget {
  final bool isListening;
  final VoidCallback onTap;

  const VoicePulseButton({
    super.key,
    required this.isListening,
    required this.onTap,
  });

  @override
  State<VoicePulseButton> createState() => _VoicePulseButtonState();
}

class _VoicePulseButtonState extends State<VoicePulseButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.isListening) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant VoicePulseButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isListening && !oldWidget.isListening) {
      _controller.repeat();
    } else if (!widget.isListening && oldWidget.isListening) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Container(
            height: 82,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: widget.isListening
                  ? AppColors.primary.withValues(alpha: 0.1)
                  : const Color(0xFFF5F6FB),
              borderRadius: BorderRadius.circular(18),
              boxShadow: widget.isListening
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(
                          alpha: 0.3 * (1 - _controller.value),
                        ),
                        blurRadius: 20 * _controller.value,
                        spreadRadius: 10 * _controller.value,
                      ),
                    ]
                  : [],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.isListening
                      ? Icons.stop_circle_rounded
                      : Icons.mic_none_outlined,
                  color: widget.isListening
                      ? AppColors.primary
                      : const Color(0xFF6C59C8),
                  size: widget.isListening ? 28 : 24,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.isListening
                      ? t.text(AppStringKeys.homeVoiceListeningLabel)
                      : t.text(AppStringKeys.homeVoiceActionLabel),
                  style: TextStyle(
                    color: widget.isListening
                        ? AppColors.primary
                        : const Color(0xFF202125),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
