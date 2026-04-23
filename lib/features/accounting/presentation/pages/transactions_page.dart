import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../../core/formatters/app_formatter.dart';
import '../../../../../core/formatters/category_formatter.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../l10n/app_string_keys.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../../../services/app_profile_service.dart';
import '../../../../../services/injection.dart';
import '../../domain/entities/entities.dart';
import '../bloc/account_bloc.dart';
import '../bloc/account_event.dart';
import '../bloc/account_state.dart';
import '../widgets/breathing_float.dart';
import '../widgets/press_feedback.dart';
import '../widgets/premium_page_chrome.dart';
import '../widgets/premium_surface_card.dart';
import '../widgets/textured_scaffold_background.dart';

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  String _filter = 'all';

  Locale get _locale => getIt<AppProfileService>().currentLocale;

  String get _baseCurrency => getIt<AppProfileService>().currentBaseCurrency;

  String _formatMoney(num amount) {
    return AppFormatter.formatCurrency(
      amount,
      currencyCode: _baseCurrency,
      locale: _locale,
    );
  }

  String _monthText(AccountState state) {
    final localeTag = _locale.countryCode == null
        ? _locale.languageCode
        : '${_locale.languageCode}_${_locale.countryCode}';
    if (state.selectedDay != null) {
      return DateFormat.yMMMd(localeTag).format(state.selectedDay!);
    }
    return DateFormat.yMMMM(
      localeTag,
    ).format(DateTime(state.selectedYear, state.selectedMonth));
  }

  @override
  void initState() {
    super.initState();
    final bloc = context.read<AccountBloc>();
    final state = bloc.state;
    bloc.add(const FilterByDay(null)); // 清空日筛选
    bloc.add(
      LoadEntriesByMonth(year: state.selectedYear, month: state.selectedMonth),
    );
  }

  List<AccountEntry> _filteredEntries(AccountState state) {
    List<AccountEntry> entries = state.entries;

    // 按日筛选
    if (state.selectedDay != null) {
      entries = entries.where((e) {
        return e.date.year == state.selectedDay!.year &&
            e.date.month == state.selectedDay!.month &&
            e.date.day == state.selectedDay!.day;
      }).toList();
    }

    switch (_filter) {
      case 'expense':
        return entries.where((e) => e.type == EntryType.expense).toList();
      case 'income':
        return entries.where((e) => e.type == EntryType.income).toList();
      default:
        return entries;
    }
  }

  /// 月份选择器：← [月份 ▼] →
  Widget _buildMonthSelector(AccountState state) {
    final monthText = _monthText(state);

    return PremiumMonthSwitcher(
      label: monthText,
      showDropdownIndicator: true,
      onLabelTap: () => _showMonthPicker(context, state),
      onPrevious: () {
        final bloc = context.read<AccountBloc>();
        int y = state.selectedYear;
        int m = state.selectedMonth - 1;
        if (m < 1) {
          m = 12;
          y--;
        }
        bloc.add(const FilterByDay(null));
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
        bloc.add(const FilterByDay(null));
        bloc.add(LoadEntriesByMonth(year: y, month: m));
      },
    );
  }

  Future<void> _showMonthPicker(
    BuildContext context,
    AccountState state,
  ) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: state.selectedDay != null
          ? state.selectedDay!
          : DateTime(state.selectedYear, state.selectedMonth),
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (picked == null || !context.mounted) return;
    context.read<AccountBloc>().add(FilterByDay(picked));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PremiumPageAppBar(
        title: t.text(AppStringKeys.transactionsTitle),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => setState(() => _filter = v),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _filter == 'expense'
                        ? t.text(AppStringKeys.reportsExpense)
                        : _filter == 'income'
                        ? t.text(AppStringKeys.reportsIncome)
                        : t.text(AppStringKeys.transactionsFilterAll),
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                  ),
                  const Icon(
                    Icons.arrow_drop_down,
                    size: 20,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'all',
                child: Text(t.text(AppStringKeys.transactionsFilterAll)),
              ),
              PopupMenuItem(
                value: 'expense',
                child: Text(t.text(AppStringKeys.reportsExpense)),
              ),
              PopupMenuItem(
                value: 'income',
                child: Text(t.text(AppStringKeys.reportsIncome)),
              ),
            ],
          ),
          const SizedBox(width: 8),
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

            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: BlocBuilder<AccountBloc, AccountState>(
                    builder: (context, state) {
                      return Column(
                        children: [
                          _buildMonthSelector(state),
                          Expanded(child: _buildBody(state)),
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

  Widget _buildBody(AccountState state) {
    if (state.status == AccountStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final bottomInset = MediaQuery.of(context).padding.bottom + 130;
    final entries = _filteredEntries(state);

    if (entries.isEmpty) {
      return const _EmptyState();
    }

    // Group by date
    final grouped = <DateTime, List<AccountEntry>>{};
    for (final e in entries) {
      final key = DateTime(e.date.year, e.date.month, e.date.day);
      grouped.putIfAbsent(key, () => []).add(e);
    }
    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset),
      itemCount: sortedDates.length,
      itemBuilder: (context, index) {
        final date = sortedDates[index];
        final dayEntries = grouped[date]!;
        final dayExpense = dayEntries
            .where((e) => e.type == EntryType.expense)
            .fold<double>(0, (s, e) => s + e.amount);
        final dayIncome = dayEntries
            .where((e) => e.type == EntryType.income)
            .fold<double>(0, (s, e) => s + e.amount);

        return _DateGroup(
          date: date,
          dayExpense: dayExpense,
          dayIncome: dayIncome,
          entries: dayEntries,
          onDelete: (e) => _confirmDelete(context, e),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, AccountEntry entry) {
    final t = AppStrings.of(context);
    showDialog(
      context: context,
      useRootNavigator: false,
      builder: (_) => AlertDialog(
        title: Text(t.text(AppStringKeys.transactionsDeleteTitle)),
        content: Text(
          t.text(
            AppStringKeys.transactionsDeleteContent,
            params: {'amount': _formatMoney(entry.amount)},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.text(AppStringKeys.commonCancel)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.read<AccountBloc>().add(DeleteAccountEntry(entry.id));
            },
            child: Text(
              t.text(AppStringKeys.commonDelete),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}

/// 日期分组组件（带吸顶效果）
class _DateGroup extends StatelessWidget {
  final DateTime date;
  final double dayExpense;
  final double dayIncome;
  final List<AccountEntry> entries;
  final Function(AccountEntry) onDelete;

  const _DateGroup({
    required this.date,
    required this.dayExpense,
    required this.dayIncome,
    required this.entries,
    required this.onDelete,
  });

  String _formatDate(DateTime d) {
    final locale = getIt<AppProfileService>().currentLocale;
    final t = AppStrings.forLocale(locale);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final target = DateTime(d.year, d.month, d.day);
    if (target == today) return t.text(AppStringKeys.transactionsToday);
    if (target == yesterday) {
      return t.text(AppStringKeys.transactionsYesterday);
    }
    return AppFormatter.formatMediumDate(d, locale: locale);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DateHeader(
          dateText: _formatDate(date),
          dayExpense: dayExpense,
          dayIncome: dayIncome,
        ),
        ...entries.map(
          (e) => _EntryTile(entry: e, onDelete: () => onDelete(e)),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// 日期分组头部
class _DateHeader extends StatelessWidget {
  final String dateText;
  final double dayExpense;
  final double dayIncome;

  const _DateHeader({
    required this.dateText,
    required this.dayExpense,
    required this.dayIncome,
  });

  @override
  Widget build(BuildContext context) {
    final locale = getIt<AppProfileService>().currentLocale;
    final currency = getIt<AppProfileService>().currentBaseCurrency;
    final t = AppStrings.of(context);
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final summaryTextStyle = TextStyle(
      color: colors.textSecondary,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: isDark
                  ? colors.secondaryBackground.withValues(alpha: 0.92)
                  : Colors.white.withValues(alpha: 0.74),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isDark
                    ? colors.subtleBorder
                    : AppColors.primary.withValues(alpha: 0.10),
              ),
            ),
            child: Text(dateText, style: summaryTextStyle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (dayExpense > 0)
                  _DaySummaryPill(
                    text: t.text(
                      AppStringKeys.transactionsDayExpense,
                      params: {
                        'amount': AppFormatter.formatCurrency(
                          dayExpense,
                          currencyCode: currency,
                          locale: locale,
                        ),
                      },
                    ),
                    backgroundColor: AppColors.marketUpSoft.withValues(
                      alpha: 0.86,
                    ),
                    borderColor: AppColors.marketUp.withValues(alpha: 0.12),
                    foregroundColor: AppColors.marketUp,
                  ),
                if (dayIncome > 0)
                  _DaySummaryPill(
                    text: t.text(
                      AppStringKeys.transactionsDayIncome,
                      params: {
                        'amount': AppFormatter.formatCurrency(
                          dayIncome,
                          currencyCode: currency,
                          locale: locale,
                        ),
                      },
                    ),
                    backgroundColor: AppColors.marketDownSoft.withValues(
                      alpha: 0.86,
                    ),
                    borderColor: AppColors.marketDown.withValues(alpha: 0.12),
                    foregroundColor: AppColors.marketDown,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 账单列表项
class _EntryTile extends StatefulWidget {
  final AccountEntry entry;
  final VoidCallback onDelete;

  const _EntryTile({required this.entry, required this.onDelete});

  @override
  State<_EntryTile> createState() => _EntryTileState();
}

class _EntryTileState extends State<_EntryTile> {
  DismissDirection? _hapticDirection;

  Locale get _locale => getIt<AppProfileService>().currentLocale;

  String get _currencyPrefix =>
      '${AppFormatter.currencySymbol(currencyCode: widget.entry.baseCurrency, locale: _locale)} ';

  @override
  Widget build(BuildContext context) {
    final cat = CategoryDef.findById(widget.entry.category);
    final locale = getIt<AppProfileService>().currentLocale;
    final currency = widget.entry.baseCurrency;
    final t = AppStrings.of(context);
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final catColor = AppColors.getCategoryColor(cat?.id ?? 'other');
    final categoryName = cat == null
        ? t.text(AppStringKeys.transactionsOtherCategory)
        : localizedCategoryName(id: cat.id, fallback: cat.name, locale: locale);

    return Dismissible(
      key: Key(widget.entry.id),
      direction: DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.2,
        DismissDirection.endToStart: 0.2,
      },
      background: _buildSwipeBackground(DismissDirection.endToStart),
      secondaryBackground: _buildSwipeBackground(DismissDirection.startToEnd),
      onUpdate: (details) {
        if (details.progress < 0.01) {
          _hapticDirection = null;
          return;
        }

        if (details.reached && _hapticDirection != details.direction) {
          _hapticDirection = details.direction;
          HapticFeedback.lightImpact();
        }
      },
      confirmDismiss: (direction) async {
        _hapticDirection = null;
        if (direction == DismissDirection.endToStart) {
          // 右滑 → 删除/编辑
          _showEditDeleteSheet(context);
        } else {
          // 左滑 → 复制/报销
          _showCopyReimbursementSheet(context);
        }
        return false;
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        child: PremiumSurfaceCard(
          radius: 20,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      catColor.withValues(alpha: 0.28),
                      catColor.withValues(alpha: 0.12),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: catColor.withValues(alpha: 0.14)),
                ),
                child: Text(
                  cat?.icon ?? '📦',
                  style: const TextStyle(fontSize: 24),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.entry.description.isEmpty
                          ? categoryName
                          : widget.entry.description,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (widget.entry.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: catColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          categoryName,
                          style: TextStyle(
                            color: Color.lerp(
                              catColor,
                              colors.textPrimary,
                              0.28,
                            ),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: widget.entry.type == EntryType.income
                      ? AppColors.marketDownSoft.withValues(alpha: 0.92)
                      : AppColors.marketUpSoft.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: widget.entry.type == EntryType.income
                        ? AppColors.marketDown.withValues(alpha: 0.12)
                        : AppColors.marketUp.withValues(alpha: 0.12),
                  ),
                ),
                child: Text(
                  '${widget.entry.type == EntryType.income ? '+' : '-'}${AppFormatter.formatCurrency(widget.entry.amount, currencyCode: currency, locale: locale)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: widget.entry.type == EntryType.income
                        ? AppColors.marketDown
                        : AppColors.marketUp,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwipeBackground(DismissDirection direction) {
    final isEndToStart = direction == DismissDirection.endToStart;
    final baseColor = isEndToStart
        ? const Color(0xFF6CCB98)
        : const Color(0xFF6D9BFF);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [baseColor, Color.lerp(baseColor, Colors.black, 0.08)!],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: baseColor.withValues(alpha: 0.20),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      alignment: isEndToStart ? Alignment.centerRight : Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isEndToStart) ...[
            const Icon(Icons.edit, color: Colors.white),
            const SizedBox(width: 12),
            const Icon(Icons.delete, color: Colors.white),
          ] else ...[
            const Icon(Icons.content_copy, color: Colors.white),
            const SizedBox(width: 12),
            const Icon(Icons.receipt_long, color: Colors.white),
          ],
        ],
      ),
    );
  }

  Future<void> _showEditDeleteSheet(BuildContext context) async {
    final t = AppStrings.of(context);
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.edit, color: colors.textPrimary),
              title: Text(
                t.text(AppStringKeys.transactionsEditEntry),
                style: TextStyle(color: colors.textPrimary),
              ),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Color(0xFFF56C6C)),
              title: Text(
                t.text(AppStringKeys.transactionsDeleteEntry),
                style: TextStyle(color: Color(0xFFF56C6C)),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (!context.mounted) return;

    if (action == 'edit') {
      await _showEditEntrySheet(context);
    } else if (action == 'delete') {
      widget.onDelete();
    }
  }

  void _showCopyReimbursementSheet(BuildContext context) {
    final t = AppStrings.of(context);
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.content_copy, color: colors.textPrimary),
              title: Text(
                t.text(AppStringKeys.transactionsCopyAmount),
                style: TextStyle(color: colors.textPrimary),
              ),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(
                  ClipboardData(text: widget.entry.amount.toStringAsFixed(2)),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      t.text(AppStringKeys.transactionsCopySuccess),
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.receipt_long, color: colors.textPrimary),
              title: Text(
                t.text(AppStringKeys.transactionsReimbursement),
                style: TextStyle(color: colors.textPrimary),
              ),
              onTap: () {
                Navigator.pop(ctx);
                // TODO: 生成报销单
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditEntrySheet(BuildContext context) async {
    final t = AppStrings.of(context);
    final amountController = TextEditingController(
      text: widget.entry.amount.toStringAsFixed(2),
    );
    final descriptionController = TextEditingController(
      text: widget.entry.description,
    );
    String selectedCategory = widget.entry.category;
    DateTime selectedDate = widget.entry.date;
    final categories = widget.entry.type == EntryType.income
        ? CategoryDef.incomeCategories
        : CategoryDef.expenseCategories;

    final updatedEntry = await showModalBottomSheet<AccountEntry>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final colors = Theme.of(sheetCtx).extension<AppColorsExtension>()!;
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16,
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        t.text(AppStringKeys.transactionsEditEntry),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: t.text(
                          AppStringKeys.transactionsAmountLabel,
                        ),
                        prefixText: _currencyPrefix,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      decoration: InputDecoration(
                        labelText: t.text(AppStringKeys.transactionsNoteLabel),
                        hintText: t.text(AppStringKeys.transactionsNoteHint),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    PressFeedback(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: sheetCtx,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (picked != null) {
                          setSheetState(() => selectedDate = picked);
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: colors.secondaryBackground,
                          border: Border.all(color: colors.subtleBorder),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          t.text(
                            AppStringKeys.transactionsDateLabel,
                            params: {
                              'date': AppFormatter.formatShortDate(
                                selectedDate,
                                locale: _locale,
                              ),
                            },
                          ),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      t.text(AppStringKeys.transactionsSelectCategory),
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: categories.map((c) {
                        final isSelected = selectedCategory == c.id;
                        return PressFeedback(
                          onTap: () =>
                              setSheetState(() => selectedCategory = c.id),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF4A47D8)
                                  : colors.secondaryBackground,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primary.withValues(alpha: 0.16)
                                    : colors.subtleBorder,
                              ),
                            ),
                            child: Text(
                              '${c.icon} ${localizedCategoryName(id: c.id, fallback: c.name, locale: _locale)}',
                              style: TextStyle(
                                fontSize: 13,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(sheetCtx),
                            child: Text(t.text(AppStringKeys.commonCancel)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4A47D8),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () {
                              final amount = double.tryParse(
                                amountController.text.trim(),
                              );
                              if (amount == null || amount <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      t.text(
                                        AppStringKeys.transactionsInvalidAmount,
                                      ),
                                    ),
                                  ),
                                );
                                return;
                              }

                              Navigator.pop(
                                sheetCtx,
                                widget.entry.copyWith(
                                  amount: amount,
                                  category: selectedCategory,
                                  description: descriptionController.text
                                      .trim(),
                                  date: selectedDate,
                                ),
                              );
                            },
                            child: Text(t.text(AppStringKeys.commonSave)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (updatedEntry == null || !context.mounted) return;

    context.read<AccountBloc>().add(UpdateAccountEntry(updatedEntry));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.text(AppStringKeys.transactionsUpdated))),
    );
  }
}

/// 空状态组件
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: PremiumSurfaceCard(
          radius: 28,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BreathingFloat(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.primary.withValues(alpha: 0.18),
                        AppColors.primary.withValues(alpha: 0.06),
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    size: 34,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                t.text(AppStringKeys.transactionsEmptyTitle),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                t.text(AppStringKeys.transactionsEmptySubtitle),
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DaySummaryPill extends StatelessWidget {
  const _DaySummaryPill({
    required this.text,
    required this.backgroundColor,
    required this.borderColor,
    required this.foregroundColor,
  });

  final String text;
  final Color backgroundColor;
  final Color borderColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: foregroundColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
