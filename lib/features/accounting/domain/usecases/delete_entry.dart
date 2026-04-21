import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/account_entry_repository.dart';

class DeleteEntry implements UseCase<void, DeleteEntryParams> {
  final AccountEntryRepository repository;

  DeleteEntry(this.repository);

  @override
  Future<Either<String, void>> call(DeleteEntryParams params) {
    return repository.deleteEntry(params.id);
  }
}

class DeleteEntryParams extends Equatable {
  final String id;

  const DeleteEntryParams({required this.id});

  @override
  List<Object?> get props => [id];
}
