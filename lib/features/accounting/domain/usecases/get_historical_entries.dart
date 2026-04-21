import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:get_it/get_it.dart';
import '../../../../app/app_flavor.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../services/app_profile_service.dart';
import '../entities/entities.dart';
import '../repositories/account_entry_repository.dart';

/// 获取近 N 个月的历史账单（用于 AI 分析和预测）
class GetHistoricalEntries
    implements UseCase<List<AccountEntry>, GetHistoricalEntriesParams> {
  final AccountEntryRepository repository;

  bool get _isIntl {
    if (GetIt.instance.isRegistered<AppProfileService>()) {
      return GetIt.instance<AppProfileService>().flavor.isIntl;
    }
    return AppFlavorX.current.isIntl;
  }

  String _message(String zh, String en) => _isIntl ? en : zh;

  GetHistoricalEntries(this.repository);

  @override
  Future<Either<String, List<AccountEntry>>> call(
    GetHistoricalEntriesParams params,
  ) async {
    final now = DateTime.now();
    final entries = <AccountEntry>[];

    for (int i = 0; i < params.months; i++) {
      final targetMonth = DateTime(now.year, now.month - i, 1);
      final result = await repository.getEntriesByMonth(
        targetMonth.year,
        targetMonth.month,
      );
      result.fold(
        (error) => null,
        (monthEntries) => entries.addAll(monthEntries),
      );
    }

    if (entries.isEmpty) {
      return Left(_message('暂无历史数据', 'Not enough history yet'));
    }
    return Right(entries);
  }
}

class GetHistoricalEntriesParams extends Equatable {
  final int months; // 获取近 N 个月的数据

  const GetHistoricalEntriesParams({this.months = 3});

  @override
  List<Object?> get props => [months];
}
