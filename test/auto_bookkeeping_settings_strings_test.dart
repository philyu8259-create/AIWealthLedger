import 'package:ai_accounting_app/l10n/app_string_keys.dart';
import 'package:ai_accounting_app/l10n/app_strings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('auto bookkeeping setup page strings are localized', () {
    const keys = [
      AppStringKeys.autoBookkeepingSetupTitle,
      AppStringKeys.autoBookkeepingHeroTitle,
      AppStringKeys.autoBookkeepingHeroSubtitle,
      AppStringKeys.autoBookkeepingTriggerSection,
      AppStringKeys.autoBookkeepingShortcutSection,
      AppStringKeys.autoBookkeepingPrivacySection,
      AppStringKeys.autoBookkeepingTestButton,
      AppStringKeys.autoBookkeepingTestExample,
      AppStringKeys.autoBookkeepingInstallSection,
      AppStringKeys.autoBookkeepingInstallButton,
      AppStringKeys.autoBookkeepingInstallBackTapNote,
      AppStringKeys.autoBookkeepingManualSection,
      AppStringKeys.autoBookkeepingManualBillText,
      AppStringKeys.autoBookkeepingBackTapSection,
      AppStringKeys.autoBookkeepingTroubleshootingSection,
    ];

    for (final locale in const [Locale('zh'), Locale('en')]) {
      final strings = AppStrings.forLocale(locale);
      for (final key in keys) {
        expect(
          strings.text(key),
          isNot(key),
          reason: '$key should be localized for ${locale.languageCode}',
        );
      }
    }
  });

  test('auto bookkeeping setup copy explains variable binding clearly', () {
    final zh = AppStrings.forLocale(const Locale('zh'));
    expect(zh.text(AppStringKeys.autoBookkeepingInstallButton), contains('安装'));
    expect(
      zh.text(AppStringKeys.autoBookkeepingInstallCopy),
      contains('添加快捷指令'),
    );
    expect(
      zh.text(AppStringKeys.autoBookkeepingInstallBackTapNote),
      allOf(contains('安装后'), contains('轻点背面')),
    );
    expect(
      zh.text(AppStringKeys.autoBookkeepingManualBillText),
      allOf(contains('Bill Text'), contains('提取的文本')),
    );
    expect(
      zh.text(AppStringKeys.autoBookkeepingBackTapCopy),
      contains('设置 > 辅助功能 > 触控 > 轻点背面'),
    );
    expect(
      [
        AppStringKeys.autoBookkeepingManualSave,
        AppStringKeys.autoBookkeepingTroubleshootingSiri,
      ].map(zh.text).join('\n'),
      isNot(contains('元元')),
    );

    final en = AppStrings.forLocale(const Locale('en'));
    expect(
      en.text(AppStringKeys.autoBookkeepingInstallButton),
      contains('Install'),
    );
    expect(
      en.text(AppStringKeys.autoBookkeepingInstallCopy),
      contains('Add Shortcut'),
    );
    expect(
      en.text(AppStringKeys.autoBookkeepingInstallBackTapNote),
      allOf(contains('After installing'), contains('Back Tap')),
    );
    expect(
      en.text(AppStringKeys.autoBookkeepingManualBillText),
      allOf(contains('Bill Text'), contains('Extracted Text')),
    );
    expect(
      en.text(AppStringKeys.autoBookkeepingBackTapCopy),
      contains('Settings > Accessibility > Touch > Back Tap'),
    );
  });
}
