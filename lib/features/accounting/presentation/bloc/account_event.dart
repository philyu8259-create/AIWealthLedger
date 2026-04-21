import 'package:equatable/equatable.dart';
import '../../domain/entities/entities.dart';

abstract class AccountEvent extends Equatable {
  const AccountEvent();

  @override
  List<Object?> get props => [];
}

/// 加载指定月份的账单
class LoadEntriesByMonth extends AccountEvent {
  final int year;
  final int month;

  const LoadEntriesByMonth({required this.year, required this.month});

  @override
  List<Object?> get props => [year, month];
}

/// 加载当月账单
class LoadCurrentMonthEntries extends AccountEvent {
  const LoadCurrentMonthEntries();
}

/// 添加账单
class AddAccountEntry extends AccountEvent {
  final AccountEntry entry;

  const AddAccountEntry(this.entry);

  @override
  List<Object?> get props => [entry];
}

/// 批量添加账单（解决多次 rapid add 导致的 state 覆盖问题）
class AddMultipleAccountEntries extends AccountEvent {
  final List<AccountEntry> entries;

  const AddMultipleAccountEntries(this.entries);

  @override
  List<Object?> get props => [entries];
}

/// 删除账单
class DeleteAccountEntry extends AccountEvent {
  final String id;

  const DeleteAccountEntry(this.id);

  @override
  List<Object?> get props => [id];
}

/// 更新账单
class UpdateAccountEntry extends AccountEvent {
  final AccountEntry entry;

  const UpdateAccountEntry(this.entry);

  @override
  List<Object?> get props => [entry];
}

/// AI 解析文字输入
class ParseTextInput extends AccountEvent {
  final String text;

  const ParseTextInput(this.text);

  @override
  List<Object?> get props => [text];
}

/// 清空 AI 解析结果
class ClearParsedResults extends AccountEvent {
  const ClearParsedResults();
}

/// 切换月份筛选
class ChangeMonthFilter extends AccountEvent {
  final int year;
  final int month;

  const ChangeMonthFilter({required this.year, required this.month});

  @override
  List<Object?> get props => [year, month];
}

/// 关闭 VIP 限额提示弹窗
class ClearVipLimitDialog extends AccountEvent {
  const ClearVipLimitDialog();
}

/// 关闭登录提示弹窗
class ClearLoginLimitDialog extends AccountEvent {
  const ClearLoginLimitDialog();
}

/// 按指定日期筛选账单（null=显示整月）
class FilterByDay extends AccountEvent {
  final DateTime? day;

  const FilterByDay(this.day);

  @override
  List<Object?> get props => [day];
}
