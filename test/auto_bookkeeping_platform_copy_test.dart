import 'package:ai_accounting_app/app/router.dart';
import 'package:ai_accounting_app/core/theme/app_colors.dart';
import 'package:ai_accounting_app/features/accounting/presentation/pages/auto_bookkeeping_page.dart';
import 'package:ai_accounting_app/l10n/app_string_keys.dart';
import 'package:ai_accounting_app/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

String _collectTexts(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .where((value) => value.isNotEmpty)
      .join('\n');
}

Future<String> _renderPageText({
  required WidgetTester tester,
  required TargetPlatform platform,
  required Locale locale,
}) async {
  await tester.pumpWidget(
    _buildAppForPlatform(platform: platform, locale: locale),
  );
  await tester.pump();
  return _collectTexts(tester);
}

Widget _buildAppForPlatform({
  required TargetPlatform platform,
  required Locale locale,
}) {
  final router = GoRouter(
    initialLocation: '/auto-bookkeeping',
    routes: [
      GoRoute(
        path: '/auto-bookkeeping',
        builder: (context, state) =>
            AutoBookkeepingPage(platformResolver: () => platform),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const Scaffold(
          key: Key('auto-bookkeeping-home-page'),
          body: Center(child: Text('auto-bookkeeping-home-page-target')),
        ),
      ),
    ],
  );

  return MaterialApp.router(
    locale: locale,
    supportedLocales: const [Locale('zh'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: AppColorsExtension.light.background,
      extensions: <ThemeExtension<dynamic>>[AppColorsExtension.light],
    ),
    routerConfig: router,
    debugShowCheckedModeBanner: false,
  );
}

void main() {
  testWidgets('Android copy wording is platform-appropriate', (tester) async {
    for (final locale in const [Locale('zh'), Locale('en')]) {
      final text = await _renderPageText(
        tester: tester,
        platform: TargetPlatform.android,
        locale: locale,
      );

      expect(
        text,
        contains(
          AppStrings.forLocale(
            locale,
          ).text(AppStringKeys.autoBookkeepingInstallButtonAndroid),
        ),
      );
      expect(text.toLowerCase(), isNot(contains('icloud')));
      expect(text.toLowerCase(), isNot(contains('shortcut')));
      expect(text.toLowerCase(), isNot(contains('shortcuts')));
      expect(text.toLowerCase(), isNot(contains('siri')));
      expect(text.toLowerCase(), isNot(contains('back tap')));
      expect(text, isNot(contains('iPhone')));
      expect(text, isNot(contains('App Store')));
      expect(text, isNot(contains('轻点背面')));
    }
  });

  testWidgets('iOS wording still contains shortcut semantics', (tester) async {
    for (final locale in const [Locale('zh'), Locale('en')]) {
      final text = await _renderPageText(
        tester: tester,
        platform: TargetPlatform.iOS,
        locale: locale,
      );

      final zh = AppStrings.forLocale(const Locale('zh'));
      final en = AppStrings.forLocale(const Locale('en'));
      final expected = locale.languageCode == 'zh'
          ? zh.text(AppStringKeys.autoBookkeepingInstallButton)
          : en.text(AppStringKeys.autoBookkeepingInstallButton);

      expect(text, contains(expected));
      expect(
        text,
        anyOf(contains('快捷指令'), contains('shortcut'), contains('Shortcuts')),
        reason: 'iOS path should retain shortcut semantics.',
      );
    }
  });

  testWidgets('Android install entry opens AI route and queues parser flow', (
    tester,
  ) async {
    clearPendingHomeOverlayRequests();
    await tester.pumpWidget(
      _buildAppForPlatform(
        platform: TargetPlatform.android,
        locale: const Locale('zh'),
      ),
    );
    await tester.pump();
    expect(consumePendingHomeAiOpen(), isFalse);

    await tester.tap(
      find.text(
        AppStrings.forLocale(
          const Locale('zh'),
        ).text(AppStringKeys.autoBookkeepingInstallButtonAndroid),
      ),
    );
    await tester.pumpAndSettle();

    expect(consumePendingHomeAiOpen(), isTrue);
    expect(find.byKey(const Key('auto-bookkeeping-home-page')), findsOneWidget);
    expect(find.text('auto-bookkeeping-home-page-target'), findsOneWidget);
  });
}
