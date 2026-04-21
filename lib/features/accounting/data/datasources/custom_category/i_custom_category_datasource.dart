import '../../../domain/entities/custom_category/custom_category.dart';

abstract class ICustomCategoryDataSource {
  Future<List<CustomCategory>> getCustomCategories();
  Future<CustomCategory> addCustomCategory(CustomCategory category);
  Future<CustomCategory> updateCustomCategory(CustomCategory category);
  Future<void> deleteCustomCategory(String id);
  Future<List<String>> getQuickChipIds();
  Future<void> saveQuickChipIds(List<String> ids);
}
