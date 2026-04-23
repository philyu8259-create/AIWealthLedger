import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class PremiumSurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final VoidCallback? onTap;

  const PremiumSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin,
    this.radius = 24,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(radius);
    final outerBorderGradient = isDark
        ? null
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary.withValues(alpha: 0.10),
              Colors.white.withValues(alpha: 0.98),
              const Color(0xFFE6EBF7).withValues(alpha: 0.92),
              AppColors.primary.withValues(alpha: 0.03),
            ],
            stops: const [0.0, 0.24, 0.72, 1.0],
          );
    final innerGradient = isDark
        ? LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colors.cardBackground,
              Color.lerp(
                colors.cardBackground,
                colors.secondaryBackground,
                0.22,
              )!,
            ],
          )
        : const RadialGradient(
            center: Alignment(-0.58, -0.62),
            radius: 1.22,
            colors: [Colors.white, AppColors.cardHighlight, Color(0xFFF4F6FD)],
            stops: [0.0, 0.56, 1.0],
          );
    final topGlow = isDark
        ? Colors.white.withValues(alpha: 0.02)
        : Colors.white.withValues(alpha: 0.74);
    final edgeGlow = isDark
        ? Colors.white.withValues(alpha: 0.03)
        : Colors.white.withValues(alpha: 0.82);
    final bottomShade = isDark
        ? Colors.black.withValues(alpha: 0.08)
        : AppColors.primary.withValues(alpha: 0.04);

    final surface = Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: isDark ? colors.subtleBorder : null,
        gradient: outerBorderGradient,
        boxShadow: colors.softShadow,
      ),
      child: Padding(
        padding: EdgeInsets.all(isDark ? 1 : 0.9),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              gradient: innerGradient,
              border: Border.all(
                color: isDark
                    ? colors.subtleBorder
                    : Colors.white.withValues(alpha: 0.50),
                width: 0.8,
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: -radius * 1.0,
                  left: -radius * 0.72,
                  child: IgnorePointer(
                    child: Container(
                      width: radius * 4.4,
                      height: radius * 3.3,
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [topGlow, Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: borderRadius,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            edgeGlow,
                            Colors.transparent,
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.14, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: borderRadius,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            bottomShade,
                          ],
                          stops: const [0.0, 0.72, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(padding: padding, child: child),
              ],
            ),
          ),
        ),
      ),
    );

    if (onTap == null) return surface;

    return InkWell(onTap: onTap, borderRadius: borderRadius, child: surface);
  }
}
