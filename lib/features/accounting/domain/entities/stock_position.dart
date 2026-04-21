import 'package:equatable/equatable.dart';

enum StockQuoteStatus { normal, stale, loading }

enum StockQuantityChangeMode { overwrite, delta }

class StockSearchItem extends Equatable {
  final String code;
  final String name;
  final String exchange;

  const StockSearchItem({
    required this.code,
    required this.name,
    required this.exchange,
  });

  factory StockSearchItem.fromJson(Map<String, dynamic> json) {
    return StockSearchItem(
      code: (json['dm'] ?? json['code'] ?? '').toString(),
      name: (json['mc'] ?? json['name'] ?? '').toString(),
      exchange: (json['jys'] ?? json['exchange'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'name': name,
    'exchange': exchange,
  };

  String get pureCode => code.split('.').first;

  @override
  List<Object?> get props => [code, name, exchange];
}

class StockPosition extends Equatable {
  final String id;
  final String assetType;
  final String code;
  final String name;
  final String exchange;
  final String marketCurrency;
  final String locale;
  final String countryCode;
  final int quantity;
  final double? costPrice;
  final double? latestPrice;
  final double? changePercent;
  final DateTime? quoteUpdatedAt;
  final StockQuoteStatus quoteStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  const StockPosition({
    required this.id,
    this.assetType = 'stock',
    required this.code,
    required this.name,
    required this.exchange,
    this.marketCurrency = 'CNY',
    this.locale = 'zh-CN',
    this.countryCode = 'CN',
    required this.quantity,
    this.costPrice,
    this.latestPrice,
    this.changePercent,
    this.quoteUpdatedAt,
    this.quoteStatus = StockQuoteStatus.loading,
    required this.createdAt,
    required this.updatedAt,
  });

  factory StockPosition.fromJson(Map<String, dynamic> json) {
    return StockPosition(
      id: json['id'] as String,
      assetType: (json['assetType'] ?? 'stock').toString(),
      code: json['code'] as String,
      name: json['name'] as String,
      exchange: (json['exchange'] ?? '').toString(),
      marketCurrency:
          (json['marketCurrency'] as String?) ??
          _defaultCurrencyForExchange((json['exchange'] ?? '').toString()),
      locale:
          (json['locale'] as String?) ??
          _defaultLocaleForExchange((json['exchange'] ?? '').toString()),
      countryCode:
          (json['countryCode'] as String?) ??
          _defaultCountryForExchange((json['exchange'] ?? '').toString()),
      quantity: (json['quantity'] as num).toInt(),
      costPrice: (json['costPrice'] as num?)?.toDouble(),
      latestPrice: (json['latestPrice'] as num?)?.toDouble(),
      changePercent: (json['changePercent'] as num?)?.toDouble(),
      quoteUpdatedAt: json['quoteUpdatedAt'] == null
          ? null
          : DateTime.parse(json['quoteUpdatedAt'] as String),
      quoteStatus: StockQuoteStatus.values.firstWhere(
        (e) => e.name == json['quoteStatus'],
        orElse: () => StockQuoteStatus.loading,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'assetType': assetType,
    'code': code,
    'name': name,
    'exchange': exchange,
    'marketCurrency': marketCurrency,
    'locale': locale,
    'countryCode': countryCode,
    'quantity': quantity,
    if (costPrice != null) 'costPrice': costPrice,
    if (latestPrice != null) 'latestPrice': latestPrice,
    if (changePercent != null) 'changePercent': changePercent,
    if (quoteUpdatedAt != null)
      'quoteUpdatedAt': quoteUpdatedAt!.toIso8601String(),
    'quoteStatus': quoteStatus.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  StockPosition copyWith({
    String? id,
    String? assetType,
    String? code,
    String? name,
    String? exchange,
    String? marketCurrency,
    String? locale,
    String? countryCode,
    int? quantity,
    double? costPrice,
    bool clearCostPrice = false,
    double? latestPrice,
    bool clearLatestPrice = false,
    double? changePercent,
    bool clearChangePercent = false,
    DateTime? quoteUpdatedAt,
    bool clearQuoteUpdatedAt = false,
    StockQuoteStatus? quoteStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StockPosition(
      id: id ?? this.id,
      assetType: assetType ?? this.assetType,
      code: code ?? this.code,
      name: name ?? this.name,
      exchange: exchange ?? this.exchange,
      marketCurrency: marketCurrency ?? this.marketCurrency,
      locale: locale ?? this.locale,
      countryCode: countryCode ?? this.countryCode,
      quantity: quantity ?? this.quantity,
      costPrice: clearCostPrice ? null : (costPrice ?? this.costPrice),
      latestPrice: clearLatestPrice ? null : (latestPrice ?? this.latestPrice),
      changePercent: clearChangePercent
          ? null
          : (changePercent ?? this.changePercent),
      quoteUpdatedAt: clearQuoteUpdatedAt
          ? null
          : (quoteUpdatedAt ?? this.quoteUpdatedAt),
      quoteStatus: quoteStatus ?? this.quoteStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  double get marketValue => (latestPrice ?? 0) * quantity;

  double? get profitAmount {
    if (costPrice == null || latestPrice == null) return null;
    return (latestPrice! - costPrice!) * quantity;
  }

  double? get profitPercent {
    if (costPrice == null || costPrice == 0 || latestPrice == null) return null;
    return ((latestPrice! - costPrice!) / costPrice!) * 100;
  }

  bool get hasQuote => latestPrice != null;

  String get displayCode => code.contains('.') ? code : '$code.$exchange';

  @override
  List<Object?> get props => [
    id,
    assetType,
    code,
    name,
    exchange,
    marketCurrency,
    locale,
    countryCode,
    quantity,
    costPrice,
    latestPrice,
    changePercent,
    quoteUpdatedAt,
    quoteStatus,
    createdAt,
    updatedAt,
  ];

  static String _defaultCurrencyForExchange(String exchange) {
    final normalized = exchange.toUpperCase();
    if (normalized.contains('NASDAQ') ||
        normalized.contains('NYSE') ||
        normalized == 'US') {
      return 'USD';
    }
    return 'CNY';
  }

  static String _defaultLocaleForExchange(String exchange) {
    final normalized = exchange.toUpperCase();
    if (normalized.contains('NASDAQ') ||
        normalized.contains('NYSE') ||
        normalized == 'US') {
      return 'en-US';
    }
    return 'zh-CN';
  }

  static String _defaultCountryForExchange(String exchange) {
    final normalized = exchange.toUpperCase();
    if (normalized.contains('NASDAQ') ||
        normalized.contains('NYSE') ||
        normalized == 'US') {
      return 'US';
    }
    return 'CN';
  }
}
