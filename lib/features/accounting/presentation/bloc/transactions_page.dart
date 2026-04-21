import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/formatters/app_formatter.dart';
import '../../../../l10n/app_string_keys.dart';
import '../../../../l10n/app_strings.dart';
import '../../../../services/app_profile_service.dart';
import '../../../../services/injection.dart';
import '../../domain/entities/entities.dart';
import '../bloc/account_bloc.dart';
import '../bloc/account_event.dart';
import '../bloc/account_state.dart';

enum _TransactionsFilter { all, expense, income }

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  _TransactionsFilter _filter = _TransactionsFilter.all;

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
      case _TransactionsFilter.expense:
        return entries.where((e) => e.type == EntryType.expense).toList();
      case _TransactionsFilter.income:
        return entries.where((e) => e.type == EntryType.income).toList();
      case _TransactionsFilter.all:
        return entries;
    }
  }

  bool _isZh(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'zh';

  String _localeName(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return locale.countryCode == null
        ? locale.languageCode
        : '${locale.languageCode}_${locale.countryCode}';
  }

  String _formatMoney(BuildContext context, num amount) {
    final locale = Localizations.localeOf(context);
    final currency = getIt<AppProfileService>().currentBaseCurrency;
    return AppFormatter.formatCurrency(
      amount,
      currencyCode: currency,
      locale: locale,
    );
  }

  String _filterLabel(BuildContext context, _TransactionsFilter filter) {
    final t = AppStrings.of(context);
    switch (filter) {
      case _TransactionsFilter.expense:
        return t.text(AppStringKeys.transactionsFilterExpense);
      case _TransactionsFilter.income:
        return t.text(AppStringKeys.transactionsFilterIncome);
      case _TransactionsFilter.all:
        return t.text(AppStringKeys.transactionsFilterAll);
    }
  }

  String _selectedMonthLabel(BuildContext context, AccountState state) {
    final localeName = _localeName(context);
    if (state.selectedDay != null) {
      return _isZh(context)
          ? DateFormat('y年M月d日', localeName).format(state.selectedDay!)
          : DateFormat.yMMMMd(localeName).format(state.selectedDay!);
    }

    final selected = DateTime(state.selectedYear, state.selectedMonth);
    return _isZh(context)
        ? DateFormat('y年M月', localeName).format(selected)
        : DateFormat.yMMMM(localeName).format(selected);
  }

  /// 月份选择器：显示当前选中月份，支持左右箭头切换
  Widget _buildMonthSelector(AccountState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.grey.shade50,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 28),
            onPressed: () {
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
          ),
          GestureDetector(
            onTap: () => _showMonthPicker(context, state),
            child: Row(
              children: [
                Text(
                  _selectedMonthLabel(context, state),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, size: 20),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 28),
            onPressed: () {
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
          ),
        ],
      ),
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
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF10B981), Color(0xFF059669)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.text(AppStringKeys.transactionsTitle),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<_TransactionsFilter>(
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
                    _filterLabel(context, _filter),
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
              _TransactionsFilter.all,
              _TransactionsFilter.expense,
              _TransactionsFilter.income,
            ]
                .map(
                  (e) => PopupMenuItem(
                    value: e,
                    child: Text(_filterLabel(context, e)),
                  ),
                )
                .toList(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: BlocBuilder<AccountBloc, AccountState>(
        builder: (context, state) {
          return Column(
            children: [
              _buildMonthSelector(state),
              Expanded(child: _buildBody(state)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(AccountState state) {
    final t = AppStrings.of(context);

    if (state.status == AccountStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final entries = _filteredEntries(state);

    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              t.text(
                AppStringKeys.transactionsEmptyFiltered,
                params: {'filter': _filterLabel(context, _filter)},
              ),
              style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
            ),
          ],
        ),
      );
    }

    // Group by date
    final grouped = <DateTime, List<AccountEntry>>{};
    for (final e in entries) {
      final key = DateTime(e.date.year, e.date.month, e.date.day);
      grouped.putIfAbsent(key, () => []).add(e);
    }
    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
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

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDate(date),
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  Row(
                    children: [
                      if (dayExpense > 0)
                        Text(
                          '${t.text(AppStringKeys.transactionsDayExpense, params: {'amount': _formatMoney(context, dayExpense)})}  ',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      if (dayIncome > 0)
                        Text(
                          t.text(
                            AppStringKeys.transactionsDayIncome,
                            params: {'amount': _formatMoney(context, dayIncome)},
                          ),
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            ...dayEntries.map(
              (e) => _EntryTile(
                entry: e,
                onDelete: () => _confirmDelete(context, e),
              ),
            ),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, AccountEntry entry) {
    showDialog(
      context: context,
      useRootNavigator: false,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.of(context).text(AppStringKeys.transactionsDeleteTitle)),
        content: Text(
          AppStrings.of(context).text(
            AppStringKeys.transactionsDeleteContent,
            params: {'amount': _formatMoney(context, entry.amount)},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppStrings.of(context).text(AppStringKeys.commonCancel)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.read<AccountBloc>().add(DeleteAccountEntry(entry.id));
            },
            child: Text(
              AppStrings.of(context).text(AppStringKeys.commonDelete),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final t = AppStrings.of(context);
    final localeName = _localeName(context);
    if (d == today) return t.text(AppStringKeys.transactionsToday);
    if (d == yesterday) return t.text(AppStringKeys.transactionsYesterday);
    return _isZh(context)
        ? DateFormat('MM月dd日 EEEE', localeName).format(d)
        : DateFormat.yMMMMEEEEd(localeName).format(d);
  }
}

class _EntryTile extends StatelessWidget {
  final AccountEntry entry;
  final VoidCallback onDelete;

  const _EntryTile({required this.entry, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cat = CategoryDef.findById(entry.category);
    final t = AppStrings.of(context);
    final syncText = entry.syncStatus == SyncStatus.pending
        ? t.text(AppStringKeys.transactionsSyncPending)
        : t.text(AppStringKeys.transactionsSyncDone);

    return Dismissible(
      key: Key(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Row(
          children: [
            Text(cat?.icon ?? '📦', style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.description.isEmpty
                        ? (cat?.name ?? t.text(AppStringKeys.transactionsOtherCategory))
                        : entry.description,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${cat?.name ?? ''} · $syncText',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              '${entry.type == EntryType.income ? '+' : '-'}¥${entry.amount.toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: entry.type == EntryType.income
                    ? const Color(0xFF10B981)
                    : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
