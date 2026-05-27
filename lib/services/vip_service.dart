import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../app/app_flavor.dart';
import 'config_service.dart';
import 'cloud_service.dart';
import 'funnel_analytics_service.dart';

enum VipType { none, monthly, yearly, lifetime }

enum VipStoreProvider { appStore, googlePlay, huawei }

const String kVipMonthlyProductIdIos = 'com.phil.AIAccountant.mon';
const String kVipYearlyProductIdIos = 'com.phil.AIAccountant.year';
const String kVipMonthlyProductIdGooglePlay = 'ai_wealth_tracker_monthly';
const String kVipYearlyProductIdGooglePlay = 'ai_wealth_tracker_yearly';
const String kVipMonthlyProductIdHuawei = 'ai_wealth_tracker_monthly';
const String kVipYearlyProductIdHuawei = 'ai_wealth_tracker_yearly';
const String kVipLifetimeAdFreeProductIdHuawei =
    'ai_wealth_tracker_lifetime_ad_free';

VipStoreProvider resolveVipStoreProvider({
  TargetPlatform? platform,
  AppFlavor? flavor,
}) {
  final effectivePlatform = platform ?? defaultTargetPlatform;
  if (effectivePlatform == TargetPlatform.iOS) return VipStoreProvider.appStore;
  if (effectivePlatform == TargetPlatform.android) {
    return (flavor ?? AppFlavorX.current) == AppFlavor.cn
        ? VipStoreProvider.huawei
        : VipStoreProvider.googlePlay;
  }
  return VipStoreProvider.appStore;
}

String resolveVipProductId({
  required VipType type,
  TargetPlatform? platform,
  AppFlavor? flavor,
}) {
  final provider = resolveVipStoreProvider(platform: platform, flavor: flavor);
  if (type == VipType.monthly) {
    return switch (provider) {
      VipStoreProvider.huawei => kVipMonthlyProductIdHuawei,
      VipStoreProvider.googlePlay => kVipMonthlyProductIdGooglePlay,
      VipStoreProvider.appStore => kVipMonthlyProductIdIos,
    };
  }
  if (type == VipType.yearly) {
    return switch (provider) {
      VipStoreProvider.huawei => kVipYearlyProductIdHuawei,
      VipStoreProvider.googlePlay => kVipYearlyProductIdGooglePlay,
      VipStoreProvider.appStore => kVipYearlyProductIdIos,
    };
  }
  if (type == VipType.lifetime) {
    return kVipLifetimeAdFreeProductIdHuawei;
  }
  return resolveVipProductId(
    type: VipType.monthly,
    platform: platform,
    flavor: flavor,
  );
}

VipType? resolveVipProductIdFromPurchaseId(String productId) {
  if (productId == kVipMonthlyProductIdIos ||
      productId == kVipMonthlyProductIdGooglePlay ||
      productId == kVipMonthlyProductIdHuawei) {
    return VipType.monthly;
  }
  if (productId == kVipYearlyProductIdIos ||
      productId == kVipYearlyProductIdGooglePlay ||
      productId == kVipYearlyProductIdHuawei) {
    return VipType.yearly;
  }
  if (productId == kVipLifetimeAdFreeProductIdHuawei) {
    return VipType.lifetime;
  }
  return null;
}

bool shouldTreatAsExpiredEntitlement({
  required String? phone,
  required int expireMs,
  int? nowMs,
}) {
  if (phone == null || phone.isEmpty || phone == 'DemoAccount') {
    return false;
  }
  if (expireMs <= 0) return false;
  return (nowMs ?? DateTime.now().millisecondsSinceEpoch) > expireMs;
}

abstract class VipInAppPurchaseGateway {
  Stream<List<PurchaseDetails>> get purchaseStream;
  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers);
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam});
  Future<void> restorePurchases({String? applicationUserName});
  Future<void> completePurchase(PurchaseDetails purchase);
}

class _DefaultVipInAppPurchaseGateway implements VipInAppPurchaseGateway {
  final InAppPurchase _iap = InAppPurchase.instance;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers) =>
      _iap.queryProductDetails(identifiers);

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) =>
      _iap.buyNonConsumable(purchaseParam: purchaseParam);

  @override
  Future<void> restorePurchases({String? applicationUserName}) =>
      _iap.restorePurchases(applicationUserName: applicationUserName);

  @override
  Future<void> completePurchase(PurchaseDetails purchase) =>
      _iap.completePurchase(purchase);
}

class VipService extends ChangeNotifier {
  static const _keyVipType = 'vip_type';
  static const _keyVipExpireMs = 'vip_expire_ms';
  static const _keyLastProcessedTransactionDate =
      'last_processed_transaction_date';
  static const _keyLastProcessedPurchaseSignature =
      'last_processed_purchase_signature';
  static const _keyLastReceiptData = 'last_receipt_data';
  static const _keyLastReceiptSource = 'last_receipt_source';
  static const _keyLastReceiptSignature = 'last_receipt_signature';
  static const _keyLastProductId = 'last_product_id';
  static const _keyLastTransactionId = 'last_transaction_id';
  static const _keyLastOriginalTransactionId = 'last_original_transaction_id';
  static const _keyLastAppAccountToken = 'last_app_account_token';
  static const _receiptChannel = MethodChannel(
    'com.aiaccounting/app_store_receipt',
  );

  final SharedPreferences _prefs;
  final VipInAppPurchaseGateway _iap;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  Future<void> _purchaseProcessingQueue = Future.value();
  Timer? _expiryTimer;

  String? _lastSnapshotPhone;
  int _lastSnapshotExpireMs = 0;
  bool _lastSnapshotIsVip = false;

  VipService(
    this._prefs, [
    FunnelAnalyticsService? analyticsService,
    VipInAppPurchaseGateway? inAppPurchaseGateway,
  ]) : _analyticsService = analyticsService ?? FunnelAnalyticsService(_prefs),
       _iap = inAppPurchaseGateway ?? _DefaultVipInAppPurchaseGateway();

  final FunnelAnalyticsService _analyticsService;
  String? get _currentPhone {
    final phone = _prefs.getString('logged_in_phone')?.trim();
    if (phone == null || phone.isEmpty) return null;
    return phone;
  }

  bool get _hasVipContext {
    final phone = _currentPhone;
    return phone != null && phone != 'DemoAccount';
  }

  String? get _appAccountToken {
    final phone = _currentPhone;
    if (phone == null || phone == 'DemoAccount') return null;

    // Store notifications can echo appAccountToken back to the backend. Use a
    // deterministic UUID-shaped hash so the phone number itself never leaves us.
    final digest = sha256
        .convert(utf8.encode('ai_wealth_tracker:$phone'))
        .bytes;
    final bytes = List<int>.from(digest.take(16));
    bytes[6] = (bytes[6] & 0x0f) | 0x50;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return [
      hex.substring(0, 8),
      hex.substring(8, 12),
      hex.substring(12, 16),
      hex.substring(16, 20),
      hex.substring(20, 32),
    ].join('-');
  }

  String _phoneSuffix(String phone) =>
      phone.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');

  String _scopedKey(String baseKey, String phone) =>
      '${baseKey}_${_phoneSuffix(phone)}';

  String? _getScopedString(String baseKey) {
    final phone = _currentPhone;
    if (phone == null) return null;
    _migrateLegacyKeysIfNeeded(phone);
    return _prefs.getString(_scopedKey(baseKey, phone));
  }

  int _getScopedInt(String baseKey) {
    final phone = _currentPhone;
    if (phone == null) return 0;
    _migrateLegacyKeysIfNeeded(phone);
    return _prefs.getInt(_scopedKey(baseKey, phone)) ?? 0;
  }

  Future<void> _setScopedString(String baseKey, String value) async {
    final phone = _currentPhone;
    if (phone == null) return;
    await _prefs.setString(_scopedKey(baseKey, phone), value);
  }

  Future<void> _setScopedInt(String baseKey, int value) async {
    final phone = _currentPhone;
    if (phone == null) return;
    await _prefs.setInt(_scopedKey(baseKey, phone), value);
  }

  Future<void> _removeScopedKey(String baseKey) async {
    final phone = _currentPhone;
    if (phone == null) return;
    await _prefs.remove(_scopedKey(baseKey, phone));
  }

  void _migrateLegacyKeysIfNeeded(String phone) {
    final vipTypeKey = _scopedKey(_keyVipType, phone);
    final vipExpireKey = _scopedKey(_keyVipExpireMs, phone);
    final lastTxKey = _scopedKey(_keyLastProcessedTransactionDate, phone);

    if (!_prefs.containsKey(vipTypeKey) && _prefs.containsKey(_keyVipType)) {
      final legacyType = _prefs.getString(_keyVipType);
      if (legacyType != null && legacyType.isNotEmpty) {
        _prefs.setString(vipTypeKey, legacyType);
      }
    }

    if (!_prefs.containsKey(vipExpireKey) &&
        _prefs.containsKey(_keyVipExpireMs)) {
      final legacyExpire = _prefs.getInt(_keyVipExpireMs);
      if (legacyExpire != null && legacyExpire > 0) {
        _prefs.setInt(vipExpireKey, legacyExpire);
      }
    }

    if (!_prefs.containsKey(lastTxKey) &&
        _prefs.containsKey(_keyLastProcessedTransactionDate)) {
      final legacyLastTx = _prefs.getInt(_keyLastProcessedTransactionDate);
      if (legacyLastTx != null && legacyLastTx > 0) {
        _prefs.setInt(lastTxKey, legacyLastTx);
      }
    }
  }

  bool _isVipByExpireMs(int expireMs) {
    if (!_hasVipContext || expireMs <= 0) return false;
    return DateTime.now().millisecondsSinceEpoch < expireMs;
  }

  void _refreshSnapshot({bool notify = false}) {
    final phone = _currentPhone;
    final expireMs = _hasVipContext ? _getScopedInt(_keyVipExpireMs) : 0;
    final isVipNow = _isVipByExpireMs(expireMs);

    final changed =
        phone != _lastSnapshotPhone ||
        expireMs != _lastSnapshotExpireMs ||
        isVipNow != _lastSnapshotIsVip;

    _lastSnapshotPhone = phone;
    _lastSnapshotExpireMs = expireMs;
    _lastSnapshotIsVip = isVipNow;

    _scheduleExpiryNotification(expireMs);

    if (notify && changed) {
      notifyListeners();
    }
  }

  void _scheduleExpiryNotification([int? expireMs]) {
    _expiryTimer?.cancel();

    final targetExpireMs =
        expireMs ?? (_hasVipContext ? _getScopedInt(_keyVipExpireMs) : 0);
    if (targetExpireMs <= 0) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final delayMs = targetExpireMs - nowMs + 500;
    if (delayMs <= 0) return;

    _expiryTimer = Timer(Duration(milliseconds: delayMs), () {
      _refreshSnapshot(notify: true);
    });
  }

  /// 初始化购买监听，必须在 app 启动后尽早调用
  Future<void> init() async {
    _expiryTimer?.cancel();
    _refreshSnapshot();
    _purchaseSubscription?.cancel();
    _purchaseProcessingQueue = Future.value();
    _purchaseSubscription = _iap.purchaseStream.listen((purchases) {
      final batch = List<PurchaseDetails>.of(purchases);
      _purchaseProcessingQueue = _purchaseProcessingQueue
          .then((_) => _handlePurchaseBatch(batch))
          .catchError((Object e, StackTrace stackTrace) {
            debugPrint('[VipService] purchase queue error: $e');
            debugPrint('[VipService] purchase queue stack: $stackTrace');
          });
    });
  }

  Future<void> _handlePurchaseBatch(List<PurchaseDetails> purchases) async {
    debugPrint('[VipService] ========================================');
    debugPrint(
      '[VipService] purchaseStream received ${purchases.length} purchases',
    );
    for (final p in purchases) {
      debugPrint('[VipService] - productID=${p.productID}, status=${p.status}');
      if (p.status == PurchaseStatus.purchased) {
        debugPrint('[VipService] stream received purchased: ${p.productID}');
        await _processPurchase(p);
        await _analyticsService.track(
          'subscription_purchased',
          properties: {'product_id': p.productID},
        );
        debugPrint('[VipService] calling notifyListeners...');
        notifyListeners(); // 通知 UI 刷新 VIP 状态
      } else if (p.status == PurchaseStatus.restored) {
        debugPrint('[VipService] stream received restored: ${p.productID}');
        await _processPurchase(p);
        await _analyticsService.track(
          'subscription_restored',
          properties: {'product_id': p.productID},
        );
        notifyListeners();
      } else {
        debugPrint('[VipService] ⚠️  忽略 status=${p.status}');
        await _analyticsService.track(
          'subscription_purchase_status',
          properties: {'product_id': p.productID, 'status': p.status.name},
        );
      }
    }
    debugPrint('[VipService] ========================================');
  }

  Future<void> _processPurchase(PurchaseDetails p) async {
    final id = p.productID;
    debugPrint('[VipService] ========================================');
    debugPrint('[VipService] _processPurchase called');
    debugPrint('[VipService] productID=$id');
    debugPrint('[VipService] status=${p.status}');
    debugPrint('[VipService] transactionDate=${p.transactionDate}');
    debugPrint(
      '[VipService] verificationData present=${p.verificationData.serverVerificationData.isNotEmpty}',
    );
    debugPrint('[VipService] error=${p.error}');
    debugPrint(
      '[VipService] pendingCompletePurchase=${p.pendingCompletePurchase}',
    );

    if (!_hasVipContext) {
      debugPrint('[VipService] ⚠️  当前没有可绑定会员的手机号，跳过处理');
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
      debugPrint('[VipService] ========================================');
      return;
    }

    final type = resolveVipProductIdFromPurchaseId(id);

    final transactionMs = _parseTransactionMs(p.transactionDate);
    final lastProcessedMs = _getScopedInt(_keyLastProcessedTransactionDate);
    final lastProcessedSignature = _getScopedString(
      _keyLastProcessedPurchaseSignature,
    );
    final receiptData = await _resolveReceiptData(p);
    if (receiptData.isNotEmpty) {
      await _setScopedString(_keyLastReceiptData, receiptData);
      debugPrint('[VipService] ✅ 缓存 receiptData，len=${receiptData.length}');
    }
    final receiptSource = p.verificationData.source;
    final receiptSignature = p.verificationData.localVerificationData;
    if (receiptSource.isNotEmpty) {
      await _setScopedString(_keyLastReceiptSource, receiptSource);
    }
    if (receiptSignature.isNotEmpty) {
      await _setScopedString(_keyLastReceiptSignature, receiptSignature);
    }
    if (id.isNotEmpty) {
      await _setScopedString(_keyLastProductId, id);
    }
    final transactionId = p.purchaseID ?? '';
    final appAccountToken = _appAccountToken;
    if (transactionId.isNotEmpty) {
      await _setScopedString(_keyLastTransactionId, transactionId);
    }
    if (appAccountToken != null) {
      await _setScopedString(_keyLastAppAccountToken, appAccountToken);
    }
    final purchaseSignature = [
      id,
      p.status.name,
      p.transactionDate ?? '',
      transactionId,
    ].join('|');

    debugPrint(
      '[VipService] 交易日期检查: hasTransactionDate=${p.transactionDate?.isNotEmpty == true}, transactionMs=$transactionMs, lastProcessedMs=$lastProcessedMs, hasLastSignature=${lastProcessedSignature?.isNotEmpty == true}',
    );

    final isRestorePurchase = p.status == PurchaseStatus.restored;
    final currentTypeStr = _getScopedString(_keyVipType);
    final incomingTypeStr = switch (type) {
      VipType.monthly => 'monthly',
      VipType.yearly => 'yearly',
      VipType.lifetime => 'lifetime',
      _ => null,
    };

    if (!isRestorePurchase &&
        lastProcessedSignature != null &&
        lastProcessedSignature == purchaseSignature) {
      debugPrint('[VipService] ⏭️  跳过重复购买签名');
      await _refreshEntitlementAfterSkippedPurchase(
        receiptData: receiptData.isNotEmpty ? receiptData : null,
        receiptSource: receiptSource.isNotEmpty ? receiptSource : null,
        receiptSignature: receiptSignature.isNotEmpty ? receiptSignature : null,
        productId: id.isNotEmpty ? id : null,
        transactionId: transactionId.isNotEmpty ? transactionId : null,
        appAccountToken: appAccountToken,
      );
      if (p.pendingCompletePurchase) {
        debugPrint('[VipService] 📝 清理重复交易，调用 completePurchase...');
        await _iap.completePurchase(p);
        debugPrint('[VipService] ✅ 重复交易清理完成');
      }
      debugPrint('[VipService] ========================================');
      return;
    }

    if (!isRestorePurchase &&
        transactionMs != null &&
        transactionMs <= lastProcessedMs &&
        incomingTypeStr != null &&
        incomingTypeStr == currentTypeStr) {
      debugPrint('[VipService] ⏭️  跳过旧交易（已处理过）');
      await _refreshEntitlementAfterSkippedPurchase(
        receiptData: receiptData.isNotEmpty ? receiptData : null,
        receiptSource: receiptSource.isNotEmpty ? receiptSource : null,
        receiptSignature: receiptSignature.isNotEmpty ? receiptSignature : null,
        productId: id.isNotEmpty ? id : null,
        transactionId: transactionId.isNotEmpty ? transactionId : null,
        appAccountToken: appAccountToken,
      );
      if (p.pendingCompletePurchase) {
        debugPrint('[VipService] 📝 清理旧交易，调用 completePurchase...');
        await _iap.completePurchase(p);
        debugPrint('[VipService] ✅ 旧交易清理完成');
      }
      debugPrint('[VipService] ========================================');
      return;
    }

    if (transactionMs != null && transactionMs > lastProcessedMs) {
      await _setScopedInt(_keyLastProcessedTransactionDate, transactionMs);
      debugPrint('[VipService] ✅ 记录交易日期: $transactionMs');
    }
    await _setScopedString(
      _keyLastProcessedPurchaseSignature,
      purchaseSignature,
    );
    debugPrint('[VipService] ✅ 记录购买签名');
    debugPrint('[VipService] mapped type=$type');

    if (type != null) {
      final transactionDate = transactionMs != null
          ? DateTime.fromMillisecondsSinceEpoch(transactionMs)
          : null;
      final platformExpireDate = _parsePlatformExpirationDate(p);
      debugPrint(
        '[VipService] ⚠️  即将调用 _activateVip($type, isRestore=${p.status == PurchaseStatus.restored}, transactionDate=$transactionDate, platformExpireDate=$platformExpireDate)',
      );
      await _activateVip(
        type,
        transactionDate: transactionDate,
        platformExpireDate: platformExpireDate,
        isRestore: p.status == PurchaseStatus.restored,
        receiptData: receiptData.isNotEmpty ? receiptData : null,
        receiptSource: receiptSource.isNotEmpty ? receiptSource : null,
        receiptSignature: receiptSignature.isNotEmpty ? receiptSignature : null,
        productId: id.isNotEmpty ? id : null,
        transactionId: transactionId.isNotEmpty ? transactionId : null,
        appAccountToken: appAccountToken,
      );

      // restore 场景下，最终再强制以云端为准。
      // 原因：store restored 可能先给出 TestFlight/sandbox 的本地日期，
      // 即使后端已拒绝错误覆盖，本地也可能被 restore 临时写脏。
      if (isRestorePurchase) {
        try {
          await syncFromCloud();
          debugPrint(
            '[VipService] restore flow: forced syncFromCloud after _activateVip',
          );
        } catch (e) {
          debugPrint(
            '[VipService] restore flow: syncFromCloud after _activateVip error: $e',
          );
        }
      }
    } else {
      debugPrint('[VipService] ⚠️  type 为 null，不调用 _activateVip');
    }

    if (p.pendingCompletePurchase) {
      debugPrint('[VipService] 📝 调用 completePurchase...');
      await _iap.completePurchase(p);
      debugPrint('[VipService] ✅ completePurchase 完成');
    }

    debugPrint('[VipService] ========================================');
  }

  bool get isVip {
    _refreshSnapshot();
    return _isVipByExpireMs(_getScopedInt(_keyVipExpireMs));
  }

  bool get isLoggedIn =>
      _prefs.getString('logged_in_phone')?.isNotEmpty == true;

  VipType get vipType {
    _refreshSnapshot();
    final typeStr = _getScopedString(_keyVipType);
    if (typeStr == 'monthly') return VipType.monthly;
    if (typeStr == 'yearly') return VipType.yearly;
    if (typeStr == 'lifetime') return VipType.lifetime;
    return VipType.none;
  }

  DateTime? get expireDate {
    _refreshSnapshot();
    final ms = _getScopedInt(_keyVipExpireMs);
    if (ms == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  bool get removesAds => isVip;

  Future<ProductDetailsResponse> queryVipProductDetails() async {
    if (resolveVipStoreProvider() == VipStoreProvider.huawei) {
      return _iap.queryProductDetails({
        resolveVipProductId(type: VipType.lifetime),
      });
    }
    final ids = {
      resolveVipProductId(type: VipType.monthly),
      resolveVipProductId(type: VipType.yearly),
    };
    return _iap.queryProductDetails(ids);
  }

  /// 购买月度会员
  Future<bool> purchaseMonthly() async {
    return _purchase(
      resolveVipProductId(type: VipType.monthly),
      VipType.monthly,
    );
  }

  /// 购买年度会员
  Future<bool> purchaseYearly() async {
    return _purchase(resolveVipProductId(type: VipType.yearly), VipType.yearly);
  }

  /// 购买终身去广告
  Future<bool> purchaseLifetimeAdFree() async {
    return _purchase(
      resolveVipProductId(type: VipType.lifetime),
      VipType.lifetime,
    );
  }

  /// 购买：发起支付后监听平台返回结果
  /// buyNonConsumable 返回 true 只表示请求发出，购买结果通过 stream 异步通知
  Future<bool> _purchase(String productId, VipType type) async {
    try {
      debugPrint('[VipService] ========================================');
      debugPrint('[VipService] _purchase START');
      debugPrint('[VipService] productId=$productId');
      debugPrint('[VipService] type=$type');
      debugPrint(
        '[VipService] 当前 VIP 状态: isVip=$isVip, vipType=$vipType, expireDate=$expireDate',
      );
      debugPrint('[VipService] ========================================');

      final products = await _iap.queryProductDetails({productId});
      debugPrint(
        '[VipService] queryProductDetails: ${products.productDetails.length} found',
      );
      if (products.notFoundIDs.isNotEmpty) {
        debugPrint(
          '[VipService] notFoundIDs=${products.notFoundIDs.join(',')}',
        );
      }
      if (products.productDetails.isEmpty) {
        debugPrint('[VipService] ❌ 未找到商品 $productId');
        return false;
      }

      final product = products.productDetails.first;
      debugPrint(
        '[VipService] 商品详情: id=${product.id}, title=${product.title}, price=${product.price}, currencyCode=${product.currencyCode}, rawPrice=${product.rawPrice}',
      );
      await _analyticsService.track(
        'subscription_purchase_requested',
        properties: {
          'product_id': productId,
          'plan': type.name,
          'price': product.price,
        },
      );

      debugPrint('[VipService] 📱 即将调用 buyNonConsumable，应该弹出平台支付窗口...');
      final appAccountToken = _appAccountToken;
      if (appAccountToken != null) {
        await _setScopedString(_keyLastAppAccountToken, appAccountToken);
      }
      final result = await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(
          productDetails: product,
          applicationUserName: appAccountToken,
        ),
      );
      debugPrint('[VipService] buyNonConsumable 返回结果: $result');
      await _analyticsService.track(
        result
            ? 'subscription_purchase_started'
            : 'subscription_purchase_not_started',
        properties: {'product_id': productId, 'plan': type.name},
      );
      if (result) {
        unawaited(_refreshEntitlementAfterPurchaseStart(appAccountToken));
      }
      debugPrint('[VipService] _purchase END');
      debugPrint('[VipService] ========================================');

      return result;
    } catch (e, stackTrace) {
      debugPrint('[VipService] ❌ Purchase error: $e');
      debugPrint('[VipService] Stack trace: $stackTrace');
      return false;
    }
  }

  Future<void> _refreshEntitlementAfterSkippedPurchase({
    String? receiptData,
    String? receiptSource,
    String? receiptSignature,
    String? productId,
    String? transactionId,
    String? appAccountToken,
  }) async {
    try {
      debugPrint('[VipService] refresh skipped purchase from platform receipt');
      await pushToCloud(
        receiptData: receiptData,
        receiptSource: receiptSource,
        receiptSignature: receiptSignature,
        productId: productId,
        transactionId: transactionId,
        appAccountToken: appAccountToken,
      );
      await refreshFromAppStoreServer(transactionId: transactionId);
      await syncFromCloud();
    } catch (e) {
      debugPrint('[VipService] skipped purchase refresh error: $e');
    }
  }

  Future<void> _refreshEntitlementAfterPurchaseStart(
    String? appAccountToken,
  ) async {
    for (final delay in const [Duration(seconds: 3), Duration(seconds: 10)]) {
      await Future<void>.delayed(delay);
      if (!_hasVipContext) return;
      try {
        final receiptData = await _fetchIosAppStoreReceiptData();
        if (receiptData != null && receiptData.isNotEmpty) {
          await _setScopedString(_keyLastReceiptData, receiptData);
        }
        debugPrint('[VipService] delayed post-purchase entitlement refresh');
        await pushToCloud(
          receiptData: receiptData,
          appAccountToken: appAccountToken,
        );
        final refreshed = await refreshFromAppStoreServer();
        if (!refreshed) {
          await syncFromCloud();
        }
      } catch (e) {
        debugPrint('[VipService] delayed post-purchase refresh error: $e');
      }
    }
  }

  Future<void> _activateVip(
    VipType type, {
    DateTime? transactionDate,
    DateTime? platformExpireDate,
    bool isRestore = false,
    String? receiptData,
    String? receiptSource,
    String? receiptSignature,
    String? productId,
    String? transactionId,
    String? originalTransactionId,
    String? appAccountToken,
  }) async {
    final now = DateTime.now();
    debugPrint('[VipService] ========================================');
    debugPrint('[VipService] _activateVip START');
    debugPrint('[VipService] type=$type');
    debugPrint('[VipService] now=$now');
    debugPrint('[VipService] transactionDate=$transactionDate');
    debugPrint('[VipService] platformExpireDate=$platformExpireDate');
    debugPrint('[VipService] isRestore=$isRestore');

    final existingExpireMs = _getScopedInt(_keyVipExpireMs);
    final existingExpireDate = existingExpireMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(existingExpireMs)
        : null;
    debugPrint('[VipService] existingExpireMs=$existingExpireMs');
    debugPrint('[VipService] existingExpireDate=$existingExpireDate');

    late final DateTime expireDate;

    if (platformExpireDate != null) {
      expireDate = platformExpireDate;
      debugPrint('[VipService] 平台返回到期时间，直接采用：$expireDate');
    } else if (type == VipType.lifetime) {
      expireDate = _calculateExpireDate(type, transactionDate ?? now);
      debugPrint('[VipService] 终身权益：采用远期有效期：$expireDate');
    } else if (isRestore) {
      final restoredBaseDate = transactionDate ?? now;
      final restoredExpireDate = _calculateExpireDate(type, restoredBaseDate);
      debugPrint(
        '[VipService] 恢复购买：按交易时间恢复，restoredBaseDate=$restoredBaseDate → restoredExpireDate=$restoredExpireDate',
      );

      // 恢复购买时直接信任平台返回的交易时间，
      // 不再保留本地“更晚”的旧错误日期，避免把曾经错误算出来的到期日一直沿用。
      expireDate = restoredExpireDate;
      debugPrint('[VipService] 恢复购买：直接采用平台恢复出的到期时间：$expireDate');
    } else {
      final DateTime baseDate;
      if (existingExpireDate != null && now.isBefore(existingExpireDate)) {
        baseDate = existingExpireDate;
        debugPrint('[VipService] 续费：从现有到期时间 $baseDate 开始叠加');
      } else {
        baseDate = transactionDate ?? now;
        debugPrint('[VipService] 新开通：从交易时间/当前时间 $baseDate 开始算');
      }
      expireDate = _calculateExpireDate(type, baseDate);
      debugPrint(
        '[VipService] 新购/续费：baseDate=$baseDate → expireDate=$expireDate',
      );
    }

    final expireMs = expireDate.millisecondsSinceEpoch;
    debugPrint('[VipService] 最终到期时间=$expireDate, expireMs=$expireMs');

    await _setScopedString(_keyVipType, switch (type) {
      VipType.monthly => 'monthly',
      VipType.yearly => 'yearly',
      VipType.lifetime => 'lifetime',
      VipType.none => '',
    });
    await _setScopedInt(_keyVipExpireMs, expireMs);

    // 购买/恢复成功后尝试同步到云端（失败不阻塞）
    var syncedToCloud = false;
    try {
      syncedToCloud = await pushToCloud(
        receiptData: receiptData,
        receiptSource: receiptSource,
        receiptSignature: receiptSignature,
        productId: productId,
        transactionId: transactionId,
        originalTransactionId: originalTransactionId,
        appAccountToken: appAccountToken,
      );
    } catch (e) {
      debugPrint(
        '[VipService] _activateVip: pushToCloud error (non-fatal): $e',
      );
    }
    _refreshSnapshot(notify: true);
    if (!syncedToCloud) {
      debugPrint('[VipService] _activateVip: using local fallback expiry');
    }

    debugPrint('[VipService] _activateVip END');
    debugPrint('[VipService] ========================================');
  }

  int? _parseTransactionMs(String? raw) {
    if (raw == null || raw.isEmpty) return null;

    final asInt = int.tryParse(raw);
    if (asInt != null) {
      if (raw.length >= 13) return asInt;
      if (raw.length >= 10) return asInt * 1000;
      return asInt;
    }

    final asDate = DateTime.tryParse(raw);
    return asDate?.millisecondsSinceEpoch;
  }

  DateTime? _parsePlatformExpirationDate(PurchaseDetails purchase) {
    if (purchase.verificationData.source != 'huawei_iap') return null;
    try {
      final raw = jsonDecode(purchase.verificationData.serverVerificationData);
      if (raw is! Map<String, dynamic>) return null;
      final expirationMs = raw['expirationDate'];
      if (expirationMs is! int || expirationMs <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(expirationMs);
    } catch (error) {
      debugPrint('[VipService] parse Huawei expirationDate failed: $error');
      return null;
    }
  }

  String _storeProviderName() {
    return switch (resolveVipStoreProvider()) {
      VipStoreProvider.huawei => 'huawei',
      VipStoreProvider.googlePlay => 'google_play',
      VipStoreProvider.appStore => 'app_store',
    };
  }

  DateTime _calculateExpireDate(VipType type, DateTime baseDate) {
    if (type == VipType.lifetime) {
      return DateTime(2099, 12, 31, 23, 59, 59);
    }
    if (type == VipType.monthly) {
      return DateTime(baseDate.year, baseDate.month + 1, baseDate.day);
    }
    return DateTime(baseDate.year + 1, baseDate.month, baseDate.day);
  }

  /// 恢复购买
  Future<void> restorePurchases() async {
    try {
      if (!_hasVipContext) {
        debugPrint(
          '[VipService] restorePurchases skipped: no real logged-in phone',
        );
        _refreshSnapshot(notify: true);
        return;
      }
      debugPrint(
        '[VipService] restorePurchases() called, hasVipContext=$_hasVipContext',
      );
      _refreshSnapshot();
      final appAccountToken = _appAccountToken;
      if (appAccountToken != null) {
        await _setScopedString(_keyLastAppAccountToken, appAccountToken);
      }
      await _iap.restorePurchases(applicationUserName: appAccountToken);

      final nativeReceiptData = await _fetchIosAppStoreReceiptData();
      if (nativeReceiptData != null && nativeReceiptData.isNotEmpty) {
        await _setScopedString(_keyLastReceiptData, nativeReceiptData);
      }

      final cachedReceiptData =
          nativeReceiptData ?? _getScopedString(_keyLastReceiptData);
      if (cachedReceiptData != null &&
          cachedReceiptData.isNotEmpty &&
          _getScopedInt(_keyVipExpireMs) >
              DateTime.now().millisecondsSinceEpoch) {
        debugPrint(
          '[VipService] restorePurchases fallback: push cached receipt to cloud, len=${cachedReceiptData.length}',
        );
        await pushToCloud(
          receiptData: cachedReceiptData,
          appAccountToken: appAccountToken,
        );
      }
    } catch (e) {
      debugPrint('Restore error: $e');
    }
  }

  /// 从云端拉取 VIP 档案（云端为权威）
  /// 用于：App 启动时、登录后主动同步
  /// 返回 true=同步成功（可能没变化），false=网络错误/未配置
  Future<bool> syncFromCloud() async {
    if (!_hasVipContext) {
      debugPrint('[VipService] syncFromCloud skipped: no real logged-in phone');
      return false;
    }

    if (!ConfigService.instance.isAliyunFCConfigured) {
      debugPrint('[VipService] syncFromCloud skipped: cloud not configured');
      return false;
    }

    try {
      debugPrint('[VipService] syncFromCloud: fetching from cloud...');
      final cloudProfile = await CloudService().getVipProfile();
      if (cloudProfile == null) {
        debugPrint('[VipService] syncFromCloud: no profile on cloud');
        return false;
      }

      final cloudType = cloudProfile['vip_type'] as String?;
      final cloudExpireMs = cloudProfile['vip_expire_ms'] as int?;
      final cloudVerifyStatus = cloudProfile['vip_verify_status'] as String?;
      final isServerAuthoritative =
          cloudVerifyStatus == 'app_store_notification' ||
          cloudVerifyStatus == 'app_store_server_api';
      final localType = _getScopedString(_keyVipType);
      final localExpireMs = _getScopedInt(_keyVipExpireMs);
      debugPrint(
        '[VipService] syncFromCloud: cloud profile = type=$cloudType, expire_ms=$cloudExpireMs, localType=$localType, localExpireMs=$localExpireMs',
      );

      // 云端无 VIP 档案（从未订阅过）→ 清理本地，避免普通用户误带旧缓存
      if (cloudProfile.isEmpty || cloudType == null || cloudType.isEmpty) {
        if (localExpireMs > DateTime.now().millisecondsSinceEpoch) {
          debugPrint(
            '[VipService] syncFromCloud: cloud empty but local VIP still valid, keeping local state',
          );
          _refreshSnapshot(notify: true);
          return true;
        }
        debugPrint(
          '[VipService] syncFromCloud: cloud has no VIP record, clearing local VIP',
        );
        await clearCurrentUserVipCache();
        return true;
      }

      // 云端已过期 → 拒绝写入本地（防客户端伪造过期时间）
      if (cloudExpireMs != null && cloudExpireMs > 0) {
        final cloudExpireTime = DateTime.fromMillisecondsSinceEpoch(
          cloudExpireMs,
        );
        if (cloudExpireTime.isBefore(DateTime.now())) {
          if (isServerAuthoritative) {
            debugPrint(
              '[VipService] syncFromCloud: authoritative cloud VIP expired, clearing local VIP',
            );
            await clearCurrentUserVipCache();
            return true;
          }
          if (localExpireMs > DateTime.now().millisecondsSinceEpoch) {
            debugPrint(
              '[VipService] syncFromCloud: cloud VIP expired but local VIP still valid, keeping local state',
            );
            _refreshSnapshot(notify: true);
            return true;
          }
          debugPrint(
            '[VipService] syncFromCloud: cloud VIP is expired, clearing local VIP',
          );
          await clearCurrentUserVipCache();
          return true;
        }
      }

      if (cloudExpireMs != null && cloudExpireMs > 0 && localExpireMs > 0) {
        if (!isServerAuthoritative && cloudExpireMs < localExpireMs) {
          debugPrint(
            '[VipService] syncFromCloud: ignore older cloud VIP, keep local newer expire_ms=$localExpireMs',
          );
          _refreshSnapshot(notify: true);
          return true;
        }
        if (isServerAuthoritative && cloudExpireMs < localExpireMs) {
          debugPrint(
            '[VipService] syncFromCloud: authoritative cloud VIP is shorter, updating local to server expire_ms=$cloudExpireMs',
          );
        }
      }

      // 云端有效 → 写入本地（本地以云端为准）
      await _setScopedString(_keyVipType, cloudType);
      if (cloudExpireMs != null && cloudExpireMs > 0) {
        await _setScopedInt(_keyVipExpireMs, cloudExpireMs);
      }
      final cloudTransactionId = cloudProfile['transaction_id'] as String?;
      final cloudOriginalTransactionId =
          cloudProfile['original_transaction_id'] as String?;
      final cloudAppAccountToken = cloudProfile['app_account_token'] as String?;
      if (cloudTransactionId != null && cloudTransactionId.isNotEmpty) {
        await _setScopedString(_keyLastTransactionId, cloudTransactionId);
      }
      if (cloudOriginalTransactionId != null &&
          cloudOriginalTransactionId.isNotEmpty) {
        await _setScopedString(
          _keyLastOriginalTransactionId,
          cloudOriginalTransactionId,
        );
      }
      if (cloudAppAccountToken != null && cloudAppAccountToken.isNotEmpty) {
        await _setScopedString(_keyLastAppAccountToken, cloudAppAccountToken);
      }
      _refreshSnapshot(notify: true);
      debugPrint(
        '[VipService] syncFromCloud: local updated from cloud. isVip=$isVip',
      );
      return true;
    } catch (e) {
      debugPrint('[VipService] syncFromCloud error: $e');
      return false;
    }
  }

  /// 与平台/服务端对账，完成后本地状态会以云端为准。
  ///
  /// 与方法名保留 `AppStore` 历史兼容，该分支仅用于刷新本地缓存，不代表强绑定平台提供方。
  Future<bool> refreshFromAppStoreServer({String? transactionId}) async {
    if (!_hasVipContext) {
      debugPrint(
        '[VipService] refreshFromStoreBackend skipped: no real logged-in phone',
      );
      return false;
    }

    if (!ConfigService.instance.isAliyunFCConfigured) {
      debugPrint(
        '[VipService] refreshFromStoreBackend skipped: cloud not configured',
      );
      return false;
    }

    final effectiveTransactionId =
        transactionId ??
        _getScopedString(_keyLastTransactionId) ??
        _getScopedString(_keyLastOriginalTransactionId);
    if (effectiveTransactionId == null || effectiveTransactionId.isEmpty) {
      debugPrint(
        '[VipService] refreshFromAppStoreServer skipped: no transaction id',
      );
      return false;
    }

    try {
      debugPrint('[VipService] refreshFromAppStoreServer: refreshing...');
      final refreshed = await CloudService().refreshVipProfile(
        transactionId: effectiveTransactionId,
      );
      if (refreshed == null) {
        debugPrint('[VipService] refreshFromAppStoreServer: no profile');
        return false;
      }
      await syncFromCloud();
      return true;
    } catch (e) {
      debugPrint('[VipService] refreshFromAppStoreServer error: $e');
      return false;
    }
  }

  /// 用本机平台凭据兜底刷新订阅状态。
  ///
  /// 覆盖场景：付款成功后 App 被杀、purchaseStream 未完成处理，或平台
  /// 通知先到但云端还没有完成用户映射。
  Future<bool> refreshFromLocalReceipt() async {
    if (!_hasVipContext) return false;
    if (!ConfigService.instance.isAliyunFCConfigured) return false;

    try {
      final receiptData = await _fetchIosAppStoreReceiptData();
      if (receiptData == null || receiptData.isEmpty) {
        debugPrint('[VipService] refreshFromLocalReceipt: no receipt');
        return false;
      }

      await _setScopedString(_keyLastReceiptData, receiptData);
      final pushed = await pushToCloud(
        receiptData: receiptData,
        appAccountToken: _appAccountToken,
      );
      if (!pushed) return false;

      await syncFromCloud();
      return true;
    } catch (e) {
      debugPrint('[VipService] refreshFromLocalReceipt error: $e');
      return false;
    }
  }

  /// 主动将本地 VIP 状态同步到云端
  /// 在购买成功、恢复成功后调用
  /// 如果云端返回 403（订阅已过期），清理本地并返回 false
  Future<bool> pushToCloud({
    String? receiptData,
    String? receiptSource,
    String? receiptSignature,
    String? productId,
    String? transactionId,
    String? originalTransactionId,
    String? appAccountToken,
  }) async {
    if (!_hasVipContext) return false;
    if (!ConfigService.instance.isAliyunFCConfigured) return false;

    try {
      final localType = _getScopedString(_keyVipType);
      final localExpireMs = _getScopedInt(_keyVipExpireMs);
      final effectiveReceiptData =
          receiptData ?? _getScopedString(_keyLastReceiptData);
      final effectiveReceiptSource =
          receiptSource ?? _getScopedString(_keyLastReceiptSource);
      final effectiveReceiptSignature =
          receiptSignature ?? _getScopedString(_keyLastReceiptSignature);
      final effectiveProductId =
          productId ?? _getScopedString(_keyLastProductId);
      final effectiveTransactionId =
          transactionId ?? _getScopedString(_keyLastTransactionId);
      final effectiveOriginalTransactionId =
          originalTransactionId ??
          _getScopedString(_keyLastOriginalTransactionId);
      final effectiveAppAccountToken =
          appAccountToken ?? _getScopedString(_keyLastAppAccountToken);
      // On Android, serverVerificationData may carry the Play purchase token.
      // Play purchase token still needs backend-side verification.
      final hasStoreEvidence =
          (effectiveReceiptData != null && effectiveReceiptData.isNotEmpty) ||
          (effectiveTransactionId != null &&
              effectiveTransactionId.isNotEmpty) ||
          (effectiveOriginalTransactionId != null &&
              effectiveOriginalTransactionId.isNotEmpty);

      if (localType == null || localType.isEmpty || localExpireMs <= 0) {
        if (!hasStoreEvidence) {
          debugPrint('[VipService] pushToCloud: no valid local VIP to push');
          return false;
        }
        debugPrint(
          '[VipService] pushToCloud: no local VIP, verifying store evidence',
        );
      }

      // 检查本地是否已过期（防止推广过期状态到云端）
      if (localExpireMs > 0 &&
          DateTime.now().millisecondsSinceEpoch > localExpireMs &&
          !hasStoreEvidence) {
        debugPrint(
          '[VipService] pushToCloud: local VIP already expired, clearing',
        );
        await clearCurrentUserVipCache();
        return false;
      }

      final result = await CloudService().syncVipProfile(
        vipType: localType ?? '',
        expireMs: localExpireMs,
        receiptData: effectiveReceiptData,
        receiptSource: effectiveReceiptSource,
        receiptSignature: effectiveReceiptSignature,
        storeProvider: _storeProviderName(),
        productId: effectiveProductId,
        transactionId: effectiveTransactionId,
        originalTransactionId: effectiveOriginalTransactionId,
        appAccountToken: effectiveAppAccountToken,
      );

      if (result != null) {
        debugPrint(
          '[VipService] pushToCloud: success, keys=${result.keys.toList()}',
        );
        // 云端同步后以云端为准（可能平台返回了不同的 expire_ms）
        final cloudType = result['vip_type'] as String?;
        final cloudExpireMs = result['vip_expire_ms'] as int?;
        final cloudVerifyStatus = result['vip_verify_status'] as String?;
        final isServerAuthoritative =
            cloudVerifyStatus == 'app_store_notification' ||
            cloudVerifyStatus == 'app_store_server_api';
        final cloudTransactionId = result['transaction_id'] as String?;
        final cloudOriginalTransactionId =
            result['original_transaction_id'] as String?;
        final cloudAppAccountToken = result['app_account_token'] as String?;
        if (cloudTransactionId != null && cloudTransactionId.isNotEmpty) {
          await _setScopedString(_keyLastTransactionId, cloudTransactionId);
        }
        if (cloudOriginalTransactionId != null &&
            cloudOriginalTransactionId.isNotEmpty) {
          await _setScopedString(
            _keyLastOriginalTransactionId,
            cloudOriginalTransactionId,
          );
        }
        if (cloudAppAccountToken != null && cloudAppAccountToken.isNotEmpty) {
          await _setScopedString(_keyLastAppAccountToken, cloudAppAccountToken);
        }
        if (cloudType != null && cloudExpireMs != null && cloudExpireMs > 0) {
          if (isServerAuthoritative || cloudExpireMs >= localExpireMs) {
            await _setScopedString(_keyVipType, cloudType);
            await _setScopedInt(_keyVipExpireMs, cloudExpireMs);
            debugPrint(
              '[VipService] pushToCloud: local updated from cloud, cloudExpireMs=$cloudExpireMs, authoritative=$isServerAuthoritative',
            );
          } else {
            debugPrint(
              '[VipService] pushToCloud: ignored older cloud expire_ms=$cloudExpireMs, keep localExpireMs=$localExpireMs',
            );
          }
          _refreshSnapshot(notify: true);
        }
        return true;
      } else {
        debugPrint(
          '[VipService] pushToCloud: server returned null (network error?)',
        );
        return false;
      }
    } catch (e) {
      debugPrint('[VipService] pushToCloud error: $e');
      return false;
    }
  }

  /// 是否是“已开通过会员，但当前已过期”的状态。
  ///
  /// 重要：
  /// - 游客：false（游客在 20 条内不应被会员过期逻辑拦截）
  /// - Demo：false（审核账号不应有任何限制）
  /// - 普通已登录非会员：false（50 条内应有完整功能）
  /// - 仅真实买过会员且当前 expireMs 已过期时：true
  bool get hasExpiredEntitlement {
    return shouldTreatAsExpiredEntitlement(
      phone: _currentPhone,
      expireMs: _getScopedInt(_keyVipExpireMs),
    );
  }

  Future<void> clearCurrentUserVipCache() async {
    if (_currentPhone == null) return;
    await _removeScopedKey(_keyVipType);
    await _removeScopedKey(_keyVipExpireMs);
    await _removeScopedKey(_keyLastProcessedTransactionDate);
    await _removeScopedKey(_keyLastProcessedPurchaseSignature);
    await _removeScopedKey(_keyLastReceiptData);
    await _removeScopedKey(_keyLastReceiptSource);
    await _removeScopedKey(_keyLastReceiptSignature);
    await _removeScopedKey(_keyLastProductId);
    await _removeScopedKey(_keyLastTransactionId);
    await _removeScopedKey(_keyLastOriginalTransactionId);
    await _removeScopedKey(_keyLastAppAccountToken);
    _refreshSnapshot(notify: true);
  }

  /// 🔧 调试工具：打印当前 VIP 状态（用于排查问题）
  void debugPrintVipStatus() {
    debugPrint('[VipService] 🔍 ====== VIP 状态调试 ======');
    debugPrint('[VipService] hasVipContext: $_hasVipContext');
    debugPrint('[VipService] isVip: $isVip');
    debugPrint('[VipService] vipType: $vipType');
    debugPrint('[VipService] expireDate: $expireDate');
    debugPrint('[VipService] expireMs: ${_getScopedInt(_keyVipExpireMs)}');
    debugPrint('[VipService] vipTypeStr: ${_getScopedString(_keyVipType)}');
    debugPrint('[VipService] 🔍 ==========================');
  }

  /// 🔧 调试工具：重置 VIP 状态（用于测试）
  Future<void> debugResetVip() async {
    debugPrint('[VipService] 🗑️  重置 VIP 状态...');
    await clearCurrentUserVipCache();
    await _prefs.remove(_keyVipType);
    await _prefs.remove(_keyVipExpireMs);
    await _prefs.remove(_keyLastProcessedTransactionDate);
    await _prefs.remove(_keyLastProcessedPurchaseSignature);
    await _prefs.remove(_keyLastReceiptData);
    await _prefs.remove(_keyLastReceiptSource);
    await _prefs.remove(_keyLastReceiptSignature);
    await _prefs.remove(_keyLastProductId);
    await _prefs.remove(_keyLastTransactionId);
    await _prefs.remove(_keyLastOriginalTransactionId);
    await _prefs.remove(_keyLastAppAccountToken);
    notifyListeners();
    debugPrint('[VipService] ✅ VIP 状态已重置');
    debugPrintVipStatus();
  }

  Future<String> _resolveReceiptData(PurchaseDetails purchase) async {
    final nativeReceiptData = await _fetchIosAppStoreReceiptData();
    if (nativeReceiptData != null && nativeReceiptData.isNotEmpty) {
      return nativeReceiptData;
    }

    final purchaseReceiptData =
        purchase.verificationData.serverVerificationData;
    return purchaseReceiptData;
  }

  @visibleForTesting
  Future<String?> fetchIosAppStoreReceiptDataForTest() async {
    return _fetchIosAppStoreReceiptData();
  }

  Future<String?> _fetchIosAppStoreReceiptData() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return null;
    }

    try {
      final receiptData = await _receiptChannel.invokeMethod<String>(
        'getReceiptData',
      );
      if (receiptData != null && receiptData.isNotEmpty) {
        debugPrint(
          '[VipService] fetched iOS app receipt data, len=${receiptData.length}',
        );
        return receiptData;
      }
    } catch (e) {
      debugPrint('[VipService] fetch iOS app receipt data error: $e');
    }

    return null;
  }
}
