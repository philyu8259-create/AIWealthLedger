import 'package:equatable/equatable.dart';
import '../../../domain/entities/custom_category/custom_category.dart';

abstract class CustomCategoryEvent extends Equatable {
  const CustomCategoryEvent();

  @override
  List<Object?> get props => [];
}

class LoadCustomCategories extends CustomCategoryEvent {
  const LoadCustomCategories();
}

class AddCustomCategoryEvent extends CustomCategoryEvent {
  final String name;
  final String icon;
  final CustomCategoryType type;

  const AddCustomCategoryEvent({
    required this.name,
    required this.icon,
    required this.type,
  });

  @override
  List<Object?> get props => [name, icon, type];
}

class UpdateCustomCategoryEvent extends CustomCategoryEvent {
  final CustomCategory category;

  const UpdateCustomCategoryEvent(this.category);

  @override
  List<Object?> get props => [category];
}

class DeleteCustomCategoryEvent extends CustomCategoryEvent {
  final String id;

  const DeleteCustomCategoryEvent(this.id);

  @override
  List<Object?> get props => [id];
}

class SaveQuickChipIds extends CustomCategoryEvent {
  final List<String> ids;

  const SaveQuickChipIds(this.ids);

  @override
  List<Object?> get props => [ids];
}
