import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'config_service.dart';
import 'cloud_service.dart';

enum VipType { none, monthly, yearly }

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

class VipService extends ChangeNotifier {
  static const _keyVipType = 'vip_type';
  static const _keyVipExpireMs = 'vip_expire_ms';
  static const _keyLastProcessedTransactionDate =
      'last_processed_transaction_date';
  static const _keyLastProcessedPurchaseSignature =
      'last_processed_purchase_signature';
  static const _keyLastReceiptData = 'last_receipt_data';

  final SharedPreferences _prefs;
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  Timer? _expiryTimer;

  String? _lastSnapshotPhone;
  int _lastSnapshotExpireMs = 0;
  bool _lastSnapshotIsVip = false;

  VipService(this._prefs);

  String? get _currentPhone {
    final phone = _prefs.getString('logged_in_phone')?.trim();
    if (phone == null || phone.isEmpty) return null;
    return phone;
  }

  bool get _hasVipContext {
    final phone = _currentPhone;
    return phone != null && phone != 'DemoAccount';
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
    _purchaseSubscription = _iap.purchaseStream.listen((purchases) async {
      debugPrint('[VipService] ========================================');
      debugPrint(
        '[VipService] purchaseStream received ${purchases.length} purchases',
      );
      for (final p in purchases) {
        debugPrint(
          '[VipService] - productID=${p.productID}, status=${p.status}',
        );
        if (p.status == PurchaseStatus.purchased) {
          debugPrint('[VipService] stream received purchased: ${p.productID}');
          await _processPurchase(p);
          debugPrint('[VipService] calling notifyListeners...');
          notifyListeners(); // 通知 UI 刷新 VIP 状态
        } else if (p.status == PurchaseStatus.restored) {
          debugPrint('[VipService] stream received restored: ${p.productID}');
          await _processPurchase(p);
          notifyListeners();
        } else {
          debugPrint('[VipService] ⚠️  忽略 status=${p.status}');
        }
      }
      debugPrint('[VipService] ========================================');
    });
  }

  Future<void> _processPurchase(PurchaseDetails p) async {
    final id = p.productID;
    debugPrint('[VipService] ========================================');
    debugPrint('[VipService] _processPurchase called');
    debugPrint('[VipService] productID=$id');
    debugPrint('[VipService] status=${p.status}');
    debugPrint('[VipService] transactionDate=${p.transactionDate}');
    debugPrint('[VipService] verificationData=${p.verificationData}');
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

    VipType? type;
    if (id == 'com.phil.AIAccountant.mon') type = VipType.monthly;
    if (id == 'com.phil.AIAccountant.year') type = VipType.yearly;

    final transactionMs = _parseTransactionMs(p.transactionDate);
    final lastProcessedMs = _getScopedInt(_keyLastProcessedTransactionDate);
    final lastProcessedSignature = _getScopedString(
      _keyLastProcessedPurchaseSignature,
    );
    final receiptData = p.verificationData.serverVerificationData;
    if (receiptData.isNotEmpty) {
      await _setScopedString(_keyLastReceiptData, receiptData);
      debugPrint('[VipService] ✅ 缓存 receiptData，len=${receiptData.length}');
    }
    final purchaseSignature = [
      id,
      p.status.name,
      p.transactionDate ?? '',
      p.purchaseID ?? '',
    ].join('|');

    debugPrint(
      '[VipService] 交易日期检查: transactionDateStr=${p.transactionDate}, transactionMs=$transactionMs, lastProcessedMs=$lastProcessedMs, lastProcessedSignature=$lastProcessedSignature, purchaseSignature=$purchaseSignature',
    );

    final isRestorePurchase = p.status == PurchaseStatus.restored;
    final currentTypeStr = _getScopedString(_keyVipType);
    final incomingTypeStr = switch (type) {
      VipType.monthly => 'monthly',
      VipType.yearly => 'yearly',
      _ => null,
    };

    if (!isRestorePurchase &&
        lastProcessedSignature != null &&
        lastProcessedSignature == purchaseSignature) {
      debugPrint('[VipService] ⏭️  跳过重复购买签名');
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
    debugPrint('[VipService] ✅ 记录购买签名: $purchaseSignature');
    debugPrint('[VipService] mapped type=$type');

    if (type != null) {
      final transactionDate = transactionMs != null
          ? DateTime.fromMillisecondsSinceEpoch(transactionMs)
          : null;
      debugPrint(
        '[VipService] ⚠️  即将调用 _activateVip($type, isRestore=${p.status == PurchaseStatus.restored}, transactionDate=$transactionDate)',
      );
      await _activateVip(
        type,
        transactionDate: transactionDate,
        isRestore: p.status == PurchaseStatus.restored,
        receiptData: receiptData.isNotEmpty ? receiptData : null,
      );

      // restore 场景下，最终再强制以云端为准。
      // 原因：StoreKit restored 可能先给出 TestFlight/sandbox 的本地日期，
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

  static const int touristLimit = 20;
  static const int freeUserLimit = 50;

  VipType get vipType {
    _refreshSnapshot();
    final typeStr = _getScopedString(_keyVipType);
    if (typeStr == 'monthly') return VipType.monthly;
    if (typeStr == 'yearly') return VipType.yearly;
    return VipType.none;
  }

  DateTime? get expireDate {
    _refreshSnapshot();
    final ms = _getScopedInt(_keyVipExpireMs);
    if (ms == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// 购买月度会员
  Future<bool> purchaseMonthly() async {
    return _purchase('com.phil.AIAccountant.mon', VipType.monthly);
  }

  /// 购买年度会员
  Future<bool> purchaseYearly() async {
    return _purchase('com.phil.AIAccountant.year', VipType.yearly);
  }

  /// 购买：发起支付后监听 Apple 返回结果
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

      debugPrint('[VipService] 📱 即将调用 buyNonConsumable，应该弹出 Apple 付款窗口...');
      final result = await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
      debugPrint('[VipService] buyNonConsumable 返回结果: $result');
      debugPrint('[VipService] _purchase END');
      debugPrint('[VipService] ========================================');

      return result;
    } catch (e, stackTrace) {
      debugPrint('[VipService] ❌ Purchase error: $e');
      debugPrint('[VipService] Stack trace: $stackTrace');
      return false;
    }
  }

  Future<void> _activateVip(
    VipType type, {
    DateTime? transactionDate,
    bool isRestore = false,
    String? receiptData,
  }) async {
    final now = DateTime.now();
    debugPrint('[VipService] ========================================');
    debugPrint('[VipService] _activateVip START');
    debugPrint('[VipService] type=$type');
    debugPrint('[VipService] now=$now');
    debugPrint('[VipService] transactionDate=$transactionDate');
    debugPrint('[VipService] isRestore=$isRestore');

    final existingExpireMs = _getScopedInt(_keyVipExpireMs);
    final existingExpireDate = existingExpireMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(existingExpireMs)
        : null;
    debugPrint('[VipService] existingExpireMs=$existingExpireMs');
    debugPrint('[VipService] existingExpireDate=$existingExpireDate');

    late final DateTime expireDate;

    if (isRestore) {
      final restoredBaseDate = transactionDate ?? now;
      final restoredExpireDate = _calculateExpireDate(type, restoredBaseDate);
      debugPrint(
        '[VipService] 恢复购买：按交易时间恢复，restoredBaseDate=$restoredBaseDate → restoredExpireDate=$restoredExpireDate',
      );

      // 热修：恢复购买时直接信任 Apple 返回的交易时间，
      // 不再保留本地“更晚”的旧错误日期，避免把曾经错误算出来的到期日一直沿用。
      expireDate = restoredExpireDate;
      debugPrint('[VipService] 恢复购买：直接采用 Apple 恢复出的到期时间：$expireDate');
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

    await _setScopedString(
      _keyVipType,
      type == VipType.monthly ? 'monthly' : 'yearly',
    );
    await _setScopedInt(_keyVipExpireMs, expireMs);
    _refreshSnapshot(notify: true);

    // 购买/恢复成功后尝试同步到云端（失败不阻塞）
    try {
      await pushToCloud(receiptData: receiptData);
    } catch (e) {
      debugPrint(
        '[VipService] _activateVip: pushToCloud error (non-fatal): $e',
      );
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

  DateTime _calculateExpireDate(VipType type, DateTime baseDate) {
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
        '[VipService] restorePurchases() called for phone=$_currentPhone',
      );
      _refreshSnapshot();
      await _iap.restorePurchases();

      final cachedReceiptData = _getScopedString(_keyLastReceiptData);
      if (cachedReceiptData != null &&
          cachedReceiptData.isNotEmpty &&
          _getScopedInt(_keyVipExpireMs) >
              DateTime.now().millisecondsSinceEpoch) {
        debugPrint(
          '[VipService] restorePurchases fallback: push cached receipt to cloud, len=${cachedReceiptData.length}',
        );
        await pushToCloud(receiptData: cachedReceiptData);
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
      debugPrint(
        '[VipService] syncFromCloud: fetching from cloud for $_currentPhone...',
      );
      final cloudProfile = await CloudService().getVipProfile();
      if (cloudProfile == null) {
        debugPrint('[VipService] syncFromCloud: no profile on cloud');
        return false;
      }

      final cloudType = cloudProfile['vip_type'] as String?;
      final cloudExpireMs = cloudProfile['vip_expire_ms'] as int?;
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
        if (cloudExpireMs < localExpireMs) {
          debugPrint(
            '[VipService] syncFromCloud: ignore older cloud VIP, keep local newer expire_ms=$localExpireMs',
          );
          _refreshSnapshot(notify: true);
          return true;
        }
      }

      // 云端有效 → 写入本地（本地以云端为准）
      await _setScopedString(_keyVipType, cloudType);
      if (cloudExpireMs != null && cloudExpireMs > 0) {
        await _setScopedInt(_keyVipExpireMs, cloudExpireMs);
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

  /// 主动将本地 VIP 状态同步到云端
  /// 在购买成功、恢复成功后调用
  /// 如果云端返回 403（订阅已过期），清理本地并返回 false
  Future<bool> pushToCloud({String? receiptData}) async {
    if (!_hasVipContext) return false;
    if (!ConfigService.instance.isAliyunFCConfigured) return false;

    try {
      final localType = _getScopedString(_keyVipType);
      final localExpireMs = _getScopedInt(_keyVipExpireMs);
      final effectiveReceiptData =
          receiptData ?? _getScopedString(_keyLastReceiptData);

      if (localType == null || localType.isEmpty || localExpireMs <= 0) {
        debugPrint('[VipService] pushToCloud: no valid local VIP to push');
        return false;
      }

      // 检查本地是否已过期（防止推广过期状态到云端）
      if (localExpireMs > 0 &&
          DateTime.now().millisecondsSinceEpoch > localExpireMs) {
        debugPrint(
          '[VipService] pushToCloud: local VIP already expired, clearing',
        );
        await clearCurrentUserVipCache();
        return false;
      }

      final result = await CloudService().syncVipProfile(
        vipType: localType,
        expireMs: localExpireMs,
        receiptData: effectiveReceiptData,
      );

      if (result != null) {
        debugPrint('[VipService] pushToCloud: success, result=$result');
        // 云端同步后以云端为准（可能 Apple 返回了不同的 expire_ms）
        final cloudType = result['vip_type'] as String?;
        final cloudExpireMs = result['vip_expire_ms'] as int?;
        if (cloudType != null && cloudExpireMs != null && cloudExpireMs > 0) {
          if (cloudExpireMs >= localExpireMs) {
            await _setScopedString(_keyVipType, cloudType);
            await _setScopedInt(_keyVipExpireMs, cloudExpireMs);
            debugPrint(
              '[VipService] pushToCloud: local updated from cloud, cloudExpireMs=$cloudExpireMs',
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
    _refreshSnapshot(notify: true);
  }

  /// 🔧 调试工具：打印当前 VIP 状态（用于排查问题）
  void debugPrintVipStatus() {
    debugPrint('[VipService] 🔍 ====== VIP 状态调试 ======');
    debugPrint('[VipService] currentPhone: $_currentPhone');
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
    notifyListeners();
    debugPrint('[VipService] ✅ VIP 状态已重置');
    debugPrintVipStatus();
  }
}
