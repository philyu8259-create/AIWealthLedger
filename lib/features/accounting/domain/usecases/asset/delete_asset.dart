import 'package:dartz/dartz.dart';
import '../../repositories/asset_repository.dart';

class DeleteAsset {
  final AssetRepository repository;

  DeleteAsset(this.repository);

  Future<Either<String, void>> call(String id) {
    return repository.deleteAsset(id);
  }
}
