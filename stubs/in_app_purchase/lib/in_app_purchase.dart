import 'dart:async';

enum PurchaseStatus { pending, purchased, error, restored, canceled }

class IAPError {
  const IAPError({
    this.code,
    this.message,
    this.details,
    this.source,
    this.stackTrace,
  });

  final String? code;
  final String? message;
  final String? details;
  final String? source;
  final String? stackTrace;
}

class PurchaseVerificationData {
  const PurchaseVerificationData({
    required this.localVerificationData,
    required this.serverVerificationData,
    required this.source,
  });

  final String localVerificationData;
  final String serverVerificationData;
  final String source;
}

class PurchaseDetails {
  const PurchaseDetails({
    required this.productID,
    required this.verificationData,
    this.transactionDate,
    required this.status,
    this.purchaseID,
    this.error,
    this.pendingCompletePurchase = false,
  });

  final String productID;
  final PurchaseVerificationData verificationData;
  final String? transactionDate;
  final String? purchaseID;
  final PurchaseStatus status;
  final IAPError? error;
  final bool pendingCompletePurchase;
}

class ProductDetails {
  const ProductDetails({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.rawPrice,
    required this.currencyCode,
    required this.currencySymbol,
  });

  final String id;
  final String title;
  final String description;
  final String price;
  final double rawPrice;
  final String currencyCode;
  final String currencySymbol;
}

class ProductDetailsResponse {
  const ProductDetailsResponse({
    required this.productDetails,
    required this.notFoundIDs,
    this.error,
  });

  final List<ProductDetails> productDetails;
  final List<String> notFoundIDs;
  final IAPError? error;
}

class PurchaseParam {
  const PurchaseParam({
    required this.productDetails,
    this.applicationUserName,
    this.obfuscatedAccountId,
    this.obfuscatedProfileId,
  });

  final ProductDetails productDetails;
  final String? applicationUserName;
  final String? obfuscatedAccountId;
  final String? obfuscatedProfileId;
}

class InAppPurchase {
  InAppPurchase._();

  static final InAppPurchase instance = InAppPurchase._();

  Stream<List<PurchaseDetails>> get purchaseStream =>
      const Stream<List<PurchaseDetails>>.empty();

  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    return ProductDetailsResponse(
      productDetails: const [],
      notFoundIDs: identifiers.toList(),
      error: null,
    );
  }

  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    return false;
  }

  Future<void> restorePurchases({String? applicationUserName}) async {}

  Future<void> completePurchase(PurchaseDetails purchase) async {}
}
