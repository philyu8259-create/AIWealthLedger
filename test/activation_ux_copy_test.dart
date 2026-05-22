import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_accounting_app/l10n/app_string_keys.dart';
import 'package:ai_accounting_app/l10n/app_strings.dart';

void main() {
  group('activation UX copy', () {
    test('saved-entry feedback explains the immediate user value', () {
      final zh = AppStrings.forLocale(const Locale('zh'));
      final en = AppStrings.forLocale(const Locale('en'));

      expect(zh.text(AppStringKeys.homeSavedInsightTitle), contains('已记录'));
      expect(zh.text(AppStringKeys.homeSavedInsightSubtitle), contains('趋势'));
      expect(en.text(AppStringKeys.homeSavedInsightTitle), contains('Saved'));
      expect(
        en.text(AppStringKeys.homeSavedInsightSubtitle),
        contains('trend'),
      );
    });

    test('home asset copy is framed as an overview, not a stock tool', () {
      final zh = AppStrings.forLocale(const Locale('zh'));
      final en = AppStrings.forLocale(const Locale('en'));

      expect(zh.text(AppStringKeys.homeAssetsTitle), '资产总览');
      expect(zh.text(AppStringKeys.homeAssetsBadge), '变化解释');
      expect(en.text(AppStringKeys.homeAssetsTitle), 'Assets overview');
      expect(en.text(AppStringKeys.homeAssetsBadge), 'Change signals');
    });
  });
}
