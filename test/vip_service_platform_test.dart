import 'dart:async';
import 'dart:convert';

import 'package:ai_accounting_app/app/app_flavor.dart';
import 'package:ai_accounting_app/services/vip_service.dart';
import 'package:ai_accounting_app/services/config_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const phone = '13800138000';
  final receiptChannel = const MethodChannel(
    'com.aiaccounting/app_store_receipt',
  );
  const receiptData = 'mock_receipt_data';
  late _FakeInAppPurchaseGateway fakeInAppPurchasePlatform;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'logged_in_phone': phone});
    fakeInAppPurchasePlatform = _FakeInAppPurchaseGateway();
    ConfigService.instance.resetForTest();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(receiptChannel, null);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    fakeInAppPurchasePlatform.dispose();
  });

  group('vip product IDs are platformized', () {
    test('iOS, Google Play, and Huawei resolve expected product IDs', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(
        resolveVipProductId(type: VipType.monthly),
        'com.phil.AIAccountant.mon',
      );
      expect(
        resolveVipProductId(type: VipType.yearly),
        'com.phil.AIAccountant.year',
      );

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
        resolveVipStoreProvider(flavor: AppFlavor.cn),
        VipStoreProvider.huawei,
      );
      expect(
        resolveVipProductId(type: VipType.monthly, flavor: AppFlavor.cn),
        'ai_wealth_tracker_monthly',
      );
      expect(
        resolveVipProductId(type: VipType.yearly, flavor: AppFlavor.cn),
        'ai_wealth_tracker_yearly',
      );
      expect(
        resolveVipProductId(type: VipType.lifetime, flavor: AppFlavor.cn),
        'ai_wealth_tracker_lifetime_ad_free',
      );
      expect(
        resolveVipStoreProvider(flavor: AppFlavor.intl),
        VipStoreProvider.googlePlay,
      );
      expect(
        resolveVipProductId(type: VipType.monthly, flavor: AppFlavor.intl),
        'ai_wealth_tracker_monthly',
      );
      expect(
        resolveVipProductId(type: VipType.yearly, flavor: AppFlavor.intl),
        'ai_wealth_tracker_yearly',
      );
    });

    test('restore/purchase processing accepts platformized product IDs', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
        resolveVipProductIdFromPurchaseId(
          resolveVipProductId(type: VipType.monthly),
        ),
        VipType.monthly,
      );
      expect(
        resolveVipProductIdFromPurchaseId(
          resolveVipProductId(type: VipType.yearly),
        ),
        VipType.yearly,
      );
      expect(
        resolveVipProductIdFromPurchaseId(kVipLifetimeAdFreeProductIdHuawei),
        VipType.lifetime,
      );
    });

    test('Huawei storefront queries lifetime ad-free product only', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = VipService(prefs, null, fakeInAppPurchasePlatform);

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await prefs.setString('app_mode', AppFlavor.cn.name);
      await service.queryVipProductDetails();

      expect(fakeInAppPurchasePlatform.lastQueriedIds, {
        kVipLifetimeAdFreeProductIdHuawei,
      });
    });
  });

  group('receipt data path', () {
    test('Android 不会调用 App Store receipt channel', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = VipService(prefs, null, fakeInAppPurchasePlatform);

      var channelCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(receiptChannel, (MethodCall call) async {
            channelCalls += 1;
            return 'should_not_be_called';
          });

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final data = await service.fetchIosAppStoreReceiptDataForTest();

      expect(channelCalls, 0);
      expect(data, isNull);
      expect(
        prefs.getString(_scopedVipStringKey('last_receipt_data', phone)),
        isNull,
      );
    });

    test('iOS 会触发并返回 receiptData', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = VipService(prefs, null, fakeInAppPurchasePlatform);
      var channelCalls = 0;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(receiptChannel, (MethodCall call) async {
            channelCalls += 1;
            return receiptData;
          });

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final data = await service.fetchIosAppStoreReceiptDataForTest();

      expect(channelCalls, 1);
      expect(data, receiptData);
    });

    test(
      'Android purchase stream 使用 serverVerificationData 作为本地回传数据',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final service = VipService(prefs, null, fakeInAppPurchasePlatform);
        final fakePlatform = fakeInAppPurchasePlatform;
        var channelCalls = 0;

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(receiptChannel, (MethodCall call) async {
              channelCalls += 1;
              return 'should_not_be_called';
            });

        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        await service.init();
        fakePlatform.emitPurchaseBatch([
          PurchaseDetails(
            productID: resolveVipProductId(type: VipType.monthly),
            verificationData: PurchaseVerificationData(
              localVerificationData: '',
              serverVerificationData: 'play_purchase_token',
              source: 'google_play',
            ),
            transactionDate: DateTime.now().millisecondsSinceEpoch.toString(),
            status: PurchaseStatus.purchased,
          ),
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(channelCalls, 0);
        expect(service.vipType, VipType.monthly);
        expect(service.isVip, isTrue);
        expect(
          prefs.getString(_scopedVipStringKey('last_receipt_data', phone)),
          'play_purchase_token',
        );
        expect(fakePlatform.completePurchaseCalls, 0);
      },
    );

    test(
      'Huawei subscription uses platform expirationDate and removes ads',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final service = VipService(prefs, null, fakeInAppPurchasePlatform);
        final fakePlatform = fakeInAppPurchasePlatform;
        final purchaseMs = DateTime.now().millisecondsSinceEpoch;
        final expirationMs =
            purchaseMs + const Duration(days: 12).inMilliseconds;
        final huaweiReceipt = jsonEncode({
          'productId': kVipMonthlyProductIdHuawei,
          'orderId': 'huawei_order_1',
          'purchaseToken': 'huawei_purchase_token',
          'purchaseTimeMillis': purchaseMs,
          'expirationDate': expirationMs,
          'subIsvalid': true,
        });

        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        await service.init();
        fakePlatform.emitPurchaseBatch([
          PurchaseDetails(
            productID: kVipMonthlyProductIdHuawei,
            purchaseID: 'huawei_order_1',
            verificationData: PurchaseVerificationData(
              localVerificationData: 'huawei_signature',
              serverVerificationData: huaweiReceipt,
              source: 'huawei_iap',
            ),
            transactionDate: purchaseMs.toString(),
            status: PurchaseStatus.purchased,
          ),
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(service.vipType, VipType.monthly);
        expect(service.isVip, isTrue);
        expect(service.removesAds, isTrue);
        expect(service.expireDate?.millisecondsSinceEpoch, expirationMs);
        expect(
          prefs.getString(_scopedVipStringKey('last_receipt_data', phone)),
          huaweiReceipt,
        );
        expect(
          prefs.getString(_scopedVipStringKey('last_receipt_source', phone)),
          'huawei_iap',
        );
        expect(
          prefs.getString(_scopedVipStringKey('last_receipt_signature', phone)),
          'huawei_signature',
        );
        expect(
          prefs.getString(_scopedVipStringKey('last_product_id', phone)),
          kVipMonthlyProductIdHuawei,
        );
      },
    );

    test('Huawei non-consumable lifetime ad-free never expires', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = VipService(prefs, null, fakeInAppPurchasePlatform);
      final fakePlatform = fakeInAppPurchasePlatform;
      final purchaseMs = DateTime.now().millisecondsSinceEpoch;
      final huaweiReceipt = jsonEncode({
        'productId': kVipLifetimeAdFreeProductIdHuawei,
        'orderId': 'huawei_lifetime_order_1',
        'purchaseToken': 'huawei_lifetime_purchase_token',
        'purchaseTimeMillis': purchaseMs,
      });

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await service.init();
      fakePlatform.emitPurchaseBatch([
        PurchaseDetails(
          productID: kVipLifetimeAdFreeProductIdHuawei,
          purchaseID: 'huawei_lifetime_order_1',
          verificationData: PurchaseVerificationData(
            localVerificationData: 'huawei_lifetime_signature',
            serverVerificationData: huaweiReceipt,
            source: 'huawei_iap',
          ),
          transactionDate: purchaseMs.toString(),
          status: PurchaseStatus.purchased,
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(service.vipType, VipType.lifetime);
      expect(service.isVip, isTrue);
      expect(service.removesAds, isTrue);
      expect(service.expireDate?.year, 2099);
      expect(
        prefs.getString(_scopedVipStringKey('last_receipt_data', phone)),
        huaweiReceipt,
      );
      expect(
        prefs.getString(_scopedVipStringKey('last_receipt_signature', phone)),
        'huawei_lifetime_signature',
      );
      expect(
        prefs.getString(_scopedVipStringKey('last_product_id', phone)),
        kVipLifetimeAdFreeProductIdHuawei,
      );
    });
  });
}

String _scopedVipStringKey(String base, String phone) =>
    '${base}_${phone.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}';

class _FakeInAppPurchaseGateway extends VipInAppPurchaseGateway {
  final StreamController<List<PurchaseDetails>> _purchaseStreamController =
      StreamController<List<PurchaseDetails>>.broadcast();

  int completePurchaseCalls = 0;
  int restorePurchaseCalls = 0;
  Set<String> lastQueriedIds = const {};

  @override
  Stream<List<PurchaseDetails>> get purchaseStream =>
      _purchaseStreamController.stream;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    lastQueriedIds = identifiers;
    return ProductDetailsResponse(
      productDetails: [],
      notFoundIDs: identifiers.toList(),
      error: null,
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completePurchaseCalls += 1;
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restorePurchaseCalls += 1;
  }

  void emitPurchaseBatch(List<PurchaseDetails> purchases) {
    _purchaseStreamController.add(purchases);
  }

  void dispose() {
    _purchaseStreamController.close();
  }
}
