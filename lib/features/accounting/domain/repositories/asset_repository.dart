import 'package:dartz/dartz.dart';
import '../../domain/entities/entities.dart';

abstract class AssetRepository {
  Future<Either<String, List<Asset>>> getAssets();
  Future<Either<String, List<Asset>>> addAsset(Asset asset);
  Future<Either<String, Asset>> updateAsset(Asset asset);
  Future<Either<String, void>> deleteAsset(String id);
}
