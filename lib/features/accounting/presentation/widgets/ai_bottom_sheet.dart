import 'package:flutter/material.dart';

import '../../../../l10n/app_string_keys.dart';
import '../../../../l10n/app_strings.dart';
import 'ai_sparkles_icon.dart';
import 'voice_pulse_button.dart';

const _sheetRadius = 30.0;

void showAiBottomSheet({
  required BuildContext context,
  required TextEditingController textController,
  required bool isListening,
  required Future<bool> Function() onStartListening,
  required Future<void> Function() onStopListening,
  required VoidCallback onPickCamera,
  required VoidCallback onPickGallery,
  required void Function(String) onSubmitText,
}) {
  final t = AppStrings.of(context);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          final mediaQuery = MediaQuery.of(ctx);
          final extraBottomOffset = mediaQuery.size.width >= 768 ? 96.0 : 0.0;

          return Padding(
            padding: EdgeInsets.only(
              bottom: mediaQuery.viewInsets.bottom + extraBottomOffset,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(_sheetRadius),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 20, 18, 20),
                      decoration: const BoxDecoration(
                        gradient: aiPrimaryGradient,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(_sheetRadius),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: AiSparklesIcon(
                                size: 23,
                                color: Color(0xFFF6E27A),
                                accentColor: Color(0xFFF6E27A),
                                strokeWidthFactor: 0.11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.text(AppStringKeys.homeAiLedgerTitle),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    height: 1.0,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  t.text(AppStringKeys.homeAiLedgerSubtitle),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.88),
                                    fontSize: 12,
                                    height: 1.0,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 24,
                            ),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
                      child: Column(
                        children: [
                          Container(
                            height: 108,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F7FB),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: const Color(0xFFEDEDF7)),
                            ),
                            child: TextField(
                              controller: textController,
                              maxLines: 4,
                              minLines: 4,
                              decoration: InputDecoration(
                                hintText: t.text(AppStringKeys.homeAiInputPlaceholder),
                                hintStyle: const TextStyle(
                                  color: Color(0xFFB7B8C7),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                ),
                                contentPadding: EdgeInsets.fromLTRB(20, 16, 20, 16),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              _aiActionButton(
                                icon: Icons.photo_camera_outlined,
                                label: t.text(AppStringKeys.homeTakePhoto),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  onPickCamera();
                                },
                              ),
                              _aiActionButton(
                                icon: Icons.image_outlined,
                                label: t.text(AppStringKeys.homeChooseFromLibrary),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  onPickGallery();
                                },
                              ),
                              Expanded(
                                child: VoicePulseButton(
                                  isListening: isListening,
                                  onTap: () async {
                                    if (isListening) {
                                      await onStopListening();
                                      if (ctx.mounted) {
                                        setModalState(() => isListening = false);
                                      }
                                    } else {
                                      final started = await onStartListening();
                                      if (started && ctx.mounted) {
                                        setModalState(() => isListening = true);
                                      }
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                elevation: 0,
                                padding: EdgeInsets.zero,
                              ),
                              onPressed: () {
                                final text = textController.text.trim();
                                if (text.isNotEmpty) {
                                  Navigator.pop(ctx);
                                  onSubmitText(text);
                                }
                              },
                              child: Ink(
                                width: double.infinity,
                                height: 52,
                                decoration: BoxDecoration(
                                  gradient: aiPrimaryGradient,
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF7A35FF).withValues(alpha: 0.22),
                                      blurRadius: 12,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const AiSparklesIcon(
                                      size: 17,
                                      color: Colors.white,
                                      accentColor: Colors.white,
                                      strokeWidthFactor: 0.11,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      t.text(AppStringKeys.homeStartAiRecognition),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        height: 1.0,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

Widget _aiActionButton({
  required IconData icon,
  required String label,
  required VoidCallback onTap,
  Color? color,
}) {
  return Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        height: 82,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F6FB),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color ?? const Color(0xFF6C59C8), size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: color ?? const Color(0xFF202125),
                fontSize: 13,
                height: 1.0,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
