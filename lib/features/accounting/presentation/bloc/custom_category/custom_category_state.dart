import 'package:equatable/equatable.dart';
import '../../../domain/entities/custom_category/custom_category.dart';

enum CustomCategoryStatus { initial, loading, loaded, error }

class CustomCategoryState extends Equatable {
  final CustomCategoryStatus status;
  final List<CustomCategory> categories;
  final String? errorMessage;
  final List<String> quickChipIds;

  const CustomCategoryState({
    this.status = CustomCategoryStatus.initial,
    this.categories = const [],
    this.errorMessage,
    this.quickChipIds = const [],
  });

  factory CustomCategoryState.initial() => const CustomCategoryState();

  List<CustomCategory> get expenseCategories =>
      categories.where((c) => c.type == CustomCategoryType.expense).toList();

  List<CustomCategory> get incomeCategories =>
      categories.where((c) => c.type == CustomCategoryType.income).toList();

  CustomCategoryState copyWith({
    CustomCategoryStatus? status,
    List<CustomCategory>? categories,
    String? errorMessage,
    List<String>? quickChipIds,
  }) {
    return CustomCategoryState(
      status: status ?? this.status,
      categories: categories ?? this.categories,
      errorMessage: errorMessage ?? this.errorMessage,
      quickChipIds: quickChipIds ?? this.quickChipIds,
    );
  }

  @override
  List<Object?> get props => [status, categories, errorMessage, quickChipIds];
}
