import 'package:dartz/dartz.dart';
import '../../entities/entities.dart';
import '../../repositories/asset_repository.dart';

class GetAssets {
  final AssetRepository repository;

  GetAssets(this.repository);

  Future<Either<String, List<Asset>>> call() {
    return repository.getAssets();
  }
}
