import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_profile_service.dart';
import '../services/injection.dart';
import 'app_flavor.dart';
import '../l10n/app_string_keys.dart';
import '../l10n/app_strings.dart';
import '../core/theme/app_colors.dart';
import '../features/accounting/presentation/pages/home_page.dart';
import '../features/accounting/presentation/pages/transactions_page.dart';
import '../features/accounting/presentation/pages/reports_page.dart';
import '../features/accounting/presentation/pages/settings_page.dart';
import '../features/accounting/presentation/pages/prediction_page.dart';
import '../features/accounting/presentation/pages/welcome_page.dart';
import '../features/accounting/presentation/pages/phone_login_page.dart';
import '../features/accounting/presentation/pages/intl_auth_page.dart';
import '../features/accounting/presentation/pages/intl_email_login_page.dart';
import '../features/accounting/presentation/pages/asset_management_page.dart';
import '../features/accounting/presentation/widgets/ai_sparkles_icon.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

/// 用于跨页面触发首页 AI 弹窗
final homeAiTrigger = ValueNotifier<int>(0);
final homeQuickAddTrigger = ValueNotifier<int>(0);
bool _pendingHomeAiOpen = false;
bool _pendingHomeQuickAddOpen = false;

void queueHomeAiOpenAfterNavigation() {
  _pendingHomeAiOpen = true;
}

bool consumePendingHomeAiOpen() {
  if (!_pendingHomeAiOpen) return false;
  _pendingHomeAiOpen = false;
  return true;
}

void queueHomeQuickAddOpenAfterNavigation() {
  _pendingHomeQuickAddOpen = true;
}

bool consumePendingHomeQuickAddOpen() {
  if (!_pendingHomeQuickAddOpen) return false;
  _pendingHomeQuickAddOpen = false;
  return true;
}

void clearPendingHomeOverlayRequests() {
  _pendingHomeAiOpen = false;
  _pendingHomeQuickAddOpen = false;
}

// 初始路由由 checkFirstTime() 决定，见下方
final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/splash',
  redirect: (context, state) {
    // splash 路由用于判断是否首次登录，由它重定向到 welcome 或 home
    return null;
  },
  routes: [
    // 闪屏/判断页
    GoRoute(path: '/splash', builder: (context, state) => const _SplashPage()),
    // 欢迎页
    GoRoute(path: '/welcome', builder: (context, state) => const WelcomePage()),
    // 手机登录
    GoRoute(
      path: '/phone_login',
      builder: (context, state) =>
          getIt<AppProfileService>().flavor == AppFlavor.intl
          ? const IntlAuthPage()
          : const PhoneLoginPage(),
    ),
    GoRoute(
      path: '/intl_email_login',
      builder: (context, state) => const IntlEmailLoginPage(),
    ),
    // 主页面（ShellRoute 含底部导航）
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) {
        return MainScaffold(child: child);
      },
      routes: [
        GoRoute(
          path: '/home',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: HomePage()),
        ),
        GoRoute(
          path: '/transactions',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: TransactionsPage()),
        ),
        GoRoute(
          path: '/reports',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: ReportsPage()),
        ),
        GoRoute(
          path: '/analysis',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: PredictionPage()),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: SettingsPage()),
        ),
        GoRoute(
          path: '/asset',
          builder: (context, state) => AssetManagementPage(),
        ),
      ],
    ),
  ],
);

// 闪屏页：判断是否已登录，决定跳转
class _SplashPage extends StatefulWidget {
  const _SplashPage();

  @override
  State<_SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<_SplashPage> {
  static const _screenshotOverlay = String.fromEnvironment(
    'SCREENSHOT_OVERLAY',
    defaultValue: '',
  );
  static const _screenshotTargetRoute = String.fromEnvironment(
    'SCREENSHOT_TARGET_ROUTE',
    defaultValue: '',
  );
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  void _goSafely(String location) {
    if (!mounted || _navigated) return;
    _navigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(location);
    });
  }

  Future<void> _checkLogin() async {
    try {
      // 冷启动时直接复用注入好的 SharedPreferences，避免 splash 阶段再次走插件初始化导致卡在 logo。
      final prefs = getIt<SharedPreferences>();
      final hasLoggedIn = prefs.getBool('has_logged_in') ?? false;
      debugPrint('[Splash] has_logged_in=$hasLoggedIn');
      if (hasLoggedIn) {
        if (_screenshotOverlay == 'ai') {
          queueHomeAiOpenAfterNavigation();
        } else if (_screenshotOverlay == 'quickadd') {
          queueHomeQuickAddOpenAfterNavigation();
        }
      }
      final targetRoute = hasLoggedIn
          ? (_screenshotTargetRoute.startsWith('/')
                ? _screenshotTargetRoute
                : '/home')
          : '/welcome';
      _goSafely(targetRoute);
    } catch (e, st) {
      debugPrint('[Splash] checkLogin error: $e\n$st');
      _goSafely('/welcome');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/icon_brand_primary.png',
                width: 72,
                height: 72,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              t.text(AppStringKeys.appTitle),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class MainScaffold extends StatelessWidget {
  final Widget child;

  const MainScaffold({super.key, required this.child});

  int _getCurrentIndex(BuildContext context) {
    final loc = GoRouterState.of(context).uri.path;
    if (loc.startsWith('/home')) return 0;
    if (loc.startsWith('/transactions')) return 1;
    if (loc.startsWith('/reports')) return 2;
    if (loc.startsWith('/analysis')) return 3;
    if (loc.startsWith('/settings')) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final compactNav = MediaQuery.of(context).size.width < 410;
    final outerHorizontalPadding = compactNav ? 14.0 : 18.0;
    final innerHorizontalPadding = compactNav ? 8.0 : 12.0;
    final navGap = compactNav ? 6.0 : 8.0;
    final centerGap = compactNav ? 10.0 : 12.0;
    final centerButtonSize = compactNav ? 48.0 : 54.0;
    final centerIconSize = compactNav ? 26.0 : 28.0;

    return Scaffold(
      extendBody: true,
      body: child,
      bottomNavigationBar: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: outerHorizontalPadding,
            right: outerHorizontalPadding,
            bottom: MediaQuery.of(context).padding.bottom + 2,
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(34),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(
                    alpha: isDark ? 0.24 : 0.10,
                  ),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: (isDark ? Colors.black : const Color(0xFF1A1A2E))
                      .withValues(alpha: isDark ? 0.28 : 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(34),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: innerHorizontalPadding,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: (isDark ? colors.cardBackground : Colors.white)
                        .withValues(alpha: isDark ? 0.74 : 0.80),
                    border: Border.all(
                      color: (isDark ? Colors.white : colors.textSecondary)
                          .withValues(alpha: isDark ? 0.10 : 0.14),
                      width: 1.2,
                    ),
                    borderRadius: BorderRadius.circular(34),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: _PremiumNavBarItem(
                                icon: Icons.home_outlined,
                                selectedIcon: Icons.home_rounded,
                                label: t.text(AppStringKeys.navHome),
                                isSelected: _getCurrentIndex(context) == 0,
                                compact: compactNav,
                                onTap: () {
                                  clearPendingHomeOverlayRequests();
                                  context.go('/home');
                                },
                              ),
                            ),
                            SizedBox(width: navGap),
                            Expanded(
                              child: Transform.translate(
                                offset: const Offset(-5, 0),
                                child: _PremiumNavBarItem(
                                  icon: Icons.receipt_long_outlined,
                                  selectedIcon: Icons.receipt_long_rounded,
                                  label: t.text(AppStringKeys.navTransactions),
                                  isSelected: _getCurrentIndex(context) == 1,
                                  compact: compactNav,
                                  onTap: () {
                                    clearPendingHomeOverlayRequests();
                                    context.go('/transactions');
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              final currentPath = GoRouterState.of(
                                context,
                              ).uri.path;
                              if (currentPath.startsWith('/home')) {
                                homeAiTrigger.value++;
                                return;
                              }
                              queueHomeAiOpenAfterNavigation();
                              context.go('/home');
                            },
                            child: Container(
                              width: centerButtonSize,
                              height: centerButtonSize,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF5B42F3),
                                    Color(0xFFB61FFF),
                                  ],
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF8C35FF,
                                    ).withValues(alpha: 0.24),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  width: 1,
                                ),
                              ),
                              child: Center(
                                child: AiSparklesIcon(
                                  size: centerIconSize,
                                  color: Colors.white,
                                  accentColor: const Color(0xFFF6E27A),
                                  strokeWidthFactor: 0.1,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: centerGap),
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              final currentPath = GoRouterState.of(
                                context,
                              ).uri.path;
                              if (currentPath.startsWith('/home')) {
                                homeQuickAddTrigger.value++;
                                return;
                              }
                              queueHomeQuickAddOpenAfterNavigation();
                              context.go('/home');
                            },
                            child: Container(
                              width: centerButtonSize,
                              height: centerButtonSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF6B4DFF),
                                    Color(0xFF4A47D8),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF4A47D8,
                                    ).withValues(alpha: 0.28),
                                    blurRadius: 12,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.38),
                                  width: 1.2,
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.add_rounded,
                                  color: Colors.white,
                                  size: centerIconSize,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: Transform.translate(
                                offset: const Offset(5, 0),
                                child: _PremiumNavBarItem(
                                  icon: Icons.bar_chart_outlined,
                                  selectedIcon: Icons.bar_chart_rounded,
                                  label: t.text(AppStringKeys.navReports),
                                  isSelected: _getCurrentIndex(context) == 2,
                                  compact: compactNav,
                                  onTap: () {
                                    clearPendingHomeOverlayRequests();
                                    context.go('/reports');
                                  },
                                ),
                              ),
                            ),
                            SizedBox(width: navGap),
                            Expanded(
                              child: _PremiumNavBarItem(
                                icon: Icons.auto_awesome_outlined,
                                selectedIcon: Icons.auto_awesome_rounded,
                                label: t.text(AppStringKeys.navAnalysis),
                                isSelected: _getCurrentIndex(context) == 3,
                                compact: compactNav,
                                onTap: () {
                                  clearPendingHomeOverlayRequests();
                                  context.go('/analysis');
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PremiumNavBarItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final bool compact;
  final VoidCallback onTap;

  const _PremiumNavBarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 4 : 6,
          vertical: compact ? 6 : 7,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? selectedIcon : icon,
              color: isSelected ? AppColors.primary : colors.textSecondary,
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 9.5 : 10.0,
                fontWeight: FontWeight.w400,
                height: 1.0,
                letterSpacing: 0.1,
                color: isSelected ? AppColors.primary : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
