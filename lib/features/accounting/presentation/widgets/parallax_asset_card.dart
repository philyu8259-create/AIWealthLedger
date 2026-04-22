import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../../core/formatters/app_formatter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../services/app_profile_service.dart';
import '../../../../services/injection.dart';
import 'ai_sparkles_icon.dart';

class ParallaxAssetCard extends StatefulWidget {
  final double totalAssets;

  const ParallaxAssetCard({super.key, required this.totalAssets});

  @override
  State<ParallaxAssetCard> createState() => _ParallaxAssetCardState();
}

class _ParallaxAssetCardState extends State<ParallaxAssetCard> {
  StreamSubscription<AccelerometerEvent>? _subscription;
  double _pitch = 0.0;
  double _roll = 0.0;

  @override
  void initState() {
    super.initState();
    _subscription = accelerometerEventStream().listen((event) {
      if (!mounted) return;
      setState(() {
        _pitch = (event.y * 0.05).clamp(-0.5, 0.5);
        _roll = (event.x * 0.05).clamp(-0.5, 0.5);
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  String _formatMoney() {
    final service = getIt<AppProfileService>();
    return AppFormatter.formatCurrency(
      widget.totalAssets,
      currencyCode: service.currentBaseCurrency,
      locale: service.currentLocale,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final textSecondary = Theme.of(context).brightness == Brightness.dark
        ? colors.textSecondary
        : Colors.white54;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateX(_pitch * value)
            ..rotateY(_roll * value),
          alignment: FractionalOffset.center,
          child: Container(
            height: 200,
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E1E2C), Color(0xFF1A1A2E)],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 30,
                  offset: Offset(_roll * -30, 15 + _pitch * -30),
                ),
              ],
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Transform.translate(
                      offset: Offset(_roll * 150, _pitch * 150),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(-0.5, -0.5),
                            radius: 1.5,
                            colors: [
                              Colors.white.withValues(alpha: 0.15),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: -32,
                  top: -28,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TOTAL ASSETS',
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 13,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _formatMoney(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const Spacer(),
                      const Align(
                        alignment: Alignment.bottomRight,
                        child: AiSparklesIcon(
                          size: 24,
                          color: Color(0xFFF6E27A),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
