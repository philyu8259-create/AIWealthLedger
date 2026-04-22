import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app/profile/capability_profile.dart';
import 'ai_privacy_consent_service.dart';
import 'ai/input_parser_service.dart';
import 'ai/receipt_ocr_service.dart';
import 'app_migration_service.dart';
import 'app_profile_service.dart';
import 'quick_chip_service.dart';
import '../features/accounting/data/datasources/i_account_entry_datasource.dart';
import '../features/accounting/data/datasources/i_asset_datasource.dart';
import '../features/accounting/data/datasources/cloud_sync_account_datasource.dart';
import '../features/accounting/data/datasources/cloud_asset_datasource.dart';
import '../features/accounting/data/datasources/custom_category/i_custom_category_datasource.dart';
import '../features/accounting/data/datasources/custom_category/mock_custom_category_datasource.dart';
import '../features/accounting/data/repositories/account_entry_repository_impl.dart';
import '../features/accounting/data/repositories/asset_repository_impl.dart';
import '../features/accounting/data/repositories/custom_category/custom_category_repository.dart';
import '../features/accounting/domain/repositories/account_entry_repository.dart';
import '../features/accounting/domain/repositories/asset_repository.dart';
import '../features/accounting/domain/usecases/add_entry.dart';
import '../features/accounting/domain/usecases/delete_entry.dart';
import '../features/accounting/domain/usecases/get_entries_by_month.dart';
import '../features/accounting/domain/usecases/get_historical_entries.dart';
import '../features/accounting/domain/usecases/predict_spending.dart';
import '../features/accounting/domain/usecases/asset/add_asset.dart';
import '../features/accounting/domain/usecases/asset/delete_asset.dart';
import '../features/accounting/domain/usecases/asset/get_assets.dart';
import '../features/accounting/domain/usecases/asset/update_asset.dart';
import '../features/accounting/presentation/bloc/account_bloc.dart';
import '../features/accounting/presentation/bloc/asset_bloc.dart';
import '../features/accounting/presentation/bloc/custom_category/custom_category_bloc.dart';
import 'aliyun_asr_service.dart';
import 'aliyun_sms_service.dart';
import 'baidu_ocr_service.dart';
import 'cloud_service.dart';
import 'config_service.dart';
import 'gemini_input_parser_service.dart';
import 'gemini_spending_prediction_service.dart';
import 'google_vision_receipt_ocr_service.dart';
import 'intl_auth_service.dart';
import 'qwen_service.dart';
import 'qwen_spending_prediction_service.dart';
import 'sms_service.dart';
import 'theme_mode_service.dart';
import 'vip_service.dart';
import 'avatar_service.dart';
import 'stock_service.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies() async {
  final prefs = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(prefs);

  // App profile / migration
  getIt.registerLazySingleton<AppProfileService>(
    () => AppProfileService(getIt<SharedPreferences>()),
  );
  getIt.registerLazySingleton<ThemeModeService>(
    () => ThemeModeService(getIt<SharedPreferences>()),
  );
  getIt.registerLazySingleton<AppMigrationService>(
    () => AppMigrationService(
      getIt<SharedPreferences>(),
      getIt<AppProfileService>(),
    ),
  );

  // Services
  getIt.registerLazySingleton<QwenService>(() => QwenService());
  getIt.registerLazySingleton<QwenSpendingPredictionService>(
    () => QwenSpendingPredictionService(),
  );
  getIt.registerLazySingleton<AliyunASRService>(() => AliyunASRService());
  getIt.registerLazySingleton<BaiduOCRService>(() => BaiduOCRService());
  getIt.registerLazySingleton<GeminiInputParserService>(
    () => GeminiInputParserService(),
  );
  getIt.registerLazySingleton<GoogleVisionReceiptOcrService>(
    () => GoogleVisionReceiptOcrService(),
  );
  getIt.registerLazySingleton<GeminiSpendingPredictionService>(
    () => GeminiSpendingPredictionService(),
  );
  getIt.registerFactory<InputParserService>(
    () => _buildInputParserService(getIt<AppProfileService>()),
  );
  getIt.registerFactory<ReceiptOcrService>(
    () => _buildReceiptOcrService(getIt<AppProfileService>()),
  );
  getIt.registerFactory<SpendingPredictionService>(
    () => _buildSpendingPredictionService(getIt<AppProfileService>()),
  );
  getIt.registerLazySingleton<QuickChipService>(
    () => QuickChipService(getIt<SharedPreferences>()),
  );
  getIt.registerLazySingleton<AIPrivacyConsentService>(
    () => AIPrivacyConsentService(getIt<SharedPreferences>()),
  );
  getIt.registerLazySingleton<IntlAuthService>(
    () => IntlAuthService(getIt<SharedPreferences>()),
  );

  // CloudService — 后台同步到阿里云 FC（如果配置了）
  if (ConfigService.instance.aliyunFCApi.isNotEmpty) {
    try {
      getIt.registerLazySingleton<CloudService>(() => CloudService());
    } catch (_) {
      // 未配置阿里云 FC，跳过
    }
  }

  // 数据层 — 读取优先从云端，缓存到本地 SharedPreferences
  // 写入时同步到阿里云 FC
  getIt.registerLazySingleton<IAccountEntryDataSource>(
    () => CloudSyncAccountDataSource(getIt<SharedPreferences>()),
  );

  getIt.registerLazySingleton<AccountEntryRepository>(
    () => AccountEntryRepositoryImpl(getIt<IAccountEntryDataSource>()),
  );
  getIt.registerLazySingleton(
    () => GetEntriesByMonth(getIt<AccountEntryRepository>()),
  );
  getIt.registerLazySingleton(() => AddEntry(getIt<AccountEntryRepository>()));
  getIt.registerLazySingleton(
    () => DeleteEntry(getIt<AccountEntryRepository>()),
  );

  // 分析预测 use cases
  getIt.registerLazySingleton(
    () => GetHistoricalEntries(getIt<AccountEntryRepository>()),
  );
  getIt.registerLazySingleton(
    () => PredictSpending(getIt<SpendingPredictionService>()),
  );
  getIt.registerLazySingleton(() => SmsService());
  getIt.registerLazySingleton(() => AliyunSmsService());
  getIt.registerLazySingleton(() => VipService(getIt<SharedPreferences>()));
  getIt.registerLazySingleton(() => AvatarService(getIt<SharedPreferences>()));
  getIt.registerLazySingleton(() => StockService(getIt<SharedPreferences>()));
  getIt.registerLazySingleton<ICustomCategoryDataSource>(
    () => MockCustomCategoryDataSource(getIt<SharedPreferences>()),
  );
  getIt.registerLazySingleton(
    () => CustomCategoryRepository(getIt<ICustomCategoryDataSource>()),
  );
  getIt.registerFactory(
    () => CustomCategoryBloc(getIt<CustomCategoryRepository>()),
  );

  // 资产账户数据层
  getIt.registerLazySingleton<IAssetDataSource>(() => CloudAssetDataSource());
  getIt.registerLazySingleton<AssetRepository>(
    () => AssetRepositoryImpl(getIt<IAssetDataSource>()),
  );
  getIt.registerLazySingleton(() => GetAssets(getIt<AssetRepository>()));
  getIt.registerLazySingleton(() => AddAsset(getIt<AssetRepository>()));
  getIt.registerLazySingleton(() => UpdateAsset(getIt<AssetRepository>()));
  getIt.registerLazySingleton(() => DeleteAsset(getIt<AssetRepository>()));

  // BLoC
  getIt.registerFactory(
    () => AccountBloc(
      getEntriesByMonth: getIt<GetEntriesByMonth>(),
      addEntry: getIt<AddEntry>(),
      deleteEntry: getIt<DeleteEntry>(),
      inputParserService: getIt<InputParserService>(),
      vipService: getIt<VipService>(),
      repository: getIt<AccountEntryRepository>(),
    ),
  );
  getIt.registerFactory(
    () => AssetBloc(
      getAssets: getIt<GetAssets>(),
      addAsset: getIt<AddAsset>(),
      updateAsset: getIt<UpdateAsset>(),
      deleteAsset: getIt<DeleteAsset>(),
      vipService: getIt<VipService>(),
    ),
  );
}

InputParserService _buildInputParserService(AppProfileService profileService) {
  switch (profileService.currentProfile.capabilityProfile.aiProvider) {
    case AiProviderType.gemini:
      return getIt<GeminiInputParserService>();
    case AiProviderType.legacyCnAi:
      return getIt<QwenService>();
  }
}

ReceiptOcrService _buildReceiptOcrService(AppProfileService profileService) {
  switch (profileService.currentProfile.capabilityProfile.ocrProvider) {
    case OcrProviderType.googleVisionGemini:
    case OcrProviderType.googleExpenseParser:
      return getIt<GoogleVisionReceiptOcrService>();
    case OcrProviderType.legacyCnOcr:
      return getIt<BaiduOCRService>();
  }
}

SpendingPredictionService _buildSpendingPredictionService(
  AppProfileService profileService,
) {
  switch (profileService.currentProfile.capabilityProfile.aiProvider) {
    case AiProviderType.gemini:
      return getIt<GeminiSpendingPredictionService>();
    case AiProviderType.legacyCnAi:
      return getIt<QwenSpendingPredictionService>();
  }
}
