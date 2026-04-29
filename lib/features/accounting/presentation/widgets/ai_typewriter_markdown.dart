import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../../core/theme/app_colors.dart';

class AiTypewriterMarkdown extends StatefulWidget {
  final String text;
  final Duration speed;
  final bool enableHaptics;

  const AiTypewriterMarkdown({
    super.key,
    required this.text,
    this.speed = const Duration(milliseconds: 30),
    this.enableHaptics = true,
  });

  @override
  State<AiTypewriterMarkdown> createState() => _AiTypewriterMarkdownState();
}

class _AiTypewriterMarkdownState extends State<AiTypewriterMarkdown> {
  String _displayedText = '';
  Timer? _timer;
  int _currentIndex = 0;
  bool _isComplete = false;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  @override
  void didUpdateWidget(covariant AiTypewriterMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.speed != widget.speed) {
      _startTyping();
    }
  }

  void _startTyping() {
    _timer?.cancel();
    _displayedText = '';
    _currentIndex = 0;
    _isComplete = false;

    if (widget.text.isEmpty) return;

    _timer = Timer.periodic(widget.speed, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_currentIndex < widget.text.length) {
        setState(() {
          _displayedText += widget.text[_currentIndex];
        });
        _currentIndex++;

        final lastChar = widget.text[_currentIndex - 1];
        if (widget.enableHaptics &&
            (_currentIndex % 10 == 0 ||
                RegExp(r'[。.!?\n]').hasMatch(lastChar))) {
          HapticFeedback.lightImpact();
        }
      } else {
        setState(() => _isComplete = true);
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    if (!_isComplete) {
      return Text(
        _displayedText.isEmpty ? ' ' : '$_displayedText▌',
        style: TextStyle(fontSize: 16, color: colors.textPrimary, height: 1.6),
      );
    }

    return MarkdownBody(
      data: _displayedText,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(fontSize: 16, color: colors.textPrimary, height: 1.6),
        h1: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
        h2: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.primaryDark,
        ),
        listBullet: const TextStyle(color: AppColors.primary),
        blockquotePadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        blockquoteDecoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: const Border(
            left: BorderSide(color: AppColors.primary, width: 4),
          ),
        ),
      ),
    );
  }
}
