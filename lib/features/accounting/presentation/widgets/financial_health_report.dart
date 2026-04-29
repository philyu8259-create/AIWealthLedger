import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/formatters/app_formatter.dart';
import '../../../../core/formatters/category_formatter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../services/app_profile_service.dart';
import '../../../../services/injection.dart';
import '../../domain/entities/entities.dart';
import '../../domain/entities/stock_position.dart';
import 'press_feedback.dart';
import 'premium_surface_card.dart';

class FinancialHealthReport {
  const FinancialHealthReport({
    required this.score,
    required this.income,
    required this.expense,
    required this.balance,
    required this.savingsRate,
    required this.expenseChangePercent,
    required this.entryCount,
    required this.topExpenseCategory,
    required this.topExpenseAmount,
    required this.assetTotal,
    required this.assetChangeAmount,
    required this.assetChangePercent,
    required this.stockCount,
    required this.stockMarketValue,
    required this.stockProfitAmount,
    required this.stockProfitPercent,
    required this.stockRiskCount,
  });

  final int score;
  final double income;
  final double expense;
  final double balance;
  final double savingsRate;
  final double expenseChangePercent;
  final int entryCount;
  final String? topExpenseCategory;
  final double topExpenseAmount;
  final double assetTotal;
  final double assetChangeAmount;
  final double? assetChangePercent;
  final int stockCount;
  final double stockMarketValue;
  final double stockProfitAmount;
  final double? stockProfitPercent;
  final int stockRiskCount;
  bool get shouldShowAssetMetrics => hasAssetData || hasStockData;

  factory FinancialHealthReport.fromEntries({
    required List<AccountEntry> entries,
    required int year,
    required int month,
    double? lastMonthExpense,
    double? lastMonthIncome,
    List<Asset> assets = const [],
    List<StockPosition> stocks = const [],
  }) {
    final currentEntries = entries
        .where((entry) => entry.date.year == year && entry.date.month == month)
        .toList();
    final income = currentEntries
        .where((entry) => entry.type == EntryType.income)
        .fold<double>(0, (sum, entry) => sum + entry.amount);
    final expense = currentEntries
        .where((entry) => entry.type == EntryType.expense)
        .fold<double>(0, (sum, entry) => sum + entry.amount);
    final balance = income - expense;
    final savingsRate = income <= 0 ? 0.0 : (balance / income);

    final previousExpense = lastMonthExpense ?? 0;
    final expenseChangePercent = previousExpense <= 0
        ? 0.0
        : ((expense - previousExpense) / previousExpense) * 100;

    final categoryTotals = <String, double>{};
    for (final entry in currentEntries) {
      if (entry.type != EntryType.expense) continue;
      categoryTotals.update(
        entry.category,
        (value) => value + entry.amount,
        ifAbsent: () => entry.amount,
      );
    }
    final topCategory = categoryTotals.entries.isEmpty
        ? null
        : (categoryTotals.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .first;

    final otherAssetsTotal = assets.fold<double>(
      0,
      (sum, asset) => sum + asset.balance,
    );
    final stockMarketValue = stocks.fold<double>(
      0,
      (sum, stock) => sum + stock.marketValue,
    );
    final stockCostBasis = stocks.fold<double>(
      0,
      (sum, stock) => sum + ((stock.costPrice ?? 0) * stock.quantity),
    );
    final stockProfitAmount = stocks.fold<double>(
      0,
      (sum, stock) => sum + (stock.profitAmount ?? 0),
    );
    final stockProfitPercent = stockCostBasis > 0
        ? (stockProfitAmount / stockCostBasis) * 100
        : null;
    final assetTotal = otherAssetsTotal + stockMarketValue;
    final assetChangePercent = assetTotal > 0
        ? (stockProfitAmount / assetTotal) * 100
        : null;
    final stockRiskCount = stocks
        .where(
          (stock) =>
              (stock.profitPercent ?? 0) <= -8 ||
              (stock.changePercent ?? 0).abs() >= 3 ||
              stock.quoteStatus != StockQuoteStatus.normal,
        )
        .length;

    var score = 64;
    score += (savingsRate * 42).round();
    if (balance < 0) score -= 18;
    if (expenseChangePercent > 25) score -= 12;
    if (expenseChangePercent < -8) score += 6;
    if (stockProfitPercent != null && stockProfitPercent < -8) score -= 8;
    if (stockRiskCount >= 2) score -= 6;
    if (assetTotal > 0 && balance > 0) score += 4;
    if (currentEntries.length >= 12) score += 5;
    if (currentEntries.length < 5) score -= 6;
    score = score.clamp(35, 96);

    return FinancialHealthReport(
      score: score,
      income: income,
      expense: expense,
      balance: balance,
      savingsRate: savingsRate,
      expenseChangePercent: expenseChangePercent,
      entryCount: currentEntries.length,
      topExpenseCategory: topCategory?.key,
      topExpenseAmount: topCategory?.value ?? 0,
      assetTotal: assetTotal,
      assetChangeAmount: stockProfitAmount,
      assetChangePercent: assetChangePercent,
      stockCount: stocks.length,
      stockMarketValue: stockMarketValue,
      stockProfitAmount: stockProfitAmount,
      stockProfitPercent: stockProfitPercent,
      stockRiskCount: stockRiskCount,
    );
  }

  bool get isSparse => entryCount < 5;
  bool get hasPositiveCashflow => balance >= 0;
  bool get isExpenseRising => expenseChangePercent >= 20;
  bool get isExpenseFalling => expenseChangePercent <= -8;
  bool get hasAssetData => assetTotal > 0;
  bool get hasStockData => stockCount > 0;
  bool get hasStockRisk =>
      stockRiskCount > 0 ||
      (stockProfitPercent != null && stockProfitPercent! < -5);

  FinancialHealthLevel get level {
    if (score >= 85) return FinancialHealthLevel.excellent;
    if (score >= 72) return FinancialHealthLevel.steady;
    if (score >= 58) return FinancialHealthLevel.watch;
    return FinancialHealthLevel.risk;
  }
}

enum FinancialHealthLevel { excellent, steady, watch, risk }

class FinancialHealthTeaserCard extends StatelessWidget {
  const FinancialHealthTeaserCard({
    super.key,
    required this.report,
    required this.onTap,
  });

  final FinancialHealthReport report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final copy = _HealthCopy(context);
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: PressFeedback(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primary.withValues(alpha: 0.13),
                AppColors.marketUpUs.withValues(alpha: 0.07),
                colors.cardBackground.withValues(alpha: 0.84),
              ],
            ),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            children: [
              _ScoreOrb(score: report.score, size: 58),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      copy.title,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      copy.homeHeadline(report),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FinancialHealthDetailCard extends StatelessWidget {
  const FinancialHealthDetailCard({super.key, required this.report});

  final FinancialHealthReport report;

  @override
  Widget build(BuildContext context) {
    final copy = _HealthCopy(context);
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final signals = copy.signals(report);
    final actions = copy.actions(report);

    return PremiumSurfaceCard(
      radius: 28,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ScoreOrb(score: report.score, size: 74),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      copy.fullTitle,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      copy.level(report.level),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      copy.fullSubtitle(report),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _MetricPill(
                  label: copy.cashflow,
                  value: _healthMoney(report.balance),
                  tint: report.balance >= 0
                      ? AppColors.marketUpUs
                      : AppColors.error,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricPill(
                  label: copy.expenseTrend,
                  value: _signedPercent(report.expenseChangePercent),
                  tint: report.isExpenseRising
                      ? AppColors.error
                      : AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricPill(
                  label: copy.dataDepth,
                  value: '${report.entryCount}',
                  tint: AppColors.primary,
                ),
              ),
            ],
          ),
          if (report.shouldShowAssetMetrics) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _MetricPill(
                    label: copy.assetChange,
                    value: report.hasAssetData
                        ? _healthMoney(report.assetTotal)
                        : copy.noDataShort,
                    tint: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricPill(
                    label: copy.stockRisk,
                    value: report.hasStockData
                        ? (report.hasStockRisk
                              ? copy.riskCount(report.stockRiskCount)
                              : copy.lowRiskShort)
                        : copy.noDataShort,
                    tint: report.hasStockRisk
                        ? AppColors.error
                        : AppColors.marketUpUs,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          Text(
            copy.diagnosis,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          ...signals.map(
            (signal) => _SignalRow(
              icon: signal.icon,
              title: signal.title,
              body: signal.body,
              color: signal.color,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            copy.nextActions,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          ...actions.map(
            (action) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      action,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthSignal {
  const _HealthSignal({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;
}

class _ScoreOrb extends StatelessWidget {
  const _ScoreOrb({required this.score, required this.size});

  final int score;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6D5DF6), Color(0xFF2E2AA8)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: Text(
          '$score',
          style: TextStyle(
            color: Colors.white,
            fontSize: size >= 70 ? 24 : 20,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.8,
          ),
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    required this.value,
    required this.tint,
  });

  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tint.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: colors.textSecondary),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalRow extends StatelessWidget {
  const _SignalRow({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    height: 1.35,
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

class _HealthCopy {
  _HealthCopy(BuildContext context) : locale = Localizations.localeOf(context);

  final Locale locale;

  bool get isZh => locale.languageCode == 'zh';

  String pick(String zh, String en) => isZh ? zh : en;

  String get title => pick('AI 财务体检', 'AI Money Checkup');
  String get fullTitle => pick('本月财务健康报告', 'Monthly Money Health Report');
  String get cashflow => pick('现金流', 'Cash flow');
  String get expenseTrend => pick('支出趋势', 'Spend trend');
  String get dataDepth => pick('数据笔数', 'Entries');
  String get assetChange => pick('资产变化', 'Assets');
  String get stockRisk => pick('股票风险', 'Stock risk');
  String get diagnosis => pick('完整诊断', 'Full diagnosis');
  String get nextActions => pick('建议动作', 'Suggested actions');
  String get noDataShort => pick('待完善', 'Pending');
  String get lowRiskShort => pick('低风险', 'Low');

  String riskCount(int count) => pick('$count 项关注', '$count alerts');

  String level(FinancialHealthLevel level) {
    switch (level) {
      case FinancialHealthLevel.excellent:
        return pick('优秀 · 现金流很稳', 'Excellent · steady cash flow');
      case FinancialHealthLevel.steady:
        return pick('健康 · 继续保持', 'Healthy · keep it steady');
      case FinancialHealthLevel.watch:
        return pick('关注 · 有几项波动', 'Watch · a few signals moved');
      case FinancialHealthLevel.risk:
        return pick('偏紧 · 需要调整', 'Tight · needs attention');
    }
  }

  String homeHeadline(FinancialHealthReport report) {
    final balance = _healthMoney(report.balance);
    if (report.isSparse) {
      return pick(
        '已生成完整诊断，多记几笔会更准',
        'Full diagnosis ready. More entries will sharpen it.',
      );
    }
    if (!report.hasPositiveCashflow) {
      return pick(
        '本月现金流为 $balance，建议优先收紧高频支出',
        'Cash flow is $balance. Start with frequent expenses.',
      );
    }
    if (report.isExpenseRising) {
      return pick(
        '支出较上月上涨 ${_signedPercent(report.expenseChangePercent)}，建议复盘大类目',
        'Spending is ${_signedPercent(report.expenseChangePercent)} vs last month. Review top categories.',
      );
    }
    return pick(
      '本月现金流 $balance，整体节奏不错',
      'Cash flow is $balance. Your month looks balanced.',
    );
  }

  String fullSubtitle(FinancialHealthReport report) {
    return pick(
      '覆盖现金流、消费异常、资产变化、股票风险和预算建议；免费用户也可查看完整诊断。',
      'Covers cash flow, spending anomalies, asset movement, stock risk, and budget suggestions. Free users can see it too.',
    );
  }

  List<_HealthSignal> signals(FinancialHealthReport report) {
    final topCategory = _topCategoryName(report.topExpenseCategory);
    final signals = <_HealthSignal>[];

    signals.add(
      _HealthSignal(
        icon: report.hasPositiveCashflow
            ? Icons.savings_rounded
            : Icons.priority_high_rounded,
        color: report.hasPositiveCashflow
            ? AppColors.marketUpUs
            : AppColors.error,
        title: report.hasPositiveCashflow
            ? pick('现金流为正', 'Positive cash flow')
            : pick('现金流承压', 'Cash flow pressure'),
        body: report.hasPositiveCashflow
            ? pick(
                '本月结余 ${_healthMoney(report.balance)}，可继续积累备用金或投资预算。',
                'You have ${_healthMoney(report.balance)} left this month, useful for savings or investing budget.',
              )
            : pick(
                '本月结余 ${_healthMoney(report.balance)}，建议先检查非必要支出。',
                'This month is at ${_healthMoney(report.balance)}. Review nonessential spending first.',
              ),
      ),
    );

    if (report.isExpenseRising) {
      signals.add(
        _HealthSignal(
          icon: Icons.trending_up_rounded,
          color: AppColors.error,
          title: pick('支出明显上升', 'Spending rose quickly'),
          body: pick(
            '本月支出较上月增加 ${_signedPercent(report.expenseChangePercent)}，适合查看是否有一次性大额或订阅扣费。',
            'Spending is ${_signedPercent(report.expenseChangePercent)} versus last month. Check one-off purchases or recurring charges.',
          ),
        ),
      );
    } else if (report.isExpenseFalling) {
      signals.add(
        _HealthSignal(
          icon: Icons.trending_down_rounded,
          color: AppColors.marketUpUs,
          title: pick('支出有所回落', 'Spending cooled down'),
          body: pick(
            '本月支出较上月下降 ${_signedPercent(report.expenseChangePercent)}，当前控制节奏值得保持。',
            'Spending is ${_signedPercent(report.expenseChangePercent)} versus last month. Keep this pace.',
          ),
        ),
      );
    }

    if (!report.isExpenseRising && !report.isExpenseFalling) {
      signals.add(
        _HealthSignal(
          icon: Icons.track_changes_rounded,
          color: AppColors.primary,
          title: pick('消费异常：暂未发现明显跳升', 'Anomaly check: no major jump'),
          body: pick(
            '本月支出较上月 ${_signedPercent(report.expenseChangePercent)}，整体节奏相对稳定。',
            'Spending is ${_signedPercent(report.expenseChangePercent)} versus last month, which looks relatively stable.',
          ),
        ),
      );
    }

    signals.add(_assetSignal(report));
    signals.add(_stockSignal(report));
    signals.add(_budgetSignal(report, topCategory));

    if (report.isSparse) {
      signals.add(
        _HealthSignal(
          icon: Icons.data_thresholding_rounded,
          color: AppColors.warning,
          title: pick('样本还偏少', 'Limited data sample'),
          body: pick(
            '当前只有 ${report.entryCount} 笔本月账单，诊断完整但准确度会随记录增加而提升。',
            'There are ${report.entryCount} entries this month. The diagnosis is complete, but accuracy improves as you record more.',
          ),
        ),
      );
    }

    return signals;
  }

  List<String> actions(FinancialHealthReport report) {
    final topCategory = _topCategoryName(report.topExpenseCategory);
    final actions = <String>[];
    if (report.topExpenseCategory != null) {
      actions.add(
        pick(
          '先复盘 $topCategory，找出 1 个可以减少的高频消费。',
          'Review $topCategory first and trim one frequent expense.',
        ),
      );
      actions.add(
        pick(
          '下月给 $topCategory 设置约 ${_healthMoney(report.topExpenseAmount * 0.9)} 的预算上限。',
          'Set next month’s $topCategory budget near ${_healthMoney(report.topExpenseAmount * 0.9)}.',
        ),
      );
    }
    if (report.hasPositiveCashflow) {
      actions.add(
        pick(
          '把本月结余的一部分固定为备用金或投资额度。',
          'Set aside part of this month’s surplus for savings or investing.',
        ),
      );
    } else {
      actions.add(
        pick(
          '先暂停 1-2 项非必要消费，优先把现金流拉回正数。',
          'Pause one or two nonessential expenses to bring cash flow back above zero.',
        ),
      );
    }
    if (!report.hasAssetData) {
      actions.add(
        pick(
          '补齐现金、银行卡、基金或股票资产后，资产变化诊断会更完整。',
          'Add cash, bank, fund, or stock assets to unlock a fuller asset diagnosis.',
        ),
      );
    } else if (report.hasStockRisk) {
      actions.add(
        pick(
          '优先复盘波动较大或亏损较深的股票，避免单一持仓拖累总资产。',
          'Review volatile or deeply losing positions first so one stock does not drag total assets.',
        ),
      );
    }
    if (report.isSparse) {
      actions.add(
        pick(
          '继续使用语音或拍照记账，数据越完整，AI 建议越精准。',
          'Keep using voice or receipt capture. Better data makes AI advice sharper.',
        ),
      );
    } else {
      actions.add(
        pick(
          '月底前每周看一次体检分，支出突然升高时及时调整。',
          'Check this score weekly and adjust quickly if spending jumps.',
        ),
      );
    }
    return actions;
  }

  _HealthSignal _assetSignal(FinancialHealthReport report) {
    if (!report.hasAssetData) {
      return _HealthSignal(
        icon: Icons.account_balance_wallet_rounded,
        color: AppColors.warning,
        title: pick('资产变化：数据待完善', 'Asset movement: pending data'),
        body: pick(
          '当前还没有可用于体检的资产数据，补齐资产后会同步评估总资产变化。',
          'No asset data is available for this checkup yet. Add assets to evaluate total asset movement.',
        ),
      );
    }

    final change = report.assetChangeAmount;
    final percent = report.assetChangePercent == null
        ? ''
        : ' (${_signedPercent(report.assetChangePercent!)})';
    return _HealthSignal(
      icon: change >= 0
          ? Icons.account_balance_wallet_rounded
          : Icons.warning_amber_rounded,
      color: change >= 0 ? AppColors.marketUpUs : AppColors.error,
      title: change >= 0
          ? pick('资产变化：整体稳定', 'Asset movement: steady')
          : pick('资产变化：出现回撤', 'Asset movement: drawdown'),
      body: pick(
        '当前总资产 ${_healthMoney(report.assetTotal)}，持仓/资产变化 ${_healthMoney(change)}$percent。',
        'Total assets are ${_healthMoney(report.assetTotal)}, with asset or holding movement of ${_healthMoney(change)}$percent.',
      ),
    );
  }

  _HealthSignal _stockSignal(FinancialHealthReport report) {
    if (!report.hasStockData) {
      return _HealthSignal(
        icon: Icons.show_chart_rounded,
        color: AppColors.warning,
        title: pick('股票风险：暂无持仓数据', 'Stock risk: no holdings yet'),
        body: pick(
          '添加股票持仓后，AI 会结合盈亏、波动和行情状态做风险提示。',
          'Add stock holdings and AI will check profit/loss, volatility, and quote status.',
        ),
      );
    }

    final profitText = report.stockProfitPercent == null
        ? _healthMoney(report.stockProfitAmount)
        : '${_healthMoney(report.stockProfitAmount)} (${_signedPercent(report.stockProfitPercent!)})';
    return _HealthSignal(
      icon: report.hasStockRisk
          ? Icons.crisis_alert_rounded
          : Icons.verified_rounded,
      color: report.hasStockRisk ? AppColors.error : AppColors.marketUpUs,
      title: report.hasStockRisk
          ? pick(
              '股票风险：${report.stockRiskCount} 项需要关注',
              'Stock risk: ${report.stockRiskCount} alerts',
            )
          : pick('股票风险：当前较低', 'Stock risk: currently low'),
      body: pick(
        '共 ${report.stockCount} 只持仓，股票市值 ${_healthMoney(report.stockMarketValue)}，持仓盈亏 $profitText。',
        '${report.stockCount} holdings, stock value ${_healthMoney(report.stockMarketValue)}, P/L $profitText.',
      ),
    );
  }

  _HealthSignal _budgetSignal(
    FinancialHealthReport report,
    String topCategory,
  ) {
    if (report.topExpenseCategory == null) {
      return _HealthSignal(
        icon: Icons.savings_rounded,
        color: AppColors.primary,
        title: pick('预算建议：先积累账单样本', 'Budget suggestion: build a sample first'),
        body: pick(
          '继续记录几笔支出后，AI 会根据高频类目给出更具体的预算上限。',
          'Record a few more expenses and AI can suggest clearer category limits.',
        ),
      );
    }

    final suggested = report.isExpenseRising
        ? report.topExpenseAmount * 0.85
        : report.topExpenseAmount * 0.9;
    return _HealthSignal(
      icon: Icons.tune_rounded,
      color: AppColors.primary,
      title: pick(
        '预算建议：先控 $topCategory',
        'Budget suggestion: start with $topCategory',
      ),
      body: pick(
        '建议下月把 $topCategory 控制在 ${_healthMoney(suggested)} 左右，并优先减少重复小额消费。',
        'Try keeping $topCategory near ${_healthMoney(suggested)} next month and trim repeated small purchases first.',
      ),
    );
  }

  String _topCategoryName(String? categoryId) {
    if (categoryId == null || categoryId.isEmpty) {
      return pick('暂无类目', 'No category yet');
    }
    final category = CategoryDef.findById(categoryId);
    return localizedCategoryName(
      id: categoryId,
      fallback: category?.name ?? categoryId,
      locale: locale,
    );
  }
}

String _healthMoney(num amount) {
  final profile = getIt<AppProfileService>();
  final symbol = AppFormatter.currencySymbol(
    currencyCode: profile.currentBaseCurrency,
    locale: profile.currentLocale,
  );
  final number = AppFormatter.formatDecimal(
    amount,
    locale: profile.currentLocale,
    decimalDigits: amount.abs() >= 1000 ? 0 : 2,
  );
  return '$symbol$number';
}

String _signedPercent(num value) {
  if (value.abs() < 0.1 || !value.isFinite) return '0%';
  final rounded = math.max(value.abs(), 0.1).toStringAsFixed(1);
  return '${value >= 0 ? '+' : '-'}$rounded%';
}
