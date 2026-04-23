import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'press_feedback.dart';

class CustomNumpadSheet extends StatefulWidget {
  final bool isIncome;
  final String title;
  final void Function(String) onSubmit;

  const CustomNumpadSheet({
    super.key,
    required this.isIncome,
    required this.title,
    required this.onSubmit,
  });

  @override
  State<CustomNumpadSheet> createState() => _CustomNumpadSheetState();
}

class _CustomNumpadSheetState extends State<CustomNumpadSheet> {
  String _amountStr = '0';

  void _onKeyPress(String key) {
    setState(() {
      if (key == 'C') {
        _amountStr = '0';
      } else if (key == '⌫') {
        if (_amountStr.length > 1) {
          _amountStr = _amountStr.substring(0, _amountStr.length - 1);
        } else {
          _amountStr = '0';
        }
      } else if (key == '.') {
        if (!_amountStr.contains('.')) {
          _amountStr += '.';
        }
      } else {
        if (_amountStr == '0') {
          _amountStr = key;
        } else {
          if (_amountStr.contains('.')) {
            final parts = _amountStr.split('.');
            if (parts[1].length >= 2) return;
          }
          if (_amountStr.length >= 10) return;
          _amountStr += key;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = widget.isIncome
        ? const Color(0xFF10B981)
        : AppColors.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: (isDark ? const Color(0xFF1A1A2E) : Colors.white)
                .withValues(alpha: 0.9),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(32),
            ),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.2),
                width: 0.5,
              ),
            ),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 20,
            top: 12,
            left: 20,
            right: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 15,
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                child: Text(
                  _amountStr,
                  style: TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.w700,
                    color: primaryColor,
                    letterSpacing: -1.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildKeypad(primaryColor, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad(Color primaryColor, bool isDark) {
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return Column(
      children: [
        Row(children: [_key('1', textColor), _key('2', textColor), _key('3', textColor)]),
        Row(children: [_key('4', textColor), _key('5', textColor), _key('6', textColor)]),
        Row(children: [_key('7', textColor), _key('8', textColor), _key('9', textColor)]),
        Row(
          children: [
            _key('C', Colors.redAccent.shade200, fontSize: 22),
            _key('0', textColor),
            _key('.', textColor),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _key('⌫', textColor.withValues(alpha: 0.6), fontSize: 26),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: PressFeedback(
                onTap: () {
                  if (_amountStr == '0' || _amountStr == '0.') return;
                  widget.onSubmit(_amountStr);
                  Navigator.of(context).pop();
                },
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      '确认',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _key(String label, Color color, {int flex = 1, double fontSize = 28}) {
    return Expanded(
      flex: flex,
      child: PressFeedback(
        onTap: () => _onKeyPress(label),
        child: Container(
          height: 60,
          margin: const EdgeInsets.all(4),
          color: Colors.transparent,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
