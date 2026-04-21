import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';

/// 高级自定义数字键盘 BottomSheet
class CustomNumpadSheet extends StatefulWidget {
  final String title;
  final bool isIncome;

  const CustomNumpadSheet({
    super.key,
    required this.title,
    required this.isIncome,
  });

  @override
  State<CustomNumpadSheet> createState() => _CustomNumpadSheetState();
}

class _CustomNumpadSheetState extends State<CustomNumpadSheet> {
  String _amountStr = '0';

  void _onKeyPress(String key) {
    HapticFeedback.lightImpact();
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
        ? AppColors.marketUp
        : AppColors.primary;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: AppColors.softShadow,
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 16,
        top: 20,
        left: 20,
        right: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.title,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F6F8),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.centerRight,
            child: Text(
              _amountStr,
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: primaryColor,
                letterSpacing: -1.0,
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildKeypad(primaryColor),
        ],
      ),
    );
  }

  Widget _buildKeypad(Color primaryColor) {
    return Column(
      children: [
        Row(
          children: [
            _key('1'),
            _key('2'),
            _key('3'),
            _key('⌫', color: Colors.grey),
          ],
        ),
        Row(
          children: [
            _key('4'),
            _key('5'),
            _key('6'),
            _key('C', color: Colors.grey),
          ],
        ),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                children: [
                  Row(children: [_key('7'), _key('8'), _key('9')]),
                  Row(children: [_key('.'), _key('0', flex: 2)]),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  final amount = double.tryParse(_amountStr) ?? 0.0;
                  if (amount > 0) {
                    Navigator.pop(context, amount);
                  }
                },
                child: Container(
                  height: 110,
                  margin: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      '确认',
                      style: TextStyle(
                        fontSize: 20,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
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

  Widget _key(String label, {int flex = 1, Color? color}) {
    return Expanded(
      flex: flex,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onKeyPress(label),
        child: Container(
          height: 52,
          margin: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: color ?? const Color(0xFF1A1A2E),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
