import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/entities.dart';
import '../repositories/account_entry_repository.dart';

class GetEntriesByMonth
    implements UseCase<List<AccountEntry>, GetEntriesByMonthParams> {
  final AccountEntryRepository repository;

  GetEntriesByMonth(this.repository);

  @override
  Future<Either<String, List<AccountEntry>>> call(
    GetEntriesByMonthParams params,
  ) {
    return repository.getEntriesByMonth(params.year, params.month);
  }
}

class GetEntriesByMonthParams extends Equatable {
  final int year;
  final int month;

  const GetEntriesByMonthParams({required this.year, required this.month});

  @override
  List<Object?> get props => [year, month];
}
