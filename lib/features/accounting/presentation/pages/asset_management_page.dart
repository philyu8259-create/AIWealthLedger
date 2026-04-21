import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/formatters/app_formatter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_string_keys.dart';
import '../../../../l10n/app_strings.dart';
import '../../../../services/app_profile_service.dart';
import '../../../../services/injection.dart';
import '../../../../services/stock_service.dart';
import '../../../../services/vip_service.dart';
import '../../../../app/profile/capability_profile.dart';
import '../../domain/entities/entities.dart';
import '../../domain/entities/stock_position.dart';
import '../../domain/repositories/asset_repository.dart';
import '../widgets/press_feedback.dart';

Locale _localeFromTag(String raw) {
  final parts = raw.split(RegExp('[-_]'));
  if (parts.length >= 2) return Locale(parts[0], parts[1].toUpperCase());
  return Locale(parts.first);
}

String _formatMoney(
  num amount, {
  required String currencyCode,
  required Locale locale,
}) {
  return AppFormatter.formatCurrency(
    amount,
    currencyCode: currencyCode,
    locale: locale,
  );
}

String _profileMoney(num amount) {
  final service = getIt<AppProfileService>();
  return _formatMoney(
    amount,
    currencyCode: service.currentBaseCurrency,
    locale: service.currentLocale,
  );
}

String _profileCurrencyPrefix() {
  final service = getIt<AppProfileService>();
  return '${AppFormatter.currencySymbol(currencyCode: service.currentBaseCurrency, locale: service.currentLocale)} ';
}

bool _isUsStockScope() {
  return getIt<AppProfileService>()
          .currentProfile
          .capabilityProfile
          .stockMarketScope ==
      StockMarketScope.us;
}

bool _isUsStockProviderReady() {
  return getIt<StockService>().isProviderReady;
}

Color _marketChangeColor(num? value) {
  return AppColors.marketChangeColor(
    value: value,
    useUsSemantics: _isUsStockScope(),
  );
}

Color _marketChangeBgColor(num? value) {
  return AppColors.marketChangeSoftColor(
    value: value,
    useUsSemantics: _isUsStockScope(),
  );
}

bool _usesOnDemandStockSearch() {
  return getIt<StockService>().usesOnDemandSearch;
}

String _profileCountryCode() =>
    getIt<AppProfileService>().currentProfile.localeProfile.countryCode;

List<AssetType> _availableManualAssetTypes() {
  final profile = getIt<AppProfileService>().currentProfile.capabilityProfile;
  final allowChinaWalletAssets = profile.isEnabled('chinaWalletAssets');

  return AssetType.values.where((type) {
    if (type == AssetType.stock) return false;
    if (!allowChinaWalletAssets &&
        (type == AssetType.alipay || type == AssetType.wechat)) {
      return false;
    }
    return true;
  }).toList();
}

String _localizedAssetTypeName(AssetType type, Locale locale) {
  if (locale.languageCode == 'zh') {
    return Asset.typeName(type);
  }

  switch (type) {
    case AssetType.cash:
      return 'Cash';
    case AssetType.bank:
      return 'Bank account';
    case AssetType.alipay:
      return 'Alipay';
    case AssetType.wechat:
      return 'WeChat';
    case AssetType.fund:
      return 'Fund';
    case AssetType.stock:
      return 'Stock';
    case AssetType.other:
      return 'Other';
  }
}

String _stockCacheText(AppStrings t, int? updatedAtMs) {
  if (_usesOnDemandStockSearch()) {
    return t.text(AppStringKeys.assetsConfigSearchCacheOnDemand);
  }

  if (updatedAtMs == null) {
    return t.text(AppStringKeys.assetsConfigCacheMissing);
  }

  return AppFormatter.formatShortDate(
    DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
    locale: getIt<AppProfileService>().currentLocale,
  );
}

String _stockSupportValue(AppStrings t) {
  if (_isUsStockScope()) {
    return _isUsStockProviderReady()
        ? t.text(AppStringKeys.assetsConfigSupportValueUsFinnhub)
        : t.text(AppStringKeys.assetsConfigSupportValueUsPending);
  }
  return t.text(AppStringKeys.assetsConfigSupportValue);
}

String _stockAutoRefreshValue(AppStrings t) {
  if (_isUsStockScope()) {
    return t.text(AppStringKeys.assetsConfigAutoRefreshValueUs);
  }
  return t.text(AppStringKeys.assetsConfigAutoRefreshValue);
}

String _stockFallbackValue(AppStrings t) {
  if (_isUsStockScope() && !_isUsStockProviderReady()) {
    return t.text(AppStringKeys.assetsConfigFallbackValueUsPending);
  }
  return t.text(AppStringKeys.assetsConfigFallbackValue);
}

class AssetManagementPage extends StatefulWidget {
  const AssetManagementPage({super.key});

  @override
  State<AssetManagementPage> createState() => _AssetManagementPageState();
}

class _AssetManagementPageState extends State<AssetManagementPage>
    with WidgetsBindingObserver {
  final AssetRepository _repo = getIt<AssetRepository>();
  final StockService _stockService = getIt<StockService>();
  final Uuid _uuid = const Uuid();

  List<Asset> _assets = [];
  List<StockPosition> _stocks = [];
  bool _loading = true;
  bool _refreshingQuotes = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAll();
    _warmUpSearchCache();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadAll();
    }
  }

  Future<void> _warmUpSearchCache() async {
    try {
      await _stockService.ensureSearchCache();
    } catch (_) {}
  }

  Future<void> _loadAll({bool autoRefreshQuotes = true}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final assetResult = await _repo.getAssets();
    final assets = assetResult.fold((_) => <Asset>[], (items) => items);

    List<StockPosition> stocks;
    try {
      await _stockService.restoreFromCloudIfNeeded();
      stocks = autoRefreshQuotes
          ? await _stockService.refreshQuotesIfNeeded()
          : await _stockService.getPositions();
    } catch (_) {
      stocks = await _stockService.getPositions();
    }

    if (!mounted) return;
    setState(() {
      _assets = assets;
      _stocks = stocks;
      _loading = false;
      _error = assetResult.fold((err) => err, (_) => null);
    });
  }

  Future<void> _manualRefreshQuotes() async {
    if (_refreshingQuotes) return;
    if (!_stockService.isProviderReady) {
      _showStockProviderPendingDialog();
      return;
    }
    setState(() => _refreshingQuotes = true);
    try {
      final refreshed = await _stockService.refreshQuotes(manual: true);
      if (!mounted) return;
      setState(() => _stocks = refreshed);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).text(AppStringKeys.assetsQuotesUpdated))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _refreshingQuotes = false);
    }
  }

  Future<void> _addAsset(
    String name,
    AssetType type,
    double balance,
    String? description,
  ) async {
    final asset = Asset(
      id: _uuid.v4(),
      name: name,
      type: type,
      balance: balance,
      currency: getIt<AppProfileService>().currentBaseCurrency,
      locale: getIt<AppProfileService>().currentLocale.toLanguageTag(),
      countryCode: _profileCountryCode(),
      createdAt: DateTime.now(),
      syncStatus: SyncStatus.pending,
      description: description,
    );
    final result = await _repo.addAsset(asset);
    result.fold(
      (err) => _showError(err),
      (assets) => setState(() => _assets = assets),
    );
  }

  Future<void> _updateAsset(
    Asset asset,
    String name,
    AssetType type,
    double balance,
    String? description,
  ) async {
    final updated = asset.copyWith(
      name: name,
      type: type,
      balance: balance,
      description: description,
    );
    final result = await _repo.updateAsset(updated);
    result.fold((err) => _showError(err), (a) {
      final newList = _assets.map((e) => e.id == a.id ? a : e).toList();
      setState(() => _assets = newList);
    });
  }

  Future<void> _deleteAsset(String id) async {
    final result = await _repo.deleteAsset(id);
    result.fold(
      (err) => _showError(err),
      (_) =>
          setState(() => _assets = _assets.where((e) => e.id != id).toList()),
    );
  }

  Future<void> _showStockForm({StockPosition? position}) async {
    final vipService = getIt<VipService>();
    if (vipService.hasExpiredEntitlement) {
      _showVipExpiredDialog();
      return;
    }
    if (!_stockService.isProviderReady) {
      _showStockProviderPendingDialog();
      return;
    }
    final result = await showModalBottomSheet<_StockFormResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) =>
          _StockFormSheet(stockService: _stockService, position: position),
    );
    if (result == null) return;

    try {
      if (position != null && result.item.pureCode != position.code) {
        await _stockService.deletePosition(position.id);
      }
      await _stockService.upsertPosition(
        result.item,
        quantityInput: result.quantityInput,
        changeMode: result.changeMode,
        costPrice: result.costPrice,
      );
      final refreshed = await _stockService.refreshQuotes(force: true);
      if (mounted) {
        setState(() => _stocks = refreshed);
      }
      await _loadAll(autoRefreshQuotes: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deleteStock(StockPosition position) async {
    await _stockService.deletePosition(position.id);
    if (!mounted) return;
    setState(
      () => _stocks = _stocks.where((e) => e.id != position.id).toList(),
    );
  }

  void _showStockProviderPendingDialog() {
    final t = AppStrings.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.text(AppStringKeys.assetsStockProviderPendingTitle)),
        content: Text(t.text(AppStringKeys.assetsStockProviderPendingContent)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.text(AppStringKeys.commonClose)),
          ),
        ],
      ),
    );
  }

  void _showAssetForm({Asset? asset}) {
    final vipService = getIt<VipService>();
    if (vipService.hasExpiredEntitlement) {
      _showVipExpiredDialog();
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _AssetFormSheet(
        asset: asset,
        onSave: (name, type, balance, description) {
          Navigator.pop(ctx);
          if (asset == null) {
            _addAsset(name, type, balance, description);
          } else {
            _updateAsset(asset, name, type, balance, description);
          }
        },
      ),
    );
  }

  void _showVipExpiredDialog() {
    final t = AppStrings.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.text(AppStringKeys.assetsVipExpiredTitle)),
        content: Text(t.text(AppStringKeys.assetsVipExpiredContent)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.text(AppStringKeys.commonMaybeLater)),
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
            child: Text(t.text(AppStringKeys.assetsVipExpiredRenew)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAsset(Asset asset) {
    final t = AppStrings.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.text(AppStringKeys.assetsDeleteAssetTitle)),
        content: Text(
          t.text(AppStringKeys.assetsDeleteAssetContent, params: {'name': asset.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.text(AppStringKeys.commonCancel)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteAsset(asset.id);
            },
            child: Text(
              t.text(AppStringKeys.commonDelete),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteStock(StockPosition position) {
    final t = AppStrings.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.text(AppStringKeys.assetsDeleteStockTitle)),
        content: Text(
          t.text(
            AppStringKeys.assetsDeleteStockContent,
            params: {'name': '${position.name} (${position.code})'},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.text(AppStringKeys.commonCancel)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteStock(position);
            },
            child: Text(
              t.text(AppStringKeys.commonDelete),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  double get _stockMarketValue =>
      _stocks.fold(0.0, (sum, item) => sum + item.marketValue);

  double get _otherAssetsTotal =>
      _assets.fold(0.0, (sum, item) => sum + item.balance);

  double get _totalAssets => _stockMarketValue + _otherAssetsTotal;

  double get _stockProfitAmount =>
      _stocks.fold(0.0, (sum, item) => sum + (item.profitAmount ?? 0));

  double? get _stockProfitPercent {
    if (_stockMarketValue <= 0) return null;
    return (_stockProfitAmount / _stockMarketValue) * 100;
  }

  DateTime? get _lastQuoteUpdatedAt {
    final times = _stocks
        .where((e) => e.quoteUpdatedAt != null)
        .map((e) => e.quoteUpdatedAt!)
        .toList();
    if (times.isEmpty) return null;
    times.sort((a, b) => b.compareTo(a));
    return times.first;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.text(AppStringKeys.assetsTitle)),
        backgroundColor: const Color(0xFF4A47D8),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _refreshingQuotes ? null : _manualRefreshQuotes,
            icon: _refreshingQuotes
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isTablet = constraints.maxWidth >= 768;
          final horizontalPadding = isTablet
              ? 24.0
              : (constraints.maxWidth > 520 ? 16.0 : 0.0);
          final maxContentWidth = isTablet
              ? (constraints.maxWidth >= 1024 ? 860.0 : 720.0)
              : (constraints.maxWidth > 620 ? 520.0 : constraints.maxWidth);

          if (_loading) {
            return const Center(child: CircularProgressIndicator());
          }

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: RefreshIndicator(
                  onRefresh: () => _loadAll(autoRefreshQuotes: true),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      MediaQuery.of(context).padding.bottom + 130,
                    ),
                    children: [
                      _AssetSummaryCard(
                        totalAssets: _totalAssets,
                        stockMarketValue: _stockMarketValue,
                        otherAssetsTotal: _otherAssetsTotal,
                        stockRatio: _totalAssets <= 0
                            ? 0
                            : _stockMarketValue / _totalAssets,
                        stockProfitAmount: _stockProfitAmount,
                        stockProfitPercent: _stockProfitPercent,
                        stockCount: _stocks.length,
                      ),
                      const SizedBox(height: 16),
                      _SectionHeader(
                        title: t.text(AppStringKeys.assetsStocksSection),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ActionPill(
                              icon: _refreshingQuotes ? null : Icons.refresh,
                              label: _refreshingQuotes
                                  ? t.text(AppStringKeys.assetsRefreshing)
                                  : (_lastQuoteUpdatedAt == null
                                        ? t.text(AppStringKeys.assetsRefreshQuotes)
                                        : AppFormatter.formatShortDate(
                                            _lastQuoteUpdatedAt!,
                                            locale: getIt<AppProfileService>().currentLocale,
                                          )),
                              onTap: _refreshingQuotes
                                  ? null
                                  : _manualRefreshQuotes,
                              loading: _refreshingQuotes,
                              outlined: true,
                            ),
                            const SizedBox(width: 8),
                            _ActionPill(
                              icon: Icons.add,
                              label: t.text(AppStringKeys.assetsAddStock),
                              onTap: () => _showStockForm(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_stocks.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _StockOverviewStrip(
                            stockCount: _stocks.length,
                            stockMarketValue: _stockMarketValue,
                            stockProfitAmount: _stockProfitAmount,
                            stockProfitPercent: _stockProfitPercent,
                          ),
                        ),
                      if (_stocks.isEmpty)
                        _AssetEmptyCard(
                          icon: '📈',
                          title: t.text(AppStringKeys.assetsEmptyStocksTitle),
                          subtitle: t.text(AppStringKeys.assetsEmptyStocksSubtitle),
                        )
                      else
                        ..._stocks.map(
                          (stock) => _StockTile(
                            position: stock,
                            onEdit: () => _showStockForm(position: stock),
                            onDelete: () => _confirmDeleteStock(stock),
                          ),
                        ),
                      const SizedBox(height: 16),
                      _SectionHeader(
                        title: t.text(AppStringKeys.assetsOtherSection),
                        trailing: _ActionPill(
                          icon: Icons.add,
                          label: t.text(AppStringKeys.assetsAddAsset),
                          onTap: () => _showAssetForm(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_assets.isEmpty)
                        _AssetEmptyCard(
                          icon: '💼',
                          title: t.text(AppStringKeys.assetsEmptyOtherTitle),
                          subtitle: t.text(AppStringKeys.assetsEmptyOtherSubtitle),
                        )
                      else
                        ..._assets.map(
                          (asset) => _OtherAssetTile(
                            asset: asset,
                            onEdit: () => _showAssetForm(asset: asset),
                            onDelete: () => _confirmDeleteAsset(asset),
                          ),
                        ),
                      const SizedBox(height: 16),
                      _SectionHeader(title: t.text(AppStringKeys.assetsConfigSection)),
                      const SizedBox(height: 8),
                      _ConfigCard(
                        searchCacheUpdatedAtMs:
                            _stockService.searchCacheUpdatedAtMs,
                        error: _error,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AssetSummaryCard extends StatelessWidget {
  const _AssetSummaryCard({
    required this.totalAssets,
    required this.stockMarketValue,
    required this.otherAssetsTotal,
    required this.stockRatio,
    required this.stockProfitAmount,
    required this.stockProfitPercent,
    required this.stockCount,
  });

  final double totalAssets;
  final double stockMarketValue;
  final double otherAssetsTotal;
  final double stockRatio;
  final double stockProfitAmount;
  final double? stockProfitPercent;
  final int stockCount;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final profitColor = _marketChangeBgColor(stockProfitAmount);
    final profitTextColor = _marketChangeColor(stockProfitAmount);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4A47D8), Color(0xFF3A38C8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A47D8).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: 总资产(最大,最突出)
          Text(
            t.text(AppStringKeys.assetsTotalAssets),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _profileMoney(totalAssets),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),

          const SizedBox(height: 14),

          // Row 2: 持仓盈亏（按市场语义色）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: profitColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              stockProfitPercent == null
                  ? t.text(AppStringKeys.assetsStockProfitEmpty)
                  : t.text(
                      AppStringKeys.assetsStockProfit,
                      params: {
                        'amount': '${stockProfitAmount >= 0 ? '+' : ''}${_profileMoney(stockProfitAmount.abs())}',
                        'percent': '${stockProfitPercent!.toStringAsFixed(2)}%',
                      },
                    ),
              style: TextStyle(
                color: profitTextColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Row 3: 股票市值 + 其他资产并列
          Row(
            children: [
              Expanded(
                child: _SummaryMiniCard(
                  title: t.text(AppStringKeys.assetsStockMarketValue),
                  value: _profileMoney(stockMarketValue),
                  subtitle: t.text(
                    AppStringKeys.assetsHoldingCount,
                    params: {'count': '$stockCount'},
                  ),
                  lightText: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryMiniCard(
                  title: t.text(AppStringKeys.assetsOtherAssets),
                  value: _profileMoney(otherAssetsTotal),
                  subtitle: t.text(AppStringKeys.assetsOtherAssetsSubtitle),
                  lightText: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryMiniCard extends StatelessWidget {
  const _SummaryMiniCard({
    required this.title,
    required this.value,
    required this.subtitle,
    this.lightText = false,
  });

  final String title;
  final String value;
  final String subtitle;
  final bool
  lightText; // true = white text (on dark bg), false = dark text (on light bg)

  @override
  Widget build(BuildContext context) {
    final titleColor = lightText ? Colors.white70 : const Color(0xFF909399);
    final valueColor = lightText ? Colors.white : const Color(0xFF303133);
    final subtitleColor = lightText ? Colors.white54 : const Color(0xFF909399);
    final bgColor = lightText
        ? Colors.white.withValues(alpha: 0.14)
        : const Color(0xFFF8F8F8);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: titleColor, fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: subtitleColor, fontSize: 11)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        if (trailing != null) ...[trailing!],
      ],
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.label,
    required this.onTap,
    this.icon,
    this.loading = false,
    this.outlined = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool loading;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final background = outlined ? Colors.white : const Color(0xFF4A47D8);
    final foreground = outlined ? const Color(0xFF4A47D8) : Colors.white;

    return PressFeedback(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: outlined
              ? Border.all(
                  color: const Color(0xFF4A47D8).withValues(alpha: 0.3),
                )
              : null,
          boxShadow: outlined
              ? null
              : [
                  BoxShadow(
                    color: const Color(0xFF4A47D8).withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            else if (icon != null)
              Icon(icon, size: 14, color: foreground),
            if (loading || icon != null) const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockOverviewStrip extends StatelessWidget {
  const _StockOverviewStrip({
    required this.stockCount,
    required this.stockMarketValue,
    required this.stockProfitAmount,
    required this.stockProfitPercent,
  });

  final int stockCount;
  final double stockMarketValue;
  final double stockProfitAmount;
  final double? stockProfitPercent;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final profitColor = _marketChangeColor(stockProfitAmount);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5EAF3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _MiniMetric(
              label: t.text(AppStringKeys.assetsStockMarketValue),
              value: _profileMoney(stockMarketValue),
            ),
          ),
          Container(width: 1, height: 36, color: const Color(0xFFE5EAF3)),
          Expanded(
            child: _MiniMetric(
              label: t.text(AppStringKeys.assetsStockProfitLabel),
              value: stockProfitPercent == null
                  ? '--'
                  : '${stockProfitAmount >= 0 ? '+' : ''}${_profileMoney(stockProfitAmount.abs())} (${stockProfitPercent!.toStringAsFixed(2)}%)',
              valueColor: profitColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.label,
    required this.value,
    this.valueColor = const Color(0xFF303133),
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            height: 1.3,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _AssetEmptyCard extends StatelessWidget {
  const _AssetEmptyCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final String icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 34)),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _StockTile extends StatelessWidget {
  const _StockTile({
    required this.position,
    required this.onEdit,
    required this.onDelete,
  });

  final StockPosition position;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final quoteColor = _marketChangeColor(position.changePercent);
    final profit = position.profitAmount;
    final profitPercent = position.profitPercent;
    final profitColor = _marketChangeColor(profit);
    final statusText = switch (position.quoteStatus) {
      StockQuoteStatus.normal => t.text(AppStringKeys.assetsQuoteStatusNormal),
      StockQuoteStatus.stale => t.text(AppStringKeys.assetsQuoteStatusStale),
      StockQuoteStatus.loading => t.text(AppStringKeys.assetsQuoteStatusLoading),
    };
    final locale = _localeFromTag(position.locale);
    final updatedText = position.quoteUpdatedAt == null
        ? t.text(AppStringKeys.assetsNotUpdated)
        : AppFormatter.formatShortDate(position.quoteUpdatedAt!, locale: locale);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          position.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF4A47D8,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            position.code,
                            style: const TextStyle(
                              color: Color(0xFF4A47D8),
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _QuoteStatusBadge(
                          statusText: statusText,
                          status: position.quoteStatus,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t.text(
                        AppStringKeys.assetsUpdatedAt,
                        params: {
                          'exchange': position.exchange,
                          'quantity': '${position.quantity}',
                          'time': updatedText,
                        },
                      ),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(t.text(AppStringKeys.assetsEditPosition)),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(t.text(AppStringKeys.assetsDeletePosition)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MetricItem(
                  label: t.text(AppStringKeys.assetsLatestPrice),
                  value: position.latestPrice == null
                      ? '--'
                      : _formatMoney(
                          position.latestPrice!,
                          currencyCode: position.marketCurrency,
                          locale: locale,
                        ),
                  valueColor: quoteColor,
                ),
              ),
              Expanded(
                child: _MetricItem(
                  label: t.text(AppStringKeys.assetsChangePercent),
                  value: position.changePercent == null
                      ? '--'
                      : '${position.changePercent!.toStringAsFixed(2)}%',
                  valueColor: quoteColor,
                ),
              ),
              Expanded(
                child: _MetricItem(
                  label: t.text(AppStringKeys.assetsPositionMarketValue),
                  value: _formatMoney(
                    position.marketValue,
                    currencyCode: position.marketCurrency,
                    locale: locale,
                  ),
                  valueColor: const Color(0xFF303133),
                ),
              ),
            ],
          ),
          if (position.costPrice != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F8F8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t.text(
                        AppStringKeys.assetsCostPrice,
                        params: {
                          'amount': _formatMoney(
                            position.costPrice!,
                            currencyCode: position.marketCurrency,
                            locale: locale,
                          ),
                        },
                      ),
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    profit == null
                        ? '--'
                        : t.text(
                            AppStringKeys.assetsFloatingProfit,
                            params: {
                              'amount': '${profit >= 0 ? '+' : ''}${_formatMoney(profit.abs(), currencyCode: position.marketCurrency, locale: locale)}',
                              'percent': '${profitPercent!.toStringAsFixed(2)}%',
                            },
                          ),
                    style: TextStyle(
                      color: profitColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuoteStatusBadge extends StatelessWidget {
  const _QuoteStatusBadge({required this.statusText, required this.status});

  final String statusText;
  final StockQuoteStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      StockQuoteStatus.normal => (
        const Color(0xFFEAF7EE),
        const Color(0xFF67C23A),
      ),
      StockQuoteStatus.stale => (
        const Color(0xFFFFF4E5),
        const Color(0xFFE6A23C),
      ),
      StockQuoteStatus.loading => (
        const Color(0xFFF4F4F5),
        const Color(0xFF909399),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        statusText,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _MetricItem extends StatelessWidget {
  const _MetricItem({
    required this.label,
    required this.value,
    this.valueColor = const Color(0xFF303133),
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _OtherAssetTile extends StatelessWidget {
  const _OtherAssetTile({
    required this.asset,
    required this.onEdit,
    required this.onDelete,
  });

  final Asset asset;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFFFA11A),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFA11A).withValues(alpha: 0.28),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Text(
              Asset.typeIcon(asset.type),
              style: const TextStyle(fontSize: 22),
            ),
          ),
        ),
        title: Text(
          asset.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _localizedAssetTypeName(asset.type, locale),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            if (asset.description != null && asset.description!.isNotEmpty)
              Text(
                asset.description!,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatMoney(
                asset.balance,
                currencyCode: asset.currency,
                locale: _localeFromTag(asset.locale),
              ),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Color(0xFF4A47D8),
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Text(AppStrings.of(context).text(AppStringKeys.assetsEdit)),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(AppStrings.of(context).text(AppStringKeys.commonDelete)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfigCard extends StatefulWidget {
  const _ConfigCard({
    required this.searchCacheUpdatedAtMs,
    required this.error,
  });

  final int? searchCacheUpdatedAtMs;
  final String? error;

  @override
  State<_ConfigCard> createState() => _ConfigCardState();
}

class _ConfigCardState extends State<_ConfigCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final cacheText = _stockCacheText(t, widget.searchCacheUpdatedAtMs);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header - always visible, tappable
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(
                    Icons.settings_outlined,
                    size: 18,
                    color: Color(0xFF909399),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t.text(AppStringKeys.assetsConfigSection),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      color: Color(0xFF909399),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Expandable content
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1, color: Color(0xFFF2F4F7)),
                  const SizedBox(height: 12),
                  _ConfigRow(
                    label: t.text(AppStringKeys.assetsConfigSearchCache),
                    value: cacheText,
                  ),
                  const SizedBox(height: 8),
                  _ConfigRow(
                    label: t.text(AppStringKeys.assetsConfigAutoRefresh),
                    value: _stockAutoRefreshValue(t),
                  ),
                  const SizedBox(height: 8),
                  _ConfigRow(
                    label: t.text(AppStringKeys.assetsConfigManualThrottle),
                    value: t.text(AppStringKeys.assetsConfigManualThrottleValue),
                  ),
                  const SizedBox(height: 8),
                  _ConfigRow(
                    label: t.text(AppStringKeys.assetsConfigSupport),
                    value: _stockSupportValue(t),
                  ),
                  const SizedBox(height: 8),
                  _ConfigRow(
                    label: t.text(AppStringKeys.assetsConfigFallback),
                    value: _stockFallbackValue(t),
                  ),
                  if (widget.error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      t.text(
                        AppStringKeys.assetsConfigLoadHint,
                        params: {'error': widget.error!},
                      ),
                      style: const TextStyle(
                        color: Color(0xFFE6A23C),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

class _ConfigRow extends StatelessWidget {
  const _ConfigRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12, color: Color(0xFF303133)),
          ),
        ),
      ],
    );
  }
}

class _StockFormResult {
  const _StockFormResult({
    required this.item,
    required this.quantityInput,
    required this.changeMode,
    this.costPrice,
  });

  final StockSearchItem item;
  final int quantityInput;
  final StockQuantityChangeMode changeMode;
  final double? costPrice;
}

class _StockFormSheet extends StatefulWidget {
  const _StockFormSheet({required this.stockService, this.position});

  final StockService stockService;
  final StockPosition? position;

  @override
  State<_StockFormSheet> createState() => _StockFormSheetState();
}

class _StockFormSheetState extends State<_StockFormSheet> {
  late final TextEditingController _searchController;
  late final TextEditingController _quantityController;
  late final TextEditingController _costController;

  List<StockSearchItem> _suggestions = [];
  StockSearchItem? _selectedItem;
  bool _searching = false;
  bool _hasSearched = false;
  String? _searchError;
  StockQuantityChangeMode _changeMode = StockQuantityChangeMode.overwrite;

  bool get _isUsScope => widget.stockService.isUsScope;

  String _searchHint(AppStrings t) => _isUsScope
      ? t.text(AppStringKeys.assetsStockNameCodeHintUs)
      : t.text(AppStringKeys.assetsStockNameCodeHint);

  String _holdingQuantityHint(AppStrings t) => _isUsScope
      ? t.text(AppStringKeys.assetsHoldingQuantityHintUs)
      : t.text(AppStringKeys.assetsHoldingQuantityHint);

  String _deltaQuantityHint(AppStrings t) => _isUsScope
      ? t.text(AppStringKeys.assetsDeltaQuantityHintUs)
      : t.text(AppStringKeys.assetsDeltaQuantityHint);

  String _stockFormHint(AppStrings t) => _isUsScope
      ? t.text(AppStringKeys.assetsStockFormHintUs)
      : t.text(AppStringKeys.assetsStockFormHint);

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: widget.position == null
          ? ''
          : '${widget.position!.name} (${widget.position!.code})',
    );
    _quantityController = TextEditingController(
      text: widget.position?.quantity.toString() ?? '',
    );
    _costController = TextEditingController(
      text: widget.position?.costPrice?.toStringAsFixed(2) ?? '',
    );

    if (widget.position != null) {
      _selectedItem = StockSearchItem(
        code: widget.position!.displayCode,
        name: widget.position!.name,
        exchange: widget.position!.exchange,
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _quantityController.dispose();
    _costController.dispose();
    super.dispose();
  }

  Future<void> _search(String text) async {
    final keyword = text.trim();
    if (keyword.isEmpty) {
      if (mounted) {
        setState(() {
          _suggestions = [];
          _hasSearched = false;
          _searchError = null;
        });
      }
      return;
    }
    setState(() {
      _searching = true;
      _hasSearched = true;
      _searchError = null;
    });
    try {
      final result = await widget.stockService.searchStocks(keyword);
      if (!mounted) return;
      setState(() {
        _suggestions = result;
        _searchError = null;
      });
    } catch (_) {
      if (!mounted) return;
      final t = AppStrings.of(context);
      setState(() {
        _suggestions = [];
        _searchError = t.text(AppStringKeys.assetsSearchFailed);
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _submit() {
    final t = AppStrings.of(context);
    final selected = _selectedItem;
    if (selected == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.text(AppStringKeys.assetsSelectStockFirst))));
      return;
    }

    final quantity = int.tryParse(_quantityController.text.trim());
    if (quantity == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.text(AppStringKeys.assetsInvalidQuantity))));
      return;
    }

    if (_changeMode == StockQuantityChangeMode.overwrite) {
      final invalid = _isUsScope ? quantity <= 0 : (quantity <= 0 || quantity % 100 != 0);
      if (invalid) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(
              t.text(
                _isUsScope
                    ? AppStringKeys.assetsQuantityPositive
                    : AppStringKeys.assetsQuantityMultiple,
              ),
            ),
          ),
        );
        return;
      }
    } else {
      final invalidDelta = _isUsScope ? quantity == 0 : (quantity == 0 || quantity % 100 != 0);
      if (invalidDelta) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t.text(
                _isUsScope
                    ? AppStringKeys.assetsDeltaQuantityNonZero
                    : AppStringKeys.assetsDeltaQuantityMultiple,
              ),
            ),
          ),
        );
        return;
      }
      final currentQty = widget.position?.quantity ?? 0;
      final nextQty = currentQty + quantity;
      final invalidNext = _isUsScope ? nextQty <= 0 : (nextQty <= 0 || nextQty % 100 != 0);
      if (invalidNext) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t.text(
                _isUsScope
                    ? AppStringKeys.assetsResultingQuantityPositive
                    : AppStringKeys.assetsResultingQuantityMultiple,
              ),
            ),
          ),
        );
        return;
      }
    }

    final rawCost = _costController.text.trim();
    final costPrice = rawCost.isEmpty ? null : double.tryParse(rawCost);
    if (rawCost.isNotEmpty && costPrice == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.text(AppStringKeys.assetsInvalidCostPrice))));
      return;
    }

    Navigator.pop(
      context,
      _StockFormResult(
        item: selected,
        quantityInput: quantity,
        changeMode: _changeMode,
        costPrice: costPrice,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.position == null
                    ? t.text(AppStringKeys.assetsAddStockPosition)
                    : t.text(AppStringKeys.assetsEditStockPosition),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: t.text(AppStringKeys.assetsStockNameCode),
                  hintText: _searchHint(t),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) {
                  if (_selectedItem != null &&
                      v !=
                          '${_selectedItem!.name} (${_selectedItem!.pureCode})') {
                    setState(() => _selectedItem = null);
                  }
                  _search(v);
                },
              ),
              if (_selectedItem != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A47D8).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    t.text(
                      AppStringKeys.assetsSelectedStock,
                      params: {
                        'name': _selectedItem!.name,
                        'code': _selectedItem!.pureCode,
                        'exchange': _selectedItem!.exchange,
                      },
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF4A47D8),
                    ),
                  ),
                ),
              ],
              if (_suggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _suggestions.length,
                    separatorBuilder: (_, index) =>
                        Divider(height: 1, color: Colors.grey.shade200),
                    itemBuilder: (context, index) {
                      final item = _suggestions[index];
                      return ListTile(
                        dense: true,
                        title: Text(item.name),
                        subtitle: Text('${item.pureCode} · ${item.exchange}'),
                        onTap: () {
                          setState(() {
                            _selectedItem = item;
                            _suggestions = [];
                            _searchController.text =
                                '${item.name} (${item.pureCode})';
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
              if (_searchError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _searchError!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.red.shade400,
                  ),
                ),
              ] else if (_hasSearched &&
                  !_searching &&
                  _selectedItem == null &&
                  _suggestions.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  t.text(AppStringKeys.assetsSearchNoResults),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (widget.position != null) ...[
                SegmentedButton<StockQuantityChangeMode>(
                  segments: [
                    ButtonSegment(
                      value: StockQuantityChangeMode.overwrite,
                      label: Text(t.text(AppStringKeys.assetsOverwrite)),
                    ),
                    ButtonSegment(
                      value: StockQuantityChangeMode.delta,
                      label: Text(t.text(AppStringKeys.assetsDelta)),
                    ),
                  ],
                  selected: {_changeMode},
                  onSelectionChanged: (set) {
                    setState(() {
                      _changeMode = set.first;
                      _quantityController.text =
                          _changeMode == StockQuantityChangeMode.overwrite
                          ? widget.position!.quantity.toString()
                          : '';
                    });
                  },
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _quantityController,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                decoration: InputDecoration(
                  labelText: _changeMode == StockQuantityChangeMode.delta
                      ? t.text(AppStringKeys.assetsDeltaQuantityLabel)
                      : t.text(AppStringKeys.assetsHoldingQuantityLabel),
                  hintText: _changeMode == StockQuantityChangeMode.delta
                      ? _deltaQuantityHint(t)
                      : _holdingQuantityHint(t),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _costController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: t.text(AppStringKeys.assetsCostPriceOptional),
                  hintText: t.text(AppStringKeys.assetsCostPriceHint),
                  prefixText: _profileCurrencyPrefix(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _stockFormHint(t),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4A47D8),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _submit,
                  child: Text(t.text(AppStringKeys.commonSave)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssetFormSheet extends StatefulWidget {
  final Asset? asset;
  final void Function(
    String name,
    AssetType type,
    double balance,
    String? description,
  )
  onSave;

  const _AssetFormSheet({this.asset, required this.onSave});

  @override
  State<_AssetFormSheet> createState() => _AssetFormSheetState();
}

class _AssetFormSheetState extends State<_AssetFormSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _balanceController;
  late final TextEditingController _descController;
  late AssetType _selectedType;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.asset?.name ?? '');
    _balanceController = TextEditingController(
      text: widget.asset != null ? widget.asset!.balance.toString() : '',
    );
    _descController = TextEditingController(
      text: widget.asset?.description ?? '',
    );
    _selectedType = widget.asset?.type ?? AssetType.bank;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final locale = Localizations.localeOf(context);
    final assetTypes = _availableManualAssetTypes().toList();
    if (!assetTypes.contains(_selectedType)) {
      assetTypes.insert(0, _selectedType);
    }
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.asset == null
                ? t.text(AppStringKeys.assetsAddAssetTitle)
                : t.text(AppStringKeys.assetsEditAssetTitle),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: t.text(AppStringKeys.assetsAssetName),
              hintText: t.text(AppStringKeys.assetsAssetNameHint),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<AssetType>(
            initialValue: _selectedType,
            decoration: InputDecoration(
              labelText: t.text(AppStringKeys.assetsAssetType),
              border: const OutlineInputBorder(),
            ),
            items: assetTypes
                .map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Row(
                      children: [
                        Text(
                          Asset.typeIcon(type),
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(width: 8),
                        Text(_localizedAssetTypeName(type, locale)),
                      ],
                    ),
                  );
                })
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _selectedType = v);
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _balanceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: t.text(AppStringKeys.assetsCurrentAmount),
              hintText: '0.00',
              border: const OutlineInputBorder(),
              prefixText: _profileCurrencyPrefix(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descController,
            decoration: InputDecoration(
              labelText: t.text(AppStringKeys.assetsNoteOptional),
              hintText: t.text(AppStringKeys.assetsNoteHint),
              border: const OutlineInputBorder(),
            ),
            maxLines: 1,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A47D8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                final name = _nameController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(
                    SnackBar(content: Text(t.text(AppStringKeys.assetsEnterAssetName))),
                  );
                  return;
                }
                final balance =
                    double.tryParse(_balanceController.text.trim()) ?? 0.0;
                final desc = _descController.text.trim();
                widget.onSave(
                  name,
                  _selectedType,
                  balance,
                  desc.isEmpty ? null : desc,
                );
              },
              child: Text(t.text(AppStringKeys.commonSave)),
            ),
          ),
        ],
      ),
    );
  }
}
