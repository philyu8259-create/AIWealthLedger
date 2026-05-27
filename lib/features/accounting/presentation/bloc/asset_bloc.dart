import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../services/vip_service.dart';
import '../../domain/usecases/asset/add_asset.dart';
import '../../domain/usecases/asset/delete_asset.dart';
import '../../domain/usecases/asset/get_assets.dart';
import '../../domain/usecases/asset/update_asset.dart';
import 'asset_event.dart';
import 'asset_state.dart';

class AssetBloc extends Bloc<AssetEvent, AssetState> {
  final GetAssets getAssets;
  final AddAsset addAsset;
  final UpdateAsset updateAsset;
  final DeleteAsset deleteAsset;
  final VipService vipService;

  AssetBloc({
    required this.getAssets,
    required this.addAsset,
    required this.updateAsset,
    required this.deleteAsset,
    required this.vipService,
  }) : super(AssetState.initial()) {
    on<LoadAssets>(_onLoadAssets);
    on<AddAssetEvent>(_onAddAsset);
    on<UpdateAssetEvent>(_onUpdateAsset);
    on<DeleteAssetEvent>(_onDeleteAsset);
  }

  Future<void> _onLoadAssets(LoadAssets event, Emitter<AssetState> emit) async {
    emit(state.copyWith(status: AssetStatus.loading));

    final result = await getAssets();

    result.fold(
      (error) =>
          emit(state.copyWith(status: AssetStatus.error, errorMessage: error)),
      (assets) =>
          emit(state.copyWith(status: AssetStatus.loaded, assets: assets)),
    );
  }

  Future<void> _onAddAsset(
    AddAssetEvent event,
    Emitter<AssetState> emit,
  ) async {
    final result = await addAsset(
      name: event.name,
      type: event.type,
      balance: event.balance,
    );

    result.fold(
      (error) {
        emit(state.copyWith(errorMessage: error));
      },
      (assets) {
        emit(state.copyWith(assets: assets));
      },
    );
  }

  Future<void> _onUpdateAsset(
    UpdateAssetEvent event,
    Emitter<AssetState> emit,
  ) async {
    final result = await updateAsset(event.asset);

    result.fold((error) => emit(state.copyWith(errorMessage: error)), (
      updated,
    ) {
      final assets = state.assets
          .map((a) => a.id == updated.id ? updated : a)
          .toList();
      emit(state.copyWith(assets: assets));
    });
  }

  Future<void> _onDeleteAsset(
    DeleteAssetEvent event,
    Emitter<AssetState> emit,
  ) async {
    final result = await deleteAsset(event.id);

    result.fold((error) => emit(state.copyWith(errorMessage: error)), (_) {
      final assets = state.assets.where((a) => a.id != event.id).toList();
      emit(state.copyWith(assets: assets));
    });
  }
}
