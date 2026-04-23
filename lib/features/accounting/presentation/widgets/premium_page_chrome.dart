import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'press_feedback.dart';

class PremiumPageAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PremiumPageAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.centerTitle = false,
    this.bottom,
    this.toolbarHeight = kToolbarHeight,
  });

  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final bool centerTitle;
  final PreferredSizeWidget? bottom;
  final double toolbarHeight;

  @override
  Size get preferredSize =>
      Size.fromHeight(toolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final leadingGlow = isDark
        ? AppColors.primary.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.24);
    final trailingGlow = isDark
        ? const Color(0xFF7D84FF).withValues(alpha: 0.18)
        : const Color(0xFFA9B7FF).withValues(alpha: 0.28);

    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: toolbarHeight,
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      centerTitle: centerTitle,
      actions: actions,
      bottom: bottom,
      foregroundColor: Colors.white,
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.1,
          shadows: [
            Shadow(
              color: Color(0x24000000),
              offset: Offset(0, 1),
              blurRadius: 10,
            ),
          ],
        ),
      ),
      flexibleSpace: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? const [Color(0xFF17182D), Color(0xFF262557)]
                : [
                    Color.lerp(AppColors.primary, Colors.white, 0.05)!,
                    Color.lerp(const Color(0xFF7C72FF), Colors.white, 0.18)!,
                  ],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.12),
              blurRadius: isDark ? 24 : 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: -68,
              left: -22,
              child: IgnorePointer(
                child: _ChromeGlow(size: 184, color: leadingGlow),
              ),
            ),
            Positioned(
              top: -46,
              right: -12,
              child: IgnorePointer(
                child: _ChromeGlow(size: 210, color: trailingGlow),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: isDark ? 0.06 : 0.16),
                        Colors.transparent,
                        Colors.black.withValues(alpha: isDark ? 0.05 : 0.02),
                      ],
                      stops: const [0.0, 0.34, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PremiumMonthSwitcher extends StatelessWidget {
  const PremiumMonthSwitcher({
    super.key,
    required this.label,
    required this.onPrevious,
    required this.onNext,
    this.onLabelTap,
    this.showDropdownIndicator = false,
  });

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback? onLabelTap;
  final bool showDropdownIndicator;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final buttonSize = compact ? 40.0 : 44.0;
        final gap = compact ? 10.0 : 12.0;
        final contentPadding = EdgeInsets.symmetric(
          horizontal: compact ? 14 : 18,
          vertical: compact ? 10 : 12,
        );
        final outerShadow = isDark
            ? colors.softShadow
            : [
                ...colors.softShadow,
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.72),
                  blurRadius: 12,
                  offset: const Offset(0, -2),
                ),
              ];

        Widget buildArrowButton(IconData icon, VoidCallback onTap) {
          return PressFeedback(
            onTap: onTap,
            child: Container(
              width: buttonSize,
              height: buttonSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(buttonSize / 2),
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
                          Colors.white,
                          Color.lerp(Colors.white, colors.background, 0.22)!,
                        ],
                ),
                border: Border.all(
                  color: isDark
                      ? colors.subtleBorder
                      : AppColors.primary.withValues(alpha: 0.14),
                ),
                boxShadow: outerShadow,
              ),
              child: Icon(
                icon,
                color: isDark ? colors.textPrimary : AppColors.primaryDark,
                size: compact ? 20 : 22,
              ),
            ),
          );
        }

        final labelCard = Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      Color.lerp(
                        colors.secondaryBackground,
                        colors.cardBackground,
                        0.22,
                      )!,
                      colors.cardBackground,
                    ]
                  : [
                      AppColors.primary.withValues(alpha: 0.11),
                      Colors.white.withValues(alpha: 0.96),
                    ],
            ),
            border: Border.all(
              color: isDark
                  ? colors.subtleBorder
                  : AppColors.primary.withValues(alpha: 0.18),
            ),
            boxShadow: outerShadow,
          ),
          child: Padding(
            padding: contentPadding,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: compact ? 15 : 16,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? colors.textPrimary
                          : AppColors.primaryDark,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
                if (showDropdownIndicator) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: compact ? 18 : 20,
                    color: isDark ? colors.textPrimary : AppColors.primaryDark,
                  ),
                ],
              ],
            ),
          ),
        );

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: compact ? 16 : 20,
          ),
          child: Row(
            children: [
              buildArrowButton(Icons.chevron_left_rounded, onPrevious),
              SizedBox(width: gap),
              Expanded(
                child: onLabelTap == null
                    ? labelCard
                    : PressFeedback(onTap: onLabelTap!, child: labelCard),
              ),
              SizedBox(width: gap),
              buildArrowButton(Icons.chevron_right_rounded, onNext),
            ],
          ),
        );
      },
    );
  }
}

class _ChromeGlow extends StatelessWidget {
  const _ChromeGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, Colors.transparent]),
      ),
    );
  }
}
