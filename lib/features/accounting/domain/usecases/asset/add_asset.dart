import 'package:dartz/dartz.dart';
import 'package:uuid/uuid.dart';
import '../../entities/entities.dart';
import '../../repositories/asset_repository.dart';

class AddAsset {
  final AssetRepository repository;

  AddAsset(this.repository);

  Future<Either<String, List<Asset>>> call({
    required String name,
    required AssetType type,
    required double balance,
  }) async {
    final asset = Asset(
      id: const Uuid().v4(),
      name: name,
      type: type,
      balance: balance,
      createdAt: DateTime.now(),
      syncStatus: SyncStatus.pending,
    );
    return repository.addAsset(asset);
  }
}
