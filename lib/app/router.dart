import 'package:flutter/material.dart';
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
      _goSafely(hasLoggedIn ? '/home' : '/welcome');
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
            const Icon(
              Icons.account_balance_wallet,
              size: 64,
              color: AppColors.primary,
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
    return Scaffold(
      body: child,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () {
                context.go('/home');
                homeAiTrigger.value++;
              },
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF5B42F3),
                      Color(0xFF7D31FF),
                      Color(0xFFB61FFF),
                    ],
                    stops: [0.0, 0.5, 1.0],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8C35FF).withValues(alpha: 0.28),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Center(
                  child: AiSparklesIcon(
                    size: 27,
                    color: Color(0xFFF6E27A),
                    accentColor: Color(0xFFF6E27A),
                    strokeWidthFactor: 0.115,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () {
                final currentPath = GoRouterState.of(context).uri.path;
                if (currentPath.startsWith('/home')) {
                  showHomeAddEntrySheet(context);
                  return;
                }
                context.go('/home');
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final shellContext = _shellNavigatorKey.currentContext;
                  if (shellContext != null) {
                    showHomeAddEntrySheet(shellContext);
                  }
                });
              },
              child: Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Color(0xFF333A4D),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _NavBarItem(
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home,
                  label: '',
                  isSelected: _getCurrentIndex(context) == 0,
                  onTap: () => context.go('/home'),
                ),
                _NavBarItem(
                  icon: Icons.receipt_long_outlined,
                  selectedIcon: Icons.receipt_long,
                  label: '',
                  isSelected: _getCurrentIndex(context) == 1,
                  onTap: () => context.go('/transactions'),
                ),
                // 中间留白给 FloatingActionButton
                const SizedBox(width: 120),
                _NavBarItem(
                  icon: Icons.bar_chart_outlined,
                  selectedIcon: Icons.bar_chart,
                  label: '',
                  isSelected: _getCurrentIndex(context) == 2,
                  onTap: () => context.go('/reports'),
                ),
                _NavBarItem(
                  icon: Icons.auto_awesome_outlined,
                  selectedIcon: Icons.auto_awesome,
                  label: '',
                  isSelected: _getCurrentIndex(context) == 3,
                  onTap: () => context.go('/analysis'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          isSelected ? selectedIcon : icon,
          color: isSelected
              ? AppColors.primary
              : Colors.grey.shade400,
          size: 28,
        ),
      ),
    );
  }
}
