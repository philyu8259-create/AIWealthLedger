import 'package:dartz/dartz.dart';
import 'package:get_it/get_it.dart';
import '../../../../../app/app_flavor.dart';
import '../../../../../services/app_profile_service.dart';
import '../../../domain/entities/custom_category/custom_category.dart';
import '../../datasources/custom_category/i_custom_category_datasource.dart';

class CustomCategoryRepository {
  final ICustomCategoryDataSource _dataSource;

  bool get _isIntl {
    if (GetIt.instance.isRegistered<AppProfileService>()) {
      return GetIt.instance<AppProfileService>().flavor.isIntl;
    }
    return AppFlavorX.current.isIntl;
  }

  String _message(String zh, String en) => _isIntl ? en : zh;

  CustomCategoryRepository(this._dataSource);

  Future<Either<String, List<CustomCategory>>> getCustomCategories() async {
    try {
      final result = await _dataSource.getCustomCategories();
      return Right(result);
    } catch (e) {
      return Left(
        _message(
          '获取自定义类目失败: $e',
          'Failed to load custom categories: $e',
        ),
      );
    }
  }

  Future<Either<String, CustomCategory>> addCustomCategory(
    CustomCategory category,
  ) async {
    try {
      final result = await _dataSource.addCustomCategory(category);
      return Right(result);
    } catch (e) {
      return Left(_message('添加类目失败: $e', 'Failed to add category: $e'));
    }
  }

  Future<Either<String, CustomCategory>> updateCustomCategory(
    CustomCategory category,
  ) async {
    try {
      final result = await _dataSource.updateCustomCategory(category);
      return Right(result);
    } catch (e) {
      return Left(
        _message('更新类目失败: $e', 'Failed to update category: $e'),
      );
    }
  }

  Future<Either<String, void>> deleteCustomCategory(String id) async {
    try {
      await _dataSource.deleteCustomCategory(id);
      return const Right(null);
    } catch (e) {
      return Left(
        _message('删除类目失败: $e', 'Failed to delete category: $e'),
      );
    }
  }

  Future<Either<String, List<String>>> getQuickChipIds() async {
    try {
      final result = await _dataSource.getQuickChipIds();
      return Right(result);
    } catch (e) {
      return Left(
        _message('获取快捷类目失败: $e', 'Failed to load quick categories: $e'),
      );
    }
  }

  Future<Either<String, void>> saveQuickChipIds(List<String> ids) async {
    try {
      await _dataSource.saveQuickChipIds(ids);
      return const Right(null);
    } catch (e) {
      return Left(
        _message('保存快捷类目失败: $e', 'Failed to save quick categories: $e'),
      );
    }
  }
}
