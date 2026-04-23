import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../../core/formatters/app_formatter.dart';
import '../../../../core/formatters/category_formatter.dart';
import '../../../../l10n/app_string_keys.dart';
import '../../../../l10n/app_strings.dart';
import '../../../../services/app_profile_service.dart';
import '../../../../services/injection.dart';
import '../widgets/textured_scaffold_background.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/entities.dart';
import '../bloc/account_bloc.dart';
import '../bloc/account_event.dart';
import '../bloc/account_state.dart';
import '../widgets/breathing_float.dart';
import '../widgets/premium_page_chrome.dart';
import '../widgets/premium_segmented_tabs.dart';
import '../widgets/premium_surface_card.dart';

const bool _screenshotReportsMock =
    String.fromEnvironment('SCREENSHOT_REPORTS_MOCK', defaultValue: '') == '1';

String _reportsMoney(num amount, {int decimalDigits = 2}) {
  final service = getIt<AppProfileService>();
  final symbol = AppFormatter.currencySymbol(
    currencyCode: service.currentBaseCurrency,
    locale: service.currentLocale,
  );
  final number = AppFormatter.formatDecimal(
    amount,
    locale: service.currentLocale,
    decimalDigits: decimalDigits,
  );
  return '$symbol$number';
}

String _reportsCategoryName(String id, String fallback) {
  final locale = getIt<AppProfileService>().currentLocale;
  return localizedCategoryName(id: id, fallback: fallback, locale: locale);
}

String _reportsMonthLabel(int year, int month) {
  final service = getIt<AppProfileService>();
  final locale = service.currentLocale;
  final tag = locale.countryCode == null
      ? locale.languageCode
      : '${locale.languageCode}_${locale.countryCode}';
  return DateFormat.yMMMM(tag).format(DateTime(year, month));
}

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PremiumPageAppBar(title: t.text(AppStringKeys.reportsTitle)),
      body: TexturedScaffoldBackground(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isTablet = constraints.maxWidth >= 768;
            final horizontalPadding = isTablet
                ? 24.0
                : (constraints.maxWidth > 520 ? 16.0 : 0.0);
            final maxContentWidth = isTablet
                ? (constraints.maxWidth >= 1024 ? 860.0 : 720.0)
                : (constraints.maxWidth > 560 ? 520.0 : constraints.maxWidth);

            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: BlocBuilder<AccountBloc, AccountState>(
                    builder: (context, state) {
                      return Column(
                        children: [
                          _MonthSelector(state: state),
                          Expanded(child: _ReportsBody(state: state)),
                        ],
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MonthSelector extends StatelessWidget {
  final AccountState state;

  const _MonthSelector({required this.state});

  @override
  Widget build(BuildContext context) {
    final monthLabel = _reportsMonthLabel(
      state.selectedYear,
      state.selectedMonth,
    );
    return PremiumMonthSwitcher(
      label: monthLabel,
      onPrevious: () {
        final bloc = context.read<AccountBloc>();
        int y = state.selectedYear;
        int m = state.selectedMonth - 1;
        if (m < 1) {
          m = 12;
          y--;
        }
        bloc.add(LoadEntriesByMonth(year: y, month: m));
      },
      onNext: () {
        final bloc = context.read<AccountBloc>();
        int y = state.selectedYear;
        int m = state.selectedMonth + 1;
        if (m > 12) {
          m = 1;
          y++;
        }
        bloc.add(LoadEntriesByMonth(year: y, month: m));
      },
    );
  }
}

class _ReportsBody extends StatefulWidget {
  final AccountState state;

  const _ReportsBody({required this.state});

  @override
  State<_ReportsBody> createState() => _ReportsBodyState();
}

class _ReportsBodyState extends State<_ReportsBody> {
  EntryType _selectedType = EntryType.expense;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final state = widget.state;

    if (state.status == AccountStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.entries.isEmpty && _screenshotReportsMock) {
      return const _ScreenshotReportsBody();
    }

    final selectedLabel = t.text(
      _selectedType == EntryType.expense
          ? AppStringKeys.reportsExpense
          : AppStringKeys.reportsIncome,
    );

    final typedEntries = state.entries
        .where((e) => e.type == _selectedType)
        .toList();
    final catMap = <String, double>{};
    for (final e in typedEntries) {
      catMap[e.category] = (catMap[e.category] ?? 0) + e.amount;
    }
    final sortedCats = catMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final selectedTotal = catMap.values.fold<double>(
      0,
      (sum, amount) => sum + amount,
    );

    final bottomInset = MediaQuery.of(context).padding.bottom + 130;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 月度卡片
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(AppColors.primary, Colors.white, 0.04)!,
                  Color.lerp(const Color(0xFF6D5DF6), Colors.white, 0.08)!,
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  top: -40,
                  right: -14,
                  child: IgnorePointer(
                    child: Container(
                      width: 144,
                      height: 144,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.18),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.14),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      t.text(
                        AppStringKeys.reportsMonthBill,
                        params: {
                          'month': _reportsMonthLabel(
                            state.selectedYear,
                            state.selectedMonth,
                          ),
                        },
                      ),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.text(AppStringKeys.reportsExpense),
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _reportsMoney(state.totalExpense),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 50, color: Colors.white30),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.text(AppStringKeys.reportsIncome),
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _reportsMoney(state.totalIncome),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        t.text(
                          AppStringKeys.reportsBalance,
                          params: {
                            'amount': _reportsMoney(
                              state.totalIncome - state.totalExpense,
                            ),
                          },
                        ),
                        style: const TextStyle(
                          color: Color(0xFF4A47D8),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // 支出分布
          PremiumSurfaceCard(
            padding: const EdgeInsets.all(16),
            radius: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PremiumSegmentedTabs(
                  labels: [
                    t.text(AppStringKeys.reportsExpense),
                    t.text(AppStringKeys.reportsIncome),
                  ],
                  selectedIndex: _selectedType == EntryType.expense ? 0 : 1,
                  onChanged: (index) {
                    setState(() {
                      _selectedType = index == 0
                          ? EntryType.expense
                          : EntryType.income;
                    });
                  },
                ),
                const SizedBox(height: 18),
                if (state.entries.isEmpty)
                  Column(
                    children: [
                      BreathingFloat(
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.bar_chart_rounded,
                            size: 32,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        t.text(AppStringKeys.reportsEmptyTitle),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t.text(AppStringKeys.reportsEmptySubtitle),
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  )
                else if (sortedCats.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: colors.secondaryBackground,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: colors.subtleBorder, width: 1),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.insights_rounded,
                          color: AppColors.primary.withValues(alpha: 0.72),
                          size: 28,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          t.text(
                            AppStringKeys.reportsBreakdownEmptyTitle,
                            params: {'type': selectedLabel},
                          ),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          t.text(
                            AppStringKeys.reportsBreakdownEmptySubtitle,
                            params: {'type': selectedLabel},
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Text(
                    t.text(
                      AppStringKeys.reportsDistributionTitle,
                      params: {'type': selectedLabel},
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 220,
                    child: Row(
                      children: [
                        Expanded(
                          child: PieChart(
                            PieChartData(
                              sections: sortedCats
                                  .take(6)
                                  .toList()
                                  .asMap()
                                  .entries
                                  .map((e) {
                                    return PieChartSectionData(
                                      value: e.value.value,
                                      title: '',
                                      color: AppColors.getCategoryColor(
                                        e.value.key,
                                      ),
                                      radius: 55,
                                    );
                                  })
                                  .toList(),
                              sectionsSpace: 1,
                              centerSpaceRadius: 40,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: sortedCats
                                .take(6)
                                .toList()
                                .asMap()
                                .entries
                                .map((e) {
                                  final cat = CategoryDef.findById(e.value.key);
                                  final pct = selectedTotal == 0
                                      ? 0
                                      : (e.value.value / selectedTotal * 100);
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: AppColors.getCategoryColor(
                                              e.value.key,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            cat == null
                                                ? e.value.key
                                                : _reportsCategoryName(
                                                    cat.id,
                                                    cat.name,
                                                  ),
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: colors.textPrimary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          '${pct.toStringAsFixed(0)}%',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colors.textSecondary,
                                          ),
                                          textAlign: TextAlign.right,
                                        ),
                                      ],
                                    ),
                                  );
                                })
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    t.text(
                      AppStringKeys.reportsCategoryRankTitle,
                      params: {'type': selectedLabel},
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...sortedCats.take(5).toList().asMap().entries.map((e) {
                    final cat = CategoryDef.findById(e.value.key);
                    final pct = selectedTotal == 0
                        ? 0.0
                        : e.value.value / selectedTotal;
                    final catColor = AppColors.getCategoryColor(e.value.key);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '${e.key + 1}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: colors.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 28,
                                    height: 28,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: catColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      cat?.icon ?? '📦',
                                      style: const TextStyle(fontSize: 15),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    cat == null
                                        ? e.value.key
                                        : _reportsCategoryName(
                                            cat.id,
                                            cat.name,
                                          ),
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                _reportsMoney(e.value.value),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pct,
                              backgroundColor: AppColors.primary.withValues(
                                alpha: 0.08,
                              ),
                              valueColor: AlwaysStoppedAnimation(catColor),
                              minHeight: 6,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScreenshotReportsBody extends StatelessWidget {
  const _ScreenshotReportsBody();

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final categories = [
      (_reportsCategoryName('food', '餐饮'), 1280.0, const Color(0xFF6D5DF6)),
      (_reportsCategoryName('transport', '交通'), 760.0, const Color(0xFF4A90E2)),
      (_reportsCategoryName('shopping', '购物'), 540.0, const Color(0xFFFF8A65)),
      (_reportsCategoryName('coffee', '咖啡'), 320.0, const Color(0xFF8D6E63)),
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        MediaQuery.of(context).padding.bottom + 130,
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(24),
            boxShadow: colors.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.text(AppStringKeys.reportsDistribution),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 220,
                child: LineChart(
                  LineChartData(
                    minX: 0,
                    maxX: 5,
                    minY: 0,
                    maxY: 2600,
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          getTitlesWidget: (value, meta) {
                            const labels = [
                              'Nov',
                              'Dec',
                              'Jan',
                              'Feb',
                              'Mar',
                              'Apr',
                            ];
                            final i = value.toInt();
                            if (i < 0 || i >= labels.length) {
                              return const SizedBox.shrink();
                            }
                            return Text(
                              labels[i],
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF8E8E93),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: 500,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: const Color(0xFFEDEAFB),
                        strokeWidth: 1,
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        isCurved: true,
                        color: const Color(0xFF6D5DF6),
                        barWidth: 4,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              const Color(0xFF6D5DF6).withValues(alpha: 0.24),
                              const Color(0xFF6D5DF6).withValues(alpha: 0.02),
                            ],
                          ),
                        ),
                        spots: const [
                          FlSpot(0, 980),
                          FlSpot(1, 1220),
                          FlSpot(2, 1160),
                          FlSpot(3, 1490),
                          FlSpot(4, 1730),
                          FlSpot(5, 2140),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(24),
            boxShadow: colors.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.text(AppStringKeys.reportsCategoryRank),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              ...categories.map((item) {
                final name = item.$1;
                final amount = item.$2;
                final color = item.$3;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        _reportsMoney(amount, decimalDigits: 0),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}
