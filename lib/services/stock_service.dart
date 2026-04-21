import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../app/app_flavor.dart';
import '../app/profile/capability_profile.dart';
import '../features/accounting/domain/entities/stock_position.dart';
import 'app_profile_service.dart';
import 'cloud_service.dart';
import 'config_service.dart';

class StockService {
  StockService(this._prefs)
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

  final SharedPreferences _prefs;
  final Dio _dio;
  final Uuid _uuid = const Uuid();
  final CloudService _cloud = GetIt.instance<CloudService>();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  bool get _isIntl {
    if (GetIt.instance.isRegistered<AppProfileService>()) {
      return GetIt.instance<AppProfileService>().flavor.isIntl;
    }
    return AppFlavorX.current.isIntl;
  }

  String _message(String zh, String en) => _isIntl ? en : zh;

  static const _token = '9CC9221B-67A1-4326-9401-60A3F0627B83';
  static const _legacyPositionsKey = 'stock_positions_v1';
  static const _positionsKeyPrefix = 'stock_positions_v2_';
  static const _demoPositionsKey = 'demo_stock_positions_v1';
  static const _deletedIdsKeyPrefix = 'stock_deleted_ids_v1_';
  static const _searchCacheKey = 'stock_search_cache_v1';
  static const _searchCacheUpdatedAtKey = 'stock_search_cache_updated_at_v1';
  static const _lastQuoteRefreshMsKey = 'stock_last_quote_refresh_ms_v1';
  static const _lastManualRefreshMsKey = 'stock_last_manual_refresh_ms_v1';
  static const _lastAutoSlotKey = 'stock_last_auto_slot_v1';

  String? get _phone => _prefs.getString('logged_in_phone');

  String _sanitizeStorageId(String? raw) {
    if (raw == null || raw.isEmpty) return 'guest';
    return raw.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
  }

  String get _activePositionsKey => _phone == 'DemoAccount'
      ? _demoPositionsKey
      : '$_positionsKeyPrefix${_sanitizeStorageId(_phone)}';

  String get _deletedIdsKey =>
      '$_deletedIdsKeyPrefix${_sanitizeStorageId(_phone)}';

  String? get _legacyActivePositionsKey =>
      _phone == 'DemoAccount' ? null : _legacyPositionsKey;

  bool get _canSync {
    final phone = _phone;
    return phone != null &&
        phone.isNotEmpty &&
        phone != 'DemoAccount' &&
        _cloud.isConfigured;
  }

  StockMarketScope get _stockMarketScope =>
      GetIt.instance<AppProfileService>()
          .currentProfile
          .capabilityProfile
          .stockMarketScope;

  bool get isUsScope => _stockMarketScope == StockMarketScope.us;

  bool get _isUsScope => _stockMarketScope == StockMarketScope.us;

  bool get _isFinnhubConfigured => ConfigService.instance.isFinnhubConfigured;

  String get _finnhubApiKey => ConfigService.instance.finnhubApiKey;

  bool get isProviderReady => !_isUsScope || _isFinnhubConfigured;

  bool get usesOnDemandSearch => _isUsScope && _isFinnhubConfigured;

  Exception get _usStockPendingException =>
      Exception('US stock search and quotes are not connected yet');

  Future<List<StockPosition>> getPositions({bool tryRestore = false}) async {
    if (tryRestore) {
      return restoreFromCloudIfNeeded();
    }
    return _getLocalPositions();
  }

  Future<List<StockPosition>> _getLocalPositions() async {
    String? raw = _prefs.getString(_activePositionsKey);

    // 兼容旧版本本地持仓 key，首次读取时自动迁移到按手机号隔离的新 key。
    if ((raw == null || raw.isEmpty) && _legacyActivePositionsKey != null) {
      final legacyRaw = _prefs.getString(_legacyActivePositionsKey!);
      if (legacyRaw != null && legacyRaw.isNotEmpty) {
        raw = legacyRaw;
        await _prefs.setString(_activePositionsKey, legacyRaw);
        await _prefs.remove(_legacyActivePositionsKey!);
      }
    }

    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final positions = list
          .map(
            (e) => _normalizePositionMarketProfile(
              StockPosition.fromJson(Map<String, dynamic>.from(e as Map)),
            ),
          )
          .toList()
        ..sort((a, b) => a.code.compareTo(b.code));
      final normalizedRaw = jsonEncode(positions.map((e) => e.toJson()).toList());
      if (normalizedRaw != raw) {
        await _prefs.setString(_activePositionsKey, normalizedRaw);
      }
      return positions;
    } catch (_) {
      return [];
    }
  }

  Future<void> savePositions(List<StockPosition> positions) async {
    final normalized = positions
        .map(_normalizePositionMarketProfile)
        .toList()
      ..sort((a, b) => a.code.compareTo(b.code));
    final raw = jsonEncode(normalized.map((e) => e.toJson()).toList());
    await _prefs.setString(_activePositionsKey, raw);
  }

  StockPosition _normalizePositionMarketProfile(StockPosition position) {
    final exchange = position.exchange.toUpperCase();
    final isUs = exchange.contains('NASDAQ') ||
        exchange.contains('NYSE') ||
        exchange == 'US';

    return position.copyWith(
      marketCurrency: isUs ? 'USD' : 'CNY',
      locale: isUs ? 'en-US' : 'zh-CN',
      countryCode: isUs ? 'US' : 'CN',
    );
  }

  Future<Set<String>> _loadDeletedIds() async {
    final raw = await _secureStorage.read(key: _deletedIdsKey);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => e.toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _saveDeletedIds(Set<String> ids) async {
    if (ids.isEmpty) {
      await _secureStorage.delete(key: _deletedIdsKey);
      return;
    }
    await _secureStorage.write(
      key: _deletedIdsKey,
      value: jsonEncode(ids.toList()),
    );
  }

  Future<void> _markDeletedId(String id) async {
    final ids = await _loadDeletedIds();
    ids.add(id);
    await _saveDeletedIds(ids);
  }

  Future<void> _unmarkDeletedIds(Iterable<String> idsToRemove) async {
    if (idsToRemove.isEmpty) return;
    final ids = await _loadDeletedIds();
    ids.removeAll(idsToRemove.toSet());
    await _saveDeletedIds(ids);
  }

  Future<List<StockPosition>> restoreFromCloudIfNeeded() async {
    final local = await _getLocalPositions();
    if (!_canSync) return local;

    var cloud = await _getCloudPositions();
    final deletedIds = await _loadDeletedIds();
    if (deletedIds.isNotEmpty) {
      final filteredCloud = cloud
          .where((e) => !deletedIds.contains(e.id))
          .toList();
      if (filteredCloud.length != cloud.length) {
        cloud = filteredCloud;
        await _syncAllToCloud(cloud);
      }
    }

    final hasLocalSnapshot = _prefs.containsKey(_activePositionsKey);
    if (local.isEmpty && cloud.isEmpty) return [];

    // 只在“本地从未保存过持仓”时，才从云端恢复。
    // 如果本地已经保存过（哪怕现在是空列表），说明本地状态才是最新的，
    // 需要用本地回写云端，避免删除后被云端旧数据恢复。
    if (!hasLocalSnapshot && local.isEmpty && cloud.isNotEmpty) {
      await savePositions(cloud);
      return cloud;
    }

    if (!_samePositions(local, cloud)) {
      await _syncAllToCloud(local);
    }
    return local;
  }

  bool _samePositions(List<StockPosition> left, List<StockPosition> right) {
    if (left.length != right.length) return false;
    return jsonEncode(left.map((e) => e.toJson()).toList()) ==
        jsonEncode(right.map((e) => e.toJson()).toList());
  }

  Future<List<StockPosition>> _getCloudPositions() async {
    final resp = await _cloud.get('/stock_positions');
    if (resp == null || resp.isEmpty) return [];
    final raw = resp['stock_positions'] as List? ?? [];
    return raw
        .map((e) => StockPosition.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList()
      ..sort((a, b) => a.code.compareTo(b.code));
  }

  Future<void> _syncAllToCloud(List<StockPosition> positions) async {
    if (!_canSync) return;
    await _cloud.put(
      '/stock_positions',
      body: {'stock_positions': positions.map((e) => e.toJson()).toList()},
    );
  }

  Future<void> clearLocalData() async {
    for (final key in _prefs.getKeys()) {
      if (key == _demoPositionsKey ||
          key == _legacyPositionsKey ||
          key.startsWith(_positionsKeyPrefix)) {
        await _prefs.remove(key);
      }
    }
    await _prefs.remove(_lastQuoteRefreshMsKey);
    await _prefs.remove(_lastManualRefreshMsKey);
    await _prefs.remove(_lastAutoSlotKey);
    final secureKeys = await _secureStorage.readAll();
    for (final key in secureKeys.keys) {
      if (key.startsWith(_deletedIdsKeyPrefix)) {
        await _secureStorage.delete(key: key);
      }
    }
  }

  Future<void> _deletePositionOnCloud(String id) async {
    if (!_canSync) return;
    await _cloud.delete('/stock_positions/$id');
  }

  Future<void> upsertPosition(
    StockSearchItem item, {
    required int quantityInput,
    required StockQuantityChangeMode changeMode,
    double? costPrice,
    bool mergeIfExists = true,
  }) async {
    final positions = await _getLocalPositions();
    final existingIndex = positions.indexWhere((e) => e.code == item.pureCode);
    final now = DateTime.now();

    if (existingIndex >= 0) {
      final current = positions[existingIndex];
      int nextQuantity = changeMode == StockQuantityChangeMode.delta
          ? current.quantity + quantityInput
          : quantityInput;

      if (mergeIfExists && changeMode == StockQuantityChangeMode.overwrite) {
        nextQuantity = quantityInput;
      }

      if (!_isValidHoldingQuantity(nextQuantity)) {
        throw Exception(_holdingQuantityErrorText());
      }

      positions[existingIndex] = current.copyWith(
        name: item.name,
        exchange: item.exchange,
        quantity: nextQuantity,
        costPrice: costPrice,
        clearCostPrice: costPrice == null,
        updatedAt: now,
      );
      positions[existingIndex] = _normalizePositionMarketProfile(
        positions[existingIndex],
      );
    } else {
      if (!_isValidHoldingQuantity(quantityInput)) {
        throw Exception(_holdingQuantityErrorText());
      }
      positions.add(
        StockPosition(
          id: _uuid.v4(),
          code: item.pureCode,
          name: item.name,
          exchange: item.exchange,
          marketCurrency: item.exchange.toUpperCase() == 'US' ? 'USD' : 'CNY',
          locale: item.exchange.toUpperCase() == 'US' ? 'en-US' : 'zh-CN',
          countryCode: item.exchange.toUpperCase() == 'US' ? 'US' : 'CN',
          quantity: quantityInput,
          costPrice: costPrice,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    await savePositions(positions);
    await _unmarkDeletedIds(positions.map((e) => e.id));
    await _syncAllToCloud(positions);
  }

  Future<void> updatePosition(StockPosition position) async {
    if (!_isValidHoldingQuantity(position.quantity)) {
      throw Exception(_holdingQuantityErrorText());
    }
    final positions = await _getLocalPositions();
    final index = positions.indexWhere((e) => e.id == position.id);
    if (index < 0) {
      throw Exception(_message('持仓记录不存在', 'Stock position not found'));
    }
    positions[index] = position.copyWith(updatedAt: DateTime.now());
    await savePositions(positions);
    await _unmarkDeletedIds([position.id]);
    await _syncAllToCloud(positions);
  }

  Future<void> deletePosition(String id) async {
    final positions = await _getLocalPositions();
    positions.removeWhere((e) => e.id == id);
    await _markDeletedId(id);
    await savePositions(positions);
    await _deletePositionOnCloud(id);
    await _syncAllToCloud(positions);
  }

  Future<List<StockSearchItem>> ensureSearchCache({bool force = false}) async {
    if (_isUsScope) {
      if (!isProviderReady) {
        throw _usStockPendingException;
      }
      return const [];
    }

    final cached = _loadSearchCache();
    if (!force && cached.isNotEmpty) return cached;

    final resp = await _dio.get(
      'https://api.zhituapi.com/hs/list/all',
      queryParameters: {'token': _token, 'page': 1, 'limit': 5000},
    );

    final data = resp.data;
    if (data is! List) {
      throw Exception(_message('股票列表接口返回异常', 'Stock list API returned an unexpected payload'));
    }

    final items = data
        .map(
          (e) => StockSearchItem.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .where((e) => e.code.isNotEmpty && e.name.isNotEmpty)
        .toList();

    await _prefs.setString(
      _searchCacheKey,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
    await _prefs.setInt(
      _searchCacheUpdatedAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
    return items;
  }

  List<StockSearchItem> _loadSearchCache() {
    final raw = _prefs.getString(_searchCacheKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map(
            (e) =>
                StockSearchItem.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  int? get searchCacheUpdatedAtMs => _prefs.getInt(_searchCacheUpdatedAtKey);

  Future<List<StockSearchItem>> searchStocks(
    String query, {
    int limit = 12,
  }) async {
    if (_isUsScope) {
      if (!isProviderReady) {
        throw _usStockPendingException;
      }
      return _searchUsStocks(query, limit: limit);
    }

    final keyword = query.trim().toUpperCase();
    if (keyword.isEmpty) return [];
    final items = await ensureSearchCache();
    final result = items
        .where((item) {
          return item.pureCode.contains(keyword) ||
              item.name.toUpperCase().contains(keyword);
        })
        .take(limit)
        .toList();
    return result;
  }

  Future<List<StockPosition>> refreshQuotes({
    bool manual = false,
    bool force = false,
  }) async {
    final positions = await _getLocalPositions();
    if (positions.isEmpty) return positions;

    if (_isUsScope) {
      if (!isProviderReady) return positions;

      final updated = await Future.wait(positions.map(_refreshOneQuote));
      await savePositions(updated);
      return updated;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (manual && !force) {
      final lastManualMs = _prefs.getInt(_lastManualRefreshMsKey) ?? 0;
      if (nowMs - lastManualMs < 3000) {
        throw Exception(_message('刷新过于频繁，请 3 秒后再试', 'Refreshing too frequently. Please try again in 3 seconds.'));
      }
      await _prefs.setInt(_lastManualRefreshMsKey, nowMs);
    }

    final updated = <StockPosition>[];
    final chunks = <List<StockPosition>>[];
    for (var i = 0; i < positions.length; i += 20) {
      chunks.add(
        positions.sublist(
          i,
          i + 20 > positions.length ? positions.length : i + 20,
        ),
      );
    }

    for (final chunk in chunks) {
      final result = await Future.wait(chunk.map(_refreshOneQuote));
      updated.addAll(result);
    }

    await savePositions(updated);
    await _prefs.setInt(_lastQuoteRefreshMsKey, nowMs);
    return updated;
  }

  Future<StockPosition> _refreshOneQuote(StockPosition position) async {
    if (_isUsScope) {
      return _refreshUsQuote(position);
    }

    try {
      final resp = await _dio.get(
        'https://api.zhituapi.com/hs/real/time/${position.code}',
        queryParameters: {'token': _token},
      );
      final data = resp.data;
      if (data is Map && data['error'] != null) {
        throw Exception(data['error']);
      }
      if (data is! Map) {
        throw Exception(_message('行情返回异常', 'Quote API returned an unexpected payload'));
      }

      final latestPrice = (data['p'] as num?)?.toDouble();
      final changePercent = (data['pc'] as num?)?.toDouble();
      final updatedAt = data['t'] == null
          ? DateTime.now()
          : DateTime.tryParse(data['t'].toString()) ?? DateTime.now();

      return position.copyWith(
        latestPrice: latestPrice,
        changePercent: changePercent,
        quoteUpdatedAt: updatedAt,
        quoteStatus: StockQuoteStatus.normal,
        updatedAt: DateTime.now(),
      );
    } catch (_) {
      return position.copyWith(
        quoteStatus: position.latestPrice == null
            ? StockQuoteStatus.loading
            : StockQuoteStatus.stale,
        updatedAt: DateTime.now(),
      );
    }
  }

  Future<List<StockPosition>> refreshQuotesIfNeeded() async {
    final now = DateTime.now();
    final slot = _currentDueSlot(now);
    if (slot == null) {
      return _getLocalPositions();
    }

    final slotId = _slotId(slot);
    if ((_prefs.getString(_lastAutoSlotKey) ?? '') == slotId) {
      return _getLocalPositions();
    }

    final lastManualMs = _prefs.getInt(_lastManualRefreshMsKey) ?? 0;
    if (lastManualMs >= slot.millisecondsSinceEpoch) {
      return _getLocalPositions();
    }

    final updated = await refreshQuotes();
    await _prefs.setString(_lastAutoSlotKey, slotId);
    return updated;
  }

  bool _isTradingDay(DateTime time) {
    return time.weekday >= DateTime.monday && time.weekday <= DateTime.friday;
  }

  DateTime? _currentDueSlot(DateTime now) {
    if (_isUsScope) {
      return _currentUsDueSlot(now);
    }

    final slot1135 = DateTime(now.year, now.month, now.day, 11, 35);
    final slot1505 = DateTime(now.year, now.month, now.day, 15, 5);
    if (!now.isBefore(slot1505)) return slot1505;
    if (!now.isBefore(slot1135)) return slot1135;
    return null;
  }

  DateTime? _currentUsDueSlot(DateTime now) {
    if (!isProviderReady) return null;

    final nowUtc = now.toUtc();
    final easternNow = _toUsEastern(nowUtc);
    if (!_isTradingDay(easternNow)) return null;

    final slots = <DateTime>[
      _usEasternSlotToUtc(easternNow, hour: 9, minute: 35),
      _usEasternSlotToUtc(easternNow, hour: 12, minute: 0),
      _usEasternSlotToUtc(easternNow, hour: 16, minute: 5),
    ];

    for (final slot in slots.reversed) {
      if (!nowUtc.isBefore(slot)) return slot.toLocal();
    }
    return null;
  }

  DateTime _toUsEastern(DateTime utcTime) {
    final isDst = _isUsEasternDstUtc(utcTime);
    return utcTime.add(Duration(hours: isDst ? -4 : -5));
  }

  DateTime _usEasternSlotToUtc(
    DateTime easternTime, {
    required int hour,
    required int minute,
  }) {
    final isDst = _isUsEasternDstLocal(
      easternTime.year,
      easternTime.month,
      easternTime.day,
    );
    final offsetHours = isDst ? 4 : 5;
    return DateTime.utc(
      easternTime.year,
      easternTime.month,
      easternTime.day,
      hour + offsetHours,
      minute,
    );
  }

  bool _isUsEasternDstUtc(DateTime utcTime) {
    final year = utcTime.year;
    final dstStartUtc = DateTime.utc(
      year,
      3,
      _nthWeekdayOfMonth(year, 3, DateTime.sunday, 2),
      7,
    );
    final dstEndUtc = DateTime.utc(
      year,
      11,
      _nthWeekdayOfMonth(year, 11, DateTime.sunday, 1),
      6,
    );
    return !utcTime.isBefore(dstStartUtc) && utcTime.isBefore(dstEndUtc);
  }

  bool _isUsEasternDstLocal(int year, int month, int day) {
    final dstStartDay = _nthWeekdayOfMonth(year, 3, DateTime.sunday, 2);
    final dstEndDay = _nthWeekdayOfMonth(year, 11, DateTime.sunday, 1);

    if (month < 3 || month > 11) return false;
    if (month > 3 && month < 11) return true;
    if (month == 3) return day >= dstStartDay;
    return day < dstEndDay;
  }

  int _nthWeekdayOfMonth(int year, int month, int weekday, int nth) {
    final firstDay = DateTime(year, month, 1);
    final delta = (weekday - firstDay.weekday + 7) % 7;
    return 1 + delta + (nth - 1) * 7;
  }

  String _slotId(DateTime slot) =>
      '${_isUsScope ? 'US' : 'CN'} ${slot.year}-${slot.month.toString().padLeft(2, '0')}-${slot.day.toString().padLeft(2, '0')} ${slot.hour.toString().padLeft(2, '0')}:${slot.minute.toString().padLeft(2, '0')}';

  bool _isValidHoldingQuantity(int quantity) {
    if (_isUsScope) {
      return quantity > 0;
    }
    return quantity > 0 && quantity % 100 == 0;
  }

  String _holdingQuantityErrorText() {
    if (_isUsScope) {
      return _message('持仓数量必须大于 0', 'Holding quantity must be greater than 0');
    }
    return _message(
      '持仓数量必须大于 0 且为 100 股的整数倍',
      'Holding quantity must be greater than 0 and in lots of 100 shares',
    );
  }

  Future<List<StockSearchItem>> _searchUsStocks(
    String query, {
    required int limit,
  }) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return [];

    final resp = await _dio.get(
      'https://finnhub.io/api/v1/search',
      queryParameters: {'q': keyword, 'token': _finnhubApiKey},
    );

    final data = resp.data;
    if (data is! Map) {
      throw Exception('US stock search returned an unexpected payload');
    }

    final raw = (data['result'] as List<dynamic>? ?? const []);
    return raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((e) {
          final symbol = (e['symbol'] ?? '').toString().trim();
          final description = (e['description'] ?? '').toString().trim();
          return symbol.isNotEmpty && description.isNotEmpty;
        })
        .map(
          (e) => StockSearchItem(
            code: (e['symbol'] ?? '').toString().trim().toUpperCase(),
            name: (e['description'] ?? '').toString().trim(),
            exchange: _inferUsExchange(e),
          ),
        )
        .where((e) => RegExp(r'^[A-Z][A-Z0-9.\-]{0,9}$').hasMatch(e.code))
        .take(limit)
        .toList();
  }

  String _inferUsExchange(Map<String, dynamic> raw) {
    final exchange = (raw['exchange'] ?? raw['mic'] ?? '').toString().trim();
    if (exchange.isNotEmpty) return exchange.toUpperCase();
    return 'US';
  }

  Future<StockPosition> _refreshUsQuote(StockPosition position) async {
    try {
      final resp = await _dio.get(
        'https://finnhub.io/api/v1/quote',
        queryParameters: {'symbol': position.code, 'token': _finnhubApiKey},
      );

      final data = resp.data;
      if (data is! Map) {
        throw Exception('US quote returned an unexpected payload');
      }

      final latestPrice = (data['c'] as num?)?.toDouble();
      final changePercent = (data['dp'] as num?)?.toDouble();
      final timestampSec = (data['t'] as num?)?.toInt();
      final updatedAt = timestampSec == null || timestampSec <= 0
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(timestampSec * 1000);

      if (latestPrice == null || latestPrice <= 0) {
        throw Exception('US quote missing current price');
      }

      return position.copyWith(
        latestPrice: latestPrice,
        changePercent: changePercent,
        quoteUpdatedAt: updatedAt,
        quoteStatus: StockQuoteStatus.normal,
        updatedAt: DateTime.now(),
      );
    } catch (_) {
      return position.copyWith(
        quoteStatus: position.latestPrice == null
            ? StockQuoteStatus.loading
            : StockQuoteStatus.stale,
        updatedAt: DateTime.now(),
      );
    }
  }
}
