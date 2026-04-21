import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';
import '../../domain/entities/entities.dart';
import 'package:uuid/uuid.dart';
import '../../../../services/vip_service.dart';
import '../../../../services/ai/input_parser_service.dart';
import '../../domain/repositories/account_entry_repository.dart';
import '../../domain/usecases/add_entry.dart';
import '../../domain/usecases/delete_entry.dart';
import '../../domain/usecases/get_entries_by_month.dart';
import 'account_event.dart';
import 'account_state.dart';

class AccountBloc extends Bloc<AccountEvent, AccountState> {
  final GetEntriesByMonth getEntriesByMonth;
  final AddEntry addEntry;
  final DeleteEntry deleteEntry;
  final InputParserService inputParserService;
  final VipService vipService;
  final AccountEntryRepository repository;
  final Uuid _uuid = const Uuid();

  static const int freeTierLimit = 30;

  AccountBloc({
    required this.getEntriesByMonth,
    required this.addEntry,
    required this.deleteEntry,
    required this.inputParserService,
    required this.vipService,
    required this.repository,
  }) : super(AccountState.initial()) {
    debugPrint('[Bloc] AccountBloc constructed');

    // 监听 VipService 状态变化（购买完成时 notifyListeners 被调用）
    vipService.addListener(_onVipServiceChanged);

    on<LoadCurrentMonthEntries>(_onLoadCurrentMonthEntries);
    on<LoadEntriesByMonth>(_onLoadEntriesByMonth);
    on<AddAccountEntry>(_onAddEntry);
    on<AddMultipleAccountEntries>(_onAddMultipleEntries);
    on<DeleteAccountEntry>(_onDeleteEntry);
    on<UpdateAccountEntry>(_onUpdateEntry);
    on<ParseTextInput>(_onParseTextInput);
    on<ClearParsedResults>(_onClearParsedResults);
    on<ChangeMonthFilter>(_onChangeMonthFilter);
    on<ClearVipLimitDialog>(_onClearVipLimitDialog);
    on<ClearLoginLimitDialog>(_onClearLoginLimitDialog);
    on<FilterByDay>(_onFilterByDay);
  }

  void _onVipServiceChanged() {
    // VipService 的 VIP 状态发生变化（购买完成），重新加载当月数据刷新 UI
    debugPrint('[Bloc] _onVipServiceChanged fired! Refreshing current month...');
    add(LoadCurrentMonthEntries());
  }

  Future<int> _getTotalEntryCount() async {
    debugPrint(
      '[Bloc] _getTotalEntryCount() calling repository.getEntries(), repo=${repository.runtimeType}',
    );
    final result = await repository.getEntries();
    debugPrint(
      '[Bloc] _getTotalEntryCount() got result, right=${result.getOrElse(() => []).length}',
    );
    return result.fold((_) => 0, (entries) => entries.length);
  }

  Future<void> _onLoadCurrentMonthEntries(
    LoadCurrentMonthEntries event,
    Emitter<AccountState> emit,
  ) async {
    debugPrint('[Bloc] LoadCurrentMonthEntries received');
    final now = DateTime.now();
    add(LoadEntriesByMonth(year: now.year, month: now.month));
  }

  Future<void> _onLoadEntriesByMonth(
    LoadEntriesByMonth event,
    Emitter<AccountState> emit,
  ) async {
    debugPrint('[Bloc] _onLoadEntriesByMonth called: ${event.year}-${event.month}');
    emit(state.copyWith(status: AccountStatus.loading));

    // 加载 VIP 状态
    final isVip = vipService.isVip;
    final vipExpire = vipService.expireDate;
    debugPrint('[Bloc] VIP checked: isVip=$isVip');

    final totalCount = await _getTotalEntryCount();
    debugPrint('[Bloc] totalCount=$totalCount');

    debugPrint('[Bloc] calling getEntriesByMonth...');
    debugPrint('[Bloc] repository=${repository.runtimeType}');
    final result = await getEntriesByMonth(
      GetEntriesByMonthParams(year: event.year, month: event.month),
    );
    debugPrint('[Bloc] getEntriesByMonth returned: ${result.isRight()}');

    // 计算上月日期
    int lastYear = event.year;
    int lastMonth = event.month - 1;
    if (lastMonth < 1) {
      lastMonth = 12;
      lastYear -= 1;
    }

    // 环比比较规则：
    // 当前月比较区间 = 当月 1 日 ~ 截止日
    // 上个月比较区间 = 上月 1 日 ~ min(截止日, 上个月最后一天)
    // 当前首页场景下，截止日即“今天”；如果查看历史月份，则按该月最后一天比较整月。
    final now = DateTime.now();
    final isCurrentMonth = event.year == now.year && event.month == now.month;
    final compareDay = isCurrentMonth
        ? now.day
        : _daysInMonth(event.year, event.month);
    final lastMonthCompareDay = compareDay > _daysInMonth(lastYear, lastMonth)
        ? _daysInMonth(lastYear, lastMonth)
        : compareDay;

    // 加载上月数据（用于环比比较）
    double? lastMonthExpense;
    double? lastMonthIncome;
    final lastMonthResult = await getEntriesByMonth(
      GetEntriesByMonthParams(year: lastYear, month: lastMonth),
    );
    lastMonthResult.fold(
      (error) {
        debugPrint('[Bloc] last month data error: $error');
      },
      (lastEntries) {
        final comparedLastEntries = lastEntries
            .where((e) => e.date.day <= lastMonthCompareDay)
            .toList();
        lastMonthExpense = comparedLastEntries
            .where((e) => e.type == EntryType.expense)
            .fold<double>(0.0, (sum, e) => sum + e.amount);
        lastMonthIncome = comparedLastEntries
            .where((e) => e.type == EntryType.income)
            .fold<double>(0.0, (sum, e) => sum + e.amount);
        debugPrint(
          '[Bloc] last month compared data loaded: day<=$lastMonthCompareDay, expense=$lastMonthExpense, income=$lastMonthIncome',
        );
      },
    );

    result.fold(
      (error) {
        debugPrint('[Bloc] getEntriesByMonth error: $error');
        emit(
          state.copyWith(
            status: AccountStatus.error,
            errorMessage: error,
            isVip: isVip,
            vipExpireDate: vipExpire,
            totalEntryCount: totalCount,
          ),
        );
      },
      (entries) {
        debugPrint(
          '[Bloc] getEntriesByMonth success, entries.length=${entries.length}',
        );
        entries.sort((a, b) => b.date.compareTo(a.date));
        emit(
          state.copyWith(
            status: AccountStatus.loaded,
            entries: entries,
            selectedYear: event.year,
            selectedMonth: event.month,
            isVip: isVip,
            vipExpireDate: vipExpire,
            totalEntryCount: totalCount,
            lastMonthExpense: lastMonthExpense,
            lastMonthIncome: lastMonthIncome,
          ),
        );
      },
    );
  }

  Future<void> _onAddEntry(
    AddAccountEntry event,
    Emitter<AccountState> emit,
  ) async {
    // 限制检查
    final phone = repository.getCurrentPhone();
    final total = await _getTotalEntryCount();
    // Demo 账号不做任何限制检查（方便审核员测试）
    if (repository.isDemoAccount()) {
      // 跳过所有限制检查
    } else if (phone == null) {
      // 游客：超过限制弹登录提示
      if (total >= VipService.touristLimit) {
        emit(state.copyWith(showLoginLimitDialog: true));
        return;
      }
    } else if (!vipService.isVip) {
      // 登录非会员：超过限制弹VIP提示
      if (total >= VipService.freeUserLimit) {
        emit(state.copyWith(showVipLimitDialog: true));
        return;
      }
    }
    // 会员已过期：禁止新增账单
    if (vipService.hasExpiredEntitlement) {
      emit(state.copyWith(showVipLimitDialog: true));
      return;
    }
    debugPrint('[Bloc] _onAddEntry called, entry.id=${event.entry.id}');
    final entryWithId = event.entry.copyWith(
      id: event.entry.id.isEmpty ? _uuid.v4() : event.entry.id,
      createdAt: event.entry.createdAt,
    );

    final result = await addEntry(AddEntryParams(entry: entryWithId));

    final foldResult = result.fold(
      (error) => <String, dynamic>{'error': error},
      (entry) => <String, dynamic>{'entry': entry},
    );

    if (foldResult.containsKey('error')) {
      debugPrint('[Bloc] _onAddEntry FAILED: ${foldResult['error']}');
      // 云端写入失败，标记为 failed
      await repository.updateEntry(
        entryWithId.copyWith(syncStatus: SyncStatus.failed),
      );
      emit(state.copyWith(errorMessage: foldResult['error'] as String));
    } else {
      final savedEntry = foldResult['entry'] as AccountEntry;
      // 直接使用 repository 返回的同步状态，不要强制修改！
      final List<AccountEntry> updated = [savedEntry, ...state.entries];
      updated.sort((a, b) => b.date.compareTo(a.date));
      emit(
        state.copyWith(
          entries: updated,
          parsedResults: const [],
          isAiPanelVisible: false,
          totalEntryCount: total + 1,
        ),
      );
    }
  }

  /// 批量添加多条账单（只做 emit，IO 由 _confirmAndSave 完成）
  Future<void> _onAddMultipleEntries(
    AddMultipleAccountEntries event,
    Emitter<AccountState> emit,
  ) async {
    // 限制检查
    final phone = repository.getCurrentPhone();
    final total = await _getTotalEntryCount();
    // Demo 账号不做任何限制检查
    if (repository.isDemoAccount()) {
      // 跳过所有限制检查
    } else if (phone == null) {
      if (total + event.entries.length > VipService.touristLimit) {
        emit(state.copyWith(showLoginLimitDialog: true));
        return;
      }
    } else if (!vipService.isVip) {
      if (total + event.entries.length > VipService.freeUserLimit) {
        emit(state.copyWith(showVipLimitDialog: true));
        return;
      }
    }
    // 会员已过期：禁止新增账单
    if (vipService.hasExpiredEntitlement) {
      emit(state.copyWith(showVipLimitDialog: true));
      return;
    }
    debugPrint(
      '[Bloc] _onAddMultipleEntries called, event.entries.length=${event.entries.length}, state.entries.length=${state.entries.length}',
    );
    final updated = [...event.entries, ...state.entries];
    debugPrint('[Bloc] _onAddMultipleEntries updated.length=${updated.length}');
    updated.sort((a, b) => b.date.compareTo(a.date));
    emit(
      state.copyWith(
        entries: updated,
        parsedResults: const [],
        isAiPanelVisible: false,
        totalEntryCount: total + event.entries.length,
      ),
    );
    debugPrint(
      '[Bloc] _onAddMultipleEntries done, final total=${total + event.entries.length}',
    );
  }

  Future<void> _onDeleteEntry(
    DeleteAccountEntry event,
    Emitter<AccountState> emit,
  ) async {
    debugPrint('[Bloc] _onDeleteEntry called, id=${event.id}');
    final result = await deleteEntry(DeleteEntryParams(id: event.id));

    await result.fold(
      (error) async {
        debugPrint('[Bloc] deleteEntry error: $error');
        emit(state.copyWith(errorMessage: error));
      },
      (_) async {
        // 不立即从云端拉取（FC 删除异步完成，立即拉取会拿到旧数据导致删除失效）
        // 本地已删除，下次 App 打开或切回前台时自然触发 getEntries 刷新
        final updated = state.entries.where((e) => e.id != event.id).toList();
        emit(state.copyWith(entries: updated, totalEntryCount: updated.length));
      },
    );
  }

  Future<void> _onUpdateEntry(
    UpdateAccountEntry event,
    Emitter<AccountState> emit,
  ) async {
    debugPrint('[Bloc] _onUpdateEntry called, id=${event.entry.id}');
    final result = await repository.updateEntry(event.entry);

    result.fold(
      (error) {
        debugPrint('[Bloc] updateEntry error: $error');
        emit(state.copyWith(errorMessage: error));
      },
      (updatedEntry) {
        final updated = state.entries.map((e) {
          return e.id == updatedEntry.id ? updatedEntry : e;
        }).toList();
        updated.sort((a, b) => b.date.compareTo(a.date));
        emit(state.copyWith(entries: updated));
      },
    );
  }

  Future<void> _onParseTextInput(
    ParseTextInput event,
    Emitter<AccountState> emit,
  ) async {
    if (event.text.trim().isEmpty) return;

    emit(state.copyWith(isParsing: true));

    final results = await inputParserService.parseInput(event.text.trim());

    emit(
      state.copyWith(
        parsedResults: results,
        isParsing: false,
        isAiPanelVisible: results.isNotEmpty,
      ),
    );
  }

  void _onClearParsedResults(
    ClearParsedResults event,
    Emitter<AccountState> emit,
  ) {
    emit(state.copyWith(parsedResults: const [], isAiPanelVisible: false));
  }

  void _onClearVipLimitDialog(
    ClearVipLimitDialog event,
    Emitter<AccountState> emit,
  ) {
    emit(state.copyWith(showVipLimitDialog: false));
  }

  void _onClearLoginLimitDialog(
    ClearLoginLimitDialog event,
    Emitter<AccountState> emit,
  ) {
    emit(state.copyWith(showLoginLimitDialog: false));
  }

  Future<void> _onChangeMonthFilter(
    ChangeMonthFilter event,
    Emitter<AccountState> emit,
  ) async {
    add(LoadEntriesByMonth(year: event.year, month: event.month));
  }

  void _onFilterByDay(FilterByDay event, Emitter<AccountState> emit) {
    emit(state.copyWith(selectedDay: event.day));
  }

  int _daysInMonth(int year, int month) {
    if (month == 12) {
      return DateTime(year + 1, 1, 0).day;
    }
    return DateTime(year, month + 1, 0).day;
  }
}
