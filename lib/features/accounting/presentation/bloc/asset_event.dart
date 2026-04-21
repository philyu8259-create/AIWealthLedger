import 'package:equatable/equatable.dart';
import '../../domain/entities/entities.dart';

abstract class AssetEvent extends Equatable {
  const AssetEvent();

  @override
  List<Object?> get props => [];
}

class LoadAssets extends AssetEvent {
  const LoadAssets();
}

class AddAssetEvent extends AssetEvent {
  final String name;
  final AssetType type;
  final double balance;

  const AddAssetEvent({
    required this.name,
    required this.type,
    required this.balance,
  });

  @override
  List<Object?> get props => [name, type, balance];
}

class UpdateAssetEvent extends AssetEvent {
  final Asset asset;

  const UpdateAssetEvent(this.asset);

  @override
  List<Object?> get props => [asset];
}

class DeleteAssetEvent extends AssetEvent {
  final String id;

  const DeleteAssetEvent(this.id);

  @override
  List<Object?> get props => [id];
}

class ClearAssetVipLimitDialog extends AssetEvent {
  const ClearAssetVipLimitDialog();
}
