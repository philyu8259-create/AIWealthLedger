import 'package:equatable/equatable.dart';
import '../../domain/entities/entities.dart';

enum AssetStatus { initial, loading, loaded, error }

class AssetState extends Equatable {
  final AssetStatus status;
  final List<Asset> assets;
  final String? errorMessage;

  const AssetState({
    this.status = AssetStatus.initial,
    this.assets = const [],
    this.errorMessage,
  });

  factory AssetState.initial() => const AssetState();

  double get totalAssets {
    return assets.fold(0.0, (sum, a) => sum + a.balance);
  }

  AssetState copyWith({
    AssetStatus? status,
    List<Asset>? assets,
    String? errorMessage,
  }) {
    return AssetState(
      status: status ?? this.status,
      assets: assets ?? this.assets,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, assets, errorMessage];
}
