import '../../domain/entities/entities.dart';

/// 账本数据源接口（抽象层）
/// Mock 和 CloudBase 都实现此接口
abstract class IAccountEntryDataSource {
  Future<List<AccountEntry>> getEntries();
  Future<List<AccountEntry>> getEntriesByMonth(int year, int month);
  Future<AccountEntry> addEntry(AccountEntry entry);
  Future<AccountEntry> updateEntry(AccountEntry entry);
  Future<void> deleteEntry(String id);

  /// 登录后从云端恢复数据（仅当本地为空时）
  Future<List<AccountEntry>> restoreFromCloudIfNeeded();

  /// 获取当前登录手机号（游客/Demo 返回 null）
  String? getCurrentPhone();

  /// 是否为 Demo 账号
  bool isDemoAccount();
}
