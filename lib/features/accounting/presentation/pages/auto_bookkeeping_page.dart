import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_string_keys.dart';
import '../../../../l10n/app_strings.dart';
import '../widgets/premium_page_chrome.dart';
import '../widgets/press_feedback.dart';
import '../widgets/textured_scaffold_background.dart';

const _autoBookkeepingShortcutTemplateUrl =
    'https://www.icloud.com/shortcuts/6962df2b8ec5474a805ffee4a09aaf65';

class AutoBookkeepingPage extends StatelessWidget {
  const AutoBookkeepingPage({super.key, this.platformResolver});

  final TargetPlatform Function()? platformResolver;

  bool _isAndroidPlatform() {
    return platformResolver?.call() == TargetPlatform.android ||
        (platformResolver == null &&
            defaultTargetPlatform == TargetPlatform.android);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final isAndroid = _isAndroidPlatform();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PremiumPageAppBar(
        title: t.text(AppStringKeys.autoBookkeepingSetupTitle),
      ),
      body: Semantics(
        identifier: 'auto-bookkeeping-page',
        container: true,
        explicitChildNodes: true,
        child: TexturedScaffoldBackground(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isTablet = constraints.maxWidth >= 768;
              final horizontalPadding = isTablet
                  ? 24.0
                  : (constraints.maxWidth > 520 ? 16.0 : 0.0);
              final maxContentWidth = isTablet
                  ? (constraints.maxWidth >= 1024 ? 780.0 : 700.0)
                  : (constraints.maxWidth > 560 ? 520.0 : constraints.maxWidth);

              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding + 16,
                      8,
                      horizontalPadding + 16,
                      MediaQuery.of(context).padding.bottom + 120,
                    ),
                    children: [
                      _HeroPanel(colors: colors, isAndroid: isAndroid),
                      const SizedBox(height: 18),
                      _InstallPanel(colors: colors, isAndroid: isAndroid),
                      const SizedBox(height: 18),
                      _SectionTitle(
                        title: t.text(
                          isAndroid
                              ? AppStringKeys
                                    .autoBookkeepingTriggerSectionAndroid
                              : AppStringKeys.autoBookkeepingTriggerSection,
                        ),
                      ),
                      _TriggerGrid(colors: colors, isAndroid: isAndroid),
                      const SizedBox(height: 18),
                      _SectionTitle(
                        title: t.text(
                          isAndroid
                              ? AppStringKeys
                                    .autoBookkeepingShortcutSectionAndroid
                              : AppStringKeys.autoBookkeepingShortcutSection,
                        ),
                      ),
                      _ShortcutSteps(colors: colors, isAndroid: isAndroid),
                      const SizedBox(height: 18),
                      _SectionTitle(
                        title: t.text(
                          isAndroid
                              ? AppStringKeys
                                    .autoBookkeepingManualSectionAndroid
                              : AppStringKeys.autoBookkeepingManualSection,
                        ),
                      ),
                      _ManualSetupPanel(colors: colors, isAndroid: isAndroid),
                      const SizedBox(height: 18),
                      _InfoPanel(
                        icon: Icons.touch_app_outlined,
                        title: t.text(
                          isAndroid
                              ? AppStringKeys
                                    .autoBookkeepingBackTapSectionAndroid
                              : AppStringKeys.autoBookkeepingBackTapSection,
                        ),
                        body: t.text(
                          isAndroid
                              ? AppStringKeys.autoBookkeepingBackTapCopyAndroid
                              : AppStringKeys.autoBookkeepingBackTapCopy,
                        ),
                        colors: colors,
                      ),
                      const SizedBox(height: 18),
                      _TroubleshootingPanel(
                        colors: colors,
                        isAndroid: isAndroid,
                      ),
                      const SizedBox(height: 18),
                      _InfoPanel(
                        icon: Icons.lock_outline_rounded,
                        title: t.text(
                          AppStringKeys.autoBookkeepingPrivacySection,
                        ),
                        body: isAndroid
                            ? t.text(
                                AppStringKeys.autoBookkeepingPrivacyCopyAndroid,
                              )
                            : t.text(AppStringKeys.autoBookkeepingPrivacyCopy),
                        colors: colors,
                      ),
                      const SizedBox(height: 14),
                      _TestPanel(colors: colors),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _InstallPanel extends StatelessWidget {
  const _InstallPanel({required this.colors, required this.isAndroid});

  final AppColorsExtension colors;
  final bool isAndroid;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.install_mobile_rounded, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t.text(
                    isAndroid
                        ? AppStringKeys.autoBookkeepingInstallSectionAndroid
                        : AppStringKeys.autoBookkeepingInstallSection,
                  ),
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            t.text(
              isAndroid
                  ? AppStringKeys.autoBookkeepingInstallCopyAndroid
                  : AppStringKeys.autoBookkeepingInstallCopy,
            ),
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Semantics(
            identifier: 'auto-bookkeeping-open-shortcuts-button',
            button: true,
            child: PressFeedback(
              onTap: () =>
                  isAndroid ? _openHomeAi(context) : _openShortcuts(context),
              child: Container(
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF1F7A5A),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.open_in_new_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        t.text(
                          isAndroid
                              ? AppStringKeys
                                    .autoBookkeepingInstallButtonAndroid
                              : AppStringKeys.autoBookkeepingInstallButton,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: AppColors.primary.withValues(alpha: 0.86),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.text(
                    isAndroid
                        ? AppStringKeys.autoBookkeepingInstallBackTapNoteAndroid
                        : AppStringKeys.autoBookkeepingInstallBackTapNote,
                  ),
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12.5,
                    height: 1.42,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openShortcuts(BuildContext context) async {
    final t = AppStrings.of(context);
    final url = Uri.parse(_autoBookkeepingShortcutTemplateUrl);
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        return;
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t.text(
              AppStringKeys.autoBookkeepingOpenShortcutsFailed,
              params: {'error': 'shortcut template unavailable'},
            ),
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t.text(
              AppStringKeys.autoBookkeepingOpenShortcutsFailed,
              params: {'error': '$e'},
            ),
          ),
        ),
      );
    }
  }

  void _openHomeAi(BuildContext context) {
    queueHomeAiOpenAfterNavigation();
    context.go('/home');
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.colors, required this.isAndroid});

  final AppColorsExtension colors;
  final bool isAndroid;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF5B42F3), Color(0xFFB61FFF)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.auto_awesome_motion_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.text(
                    isAndroid
                        ? AppStringKeys.autoBookkeepingHeroTitleAndroid
                        : AppStringKeys.autoBookkeepingHeroTitle,
                  ),
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t.text(
                    isAndroid
                        ? AppStringKeys.autoBookkeepingHeroSubtitleAndroid
                        : AppStringKeys.autoBookkeepingHeroSubtitle,
                  ),
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TriggerGrid extends StatelessWidget {
  const _TriggerGrid({required this.colors, required this.isAndroid});

  final AppColorsExtension colors;
  final bool isAndroid;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final items = [
      if (isAndroid)
        (
          icon: Icons.content_copy_rounded,
          label: t.text(AppStringKeys.autoBookkeepingTriggerCopy),
        )
      else
        (
          icon: Icons.touch_app_outlined,
          label: t.text(AppStringKeys.autoBookkeepingTriggerBackTap),
        ),
      if (isAndroid)
        (
          icon: Icons.arrow_back_rounded,
          label: t.text(AppStringKeys.autoBookkeepingTriggerReturn),
        )
      else
        (
          icon: Icons.adjust_outlined,
          label: t.text(AppStringKeys.autoBookkeepingTriggerAssistive),
        ),
      if (isAndroid)
        (
          icon: Icons.checklist_rtl_rounded,
          label: t.text(AppStringKeys.autoBookkeepingTriggerParse),
        )
      else
        (
          icon: Icons.graphic_eq_rounded,
          label: t.text(AppStringKeys.autoBookkeepingTriggerSiri),
        ),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Expanded(
            child: _MiniActionCard(
              icon: items[i].icon,
              label: items[i].label,
              colors: colors,
            ),
          ),
          if (i != items.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

class _MiniActionCard extends StatelessWidget {
  const _MiniActionCard({
    required this.icon,
    required this.label,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 92,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.primary, size: 24),
          const SizedBox(height: 9),
          SizedBox(
            height: 18,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutSteps extends StatelessWidget {
  const _ShortcutSteps({required this.colors, required this.isAndroid});

  final AppColorsExtension colors;
  final bool isAndroid;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final steps = isAndroid
        ? [
            t.text(AppStringKeys.autoBookkeepingShortcutStepCopy),
            t.text(AppStringKeys.autoBookkeepingShortcutStepReturn),
            t.text(AppStringKeys.autoBookkeepingShortcutStepPaste),
          ]
        : [
            t.text(AppStringKeys.autoBookkeepingShortcutStepScreenshot),
            t.text(AppStringKeys.autoBookkeepingShortcutStepExtract),
            t.text(AppStringKeys.autoBookkeepingShortcutStepRun),
          ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            _StepRow(index: i + 1, text: steps[i], colors: colors),
            if (i != steps.length - 1)
              Divider(
                height: 22,
                color: colors.textSecondary.withValues(alpha: 0.12),
              ),
          ],
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.index,
    required this.text,
    required this.colors,
  });

  final int index;
  final String text;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$index',
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _ManualSetupPanel extends StatelessWidget {
  const _ManualSetupPanel({required this.colors, required this.isAndroid});

  final AppColorsExtension colors;
  final bool isAndroid;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final steps = isAndroid
        ? [
            (
              Icons.copy_all_rounded,
              t.text(AppStringKeys.autoBookkeepingManualCopy),
            ),
            (
              Icons.subdirectory_arrow_left_rounded,
              t.text(AppStringKeys.autoBookkeepingManualReturn),
            ),
            (
              Icons.paste_rounded,
              t.text(AppStringKeys.autoBookkeepingManualPaste),
            ),
            (
              Icons.done_all_rounded,
              t.text(AppStringKeys.autoBookkeepingManualConfirm),
            ),
          ]
        : [
            (
              Icons.screenshot_monitor_outlined,
              t.text(AppStringKeys.autoBookkeepingManualScreenshot),
            ),
            (
              Icons.document_scanner_outlined,
              t.text(AppStringKeys.autoBookkeepingManualExtract),
            ),
            (
              Icons.auto_awesome_motion_outlined,
              t.text(AppStringKeys.autoBookkeepingManualAction),
            ),
            (
              Icons.text_fields_rounded,
              t.text(AppStringKeys.autoBookkeepingManualBillText),
            ),
            (
              Icons.save_outlined,
              t.text(AppStringKeys.autoBookkeepingManualSave),
            ),
          ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            _InstructionStep(
              index: i + 1,
              icon: steps[i].$1,
              text: steps[i].$2,
              colors: colors,
            ),
            if (i != steps.length - 1)
              Divider(
                height: 22,
                color: colors.textSecondary.withValues(alpha: 0.12),
              ),
          ],
        ],
      ),
    );
  }
}

class _InstructionStep extends StatelessWidget {
  const _InstructionStep({
    required this.index,
    required this.icon,
    required this.text,
    required this.colors,
  });

  final int index;
  final IconData icon;
  final String text;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: AppColors.primary, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              '$index. $text',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.icon,
    required this.title,
    required this.body,
    required this.colors,
  });

  final IconData icon;
  final String title;
  final String body;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TroubleshootingPanel extends StatelessWidget {
  const _TroubleshootingPanel({required this.colors, required this.isAndroid});

  final AppColorsExtension colors;
  final bool isAndroid;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final items = isAndroid
        ? [
            t.text(AppStringKeys.autoBookkeepingTroubleshootingNoText),
            t.text(AppStringKeys.autoBookkeepingTroubleshootingPasteFailed),
            t.text(AppStringKeys.autoBookkeepingTroubleshootingParseFailed),
          ]
        : [
            t.text(AppStringKeys.autoBookkeepingTroubleshootingActionMissing),
            t.text(AppStringKeys.autoBookkeepingTroubleshootingVariableMissing),
            t.text(AppStringKeys.autoBookkeepingTroubleshootingSiri),
          ];

    return _InfoPanel(
      icon: Icons.help_outline_rounded,
      title: t.text(
        isAndroid
            ? AppStringKeys.autoBookkeepingTroubleshootingSectionAndroid
            : AppStringKeys.autoBookkeepingTroubleshootingSection,
      ),
      body: items.map((item) => '• $item').join('\n'),
      colors: colors,
    );
  }
}

class _TestPanel extends StatelessWidget {
  const _TestPanel({required this.colors});

  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.text(AppStringKeys.autoBookkeepingTestSection),
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t.text(AppStringKeys.autoBookkeepingTestCopy),
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Semantics(
            identifier: 'auto-bookkeeping-test-button',
            button: true,
            child: PressFeedback(
              onTap: () {
                queueHomeShortcutTextAfterNavigation(
                  t.text(AppStringKeys.autoBookkeepingTestExample),
                );
                context.go('/home');
              },
              child: Container(
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  t.text(AppStringKeys.autoBookkeepingTestButton),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10),
      child: Text(
        title,
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
