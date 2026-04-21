import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../data/repositories/custom_category/custom_category_repository.dart';
import '../../../domain/entities/custom_category/custom_category.dart';
import 'custom_category_event.dart';
import 'custom_category_state.dart';

class CustomCategoryBloc
    extends Bloc<CustomCategoryEvent, CustomCategoryState> {
  final CustomCategoryRepository _repository;

  CustomCategoryBloc(this._repository) : super(CustomCategoryState.initial()) {
    on<LoadCustomCategories>(_onLoad);
    on<AddCustomCategoryEvent>(_onAdd);
    on<UpdateCustomCategoryEvent>(_onUpdate);
    on<DeleteCustomCategoryEvent>(_onDelete);
    on<SaveQuickChipIds>(_onSaveQuickChipIds);
  }

  Future<void> _onLoad(
    LoadCustomCategories event,
    Emitter<CustomCategoryState> emit,
  ) async {
    emit(state.copyWith(status: CustomCategoryStatus.loading));
    final result = await _repository.getCustomCategories();
    final quickChipResult = await _repository.getQuickChipIds();
    result.fold(
      (error) => emit(
        state.copyWith(status: CustomCategoryStatus.error, errorMessage: error),
      ),
      (categories) {
        final quickChipIds = quickChipResult.fold(
          (_) => <String>[],
          (ids) => ids,
        );
        emit(
          state.copyWith(
            status: CustomCategoryStatus.loaded,
            categories: categories,
            quickChipIds: quickChipIds,
          ),
        );
      },
    );
  }

  Future<void> _onAdd(
    AddCustomCategoryEvent event,
    Emitter<CustomCategoryState> emit,
  ) async {
    // 立即添加到 UI（同步），让 BlocBuilder 立即渲染新类目
    final category = CustomCategory(
      id: const Uuid().v4(),
      name: event.name,
      icon: event.icon,
      type: event.type,
      createdAt: DateTime.now(),
    );
    emit(
      state.copyWith(
        status: CustomCategoryStatus.loaded,
        categories: [...state.categories, category],
      ),
    );
    // 异步持久化到 SharedPreferences
    await _repository.addCustomCategory(category);
  }

  Future<void> _onUpdate(
    UpdateCustomCategoryEvent event,
    Emitter<CustomCategoryState> emit,
  ) async {
    final result = await _repository.updateCustomCategory(event.category);
    result.fold(
      (error) => emit(state.copyWith(errorMessage: error)),
      (updated) => emit(
        state.copyWith(
          categories: state.categories
              .map((c) => c.id == updated.id ? updated : c)
              .toList(),
        ),
      ),
    );
  }

  Future<void> _onDelete(
    DeleteCustomCategoryEvent event,
    Emitter<CustomCategoryState> emit,
  ) async {
    final result = await _repository.deleteCustomCategory(event.id);
    result.fold(
      (error) => emit(state.copyWith(errorMessage: error)),
      (_) => emit(
        state.copyWith(
          categories: state.categories.where((c) => c.id != event.id).toList(),
        ),
      ),
    );
  }

  Future<void> _onSaveQuickChipIds(
    SaveQuickChipIds event,
    Emitter<CustomCategoryState> emit,
  ) async {
    await _repository.saveQuickChipIds(event.ids);
    emit(state.copyWith(quickChipIds: event.ids));
  }
}
