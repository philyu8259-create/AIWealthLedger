import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'press_feedback.dart';

class PremiumSegmentedTabs extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final double height;

  const PremiumSegmentedTabs({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    this.height = 52,
  }) : assert(labels.length > 1);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        const outerPadding = 4.0;
        final segmentWidth =
            (constraints.maxWidth - outerPadding * 2) / labels.length;

        return Container(
          height: height,
          decoration: BoxDecoration(
            color: isDark ? null : AppColors.recessedTrackBackground,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [
                      colors.secondaryBackground,
                      Color.lerp(
                        colors.secondaryBackground,
                        colors.background,
                        0.18,
                      )!,
                    ]
                  : [
                      Color.lerp(
                        AppColors.recessedTrackBackground,
                        colors.background,
                        0.04,
                      )!,
                      AppColors.recessedTrackBackground,
                      Color.lerp(
                        AppColors.recessedTrackBackground,
                        colors.secondaryBackground,
                        0.24,
                      )!,
                    ],
              stops: isDark ? null : const [0.0, 0.56, 1.0],
            ),
            borderRadius: BorderRadius.circular(height / 2),
            border: Border.all(
              color: isDark
                  ? colors.subtleBorder
                  : Colors.black.withValues(alpha: 0.025),
              width: 1,
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(height / 2),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: isDark
                            ? [
                                Colors.white.withValues(alpha: 0.02),
                                Colors.transparent,
                              ]
                            : [
                                Colors.black.withValues(alpha: 0.035),
                                Colors.transparent,
                                Colors.white.withValues(alpha: 0.58),
                              ],
                        stops: isDark
                            ? const [0.0, 1.0]
                            : const [0.0, 0.22, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                left: outerPadding + segmentWidth * selectedIndex,
                top: outerPadding,
                width: segmentWidth,
                height: height - outerPadding * 2,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular((height - 8) / 2),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: isDark
                          ? [
                              Color.lerp(
                                colors.cardBackground,
                                colors.secondaryBackground,
                                0.05,
                              )!,
                              colors.cardBackground,
                            ]
                          : [Colors.white, AppColors.cardHighlight],
                    ),
                    border: Border.all(
                      color: isDark
                          ? colors.subtleBorder
                          : AppColors.primary.withValues(alpha: 0.07),
                      width: 0.9,
                    ),
                    boxShadow: isDark
                        ? colors.softShadow
                        : [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.06),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.7),
                              blurRadius: 10,
                              offset: const Offset(0, -2),
                            ),
                          ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular((height - 8) / 2),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.86),
                            Colors.transparent,
                            AppColors.primary.withValues(alpha: 0.02),
                          ],
                          stops: const [0.0, 0.38, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                children: List.generate(labels.length, (index) {
                  final selected = index == selectedIndex;
                  return Expanded(
                    child: PressFeedback(
                      onTap: () => onChanged(index),
                      hapticType: HapticType.selection,
                      scaleFactor: 0.985,
                      behavior: HitTestBehavior.opaque,
                      child: SizedBox(
                        height: height,
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: selected
                                  ? (isDark
                                        ? colors.textPrimary
                                        : AppColors.primaryDark)
                                  : colors.textSecondary,
                              letterSpacing: selected ? 0.1 : 0,
                            ),
                            child: Text(
                              labels[index],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}
