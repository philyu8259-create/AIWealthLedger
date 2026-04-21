import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'press_feedback.dart';

class PremiumCapsuleButton extends StatelessWidget {
  final String text;
  final IconData? icon;
  final VoidCallback onTap;

  const PremiumCapsuleButton({
    super.key,
    required this.text,
    this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressFeedback(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.15),
            width: 0.5,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
                letterSpacing: 0.2,
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 4),
              Icon(icon, size: 12, color: AppColors.primary),
            ],
          ],
        ),
      ),
    );
  }
}
