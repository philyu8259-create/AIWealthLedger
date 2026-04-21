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
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/entities.dart';
import '../bloc/account_bloc.dart';
import '../bloc/account_event.dart';
import '../bloc/account_state.dart';
import '../widgets/breathing_float.dart';
import '../widgets/press_feedback.dart';

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
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF4A47D8), Color(0xFF6D5DF6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          t.text(AppStringKeys.reportsTitle),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: LayoutBuilder(
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final arrowSize = compact ? 36.0 : 40.0;
        final gap = compact ? 8.0 : 12.0;

        Widget arrowButton(IconData icon, VoidCallback onTap) {
          return PressFeedback(
            onTap: onTap,
            child: Container(
              width: arrowSize,
              height: arrowSize,
              decoration: BoxDecoration(
                color: const Color(0xFF4A47D8),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: Colors.white, size: compact ? 20 : 24),
            ),
          );
        }

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: compact ? 16 : 20,
          ),
          child: Row(
            children: [
              arrowButton(Icons.chevron_left, () {
                final bloc = context.read<AccountBloc>();
                int y = state.selectedYear;
                int m = state.selectedMonth - 1;
                if (m < 1) {
                  m = 12;
                  y--;
                }
                bloc.add(LoadEntriesByMonth(year: y, month: m));
              }),
              SizedBox(width: gap),
              Expanded(
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 12 : 16,
                    vertical: compact ? 8 : 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F1FF),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF4A47D8),
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    monthLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: compact ? 15 : 16,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF4A47D8),
                    ),
                  ),
                ),
              ),
              SizedBox(width: gap),
              arrowButton(Icons.chevron_right, () {
                final bloc = context.read<AccountBloc>();
                int y = state.selectedYear;
                int m = state.selectedMonth + 1;
                if (m > 12) {
                  m = 1;
                  y++;
                }
                bloc.add(LoadEntriesByMonth(year: y, month: m));
              }),
            ],
          ),
        );
      },
    );
  }
}

class _ReportsBody extends StatelessWidget {
  final AccountState state;

  const _ReportsBody({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    if (state.status == AccountStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t.text(AppStringKeys.reportsEmptySubtitle),
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ],
        ),
      );
    }

    // Category breakdown for expense
    final catMap = <String, double>{};
    for (final e in state.entries.where((e) => e.type == EntryType.expense)) {
      catMap[e.category] = (catMap[e.category] ?? 0) + e.amount;
    }
    final sortedCats = catMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 月度卡片
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4A47D8), Color(0xFF6D5DF6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
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
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
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
                    borderRadius: BorderRadius.circular(8),
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
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // 支出分布
          if (sortedCats.isNotEmpty) ...[
            Text(
              t.text(AppStringKeys.reportsDistribution),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
                                color: AppColors.getCategoryColor(e.value.key),
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
                      children: sortedCats.take(6).toList().asMap().entries.map(
                        (e) {
                          final cat = CategoryDef.findById(e.value.key);
                          final pct =
                              (e.value.value / state.totalExpense * 100);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
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
                                    style: const TextStyle(fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '${pct.toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ],
                            ),
                          );
                        },
                      ).toList(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Top 支出类目
            Text(
              t.text(AppStringKeys.reportsCategoryRank),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ...sortedCats.take(5).toList().asMap().entries.map((e) {
              final cat = CategoryDef.findById(e.value.key);
              final pct = e.value.value / state.totalExpense;
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
                                color: Colors.grey.shade400,
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
                                  : _reportsCategoryName(cat.id, cat.name),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                        Text(
                          _reportsMoney(e.value.value),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation(
                          AppColors.getCategoryColor(e.value.key),
                        ),
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
    );
  }
}
