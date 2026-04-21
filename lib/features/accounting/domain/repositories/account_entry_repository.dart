import 'package:dartz/dartz.dart';
import '../../domain/entities/entities.dart';

abstract class AccountEntryRepository {
  /// 获取所有账单
  Future<Either<String, List<AccountEntry>>> getEntries();

  /// 按月份获取账单
  Future<Either<String, List<AccountEntry>>> getEntriesByMonth(
    int year,
    int month,
  );

  /// 添加账单
  Future<Either<String, AccountEntry>> addEntry(AccountEntry entry);

  /// 更新账单
  Future<Either<String, AccountEntry>> updateEntry(AccountEntry entry);

  /// 删除账单
  Future<Either<String, void>> deleteEntry(String id);

  /// 获取当前登录手机号（游客返回 null）
  String? getCurrentPhone();

  /// 是否为 Demo 账号
  bool isDemoAccount();
}
