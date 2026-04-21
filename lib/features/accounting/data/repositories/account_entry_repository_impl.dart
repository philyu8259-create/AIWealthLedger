import 'package:dartz/dartz.dart';
import 'package:get_it/get_it.dart';
import '../../../../app/app_flavor.dart';
import '../../../../services/app_profile_service.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/account_entry_repository.dart';
import '../datasources/i_account_entry_datasource.dart';

class AccountEntryRepositoryImpl implements AccountEntryRepository {
  final IAccountEntryDataSource dataSource;

  bool get _isIntl {
    if (GetIt.instance.isRegistered<AppProfileService>()) {
      return GetIt.instance<AppProfileService>().flavor.isIntl;
    }
    return AppFlavorX.current.isIntl;
  }

  String _message(String zh, String en) => _isIntl ? en : zh;

  AccountEntryRepositoryImpl(this.dataSource);

  @override
  Future<Either<String, List<AccountEntry>>> getEntries() async {
    try {
      final entries = await dataSource.getEntries();
      return Right(entries);
    } catch (e) {
      return Left(_message('加载账单失败: $e', 'Failed to load entries: $e'));
    }
  }

  @override
  Future<Either<String, List<AccountEntry>>> getEntriesByMonth(
    int year,
    int month,
  ) async {
    try {
      final entries = await dataSource.getEntriesByMonth(year, month);
      return Right(entries);
    } catch (e) {
      return Left(_message('加载账单失败: $e', 'Failed to load entries: $e'));
    }
  }

  @override
  Future<Either<String, AccountEntry>> addEntry(AccountEntry entry) async {
    try {
      final model = await dataSource.addEntry(entry);
      return Right(model);
    } catch (e) {
      return Left(_message('添加账单失败: $e', 'Failed to add entry: $e'));
    }
  }

  @override
  Future<Either<String, AccountEntry>> updateEntry(AccountEntry entry) async {
    try {
      final model = await dataSource.updateEntry(entry);
      return Right(model);
    } catch (e) {
      return Left(_message('更新账单失败: $e', 'Failed to update entry: $e'));
    }
  }

  @override
  Future<Either<String, void>> deleteEntry(String id) async {
    try {
      await dataSource.deleteEntry(id);
      return const Right(null);
    } catch (e) {
      return Left(_message('删除账单失败: $e', 'Failed to delete entry: $e'));
    }
  }

  @override
  String? getCurrentPhone() => dataSource.getCurrentPhone();

  @override
  bool isDemoAccount() => dataSource.isDemoAccount();
}
