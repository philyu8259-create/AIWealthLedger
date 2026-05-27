import 'dart:async';

import 'package:flutter/services.dart';
import 'package:huawei_iap/huawei_iap.dart' as hms;
import 'package:in_app_purchase/in_app_purchase.dart' as iap;

import 'vip_service.dart';

class HuaweiIapVipGateway implements VipInAppPurchaseGateway {
  HuaweiIapVipGateway() {
    unawaited(hms.IapClient.enablePendingPurchase());
  }

  final StreamController<List<iap.PurchaseDetails>> _purchaseController =
      StreamController<List<iap.PurchaseDetails>>.broadcast();
  static const Duration _iapCallTimeout = Duration(seconds: 20);

  @override
  Stream<List<iap.PurchaseDetails>> get purchaseStream =>
      _purchaseController.stream;

  @override
  Future<iap.ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    try {
      final result = await hms.IapClient.obtainProductInfo(
        hms.ProductInfoReq(
          priceType: _priceTypeForProductIds(identifiers),
          skuIds: identifiers.toList(),
        ),
      ).timeout(_iapCallTimeout);
      final products = (result.productInfoList ?? const [])
          .whereType<hms.ProductInfo>()
          .map(_mapProduct)
          .toList();
      final foundIds = products.map((product) => product.id).toSet();
      return iap.ProductDetailsResponse(
        productDetails: products,
        notFoundIDs: identifiers.difference(foundIds).toList(),
        error: null,
      );
    } on PlatformException catch (error) {
      return iap.ProductDetailsResponse(
        productDetails: const [],
        notFoundIDs: identifiers.toList(),
        error: iap.IAPError(
          code: error.code,
          message: error.message,
          details: '${error.details}',
          source: 'huawei_iap',
        ),
      );
    } on TimeoutException catch (error) {
      return iap.ProductDetailsResponse(
        productDetails: const [],
        notFoundIDs: identifiers.toList(),
        error: iap.IAPError(
          code: 'timeout',
          message: 'Huawei IAP product query timed out.',
          details: error.toString(),
          source: 'huawei_iap',
        ),
      );
    }
  }

  @override
  Future<bool> buyNonConsumable({
    required iap.PurchaseParam purchaseParam,
  }) async {
    try {
      final result = await hms.IapClient.createPurchaseIntent(
        hms.PurchaseIntentReq(
          priceType: _priceTypeForProductId(purchaseParam.productDetails.id),
          productId: purchaseParam.productDetails.id,
          developerPayload: purchaseParam.applicationUserName,
        ),
      ).timeout(_iapCallTimeout);
      final data = result.inAppPurchaseData;
      if (result.returnCode == '0' && data != null) {
        _purchaseController.add([
          _mapPurchase(
            data,
            status: iap.PurchaseStatus.purchased,
            signature: result.inAppDataSignature,
          ),
        ]);
        return true;
      }
      _purchaseController.add([
        iap.PurchaseDetails(
          productID: purchaseParam.productDetails.id,
          verificationData: const iap.PurchaseVerificationData(
            localVerificationData: '',
            serverVerificationData: '',
            source: 'huawei_iap',
          ),
          status: iap.PurchaseStatus.error,
          error: iap.IAPError(
            code: result.returnCode,
            message: result.errMsg,
            source: 'huawei_iap',
          ),
        ),
      ]);
      return false;
    } on PlatformException catch (error) {
      _purchaseController.add([
        iap.PurchaseDetails(
          productID: purchaseParam.productDetails.id,
          verificationData: const iap.PurchaseVerificationData(
            localVerificationData: '',
            serverVerificationData: '',
            source: 'huawei_iap',
          ),
          status: iap.PurchaseStatus.error,
          error: iap.IAPError(
            code: error.code,
            message: error.message,
            details: '${error.details}',
            source: 'huawei_iap',
          ),
        ),
      ]);
      return false;
    } on TimeoutException catch (error) {
      _purchaseController.add([
        iap.PurchaseDetails(
          productID: purchaseParam.productDetails.id,
          verificationData: const iap.PurchaseVerificationData(
            localVerificationData: '',
            serverVerificationData: '',
            source: 'huawei_iap',
          ),
          status: iap.PurchaseStatus.error,
          error: iap.IAPError(
            code: 'timeout',
            message: 'Huawei IAP purchase timed out.',
            details: error.toString(),
            source: 'huawei_iap',
          ),
        ),
      ]);
      return false;
    }
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    final purchases = <iap.PurchaseDetails>[];
    for (final priceType in const [
      hms.IapClient.IN_APP_NONCONSUMABLE,
      hms.IapClient.IN_APP_SUBSCRIPTION,
    ]) {
      String? continuationToken;
      do {
        final result = await hms.IapClient.obtainOwnedPurchases(
          hms.OwnedPurchasesReq(
            priceType: priceType,
            continuationToken: continuationToken,
          ),
        ).timeout(_iapCallTimeout);
        final signatures = result.inAppSignature ?? const <String>[];
        final ownedData = result.inAppPurchaseDataList ?? const [];
        for (var index = 0; index < ownedData.length; index += 1) {
          final data = ownedData[index];
          if (priceType == hms.IapClient.IN_APP_SUBSCRIPTION &&
              data.subIsvalid != true) {
            continue;
          }
          purchases.add(
            _mapPurchase(
              data,
              status: iap.PurchaseStatus.restored,
              signature: index < signatures.length ? signatures[index] : null,
            ),
          );
        }
        continuationToken = result.continuationToken;
      } while (continuationToken != null && continuationToken.isNotEmpty);
    }

    if (purchases.isNotEmpty) {
      _purchaseController.add(purchases);
    }
  }

  @override
  Future<void> completePurchase(iap.PurchaseDetails purchase) async {}

  int _priceTypeForProductIds(Set<String> productIds) {
    if (productIds.contains(kVipLifetimeAdFreeProductIdHuawei)) {
      return hms.IapClient.IN_APP_NONCONSUMABLE;
    }
    return hms.IapClient.IN_APP_SUBSCRIPTION;
  }

  int _priceTypeForProductId(String productId) {
    if (productId == kVipLifetimeAdFreeProductIdHuawei) {
      return hms.IapClient.IN_APP_NONCONSUMABLE;
    }
    return hms.IapClient.IN_APP_SUBSCRIPTION;
  }

  iap.ProductDetails _mapProduct(hms.ProductInfo product) {
    final price = product.price ?? product.originalLocalPrice ?? '';
    final micros = product.microsPrice ?? product.originalMicroPrice ?? 0;
    final rawPrice = micros / 1000000.0;
    return iap.ProductDetails(
      id: product.productId ?? '',
      title: product.productName ?? '',
      description: product.productDesc ?? '',
      price: price,
      rawPrice: rawPrice,
      currencyCode: product.currency ?? 'CNY',
      currencySymbol: _currencySymbol(price),
    );
  }

  iap.PurchaseDetails _mapPurchase(
    hms.InAppPurchaseData data, {
    required iap.PurchaseStatus status,
    String? signature,
  }) {
    return iap.PurchaseDetails(
      productID: data.productId ?? '',
      purchaseID: data.orderId ?? data.payOrderId,
      transactionDate: data.purchaseTimeMillis?.toString(),
      status: status,
      verificationData: iap.PurchaseVerificationData(
        localVerificationData: signature ?? '',
        serverVerificationData: data.toJson(),
        source: 'huawei_iap',
      ),
      pendingCompletePurchase: false,
    );
  }

  String _currencySymbol(String price) {
    if (price.isEmpty) return '';
    final match = RegExp(r'^\D+').firstMatch(price.trim());
    return match?.group(0)?.trim() ?? '';
  }
}
