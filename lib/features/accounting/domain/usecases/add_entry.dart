import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/entities.dart';
import '../repositories/account_entry_repository.dart';

class AddEntry implements UseCase<AccountEntry, AddEntryParams> {
  final AccountEntryRepository repository;

  AddEntry(this.repository);

  @override
  Future<Either<String, AccountEntry>> call(AddEntryParams params) {
    return repository.addEntry(params.entry);
  }
}

class AddEntryParams extends Equatable {
  final AccountEntry entry;

  const AddEntryParams({required this.entry});

  @override
  List<Object?> get props => [entry];
}
