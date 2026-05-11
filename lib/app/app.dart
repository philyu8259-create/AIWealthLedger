import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme/app_colors.dart';
import '../l10n/app_string_keys.dart';
import '../l10n/app_strings.dart';
import '../features/accounting/presentation/bloc/account_bloc.dart';
import '../features/accounting/presentation/bloc/custom_category/custom_category_bloc.dart';
import '../features/accounting/presentation/bloc/custom_category/custom_category_event.dart';
import '../services/app_profile_service.dart';
import '../services/auto_bookkeeping_shortcut_service.dart';
import '../services/injection.dart';
import '../services/theme_mode_service.dart';
import 'router.dart';

class AIAccountingApp extends StatefulWidget {
  const AIAccountingApp({super.key});

  @override
  State<AIAccountingApp> createState() => _AIAccountingAppState();
}

class _AIAccountingAppState extends State<AIAccountingApp> {
  StreamSubscription<String>? _shortcutSubscription;

  @override
  void initState() {
    super.initState();
    final shortcutService = getIt<AutoBookkeepingShortcutService>();
    shortcutService.start();
    _shortcutSubscription = shortcutService.textRequests.listen(
      _handleShortcutText,
    );
  }

  @override
  void dispose() {
    _shortcutSubscription?.cancel();
    super.dispose();
  }

  void _handleShortcutText(String text) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final hasLoggedIn =
          getIt<SharedPreferences>().getBool('has_logged_in') ?? false;
      if (!hasLoggedIn) return;

      final currentPath = appRouter.routeInformationProvider.value.uri.path;
      if (currentPath.startsWith('/home')) {
        deliverHomeShortcutText(text);
        return;
      }

      queueHomeShortcutTextAfterNavigation(text);
      appRouter.go('/home');
    });
  }

  @override
  Widget build(BuildContext context) {
    final profileService = getIt<AppProfileService>();
    final themeModeService = getIt<ThemeModeService>();
    return ListenableBuilder(
      listenable: Listenable.merge([profileService, themeModeService]),
      builder: (context, _) {
        final profile = profileService.currentProfile;
        final appStrings = AppStrings.forLocale(profile.localeProfile.locale);
        return MultiBlocProvider(
          key: ValueKey(
            '${profile.flavor.name}:${profile.localeProfile.localeTag}:${profile.localeProfile.countryCode}',
          ),
          providers: [
            BlocProvider(create: (_) => getIt<AccountBloc>()),
            BlocProvider(
              create: (_) =>
                  getIt<CustomCategoryBloc>()
                    ..add(const LoadCustomCategories()),
            ),
          ],
          child: MaterialApp.router(
            title: appStrings.text(AppStringKeys.appTitle),
            debugShowCheckedModeBanner: false,
            locale: profile.localeProfile.locale,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: profileService.supportedLocales,
            theme: ThemeData(
              brightness: Brightness.light,
              colorScheme: ColorScheme.fromSeed(
                seedColor: AppColors.primary,
                brightness: Brightness.light,
              ),
              useMaterial3: true,
              scaffoldBackgroundColor: AppColorsExtension.light.background,
              extensions: <ThemeExtension<dynamic>>[AppColorsExtension.light],
              appBarTheme: const AppBarTheme(
                centerTitle: true,
                elevation: 0,
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.black87,
              ),
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              colorScheme: ColorScheme.fromSeed(
                seedColor: AppColors.primary,
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
              scaffoldBackgroundColor: AppColorsExtension.dark.background,
              extensions: <ThemeExtension<dynamic>>[AppColorsExtension.dark],
              appBarTheme: const AppBarTheme(
                centerTitle: true,
                elevation: 0,
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
              ),
            ),
            themeMode: themeModeService.themeMode,
            scrollBehavior: const _DesktopAwareScrollBehavior(),
            routerConfig: appRouter,
          ),
        );
      },
    );
  }
}

class _DesktopAwareScrollBehavior extends MaterialScrollBehavior {
  const _DesktopAwareScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices {
    final devices = super.dragDevices;
    if (defaultTargetPlatform != TargetPlatform.macOS) return devices;

    return {...devices, PointerDeviceKind.mouse, PointerDeviceKind.trackpad};
  }
}
