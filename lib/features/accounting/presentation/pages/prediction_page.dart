import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../../core/formatters/app_formatter.dart';
import '../../../../core/formatters/category_formatter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_string_keys.dart';
import '../../../../l10n/app_strings.dart';
import '../../../../services/app_profile_service.dart';
import '../../../../services/config_service.dart';
import '../../../../services/injection.dart';
import '../../../../app/profile/capability_profile.dart';
import '../../domain/entities/entities.dart';
import '../bloc/account_bloc.dart';
import '../../domain/usecases/get_historical_entries.dart';
import '../../domain/usecases/predict_spending.dart';
import '../widgets/ai_typewriter_markdown.dart';
import '../widgets/premium_page_chrome.dart';
import '../widgets/premium_surface_card.dart';
import '../widgets/textured_scaffold_background.dart';

const bool _screenshotPredictionMock =
    String.fromEnvironment('SCREENSHOT_PREDICTION_MOCK', defaultValue: '') ==
    '1';

Locale _predictionLocale() => getIt<AppProfileService>().currentLocale;

String _predictionCurrency() => getIt<AppProfileService>().currentBaseCurrency;

String _predictionMoney(num amount, {int decimalDigits = 0}) {
  final locale = _predictionLocale();
  final currency = _predictionCurrency();
  final symbol = AppFormatter.currencySymbol(
    currencyCode: currency,
    locale: locale,
  );
  final number = AppFormatter.formatDecimal(
    amount,
    locale: locale,
    decimalDigits: decimalDigits,
  );
  return '$symbol$number';
}

String _predictionMonthLabel(DateTime date) {
  final locale = _predictionLocale();
  if (locale.languageCode == 'zh') {
    return DateFormat('MM月', 'zh_CN').format(date);
  }
  return DateFormat(
    'MMM',
    locale.countryCode == null
        ? locale.languageCode
        : '${locale.languageCode}_${locale.countryCode}',
  ).format(date);
}

bool _predictionAiReady() {
  final provider =
      getIt<AppProfileService>().currentProfile.capabilityProfile.aiProvider;
  switch (provider) {
    case AiProviderType.gemini:
      return ConfigService.instance.isGeminiConfigured;
    case AiProviderType.legacyCnAi:
      return true;
  }
}

String _predictionAiProviderLabel(AppStrings t) {
  final provider =
      getIt<AppProfileService>().currentProfile.capabilityProfile.aiProvider;
  switch (provider) {
    case AiProviderType.gemini:
      return t.text(AppStringKeys.providerAiGemini);
    case AiProviderType.legacyCnAi:
      return t.text(AppStringKeys.providerAiQwen);
  }
}

const Map<String, String> _predictionCategoryAliases = {
  'food': 'food',
  'dining': 'food',
  'dining out': 'food',
  'meal': 'food',
  'meals': 'food',
  'transport': 'transport',
  'transportation': 'transport',
  'shopping': 'shopping',
  'shop': 'shopping',
  'entertainment': 'entertainment',
  'living': 'housing',
  'housing': 'housing',
  'healthcare': 'health',
  'health': 'health',
  'education': 'education',
  'beauty': 'beauty',
  'social': 'social',
  'travel': 'travel',
  'sports': 'sports',
  'coffee': 'coffee',
  'snack': 'snack',
  'snacks': 'snack',
  'fruit': 'fruit',
  'daily': 'daily',
  'groceries': 'grocery',
  'grocery': 'grocery',
  'takeout': 'takeout',
  'vegetables': 'vegetable',
  'vegetable': 'vegetable',
  'drinks': 'drink',
  'drink': 'drink',
};

String _predictionCategoryDisplayFromRaw(String raw, Locale locale) {
  final normalized = raw.trim();
  final canonicalId = _predictionCategoryAliases[normalized.toLowerCase()];
  if (canonicalId != null) {
    final category = CategoryDef.findById(canonicalId);
    if (category != null) {
      return localizedCategoryName(
        id: category.id,
        fallback: category.name,
        locale: locale,
      );
    }
  }

  final all = [
    ...CategoryDef.expenseCategories,
    ...CategoryDef.incomeCategories,
  ];

  for (final category in all) {
    if (category.id == normalized || category.name == normalized) {
      return localizedCategoryName(
        id: category.id,
        fallback: category.name,
        locale: locale,
      );
    }
  }

  const topicMap = {
    '外出就餐': 'dining out',
    '吃外卖': 'takeout',
    '交通出行': 'transport',
    '网购': 'shopping',
  };
  return topicMap[normalized] ?? normalized;
}

String _localizePredictionNarrative(String text) {
  final locale = _predictionLocale();
  final trimmed = text.trim();
  if (trimmed.isEmpty || locale.languageCode == 'zh') return trimmed;
  final strings = AppStrings.forLocale(locale);

  final warningMatch = RegExp(
    r'^(.+?)支出已达预算(\d+)%[，,]注意控制$',
  ).firstMatch(trimmed);
  if (warningMatch != null) {
    final category = _predictionCategoryDisplayFromRaw(
      warningMatch.group(1)!,
      locale,
    );
    final percent = warningMatch.group(2)!;
    return '$category spending has reached $percent% of the budget. Keep an eye on it.';
  }

  final growthMatch = RegExp(
    r'^本月支出较上月同期增长(\d+)%[，,]建议减少(.+)$',
  ).firstMatch(trimmed);
  if (growthMatch != null) {
    final percent = growthMatch.group(1)!;
    final target = _predictionCategoryDisplayFromRaw(
      growthMatch.group(2)!,
      locale,
    );
    return 'Spending is up $percent% versus the same point last month. Consider cutting back on $target.';
  }

  final localized = _replaceEmbeddedChineseCategories(trimmed, locale);
  if (!RegExp(r'[\u4e00-\u9fff]').hasMatch(localized)) {
    return localized;
  }

  if (trimmed.contains('预算') || trimmed.contains('预警')) {
    return strings.text(AppStringKeys.predictionNarrativeWarningFallback);
  }

  if (trimmed.contains('较上月') ||
      trimmed.contains('增长') ||
      trimmed.contains('下降')) {
    return strings.text(AppStringKeys.predictionNarrativeTrendFallback);
  }

  return strings.text(AppStringKeys.predictionNarrativeFallback);
}

String _replaceEmbeddedChineseCategories(String text, Locale locale) {
  var result = text;
  final all = [
    ...CategoryDef.expenseCategories,
    ...CategoryDef.incomeCategories,
  ];

  for (final category in all) {
    final raw = category.name.trim();
    if (raw.isEmpty) continue;
    if (!RegExp(r'[\u4e00-\u9fff]').hasMatch(raw)) continue;

    final localized = localizedCategoryName(
      id: category.id,
      fallback: category.name,
      locale: locale,
    );

    result = result.replaceAll("'$raw'", "'$localized'");
    result = result.replaceAll('"$raw"', '"$localized"');
    result = result.replaceAll(raw, localized);
  }

  return result;
}

class PredictionPage extends StatefulWidget {
  const PredictionPage({super.key});

  @override
  State<PredictionPage> createState() => _PredictionPageState();
}

class _PredictionPageState extends State<PredictionPage> {
  SpendingPrediction? _prediction;
  bool _isLoading = false;
  String? _errorMsg;
  List<AccountEntry> _history = [];
  bool _didLoadOnce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoadOnce) return;
    _didLoadOnce = true;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    final t = AppStrings.of(context);
    if (_screenshotPredictionMock) {
      setState(() {
        _history = _mockPredictionHistory();
        _prediction = SpendingPrediction(
          predictedTotalExpense: _predictionCurrency() == 'USD' ? 2530 : 4860,
          predictedDailyAverage: _predictionCurrency() == 'USD' ? 84 : 162,
          categoryPredictions: {
            'dining': _predictionCurrency() == 'USD' ? 720 : 1380,
            'shopping': _predictionCurrency() == 'USD' ? 560 : 1160,
            'transport': _predictionCurrency() == 'USD' ? 340 : 780,
          },
          budgetRecommendations: {
            'dining': _predictionCurrency() == 'USD' ? 650 : 1280,
            'shopping': _predictionCurrency() == 'USD' ? 480 : 980,
            'transport': _predictionCurrency() == 'USD' ? 300 : 680,
          },
          warnings: [t.text(AppStringKeys.predictionNarrativeWarningFallback)],
          aiInsight: _predictionLocale().languageCode == 'zh'
              ? '本月餐饮和购物支出明显走高，建议优先控制高频小额消费，并为交通和日常支出预留更稳定预算。'
              : 'Dining and shopping are trending higher this month. Try trimming small frequent expenses first and keep a steadier budget for transport and daily spending.',
        );
        _isLoading = false;
      });
      return;
    }

    if (!_predictionAiReady()) {
      setState(() {
        _errorMsg = t.text(
          AppStringKeys.predictionSetupRequired,
          params: {'aiProvider': _predictionAiProviderLabel(t)},
        );
        _isLoading = false;
      });
      return;
    }

    try {
      final expense = context.read<AccountBloc>().state.totalExpense;
      final r1 = await getIt<GetHistoricalEntries>()(
        const GetHistoricalEntriesParams(months: 3),
      );
      final hist = r1.fold((_) => <AccountEntry>[], (r) => r);
      _history = hist;

      if (hist.isEmpty) {
        setState(() {
          _errorMsg = t.text(AppStringKeys.predictionInsufficientHistory);
          _isLoading = false;
        });
        return;
      }

      final r2 = await getIt<PredictSpending>()(
        PredictSpendingParams(entries: hist, currentMonthExpense: expense),
      );
      if (!mounted) return;
      r2.fold(
        (e) => setState(() {
          _errorMsg = e;
          _isLoading = false;
        }),
        (p) => setState(() {
          _prediction = p;
          _isLoading = false;
        }),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = t.text(AppStringKeys.predictionFailed);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PremiumPageAppBar(
        title: t.text(AppStringKeys.predictionTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _load,
          ),
        ],
      ),
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

            Widget child;
            if (_isLoading) {
              child = const Center(child: CircularProgressIndicator());
            } else if (_errorMsg != null) {
              child = Center(
                child: _ErrorWidget(msg: _errorMsg!, onRetry: _load),
              );
            } else if (_prediction == null) {
              child = Center(
                child: Text(t.text(AppStringKeys.reportsEmptyTitle)),
              );
            } else {
              child = _Body(prediction: _prediction!, history: _history);
            }

            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: child,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

List<AccountEntry> _mockPredictionHistory() {
  final now = DateTime.now();
  return [
    AccountEntry(
      id: 'm1',
      amount: 58,
      category: 'food',
      description: 'Lunch',
      date: DateTime(now.year, now.month - 2, 4),
      createdAt: DateTime(now.year, now.month - 2, 4),
      type: EntryType.expense,
    ),
    AccountEntry(
      id: 'm2',
      amount: 120,
      category: 'shopping',
      description: 'Shopping',
      date: DateTime(now.year, now.month - 2, 12),
      createdAt: DateTime(now.year, now.month - 2, 12),
      type: EntryType.expense,
    ),
    AccountEntry(
      id: 'm3',
      amount: 36,
      category: 'transport',
      description: 'Taxi',
      date: DateTime(now.year, now.month - 1, 3),
      createdAt: DateTime(now.year, now.month - 1, 3),
      type: EntryType.expense,
    ),
    AccountEntry(
      id: 'm4',
      amount: 82,
      category: 'food',
      description: 'Dinner',
      date: DateTime(now.year, now.month - 1, 10),
      createdAt: DateTime(now.year, now.month - 1, 10),
      type: EntryType.expense,
    ),
    AccountEntry(
      id: 'm5',
      amount: 148,
      category: 'shopping',
      description: 'Groceries',
      date: DateTime(now.year, now.month, 6),
      createdAt: DateTime(now.year, now.month, 6),
      type: EntryType.expense,
    ),
    AccountEntry(
      id: 'm6',
      amount: 64,
      category: 'transport',
      description: 'Metro',
      date: DateTime(now.year, now.month, 11),
      createdAt: DateTime(now.year, now.month, 11),
      type: EntryType.expense,
    ),
  ];
}

class _ErrorWidget extends StatelessWidget {
  final String msg;
  final VoidCallback onRetry;
  const _ErrorWidget({required this.msg, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: PremiumSurfaceCard(
        radius: 28,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 56, color: Colors.orange.shade400),
            const SizedBox(height: 16),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, height: 1.5),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(t.text(AppStringKeys.commonRetry)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final SpendingPrediction prediction;
  final List<AccountEntry> history;
  const _Body({required this.prediction, required this.history});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom + 130;

    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset),
        children: [
          _InsightCard(insight: prediction.aiInsight),
          const SizedBox(height: 16),
          _OverviewCard(prediction: prediction),
          const SizedBox(height: 16),
          if (prediction.warnings.isNotEmpty) ...[
            _WarningsCard(warnings: prediction.warnings),
            const SizedBox(height: 16),
          ],
          _BudgetCard(recs: prediction.budgetRecommendations),
          const SizedBox(height: 16),
          _TrendCard(entries: history),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final String insight;
  const _InsightCard({required this.insight});

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    return PremiumSurfaceCard(
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                color: Color(0xFF8B5CF6),
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                t.text(AppStringKeys.predictionInsightTitle),
                style: const TextStyle(
                  color: Color(0xFF8B5CF6),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AiTypewriterMarkdown(
            text: insight.isEmpty
                ? t.text(AppStringKeys.predictionInsightFallback)
                : _localizePredictionNarrative(insight),
          ),
        ],
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  final SpendingPrediction prediction;
  const _OverviewCard({required this.prediction});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final daysLeft = DateTime(now.year, now.month + 1, 0).day - now.day;
    final t = AppStrings.of(context);
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return PremiumSurfaceCard(
      radius: 24,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.text(AppStringKeys.predictionPredictedTotalExpense),
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _predictionMoney(prediction.predictedTotalExpense),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 50,
                color: colors.textSecondary.withValues(alpha: 0.16),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.text(AppStringKeys.predictionPredictedDailyAverage),
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _predictionMoney(prediction.predictedDailyAverage),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              t.text(
                AppStringKeys.predictionThisMonthTip,
                params: {
                  'daysLeft': '$daysLeft',
                  'amount': _predictionMoney(prediction.predictedDailyAverage),
                },
              ),
              style: TextStyle(fontSize: 12, color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningsCard extends StatelessWidget {
  final List<String> warnings;
  const _WarningsCard({required this.warnings});

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    return PremiumSurfaceCard(
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber, color: Color(0xFFEF4444), size: 20),
              const SizedBox(width: 8),
              Text(
                t.text(AppStringKeys.predictionWarningsTitle),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFEF4444),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...warnings.map(
            (w) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(color: Color(0xFFEF4444))),
                  Expanded(
                    child: Text(
                      _localizePredictionNarrative(w),
                      style: TextStyle(color: colors.textPrimary, fontSize: 13),
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

class _BudgetCard extends StatelessWidget {
  final Map<String, double> recs;
  const _BudgetCard({required this.recs});

  String _budgetCategoryName(String id, String fallback, Locale locale) {
    return _predictionCategoryDisplayFromRaw(
      id == fallback ? id : fallback,
      locale,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final locale = _predictionLocale();
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final sorted = recs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return PremiumSurfaceCard(
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lightbulb_outline,
                color: Color(0xFF4A47D8),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                t.text(AppStringKeys.predictionBudgetSuggestions),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...sorted.take(6).map((e) {
            final cat = CategoryDef.findById(e.key);
            final name = _budgetCategoryName(e.key, cat?.name ?? e.key, locale);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Text(cat?.icon ?? '📦', style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    t.text(
                      AppStringKeys.predictionApproxPerDay,
                      params: {'amount': _predictionMoney(e.value / 30)},
                    ),
                    style: TextStyle(fontSize: 11, color: colors.textSecondary),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    t.text(
                      AppStringKeys.predictionPerMonth,
                      params: {'amount': _predictionMoney(e.value)},
                    ),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _TrendCard extends StatefulWidget {
  final List<AccountEntry> entries;
  const _TrendCard({required this.entries});

  @override
  State<_TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<_TrendCard> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final monthMap = <String, double>{};
    final now = DateTime.now();
    for (int i = 2; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      monthMap[_predictionMonthLabel(d)] = 0.0;
    }
    for (final e in widget.entries.where((e) => e.type == EntryType.expense)) {
      final key = _predictionMonthLabel(e.date);
      if (monthMap.containsKey(key)) monthMap[key] = monthMap[key]! + e.amount;
    }

    final months = monthMap.keys.toList();
    final values = monthMap.values.toList();
    final maxVal = values.isEmpty
        ? 1.0
        : values.reduce((a, b) => a > b ? a : b) * 1.2;

    // 找出峰值和低谷
    double? maxValue;
    double? minValue;
    int? maxIndex;
    int? minIndex;
    for (int i = 0; i < values.length; i++) {
      if (maxValue == null || values[i] > maxValue) {
        maxValue = values[i];
        maxIndex = i;
      }
      if (minValue == null || values[i] < minValue) {
        minValue = values[i];
        minIndex = i;
      }
    }

    return PremiumSurfaceCard(
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.text(
              AppStringKeys.predictionTrendTitle,
              params: {'count': '${months.length}'},
            ),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: values.isEmpty
                ? Center(
                    child: Text(
                      t.text(AppStringKeys.reportsEmptyTitle),
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  )
                : _LineChartWidget(
                    months: months,
                    values: values,
                    maxVal: maxVal,
                    maxIndex: maxIndex,
                    minIndex: minIndex,
                    touchedIndex: _touchedIndex,
                    onTouch: (index) {
                      setState(() => _touchedIndex = index);
                      if (index != null) {
                        // 点击显示详情（这里简化处理）
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              t.text(
                                AppStringKeys.predictionTrendPoint,
                                params: {
                                  'month': months[index],
                                  'amount': _predictionMoney(values[index]),
                                },
                              ),
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _LineChartWidget extends StatelessWidget {
  final List<String> months;
  final List<double> values;
  final double maxVal;
  final int? maxIndex;
  final int? minIndex;
  final int? touchedIndex;
  final Function(int?) onTouch;

  const _LineChartWidget({
    required this.months,
    required this.values,
    required this.maxVal,
    required this.maxIndex,
    required this.minIndex,
    required this.touchedIndex,
    required this.onTouch,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final spots = <FlSpot>[];
    for (int i = 0; i < values.length; i++) {
      spots.add(FlSpot(i.toDouble(), values[i]));
    }

    return LineChart(
      LineChartData(
        maxY: maxVal,
        lineTouchData: LineTouchData(
          touchCallback: (event, response) {
            if (event is FlTapUpEvent) {
              if (response != null && response.lineBarSpots != null) {
                final index = response.lineBarSpots!.first.x.toInt();
                onTouch(index);
              } else {
                onTouch(null);
              }
            }
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) =>
                isDark ? const Color(0xFF151523) : const Color(0xFF2A2A3F),
            tooltipRoundedRadius: 8,
            getTooltipItems: (spots) => spots
                .map(
                  (spot) => LineTooltipItem(
                    _predictionMoney(spot.y),
                    const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxVal <= 0 ? 1 : maxVal / 4,
          getDrawingHorizontalLine: (_) => FlLine(
            color: colors.textSecondary.withValues(alpha: isDark ? 0.10 : 0.12),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              getTitlesWidget: (v, _) => Text(
                _predictionMoney(v, decimalDigits: 0),
                style: TextStyle(fontSize: 10, color: colors.textSecondary),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx >= 0 && idx < months.length) {
                  return Text(
                    months[idx],
                    style: TextStyle(fontSize: 11, color: colors.textSecondary),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: const Color(0xFF4A47D8),
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                Color dotColor = const Color(0xFF4A47D8);
                double dotSize = 6;
                if (index == maxIndex) {
                  dotColor = const Color(0xFFEF4444); // 红色 - 峰值
                  dotSize = 8;
                } else if (index == minIndex) {
                  dotColor = const Color(0xFF4A47D8); // 绿色 - 低谷
                  dotSize = 8;
                }
                if (touchedIndex == index) {
                  dotSize = 10;
                }
                return FlDotCirclePainter(
                  radius: dotSize,
                  color: dotColor,
                  strokeWidth: 2,
                  strokeColor: colors.cardBackground,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(
                0xFF4A47D8,
              ).withValues(alpha: isDark ? 0.18 : 0.10),
            ),
          ),
        ],
      ),
    );
  }
}
