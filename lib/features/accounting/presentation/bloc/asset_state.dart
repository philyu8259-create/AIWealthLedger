import 'package:equatable/equatable.dart';
import '../../domain/entities/entities.dart';

enum AssetStatus { initial, loading, loaded, error }

class AssetState extends Equatable {
  final AssetStatus status;
  final List<Asset> assets;
  final String? errorMessage;
  final bool showVipLimitDialog;

  const AssetState({
    this.status = AssetStatus.initial,
    this.assets = const [],
    this.errorMessage,
    this.showVipLimitDialog = false,
  });

  factory AssetState.initial() => const AssetState();

  double get totalAssets {
    return assets.fold(0.0, (sum, a) => sum + a.balance);
  }

  AssetState copyWith({
    AssetStatus? status,
    List<Asset>? assets,
    String? errorMessage,
    bool? showVipLimitDialog,
  }) {
    return AssetState(
      status: status ?? this.status,
      assets: assets ?? this.assets,
      errorMessage: errorMessage,
      showVipLimitDialog: showVipLimitDialog ?? this.showVipLimitDialog,
    );
  }

  @override
  List<Object?> get props => [status, assets, errorMessage, showVipLimitDialog];
}
