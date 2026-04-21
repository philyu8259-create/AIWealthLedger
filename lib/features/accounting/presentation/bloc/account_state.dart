import 'package:equatable/equatable.dart';
import '../../domain/entities/entities.dart';
import '../../../../services/ai/input_parser_service.dart';

enum AccountStatus { initial, loading, loaded, error }

class AccountState extends Equatable {
  final AccountStatus status;
  final List<AccountEntry> entries;
  final int selectedYear;
  final int selectedMonth;
  final DateTime? selectedDay; // null = 显示整月，set = 只显示这天
  final String? errorMessage;
  final List<ParsedResult> parsedResults;
  final bool isParsing;
  final bool isAiPanelVisible;
  final bool isVip;
  final DateTime? vipExpireDate;
  final int totalEntryCount;
  final bool showVipLimitDialog;
  final bool showLoginLimitDialog;
  // 上月数据，用于环比比较
  final double? lastMonthExpense;
  final double? lastMonthIncome;

  const AccountState({
    this.status = AccountStatus.initial,
    required this.entries,
    required this.selectedYear,
    required this.selectedMonth,
    this.selectedDay,
    this.errorMessage,
    this.parsedResults = const [],
    this.isParsing = false,
    this.isAiPanelVisible = false,
    this.isVip = false,
    this.vipExpireDate,
    this.totalEntryCount = 0,
    this.showVipLimitDialog = false,
    this.showLoginLimitDialog = false,
    this.lastMonthExpense,
    this.lastMonthIncome,
  });

  factory AccountState.initial() {
    final now = DateTime.now();
    return AccountState(
      selectedYear: now.year,
      selectedMonth: now.month,
      entries: const [],
    );
  }

  AccountState copyWith({
    AccountStatus? status,
    List<AccountEntry>? entries,
    int? selectedYear,
    int? selectedMonth,
    DateTime? selectedDay,
    String? errorMessage,
    List<ParsedResult>? parsedResults,
    bool? isParsing,
    bool? isAiPanelVisible,
    bool? isVip,
    DateTime? vipExpireDate,
    int? totalEntryCount,
    bool? showVipLimitDialog,
    bool? showLoginLimitDialog,
    double? lastMonthExpense,
    double? lastMonthIncome,
  }) {
    return AccountState(
      status: status ?? this.status,
      entries: entries ?? this.entries,
      selectedYear: selectedYear ?? this.selectedYear,
      selectedMonth: selectedMonth ?? this.selectedMonth,
      selectedDay: selectedDay,
      parsedResults: parsedResults ?? this.parsedResults,
      isParsing: isParsing ?? this.isParsing,
      isAiPanelVisible: isAiPanelVisible ?? this.isAiPanelVisible,
      isVip: isVip ?? this.isVip,
      vipExpireDate: vipExpireDate ?? this.vipExpireDate,
      totalEntryCount: totalEntryCount ?? this.totalEntryCount,
      showVipLimitDialog: showVipLimitDialog ?? this.showVipLimitDialog,
      showLoginLimitDialog: showLoginLimitDialog ?? this.showLoginLimitDialog,
      lastMonthExpense: lastMonthExpense ?? this.lastMonthExpense,
      lastMonthIncome: lastMonthIncome ?? this.lastMonthIncome,
    );
  }

  double get totalExpense => entries
      .where((e) => e.type == EntryType.expense)
      .fold(0.0, (sum, e) => sum + e.amount);

  double get totalIncome => entries
      .where((e) => e.type == EntryType.income)
      .fold(0.0, (sum, e) => sum + e.amount);

  Map<DateTime, List<AccountEntry>> get entriesByDate {
    final map = <DateTime, List<AccountEntry>>{};
    for (final entry in entries) {
      final key = DateTime(entry.date.year, entry.date.month, entry.date.day);
      map.putIfAbsent(key, () => []).add(entry);
    }
    return map;
  }

  @override
  List<Object?> get props => [
    status,
    entries,
    selectedYear,
    selectedMonth,
    selectedDay,
    errorMessage,
    parsedResults,
    isParsing,
    isAiPanelVisible,
    showLoginLimitDialog,
    showVipLimitDialog,
    lastMonthExpense,
    lastMonthIncome,
  ];
}
