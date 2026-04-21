import 'package:dartz/dartz.dart';
import '../../entities/entities.dart';
import '../../repositories/asset_repository.dart';

class UpdateAsset {
  final AssetRepository repository;

  UpdateAsset(this.repository);

  Future<Either<String, Asset>> call(Asset asset) {
    return repository.updateAsset(
      asset.copyWith(syncStatus: SyncStatus.pending),
    );
  }
}
