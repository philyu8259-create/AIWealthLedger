import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:uuid/uuid.dart';
import '../../domain/entities/entities.dart';
import '../../domain/entities/custom_category/custom_category.dart';
import '../../domain/repositories/account_entry_repository.dart';
import '../../domain/repositories/asset_repository.dart';
import '../bloc/account_bloc.dart';
import '../bloc/account_event.dart';
import '../bloc/account_state.dart';
import '../bloc/custom_category/custom_category_bloc.dart';
import '../bloc/custom_category/custom_category_event.dart';
import '../bloc/custom_category/custom_category_state.dart';
import '../../../../core/formatters/app_formatter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/formatters/category_formatter.dart';
import '../../../../app/profile/capability_profile.dart';
import '../../../../l10n/app_string_keys.dart';
import '../../../../l10n/app_strings.dart';
import '../../../../services/ai/input_parser_service.dart';
import '../../../../services/ai/receipt_ocr_service.dart';
import '../../../../services/ai_privacy_consent_service.dart';
import '../../../../services/app_profile_service.dart';
import '../../../../services/config_service.dart';
import '../../../../services/quick_chip_service.dart';
import '../../../../services/injection.dart';
import '../../../../services/stock_service.dart';
import '../../../../app/router.dart';
import '../widgets/press_feedback.dart';
import '../widgets/ai_bottom_sheet.dart';
import '../widgets/custom_numpad_sheet.dart';
import '../widgets/animated_number_text.dart';
import '../widgets/premium_capsule_button.dart';
import '../widgets/section_header.dart';
import '../widgets/shimmer_loading.dart';

String _homeMoney(num amount, {int decimalDigits = 2}) {
  final service = getIt<AppProfileService>();
  final symbol = AppFormatter.currencySymbol(
    currencyCode: service.currentBaseCurrency,
    locale: service.currentLocale,
  );
  final number = AppFormatter.formatDecimal(
    amount,
    locale: service.currentLocale,
    decimalDigits: decimalDigits,
  );
  return '$symbol$number';
}

String _homeBaseCurrency() => getIt<AppProfileService>().currentBaseCurrency;

Locale _homeLocale() => getIt<AppProfileService>().currentLocale;

String _homeCountryCode() =>
    getIt<AppProfileService>().currentProfile.localeProfile.countryCode;

String _homeCategoryName(String id, String fallback) {
  final locale = getIt<AppProfileService>().currentLocale;
  return localizedCategoryName(id: id, fallback: fallback, locale: locale);
}

String _homeAiProviderLabel(AppStrings t) {
  final provider =
      getIt<AppProfileService>().currentProfile.capabilityProfile.aiProvider;
  switch (provider) {
    case AiProviderType.gemini:
      return t.text(AppStringKeys.providerAiGemini);
    case AiProviderType.legacyCnAi:
      return t.text(AppStringKeys.providerAiQwen);
  }
}

String _homeOcrProviderLabel(AppStrings t) {
  final provider =
      getIt<AppProfileService>().currentProfile.capabilityProfile.ocrProvider;
  switch (provider) {
    case OcrProviderType.googleVisionGemini:
    case OcrProviderType.googleExpenseParser:
      return t.text(AppStringKeys.providerOcrGoogleVision);
    case OcrProviderType.legacyCnOcr:
      return t.text(AppStringKeys.providerOcrBaidu);
  }
}

bool _homeAiReady() {
  final provider =
      getIt<AppProfileService>().currentProfile.capabilityProfile.aiProvider;
  switch (provider) {
    case AiProviderType.gemini:
      return ConfigService.instance.isGeminiConfigured;
    case AiProviderType.legacyCnAi:
      return true;
  }
}

bool _homeOcrReady() {
  final provider =
      getIt<AppProfileService>().currentProfile.capabilityProfile.ocrProvider;
  switch (provider) {
    case OcrProviderType.googleVisionGemini:
    case OcrProviderType.googleExpenseParser:
      return ConfigService.instance.isGoogleVisionConfigured;
    case OcrProviderType.legacyCnOcr:
      return true;
  }
}

String _homeCurrencyPrefix() {
  final service = getIt<AppProfileService>();
  return '${AppFormatter.currencySymbol(currencyCode: service.currentBaseCurrency, locale: service.currentLocale)} ';
}

bool _homeUsesUsMarketColors() {
  return getIt<AppProfileService>()
          .currentProfile
          .capabilityProfile
          .stockMarketScope ==
      StockMarketScope.us;
}

Color _homeMarketChangeColor(num value) {
  return AppColors.marketChangeColor(
    value: value,
    useUsSemantics: _homeUsesUsMarketColors(),
  );
}

String _homeMonthLabel(int year, int month) {
  final service = getIt<AppProfileService>();
  final locale = service.currentLocale;
  final tag = locale.countryCode == null
      ? locale.languageCode
      : '${locale.languageCode}_${locale.countryCode}';
  return DateFormat.yMMMM(tag).format(DateTime(year, month));
}

String _homeMonthShortLabel(int year, int month) {
  final service = getIt<AppProfileService>();
  final locale = service.currentLocale;
  if (locale.languageCode == 'zh') {
    return DateFormat('M月', 'zh_CN').format(DateTime(year, month));
  }
  final tag = locale.countryCode == null
      ? locale.languageCode
      : '${locale.languageCode}_${locale.countryCode}';
  return DateFormat.MMMM(tag).format(DateTime(year, month));
}

Future<void> showHomeAddEntrySheet(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _AddEntrySheet(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const _assetPrivacyHiddenKey = 'home_asset_privacy_hidden_v1';

  final _textController = TextEditingController();
  final _uuid = const Uuid();
  final _speech = stt.SpeechToText();
  final AssetRepository _assetRepository = getIt<AssetRepository>();
  final StockService _stockService = getIt<StockService>();
  bool _isListening = false;
  bool _speechAvailable = false;
  bool _speechInitialized = false;

  bool _ensureAiReady() {
    if (_homeAiReady()) return true;
    final t = AppStrings.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          t.text(
            AppStringKeys.homeAiSetupRequired,
            params: {'aiProvider': _homeAiProviderLabel(t)},
          ),
        ),
      ),
    );
    return false;
  }

  bool _ensureOcrFlowReady() {
    if (_homeOcrReady() && _homeAiReady()) return true;
    final t = AppStrings.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          t.text(
            AppStringKeys.homeOcrSetupRequired,
            params: {
              'ocrProvider': _homeOcrProviderLabel(t),
              'aiProvider': _homeAiProviderLabel(t),
            },
          ),
        ),
      ),
    );
    return false;
  }

  bool _assetPrivacyHidden = false;
  late final CustomCategoryBloc _bloc;
  late Future<_HomeAssetSummary> _assetSummaryFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bloc = context.read<CustomCategoryBloc>();
    _assetSummaryFuture = _loadAssetSummary();
    context.read<AccountBloc>().add(const LoadCurrentMonthEntries());
    _loadAssetPrivacyHidden();
    homeAiTrigger.addListener(_onAiTriggered);
  }

  void _onAiTriggered() {
    if (mounted) {
      showAiBottomSheet(
        context: context,
        textController: _textController,
        isListening: _isListening,
        onStartListening: _startListening,
        onStopListening: _stopListening,
        onPickCamera: () => _pickImageForOCR(ImageSource.camera),
        onPickGallery: () => _pickImageForOCR(ImageSource.gallery),
        onSubmitText: _submitText,
      );
    }
  }

  @override
  void dispose() {
    homeAiTrigger.removeListener(_onAiTriggered);
    WidgetsBinding.instance.removeObserver(this);
    _textController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // App 从后台切回来，刷新账单和资产数据
      context.read<AccountBloc>().add(const LoadCurrentMonthEntries());
      setState(() {
        _assetSummaryFuture = _loadAssetSummary();
      });
    }
  }

  Future<bool> _ensureSpeechInitialized() async {
    if (_speechInitialized) return _speechAvailable;
    try {
      _speechAvailable = await _speech.initialize();
    } catch (_) {
      _speechAvailable = false;
    }
    _speechInitialized = true;
    return _speechAvailable;
  }

  void _startListening() async {
    // 语音能力改为按需初始化，避免页面首帧阶段触发原生插件导致启动闪退
    final available = await _ensureSpeechInitialized();
    if (!mounted) return;
    if (!available) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(context).text(AppStringKeys.homeVoiceUnavailable),
          ),
        ),
      );
      return;
    }
    setState(() => _isListening = true);
    await _speech.listen(
      localeId: getIt<AppProfileService>().speechLocaleId,
      onResult: (result) {
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          _textController.text = result.recognizedWords;
          if (!_ensureAiReady()) return;
          context.read<AccountBloc>().add(
            ParseTextInput(result.recognizedWords),
          );
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
    );
  }

  void _stopListening() async {
    await _speech.stop();
    setState(() => _isListening = false);
  }

  Future<void> _loadAssetPrivacyHidden() async {
    final prefs = getIt<SharedPreferences>();
    final hidden = prefs.getBool(_assetPrivacyHiddenKey) ?? false;
    if (!mounted) return;
    setState(() => _assetPrivacyHidden = hidden);
  }

  void _setAssetPrivacyHidden(bool hidden) {
    setState(() => _assetPrivacyHidden = hidden);
    unawaited(
      getIt<SharedPreferences>().setBool(_assetPrivacyHiddenKey, hidden),
    );
  }

  Future<_HomeAssetSummary> _loadAssetSummary() async {
    final assetResult = await _assetRepository.getAssets();
    final assets = assetResult.fold((_) => <Asset>[], (items) => items);
    await _stockService.restoreFromCloudIfNeeded();
    final stocks = await _stockService.getPositions();

    final otherAssetsTotal = assets.fold<double>(
      0.0,
      (sum, item) => sum + item.balance,
    );
    final stockMarketValue = stocks.fold<double>(
      0.0,
      (sum, item) => sum + item.marketValue,
    );
    final stockCostBasis = stocks.fold<double>(
      0.0,
      (sum, item) => sum + ((item.costPrice ?? 0) * item.quantity),
    );
    final totalAssets = otherAssetsTotal + stockMarketValue;
    final totalAssetChangeAmount = stocks.fold<double>(
      0.0,
      (sum, item) => sum + (item.profitAmount ?? 0),
    );
    final totalAssetChangePercent = totalAssets > 0
        ? (totalAssetChangeAmount / totalAssets) * 100
        : null;
    final stockProfitPercent = stockMarketValue > 0
        ? (totalAssetChangeAmount / stockMarketValue) * 100
        : (stockCostBasis > 0
              ? (totalAssetChangeAmount / stockCostBasis) * 100
              : null);

    return _HomeAssetSummary(
      totalAssets: totalAssets,
      otherAssetsTotal: otherAssetsTotal,
      stockMarketValue: stockMarketValue,
      stockCount: stocks.length,
      totalAssetChangeAmount: totalAssetChangeAmount,
      totalAssetChangePercent: totalAssetChangePercent,
      stockProfitPercent: stockProfitPercent,
    );
  }

  void _pickImageForOCR(ImageSource source) async {
    if (!_ensureOcrFlowReady()) return;

    // AI 隐私授权检查
    final consent = getIt<AIPrivacyConsentService>();
    if (!consent.hasOcrConsent) {
      final agreed = await _showAIPrivacyDialog(
        AppStrings.of(context).text(AppStringKeys.homeOcrConsentTitle),
        AppStrings.of(context).text(
          AppStringKeys.homeOcrConsentContent,
          params: {
            'ocrProvider': _homeOcrProviderLabel(AppStrings.of(context)),
            'aiProvider': _homeAiProviderLabel(AppStrings.of(context)),
          },
        ),
      );
      if (!mounted) return;
      if (!agreed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).text(AppStringKeys.homeOcrCancelled),
            ),
          ),
        );
        return;
      }
      await consent.setOcrConsent();
      if (!mounted) return;
    }

    final picker = ImagePicker();
    try {
      final image = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 768,
        imageQuality: 60,
      );
      if (image == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).text(AppStringKeys.homeNoImage),
            ),
          ),
        );
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(context).text(AppStringKeys.homeRecognizingReceipt),
          ),
          duration: Duration(seconds: 1),
        ),
      );
      final ocr = getIt<ReceiptOcrService>();
      final bytes = await image.readAsBytes();
      final text = await ocr.recognizeText(bytes);
      if (!mounted) return;
      if (text == null || text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).text(AppStringKeys.homeOcrUnavailable),
            ),
          ),
        );
        return;
      }
      context.read<AccountBloc>().add(ParseTextInput(text));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(
              context,
            ).text(AppStringKeys.homeOcrFailed, params: {'error': '$e'}),
          ),
        ),
      );
    }
  }

  void _submitText(String text) async {
    if (text.isEmpty) return;

    if (!_ensureAiReady()) return;

    // AI 隐私授权检查（文本输入）
    final consent = getIt<AIPrivacyConsentService>();
    if (!consent.hasTextConsent) {
      final agreed = await _showAIPrivacyDialog(
        AppStrings.of(context).text(AppStringKeys.homeTextConsentTitle),
        AppStrings.of(context).text(
          AppStringKeys.homeTextConsentContent,
          params: {'aiProvider': _homeAiProviderLabel(AppStrings.of(context))},
        ),
      );
      if (!mounted) return;
      if (!agreed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).text(AppStringKeys.homeTextCancelled),
            ),
          ),
        );
        return;
      }
      await consent.setTextConsent();
      if (!mounted) return;
    }

    context.read<AccountBloc>().add(ParseTextInput(text));
  }

  Future<void> _confirmAndSave(
    List<ParsedResult> results,
    EntryType type,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final t = AppStrings.of(context);
    try {
      final bloc = context.read<AccountBloc>();
      final now = DateTime.now();
      final entries = results
          .map(
            (r) => AccountEntry(
              id: _uuid.v4(),
              amount: r.amount,
              type: r.type == 'income' ? EntryType.income : type,
              category: r.category,
              description: r.note,
              date: now,
              createdAt: now,
              originalCurrency: _homeBaseCurrency(),
              baseCurrency: _homeBaseCurrency(),
              locale: _homeLocale().toLanguageTag(),
              countryCode: _homeCountryCode(),
              syncStatus: SyncStatus.pending,
            ),
          )
          .toList();

      // IO 在 bloc 外部顺序完成：全部写完后再触发一次 event
      final List<AccountEntry> saved = [];
      for (final entry in entries) {
        final result = await getIt<AccountEntryRepository>().addEntry(entry);
        result.fold(
          (error) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  t.text(
                    AppStringKeys.homeSaveFailed,
                    params: {'error': error.toString()},
                  ),
                ),
                duration: const Duration(seconds: 3),
              ),
            );
          },
          (savedEntry) {
            saved.add(savedEntry);
          },
        );
      }

      if (saved.isNotEmpty) {
        bloc.add(AddMultipleAccountEntries(saved));
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              t.text(
                AppStringKeys.homeAddedEntries,
                params: {'count': saved.length.toString()},
              ),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(t.text(AppStringKeys.homeSaveMissing)),
            duration: Duration(seconds: 3),
          ),
        );
      }
      _textController.clear();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            t.text(
              AppStringKeys.homeSaveFailed,
              params: {'error': e.toString()},
            ),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showAmountDialog(String categoryId, String note, String icon) async {
    final isIncome = CategoryDef.incomeCategories.any(
      (c) => c.id == categoryId,
    );
    final type = isIncome ? 'income' : 'expense';
    final entryType = isIncome ? EntryType.income : EntryType.expense;

    final amount = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CustomNumpadSheet(
        title: '$icon $note',
        isIncome: isIncome,
      ),
    );

    if (!mounted || amount == null || amount <= 0) return;

    await _confirmAndSave([
      ParsedResult(
        amount: amount,
        category: categoryId,
        type: type,
        note: note,
      ),
    ], entryType);
  }

  void _showVipUpgradeDialog(BuildContext ctx) {
    final t = AppStrings.of(ctx);
    showDialog(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: Text(t.text(AppStringKeys.homeVipUpgradeTitle)),
        content: Text(t.text(AppStringKeys.homeVipUpgradeContent)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.text(AppStringKeys.homeVipUpgradeLater)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A47D8),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/settings');
            },
            child: Text(t.text(AppStringKeys.homeVipUpgradeNow)),
          ),
        ],
      ),
    );
  }

  void _showLoginPromptDialog(BuildContext ctx) {
    final t = AppStrings.of(ctx);
    showDialog(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: Text(t.text(AppStringKeys.homeLoginPromptTitle)),
        content: Text(t.text(AppStringKeys.homeLoginPromptContent)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.text(AppStringKeys.homeLoginPromptLater)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A47D8),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/phone_login');
            },
            child: Text(t.text(AppStringKeys.homeLoginPromptNow)),
          ),
        ],
      ),
    );
  }

  void _showAiConfirmDialog(BuildContext ctx, List<ParsedResult> results) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: _AiConfirmSheet(results: results),
      ),
    );
  }

  String _formatTime(DateTime d) {
    final t = AppStrings.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(d.year, d.month, d.day);
    if (date == today) return t.text(AppStringKeys.transactionsToday);
    if (date == today.subtract(const Duration(days: 1))) {
      return t.text(AppStringKeys.transactionsYesterday);
    }
    return '${d.month}/${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6F8),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 360;
              final isTablet = constraints.maxWidth >= 768;
              final horizontalPadding = isTablet
                  ? 24.0
                  : (constraints.maxWidth > 520 ? 16.0 : 0.0);
              final maxContentWidth = isTablet
                  ? (constraints.maxWidth >= 1024 ? 860.0 : 720.0)
                  : (constraints.maxWidth > 560 ? 520.0 : constraints.maxWidth);

              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    child: BlocBuilder<AccountBloc, AccountState>(
                      builder: (context, state) {
                        final t = AppStrings.of(context);
                        // AI 解析完成，显示确认弹窗
                        if (state.isAiPanelVisible &&
                            state.parsedResults.isNotEmpty) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!context.mounted) return;
                            _showAiConfirmDialog(context, state.parsedResults);
                          });
                          context.read<AccountBloc>().add(
                            const ClearParsedResults(),
                          );
                        }

                        // VIP 限额弹窗
                        if (state.showVipLimitDialog) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!context.mounted) return;
                            _showVipUpgradeDialog(context);
                          });
                          context.read<AccountBloc>().add(
                            const ClearVipLimitDialog(),
                          );
                        }

                        // 游客登录提示弹窗
                        if (state.showLoginLimitDialog) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!context.mounted) return;
                            _showLoginPromptDialog(context);
                          });
                          context.read<AccountBloc>().add(
                            const ClearLoginLimitDialog(),
                          );
                        }

                        final monthStr = _homeMonthLabel(
                          state.selectedYear,
                          state.selectedMonth,
                        );

                        return CustomScrollView(
                          slivers: [
                            // ── 1. 头部：图标 + 标题 + 添加按钮 ─────────────────────
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                  compact ? 16 : 20,
                                  16,
                                  compact ? 16 : 20,
                                  0,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            child: Image.asset(
                                              'assets/icon_brand_primary.png',
                                              width: compact ? 32 : 36,
                                              height: compact ? 32 : 36,
                                            ),
                                          ),
                                          SizedBox(width: compact ? 6 : 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  getIt<AppProfileService>()
                                                      .appTitle,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: compact ? 17 : 19,
                                                    fontWeight: FontWeight.w400,
                                                    letterSpacing: -0.2,
                                                    color: const Color(0xFF1A1A2E),
                                                  ),
                                                ),
                                                Text(
                                                  monthStr,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: compact ? 12 : 13,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(width: compact ? 12 : 16),
                                    PressFeedback(
                                      onTap: () => context.go('/settings'),
                                      child: Container(
                                        width: compact ? 40 : 44,
                                        height: compact ? 40 : 44,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          boxShadow: AppColors.softShadow,
                                        ),
                                        child: const Icon(
                                          Icons.settings_outlined,
                                          color: Color(0xFF1A1A2E),
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SliverToBoxAdapter(
                              child: SizedBox(height: 16),
                            ),

                            // ── 3. 本月收支汇总卡片 ────────────────────────────────
                            SliverToBoxAdapter(
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF6B4DFF),
                                      Color(0xFF4A47D8),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.25,
                                      ),
                                      blurRadius: 16,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 18,
                                        ),
                                        decoration: const BoxDecoration(
                                          borderRadius: BorderRadius.only(
                                            topLeft: Radius.circular(16),
                                            bottomLeft: Radius.circular(16),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(
                                                    6,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.2),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  child: Icon(
                                                    (state.lastMonthExpense ==
                                                                null ||
                                                            state.totalExpense >=
                                                                state
                                                                    .lastMonthExpense!)
                                                        ? Icons.arrow_upward
                                                        : Icons.arrow_downward,
                                                    color: Colors.white,
                                                    size: 14,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    t.text(
                                                      AppStringKeys
                                                          .homeMonthExpense,
                                                      params: {
                                                        'month':
                                                            _homeMonthShortLabel(
                                                              state
                                                                  .selectedYear,
                                                              state
                                                                  .selectedMonth,
                                                            ),
                                                      },
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 10),
                                            AnimatedNumberText(
                                              value: state.totalExpense.toDouble(),
                                              formatter: (val) => _homeMoney(val),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 28,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: -1.0,
                                              ),
                                            ),
                                            if (state.lastMonthExpense !=
                                                    null &&
                                                state.lastMonthExpense! > 0)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 4,
                                                ),
                                                child: Text(
                                                  t.text(
                                                    AppStringKeys
                                                        .homeVsLastMonth,
                                                    params: {
                                                      'direction':
                                                          state.totalExpense >=
                                                              state
                                                                  .lastMonthExpense!
                                                          ? '↑'
                                                          : '↓',
                                                      'percent':
                                                          (((state.totalExpense -
                                                                              state.lastMonthExpense!) /
                                                                          state
                                                                              .lastMonthExpense!)
                                                                      .abs() *
                                                                  100)
                                                              .toStringAsFixed(
                                                                0,
                                                              ),
                                                    },
                                                  ),
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.6),
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Container(
                                      width: 1,
                                      height: 60,
                                      color: Colors.white30,
                                    ),
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 18,
                                        ),
                                        decoration: const BoxDecoration(
                                          borderRadius: BorderRadius.only(
                                            topRight: Radius.circular(16),
                                            bottomRight: Radius.circular(16),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(
                                                    6,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.2),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  child: Icon(
                                                    (state.lastMonthIncome ==
                                                                null ||
                                                            state.totalIncome >=
                                                                state
                                                                    .lastMonthIncome!)
                                                        ? Icons.arrow_upward
                                                        : Icons.arrow_downward,
                                                    color: Colors.white,
                                                    size: 14,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    t.text(
                                                      AppStringKeys
                                                          .homeMonthIncome,
                                                      params: {
                                                        'month':
                                                            _homeMonthShortLabel(
                                                              state
                                                                  .selectedYear,
                                                              state
                                                                  .selectedMonth,
                                                            ),
                                                      },
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 10),
                                            AnimatedNumberText(
                                              value: state.totalIncome.toDouble(),
                                              formatter: (val) => _homeMoney(val),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 28,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: -1.0,
                                              ),
                                            ),
                                            if (state.lastMonthIncome != null &&
                                                state.lastMonthIncome! > 0)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 4,
                                                ),
                                                child: Text(
                                                  t.text(
                                                    AppStringKeys
                                                        .homeVsLastMonth,
                                                    params: {
                                                      'direction':
                                                          state.totalIncome >=
                                                              state
                                                                  .lastMonthIncome!
                                                          ? '↑'
                                                          : '↓',
                                                      'percent':
                                                          (((state.totalIncome -
                                                                              state.lastMonthIncome!) /
                                                                          state
                                                                              .lastMonthIncome!)
                                                                      .abs() *
                                                                  100)
                                                              .toStringAsFixed(
                                                                0,
                                                              ),
                                                    },
                                                  ),
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.6),
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // ── 4. 资产管理入口 ───────────────────────────────────────
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  16,
                                  20,
                                  0,
                                ),
                                child: FutureBuilder<_HomeAssetSummary>(
                                  future: _assetSummaryFuture,
                                  builder: (context, snapshot) {
                                    final summary = snapshot.data;
                                    return PressFeedback(
                                      onTap: () async {
                                        await context.push('/asset');
                                        if (!mounted) return;
                                        setState(() {
                                          _assetSummaryFuture =
                                              _loadAssetSummary();
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF4F1FF),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.04,
                                              ),
                                              blurRadius: 16,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Container(
                                              width: 44,
                                              height: 44,
                                              decoration: BoxDecoration(
                                                color: AppColors.primary
                                                    .withValues(alpha: 0.12),
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                border: Border.all(
                                                  color: AppColors.primary
                                                      .withValues(alpha: 0.05),
                                                  width: 1,
                                                ),
                                              ),
                                              child: const Icon(
                                                Icons
                                                    .account_balance_wallet_rounded,
                                                color: AppColors.primary,
                                                size: 22,
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          t.text(
                                                            AppStringKeys
                                                                .homeAssetsTitle,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 14,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w400,
                                                                color: Color(
                                                                  0xFF1A1A2E,
                                                                ),
                                                              ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Container(
                                                        constraints:
                                                            const BoxConstraints(
                                                              maxWidth: 112,
                                                            ),
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 7,
                                                              vertical: 3,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: AppColors
                                                              .primary
                                                              .withValues(
                                                                alpha: 0.08,
                                                              ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                7,
                                                              ),
                                                        ),
                                                        child: FittedBox(
                                                          fit: BoxFit.scaleDown,
                                                          child: Text(
                                                            t.text(
                                                              AppStringKeys
                                                                  .homeAssetsBadge,
                                                            ),
                                                            maxLines: 1,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 11,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                  color: AppColors
                                                                      .primary,
                                                                ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      PressFeedback(
                                                        onTap: () =>
                                                            _setAssetPrivacyHidden(
                                                              !_assetPrivacyHidden,
                                                            ),
                                                        child: Container(
                                                          width: 32,
                                                          height: 32,
                                                          alignment:
                                                              Alignment.center,
                                                          decoration: BoxDecoration(
                                                            color: const Color(
                                                              0xFFF6F6F9,
                                                            ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  9,
                                                                ),
                                                          ),
                                                          child: Icon(
                                                            _assetPrivacyHidden
                                                                ? Icons
                                                                      .visibility_off_outlined
                                                                : Icons
                                                                      .visibility_outlined,
                                                            color: const Color(
                                                              0xFF8E8E8E,
                                                            ),
                                                            size: 19,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 10),
                                                  LayoutBuilder(
                                                    builder: (context, constraints) {
                                                      final amountRow =
                                                          _assetPrivacyHidden
                                                          ? Text(
                                                              '${AppFormatter.currencySymbol(currencyCode: getIt<AppProfileService>().currentBaseCurrency, locale: getIt<AppProfileService>().currentLocale)} ••••••••',
                                                              style: const TextStyle(
                                                                fontSize: 18,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: Color(
                                                                  0xFF1A1A2E,
                                                                ),
                                                              ),
                                                            )
                                                          : Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .baseline,
                                                              textBaseline:
                                                                  TextBaseline
                                                                      .alphabetic,
                                                              children: [
                                                                Text(
                                                                  summary ==
                                                                          null
                                                                      ? '--'
                                                                      : _homeMoney(
                                                                          summary
                                                                              .totalAssets,
                                                                        ),
                                                                  style: const TextStyle(
                                                                    fontSize:
                                                                        18,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    color: Color(
                                                                      0xFF1A1A2E,
                                                                    ),
                                                                  ),
                                                                ),
                                                                if (summary !=
                                                                        null &&
                                                                    summary.totalAssetChangeAmount !=
                                                                        0) ...[
                                                                  const SizedBox(
                                                                    width: 8,
                                                                  ),
                                                                  Icon(
                                                                    summary.totalAssetChangeAmount >=
                                                                            0
                                                                        ? Icons
                                                                              .arrow_upward
                                                                        : Icons
                                                                              .arrow_downward,
                                                                    color: _homeMarketChangeColor(
                                                                      summary
                                                                          .totalAssetChangeAmount,
                                                                    ),
                                                                    size: 14,
                                                                  ),
                                                                  const SizedBox(
                                                                    width: 2,
                                                                  ),
                                                                  Text(
                                                                    '${summary.totalAssetChangeAmount >= 0 ? '+' : ''}${summary.totalAssetChangeAmount.toStringAsFixed(0)}',
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          13,
                                                                      color: _homeMarketChangeColor(
                                                                        summary
                                                                            .totalAssetChangeAmount,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  if (summary
                                                                          .totalAssetChangePercent !=
                                                                      null)
                                                                    Text(
                                                                      ' (${summary.totalAssetChangePercent! >= 0 ? '+' : ''}${summary.totalAssetChangePercent!.toStringAsFixed(2)}%)',
                                                                      style: TextStyle(
                                                                        fontSize:
                                                                            13,
                                                                        color: _homeMarketChangeColor(
                                                                          summary
                                                                              .totalAssetChangePercent!,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                ],
                                                              ],
                                                            );

                                                      return SizedBox(
                                                        width: constraints
                                                            .maxWidth,
                                                        child: FittedBox(
                                                          fit: BoxFit.scaleDown,
                                                          alignment: Alignment
                                                              .centerLeft,
                                                          child: amountRow,
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                  const SizedBox(height: 8),
                                                  _assetPrivacyHidden
                                                      ? Text(
                                                          t.text(
                                                            AppStringKeys
                                                                .homeStocksSummaryHidden,
                                                            params: {
                                                              'count':
                                                                  '${summary?.stockCount ?? '--'}',
                                                            },
                                                          ),
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 12,
                                                                color: Color(
                                                                  0xFF8E8E8E,
                                                                ),
                                                              ),
                                                        )
                                                      : Text(
                                                          (() {
                                                            final count =
                                                                summary
                                                                    ?.stockCount ??
                                                                '--';
                                                            final percent = summary
                                                                ?.stockProfitPercent;
                                                            final percentText =
                                                                percent == null
                                                                ? '--'
                                                                : '${percent >= 0 ? '+' : ''}${percent.toStringAsFixed(2)}%';
                                                            return t.text(
                                                              AppStringKeys
                                                                  .homeStocksSummaryVisible,
                                                              params: {
                                                                'count':
                                                                    '$count',
                                                                'percent':
                                                                    percentText,
                                                              },
                                                            );
                                                          })(),
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 12,
                                                                color: Color(
                                                                  0xFF8E8E8E,
                                                                ),
                                                              ),
                                                        ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),

                            // ── 5. AI记账区域 ────────────────────────────────────────

                            // ── 6. 快捷记账区域 ──────────────────────────────────────
                            SliverToBoxAdapter(
                              child:
                                  BlocBuilder<
                                    CustomCategoryBloc,
                                    CustomCategoryState
                                  >(
                                    builder: (context, catState) =>
                                        _QuickChipsGrid(
                                          bloc: _bloc,
                                          catState: catState,
                                          onTap: (id, name, icon) =>
                                              _showAmountDialog(id, name, icon),
                                        ),
                                  ),
                            ),

                            // ── 7. 最近账单标题 ────────────────────────────────────
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  16,
                                  20,
                                  8,
                                ),
                                child: SectionHeader(
                                  title: AppStrings.of(context).text(
                                    AppStringKeys.homeRecentEntriesTitle,
                                  ),
                                  trailing: PremiumCapsuleButton(
                                    text: AppStrings.of(context).text(
                                      AppStringKeys.homeRecentEntriesSeeAll,
                                    ),
                                    icon: Icons.arrow_forward_ios_rounded,
                                    onTap: () => context.go('/transactions'),
                                  ),
                                ),
                              ),
                            ),

                            // ── 8. 最近账单列表 ─────────────────────────────────────
                            if (state.isParsing)
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 20),
                                  child: ShimmerLoading(
                                    child: Column(
                                      children: const [
                                        EntrySkeleton(),
                                        EntrySkeleton(),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            state.entries.isEmpty
                                ? SliverToBoxAdapter(
                                    child: Center(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 40,
                                        ),
                                        child: Column(
                                          children: [
                                            Container(
                                              width: 72,
                                              height: 72,
                                              decoration: BoxDecoration(
                                                color: const Color(
                                                  0xFF4A47D8,
                                                ).withValues(alpha: 0.1),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.receipt_long,
                                                size: 36,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              AppStrings.of(context).text(
                                                AppStringKeys
                                                    .homeRecentEntriesEmptyTitle,
                                              ),
                                              style: TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.black87,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              AppStrings.of(context).text(
                                                AppStringKeys
                                                    .homeRecentEntriesEmptySubtitle,
                                              ),
                                              style: TextStyle(
                                                color: Colors.grey,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  )
                                : SliverToBoxAdapter(
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFAF9FF),
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.04,
                                            ),
                                            blurRadius: 16,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: ListView.builder(
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        padding: EdgeInsets.zero,
                                        itemCount: state.entries
                                            .take(20)
                                            .length,
                                        itemBuilder: (context, index) {
                                          final entry = state.entries[index];
                                          final catDef =
                                              CategoryDef.findById(
                                                entry.category,
                                              ) ??
                                              CategoryDef(
                                                id: 'other',
                                                name: AppStrings.of(context).text(
                                                  AppStringKeys
                                                      .transactionsOtherCategory,
                                                ),
                                                icon: '📦',
                                              );
                                          final categoryName =
                                              _homeCategoryName(
                                                catDef.id,
                                                catDef.name,
                                              );
                                          final catColor =
                                              AppColors.getCategoryColor(
                                                catDef.id,
                                              );
                                          return ListTile(
                                            leading: Container(
                                              width: 44,
                                              height: 44,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                color: catColor.withValues(
                                                  alpha: 0.15,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                              child: Text(
                                                catDef.icon,
                                                style: const TextStyle(
                                                  fontSize: 22,
                                                ),
                                              ),
                                            ),
                                            title: Text(
                                              entry.description.isEmpty
                                                  ? categoryName
                                                  : entry.description,
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            subtitle: Text(
                                              _formatTime(entry.date),
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                            trailing: Text(
                                              '${entry.type == EntryType.income ? '+' : '-'}${_homeMoney(entry.amount)}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color:
                                                    entry.type ==
                                                        EntryType.income
                                                    ? AppColors.primary
                                                    : Colors.black87,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),

                            const SliverToBoxAdapter(
                              child: SizedBox(height: 24),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 显示 AI 隐私授权弹窗，返回用户是否同意
  Future<bool> _showAIPrivacyDialog(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  AppStrings.of(ctx).text(AppStringKeys.commonCancel),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  AppStrings.of(ctx).text(AppStringKeys.homePrivacyAgree),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class _HomeAssetSummary {
  const _HomeAssetSummary({
    required this.totalAssets,
    required this.otherAssetsTotal,
    required this.stockMarketValue,
    required this.stockCount,
    required this.totalAssetChangeAmount,
    required this.totalAssetChangePercent,
    required this.stockProfitPercent,
  });

  final double totalAssets;
  final double otherAssetsTotal;
  final double stockMarketValue;
  final int stockCount;
  final double totalAssetChangeAmount;
  final double? totalAssetChangePercent;
  final double? stockProfitPercent;
}

// ── 记一笔：选择金额和类目 ─────────────────────────────────────
class _AddEntrySheet extends StatefulWidget {
  const _AddEntrySheet();

  @override
  State<_AddEntrySheet> createState() => _AddEntrySheetState();
}

class _AddEntrySheetState extends State<_AddEntrySheet> {
  static const _primaryColor = AppColors.primary;
  static const _defaultCategoryIds = [
    'food',
    'transport',
    'shopping',
    'entertainment',
    'housing',
    'coffee',
    'fruit',
    'grocery',
    'takeout',
    'daily',
  ];

  final TextEditingController _amountController = TextEditingController();
  String? _selectedCategoryId;
  String? _selectedName;
  List<String> _enabledIds = [];

  List<CategoryDef> get _allCategories => [
    ...CategoryDef.expenseCategories,
    ...CategoryDef.incomeCategories,
  ];

  Map<String, CategoryDef> get _categoryMap => {
    for (final category in _allCategories) category.id: category,
  };

  List<CategoryDef> get _visibleCategories {
    final ids = _enabledIds.isEmpty ? _defaultCategoryIds : _enabledIds;
    return ids.map((id) => _categoryMap[id]).whereType<CategoryDef>().toList();
  }

  EntryType _resolveType(String categoryId) {
    final isIncome = CategoryDef.incomeCategories.any(
      (c) => c.id == categoryId,
    );
    return isIncome ? EntryType.income : EntryType.expense;
  }

  @override
  void initState() {
    super.initState();
    _enabledIds = List.from(getIt<QuickChipService>().getIds());
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _showCategoryEditSheet(BuildContext ctx) async {
    final allExpense = CategoryDef.expenseCategories.toList();
    final allIncome = CategoryDef.incomeCategories.toList();
    final selected = Set<String>.from(_enabledIds);

    await showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  AppStrings.of(
                    sheetCtx,
                  ).text(AppStringKeys.homeEditCategoriesTitle),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  AppStrings.of(
                    sheetCtx,
                  ).text(AppStringKeys.homeEditCategoriesSubtitle),
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CategorySection(
                          title: AppStrings.of(
                            sheetCtx,
                          ).text(AppStringKeys.reportsExpense),
                          categories: allExpense,
                          selected: selected,
                          onToggle: (id) => setSheetState(() {
                            if (selected.contains(id)) {
                              selected.remove(id);
                            } else {
                              selected.add(id);
                            }
                          }),
                        ),
                        const SizedBox(height: 16),
                        _CategorySection(
                          title: AppStrings.of(
                            sheetCtx,
                          ).text(AppStringKeys.reportsIncome),
                          categories: allIncome,
                          selected: selected,
                          onToggle: (id) => setSheetState(() {
                            if (selected.contains(id)) {
                              selected.remove(id);
                            } else {
                              selected.add(id);
                            }
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    final orderedIds = _allCategories
                        .where((c) => selected.contains(c.id))
                        .map((c) => c.id)
                        .toList();
                    await getIt<QuickChipService>().saveIds(orderedIds);
                    setState(() {
                      _enabledIds = orderedIds;
                      if (_selectedCategoryId != null &&
                          !orderedIds.contains(_selectedCategoryId)) {
                        _selectedCategoryId = null;
                        _selectedName = null;
                      }
                    });
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    AppStrings.of(sheetCtx).text(AppStringKeys.commonSave),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final visibleCategories = _visibleCategories;
    final effectiveSelectedId =
        _selectedCategoryId ??
        (visibleCategories.isNotEmpty ? visibleCategories.first.id : 'food');
    final bottomFloatingGap = mediaQuery.padding.bottom + 88;

    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 16,
        bottom: mediaQuery.viewInsets.bottom + bottomFloatingGap,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 18, 0, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE4E5EF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0xFF5B42F3), Color(0xFFB61FFF)],
                    ),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.of(context).text(AppStringKeys.homeQuickAddTitle),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        AppStrings.of(context).text(AppStringKeys.homeQuickAddSubtitle),
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.86),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F8FA),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: TextField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          autofocus: false,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            labelText: AppStrings.of(
                              context,
                            ).text(AppStringKeys.homeAmountLabel),
                            hintText: AppStrings.of(
                              context,
                            ).text(AppStringKeys.homeAmountHint),
                            prefixText: _homeCurrencyPrefix(),
                            filled: true,
                            fillColor: Colors.transparent,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 18,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(color: _primaryColor),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text(
                            AppStrings.of(
                              context,
                            ).text(AppStringKeys.transactionsSelectCategory),
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                          const Spacer(),
                          PressFeedback(
                            onTap: () => _showCategoryEditSheet(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _primaryColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                AppStrings.of(context).text(AppStringKeys.assetsEdit),
                                style: TextStyle(fontSize: 13, color: _primaryColor),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: visibleCategories.map((c) {
                          final isSelected = _selectedCategoryId == c.id;
                          return PressFeedback(
                            onTap: () {
                              setState(() {
                                _selectedCategoryId = c.id;
                                _selectedName = _homeCategoryName(c.id, c.name);
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected ? _primaryColor : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected ? _primaryColor : Colors.transparent,
                                ),
                              ),
                              child: Text(
                                '${c.icon} ${_homeCategoryName(c.id, c.name)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isSelected ? Colors.white : Colors.black87,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        onPressed: () {
                          final amount = double.tryParse(_amountController.text);
                          if (amount == null || amount <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  AppStrings.of(
                                    context,
                                  ).text(AppStringKeys.homeInvalidAmount),
                                ),
                                duration: Duration(seconds: 1),
                              ),
                            );
                            return;
                          }
                          final category =
                              _categoryMap[effectiveSelectedId] ??
                              CategoryDef.expenseCategories.first;
                          final entryType = _resolveType(category.id);
                          context.read<AccountBloc>().add(
                            AddAccountEntry(
                              AccountEntry(
                                id: const Uuid().v4(),
                                amount: amount,
                                type: entryType,
                                category: category.id,
                                description:
                                    _selectedName ??
                                    _homeCategoryName(category.id, category.name),
                                date: DateTime.now(),
                                createdAt: DateTime.now(),
                                originalCurrency: _homeBaseCurrency(),
                                baseCurrency: _homeBaseCurrency(),
                                locale: _homeLocale().toLanguageTag(),
                                countryCode: _homeCountryCode(),
                                syncStatus: SyncStatus.pending,
                              ),
                            ),
                          );
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppStrings.of(context).text(
                                  AppStringKeys.homeSavedAmount,
                                  params: {'amount': _homeMoney(amount)},
                                ),
                              ),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                        child: Text(
                          AppStrings.of(context).text(AppStringKeys.commonConfirm),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  final String title;
  final List<CategoryDef> categories;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const _CategorySection({
    required this.title,
    required this.categories,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: categories.map((c) {
            final isSelected = selected.contains(c.id);
            return PressFeedback(
              onTap: () => onToggle(c.id),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${c.icon} ${_homeCategoryName(c.id, c.name)}',
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── 动态快捷类目网格 ───────────────────────────────────────────
class _QuickChipsGrid extends StatefulWidget {
  final CustomCategoryBloc bloc;
  final CustomCategoryState catState;
  final Function(String id, String name, String icon) onTap;

  const _QuickChipsGrid({
    required this.bloc,
    required this.catState,
    required this.onTap,
  });

  @override
  State<_QuickChipsGrid> createState() => _QuickChipsGridState();
}

class _QuickChipsGridState extends State<_QuickChipsGrid> {
  // 首页默认启用的 6 个常用类目（与编辑器保持一致）
  static const _defaultEnabledIds = {
    'food',
    'transport',
    'shopping',
    'entertainment',
    'housing',
    'coffee',
  };

  @override
  Widget build(BuildContext context) {
    // 构建所有可用类目（全部系统内置 + 自定义）
    final allExpense = CategoryDef.expenseCategories
        .map(
          (c) =>
              (id: c.id, name: _homeCategoryName(c.id, c.name), icon: c.icon),
        )
        .toList();
    final allIncome = CategoryDef.incomeCategories
        .map(
          (c) =>
              (id: c.id, name: _homeCategoryName(c.id, c.name), icon: c.icon),
        )
        .toList();
    final custom = widget.catState.status == CustomCategoryStatus.loaded
        ? widget.catState.categories
              .map((c) => (id: c.id, name: c.name, icon: c.icon))
              .toList()
        : <({String id, String name, String icon})>[];
    final allMap = <String, ({String id, String name, String icon})>{};
    for (final c in allExpense) {
      allMap[c.id] = c;
    }
    for (final c in allIncome) {
      allMap[c.id] = c;
    }
    for (final c in custom) {
      allMap[c.id] = c;
    }

    // quickChipIds 有效则使用，否则用默认 6 个
    final List<({String id, String name, String icon})> chips;
    if (widget.catState.quickChipIds.isNotEmpty) {
      chips = widget.catState.quickChipIds
          .map((id) => allMap[id])
          .whereType<({String id, String name, String icon})>()
          .toList();
    } else {
      chips = allExpense
          .where((c) => _defaultEnabledIds.contains(c.id))
          .toList();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: AppStrings.of(
              context,
            ).text(AppStringKeys.homeQuickAccountingTitle),
            trailing: PremiumCapsuleButton(
              text: AppStrings.of(context).text(AppStringKeys.homeManage),
              icon: Icons.tune_rounded,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BlocProvider<CustomCategoryBloc>.value(
                      value: widget.bloc,
                      child: _QuickChipEditorPage(bloc: widget.bloc),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.35,
            ),
            itemCount: chips.length,
            itemBuilder: (context, index) {
              final c = chips[index];
              return _QuickChipItem(
                icon: c.icon,
                name: c.name,
                onTap: () => widget.onTap(c.id, c.name, c.icon),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── 快捷记账单项组件（带交互反馈） ─────────────────────────────
class _QuickChipItem extends StatefulWidget {
  final String icon;
  final String name;
  final VoidCallback onTap;

  const _QuickChipItem({
    required this.icon,
    required this.name,
    required this.onTap,
  });

  @override
  State<_QuickChipItem> createState() => _QuickChipItemState();
}

class _QuickChipItemState extends State<_QuickChipItem> {
  @override
  Widget build(BuildContext context) {
    return PressFeedback(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Text(widget.icon, style: const TextStyle(fontSize: 24, height: 1)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.name,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF333333),
                  height: 1.1,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 快捷类目管理 ───────────────────────────────────────────────
class _QuickChipEditorPage extends StatefulWidget {
  final CustomCategoryBloc bloc;
  const _QuickChipEditorPage({required this.bloc});

  @override
  State<_QuickChipEditorPage> createState() => _QuickChipEditorPageState();
}

class _QuickChipEditorPageState extends State<_QuickChipEditorPage> {
  static const _sectionExpense = 'expense';
  static const _sectionIncome = 'income';
  static const _sectionCustomExpense = 'customExpense';
  static const _sectionCustomIncome = 'customIncome';

  late Set<String> _enabledIds;
  CustomCategoryBloc get _bloc => widget.bloc;
  late final StreamSubscription<CustomCategoryState> _sub;

  // 默认启用的 6 个常用类目
  static const _defaultEnabledIds = {
    'food', // 餐饮
    'transport', // 交通
    'shopping', // 购物
    'entertainment', // 娱乐
    'housing', // 居住
    'coffee', // 咖啡
  };

  @override
  void initState() {
    super.initState();
    final state = _bloc.state;
    if (state.quickChipIds.isNotEmpty) {
      _enabledIds = Set.from(state.quickChipIds);
    } else {
      _enabledIds = Set.from(_defaultEnabledIds);
    }
    // 监听 custom categories 变化，实时同步列表（新增自定义类目后自动出现）
    _sub = _bloc.stream.listen((s) {
      if (s.quickChipIds.isNotEmpty) {
        setState(() {
          _enabledIds = Set.from(s.quickChipIds);
        });
      }
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  void _toggle(String id) {
    setState(() {
      if (_enabledIds.contains(id)) {
        _enabledIds.remove(id);
      } else {
        _enabledIds.add(id);
      }
    });
  }

  List<({String id, String name, String icon, String section})>
  _buildAllCategories(CustomCategoryState state) {
    final result = <({String id, String name, String icon, String section})>[];

    for (final c in CategoryDef.expenseCategories) {
      result.add((
        id: c.id,
        name: c.name,
        icon: c.icon,
        section: _sectionExpense,
      ));
    }
    for (final c in CategoryDef.incomeCategories) {
      result.add((
        id: c.id,
        name: c.name,
        icon: c.icon,
        section: _sectionIncome,
      ));
    }
    for (final c in state.categories) {
      result.add((
        id: c.id,
        name: c.name,
        icon: c.icon,
        section: c.type == CustomCategoryType.expense
            ? _sectionCustomExpense
            : _sectionCustomIncome,
      ));
    }
    return result;
  }

  String _sectionLabel(String section, AppStrings t) {
    switch (section) {
      case _sectionExpense:
        return t.text(AppStringKeys.reportsExpense);
      case _sectionIncome:
        return t.text(AppStringKeys.reportsIncome);
      case _sectionCustomExpense:
        return t.text(AppStringKeys.homeCustomExpenseSection);
      case _sectionCustomIncome:
        return t.text(AppStringKeys.homeCustomIncomeSection);
      default:
        return section;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    return StreamBuilder<CustomCategoryState>(
      stream: _bloc.stream,
      initialData: _bloc.state,
      builder: (context, snapshot) {
        final state = snapshot.data!;
        final allCategories = _buildAllCategories(state);

        // 按 section 分组
        final sections =
            <
              String,
              List<({String id, String name, String icon, String section})>
            >{};
        for (final c in allCategories) {
          sections.putIfAbsent(c.section, () => []).add(c);
        }

        final sectionNames = [
          _sectionExpense,
          _sectionIncome,
          _sectionCustomExpense,
          _sectionCustomIncome,
        ].where((s) => sections.containsKey(s)).toList();

        int totalItems = sectionNames.fold(
          0,
          (sum, s) => sum + 1 + sections[s]!.length,
        ); // header + items

        return Scaffold(
          appBar: AppBar(
            title: Text(
              AppStrings.of(
                context,
              ).text(AppStringKeys.homeManageQuickCategoriesTitle),
            ),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isTablet = constraints.maxWidth >= 768;
              final horizontalPadding = isTablet
                  ? 24.0
                  : (constraints.maxWidth > 520 ? 16.0 : 0.0);
              final maxContentWidth = isTablet
                  ? 560.0
                  : (constraints.maxWidth > 560 ? 520.0 : constraints.maxWidth);

              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    child: ListView.builder(
                      itemCount: totalItems,
                      itemBuilder: (ctx, index) {
                        int pos = 0;
                        for (final sec in sectionNames) {
                          if (index == pos) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                              child: Text(
                                _sectionLabel(sec, t),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }
                          pos++;
                          final items = sections[sec]!;
                          if (index < pos + items.length) {
                            final c = items[index - pos];
                            final enabled = _enabledIds.contains(c.id);
                            return ListTile(
                              dense: true,
                              leading: Text(
                                c.icon,
                                style: const TextStyle(fontSize: 18),
                              ),
                              title: Text(
                                _homeCategoryName(c.id, c.name),
                                style: const TextStyle(fontSize: 14),
                              ),
                              trailing: Switch(
                                value: enabled,
                                activeThumbColor: AppColors.primary,
                                onChanged: (_) => _toggle(c.id),
                              ),
                            );
                          }
                          pos += items.length;
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
              );
            },
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  _bloc.add(SaveQuickChipIds(_enabledIds.toList()));
                  Navigator.pop(context);
                },
                child: Text(
                  AppStrings.of(context).text(AppStringKeys.homeDone),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AiConfirmSheet extends StatefulWidget {
  final List<ParsedResult> results;
  const _AiConfirmSheet({required this.results});

  @override
  State<_AiConfirmSheet> createState() => _AiConfirmSheetState();
}

class _AiConfirmSheetState extends State<_AiConfirmSheet> {
  late List<ParsedResult> _results;

  @override
  void initState() {
    super.initState();
    _results = List.from(widget.results);
  }

  void _delete(int index) {
    setState(() => _results.removeAt(index));
  }

  void _confirm() async {
    if (_results.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final bloc = context.read<AccountBloc>();
    final now = DateTime.now();
    final messenger = ScaffoldMessenger.of(context);

    // 等待所有账单添加完成
    final futures = <Future>[];
    for (final r in _results) {
      final entry = AccountEntry(
        id: const Uuid().v4(),
        amount: r.amount,
        type: r.type == 'income' ? EntryType.income : EntryType.expense,
        category: r.category,
        description: r.note,
        date: now,
        createdAt: now,
        originalCurrency: _homeBaseCurrency(),
        baseCurrency: _homeBaseCurrency(),
        locale: _homeLocale().toLanguageTag(),
        countryCode: _homeCountryCode(),
        syncStatus: SyncStatus.pending,
      );
      futures.add(_addEntryAndWait(bloc, entry));
    }

    await Future.wait(futures);
    if (!mounted) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          AppStrings.of(context).text(
            AppStringKeys.homeAddedEntries,
            params: {'count': '${_results.length}'},
          ),
        ),
        duration: const Duration(seconds: 1),
      ),
    );
    Navigator.pop(context);
  }

  Future<void> _addEntryAndWait(AccountBloc bloc, AccountEntry entry) async {
    final completer = Completer<void>();
    final subscription = bloc.stream.listen((state) {
      // 检查这条记录是否已经被添加（通过检查 state.entries）
      final exists = state.entries.any((e) => e.id == entry.id);
      if (exists || state.status == AccountStatus.loaded) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });
    bloc.add(AddAccountEntry(entry));
    // 超时保护
    await completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );
    subscription.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppStrings.of(context).text(AppStringKeys.homeAiResultsTitle),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_results.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    AppStrings.of(
                      context,
                    ).text(AppStringKeys.homeAiResultsEmpty),
                  ),
                ),
              )
            else
              ...List.generate(_results.length, (i) {
                final r = _results[i];
                final cat = CategoryDef.expenseCategories.firstWhere(
                  (c) => c.id == r.category,
                  orElse: () => CategoryDef(
                    id: 'other',
                    name: AppStrings.of(
                      context,
                    ).text(AppStringKeys.transactionsOtherCategory),
                    icon: '📦',
                  ),
                );
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Text(cat.icon, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _homeCategoryName(cat.id, cat.name),
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (r.note.isNotEmpty)
                              Text(
                                r.note,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        '${r.type == 'income' ? '+' : '-'}${r.amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: r.type == 'income'
                              ? AppColors.primary
                              : Colors.red,
                        ),
                      ),
                      const SizedBox(width: 8),
                      PressFeedback(
                        onTap: () => _delete(i),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            Icons.delete_outline,
                            size: 24,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A47D8),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 2,
                ),
                onPressed: _results.isEmpty ? null : _confirm,
                child: Text(
                  AppStrings.of(context).text(
                    AppStringKeys.homeConfirmSave,
                    params: {'count': '${_results.length}'},
                  ),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
