import 'package:equatable/equatable.dart';

/// 账单类型
enum EntryType { income, expense }

/// 同步状态
enum SyncStatus { synced, pending, failed }

/// 资产账户类型
enum AssetType { cash, bank, alipay, wechat, fund, stock, other }

/// 资产账户实体
class Asset extends Equatable {
  final String id;
  final String name;
  final AssetType type;
  final double balance;
  final String currency;
  final String locale;
  final String countryCode;
  final DateTime createdAt;
  final SyncStatus syncStatus;
  final String? description; // V2: 二级说明（如卡号、备注等）

  const Asset({
    required this.id,
    required this.name,
    required this.type,
    required this.balance,
    this.currency = 'CNY',
    this.locale = 'zh-CN',
    this.countryCode = 'CN',
    required this.createdAt,
    this.syncStatus = SyncStatus.pending,
    this.description,
  });

  Asset copyWith({
    String? id,
    String? name,
    AssetType? type,
    double? balance,
    String? currency,
    String? locale,
    String? countryCode,
    DateTime? createdAt,
    SyncStatus? syncStatus,
    String? description,
  }) {
    return Asset(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      balance: balance ?? this.balance,
      currency: currency ?? this.currency,
      locale: locale ?? this.locale,
      countryCode: countryCode ?? this.countryCode,
      createdAt: createdAt ?? this.createdAt,
      syncStatus: syncStatus ?? this.syncStatus,
      description: description ?? this.description,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    type,
    balance,
    currency,
    locale,
    countryCode,
    createdAt,
    syncStatus,
    description,
  ];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'balance': balance,
    'currency': currency,
    'locale': locale,
    'countryCode': countryCode,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'syncStatus': syncStatus == SyncStatus.synced
        ? 'synced'
        : (syncStatus == SyncStatus.failed ? 'failed' : 'pending'),
    if (description != null) 'description': description,
  };

  static String typeIcon(AssetType type) {
    switch (type) {
      case AssetType.cash:
        return '💵';
      case AssetType.bank:
        return '🏦';
      case AssetType.alipay:
        return '💳';
      case AssetType.wechat:
        return '💬';
      case AssetType.fund:
        return '📊';
      case AssetType.stock:
        return '📈';
      case AssetType.other:
        return '📦';
    }
  }

  static String typeName(AssetType type) {
    switch (type) {
      case AssetType.cash:
        return '现金';
      case AssetType.bank:
        return '银行卡';
      case AssetType.alipay:
        return '支付宝';
      case AssetType.wechat:
        return '微信';
      case AssetType.fund:
        return '基金';
      case AssetType.stock:
        return '股票';
      case AssetType.other:
        return '其他';
    }
  }
}

/// 账单项实体
class AccountEntry extends Equatable {
  final String id;
  final double amount; // legacy alias，当前等同于 baseAmount
  final EntryType type;
  final String category;
  final String description;
  final DateTime date;
  final DateTime createdAt;
  final SyncStatus syncStatus;
  final String? assetId; // 关联资产账户（可选）
  final double originalAmount;
  final String originalCurrency;
  final double baseAmount;
  final String baseCurrency;
  final double fxRate;
  final DateTime? fxRateDate;
  final String fxRateSource;
  final String? merchantRaw;
  final String? merchantNormalized;
  final String sourceType;
  final String locale;
  final String countryCode;

  const AccountEntry({
    required this.id,
    required this.amount,
    required this.type,
    required this.category,
    required this.description,
    required this.date,
    required this.createdAt,
    this.syncStatus = SyncStatus.pending,
    this.assetId,
    double? originalAmount,
    this.originalCurrency = 'CNY',
    double? baseAmount,
    String? baseCurrency,
    double? fxRate,
    this.fxRateDate,
    String? fxRateSource,
    this.merchantRaw,
    this.merchantNormalized,
    this.sourceType = 'manual',
    this.locale = 'zh-CN',
    this.countryCode = 'CN',
  }) : originalAmount = originalAmount ?? amount,
       baseAmount = baseAmount ?? amount,
       baseCurrency = baseCurrency ?? originalCurrency,
       fxRate = fxRate ?? 1,
       fxRateSource = fxRateSource ?? 'legacy';

  String get categoryId => category;

  /// 从 JSON Map 构造（用于从 SharedPreferences/云端数据反序列化）
  factory AccountEntry.fromJson(Map<String, dynamic> json) {
    final parsedAmount =
        _parseNum(json['amount'] ?? json['baseAmount'] ?? json['originalAmount']) ??
        0;
    final parsedOriginalAmount =
        _parseNum(json['originalAmount']) ?? parsedAmount;
    final parsedBaseAmount = _parseNum(json['baseAmount']) ?? parsedAmount;
    final parsedOriginalCurrency =
        (json['originalCurrency'] as String?) ?? 'CNY';
    final parsedBaseCurrency =
        (json['baseCurrency'] as String?) ?? parsedOriginalCurrency;

    return AccountEntry(
      id: json['id'] as String,
      amount: parsedBaseAmount,
      type: json['type'] == 'income' ? EntryType.income : EntryType.expense,
      category: (json['categoryId'] ?? json['category'] ?? 'other').toString(),
      description: json['description'] as String? ?? '',
      date: _parseDateTime(json['date']) ?? DateTime.now(),
      createdAt: _parseDateTime(json['createdAt']) ?? DateTime.now(),
      syncStatus: _parseSyncStatus(json['syncStatus'] as String?),
      assetId: json['assetId'] as String?,
      originalAmount: parsedOriginalAmount,
      originalCurrency: parsedOriginalCurrency,
      baseAmount: parsedBaseAmount,
      baseCurrency: parsedBaseCurrency,
      fxRate: _parseNum(json['fxRate']) ??
          (parsedOriginalAmount == 0 ? 1 : parsedBaseAmount / parsedOriginalAmount),
      fxRateDate: _parseDateTime(json['fxRateDate']),
      fxRateSource: (json['fxRateSource'] as String?) ?? 'legacy',
      merchantRaw: json['merchantRaw'] as String?,
      merchantNormalized: json['merchantNormalized'] as String?,
      sourceType: (json['sourceType'] as String?) ?? 'manual',
      locale: (json['locale'] as String?) ?? 'zh-CN',
      countryCode: (json['countryCode'] as String?) ?? 'CN',
    );
  }

  static SyncStatus _parseSyncStatus(String? value) {
    switch (value) {
      case 'synced':
        return SyncStatus.synced;
      case 'pending':
        return SyncStatus.pending;
      case 'failed':
        return SyncStatus.failed;
      default:
        return SyncStatus.pending;
    }
  }

  static double? _parseNum(dynamic value) {
    if (value == null) return null;
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  AccountEntry copyWith({
    String? id,
    double? amount,
    EntryType? type,
    String? category,
    String? description,
    DateTime? date,
    DateTime? createdAt,
    SyncStatus? syncStatus,
    String? assetId,
    double? originalAmount,
    String? originalCurrency,
    double? baseAmount,
    String? baseCurrency,
    double? fxRate,
    DateTime? fxRateDate,
    String? fxRateSource,
    String? merchantRaw,
    String? merchantNormalized,
    String? sourceType,
    String? locale,
    String? countryCode,
  }) {
    return AccountEntry(
      id: id ?? this.id,
      amount: amount ?? baseAmount ?? this.baseAmount,
      type: type ?? this.type,
      category: category ?? this.category,
      description: description ?? this.description,
      date: date ?? this.date,
      createdAt: createdAt ?? this.createdAt,
      syncStatus: syncStatus ?? this.syncStatus,
      assetId: assetId ?? this.assetId,
      originalAmount: originalAmount ?? this.originalAmount,
      originalCurrency: originalCurrency ?? this.originalCurrency,
      baseAmount: baseAmount ?? this.baseAmount,
      baseCurrency: baseCurrency ?? this.baseCurrency,
      fxRate: fxRate ?? this.fxRate,
      fxRateDate: fxRateDate ?? this.fxRateDate,
      fxRateSource: fxRateSource ?? this.fxRateSource,
      merchantRaw: merchantRaw ?? this.merchantRaw,
      merchantNormalized: merchantNormalized ?? this.merchantNormalized,
      sourceType: sourceType ?? this.sourceType,
      locale: locale ?? this.locale,
      countryCode: countryCode ?? this.countryCode,
    );
  }

  @override
  List<Object?> get props => [
    id,
    amount,
    type,
    category,
    description,
    date,
    createdAt,
    syncStatus,
    assetId,
    originalAmount,
    originalCurrency,
    baseAmount,
    baseCurrency,
    fxRate,
    fxRateDate,
    fxRateSource,
    merchantRaw,
    merchantNormalized,
    sourceType,
    locale,
    countryCode,
  ];

  Map<String, dynamic> toJson() => {
    'id': id,
    'amount': baseAmount,
    'type': type == EntryType.income ? 'income' : 'expense',
    'category': category,
    'categoryId': category,
    'description': description,
    'date': date.millisecondsSinceEpoch,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'syncStatus': syncStatus == SyncStatus.synced
        ? 'synced'
        : (syncStatus == SyncStatus.failed ? 'failed' : 'pending'),
    'originalAmount': originalAmount,
    'originalCurrency': originalCurrency,
    'baseAmount': baseAmount,
    'baseCurrency': baseCurrency,
    'fxRate': fxRate,
    if (fxRateDate != null) 'fxRateDate': fxRateDate!.toIso8601String(),
    'fxRateSource': fxRateSource,
    'sourceType': sourceType,
    'locale': locale,
    'countryCode': countryCode,
    if (merchantRaw != null) 'merchantRaw': merchantRaw,
    if (merchantNormalized != null) 'merchantNormalized': merchantNormalized,
    if (assetId != null) 'assetId': assetId,
  };
}

/// 分类定义
class CategoryDef {
  final String id;
  final String name;
  final String icon;

  const CategoryDef({required this.id, required this.name, required this.icon});

  static const List<CategoryDef> expenseCategories = [
    CategoryDef(id: 'food', name: '餐饮', icon: '🍜'),
    CategoryDef(id: 'transport', name: '交通', icon: '🚗'),
    CategoryDef(id: 'shopping', name: '购物', icon: '🛒'),
    CategoryDef(id: 'entertainment', name: '娱乐', icon: '🎮'),
    CategoryDef(id: 'housing', name: '居住', icon: '🏠'),
    CategoryDef(id: 'health', name: '医疗', icon: '💊'),
    CategoryDef(id: 'education', name: '教育', icon: '📚'),
    CategoryDef(id: 'beauty', name: '美容', icon: '💅'),
    CategoryDef(id: 'social', name: '社交', icon: '👥'),
    CategoryDef(id: 'travel', name: '旅行', icon: '✈️'),
    CategoryDef(id: 'sports', name: '运动', icon: '⚽'),
    CategoryDef(id: 'coffee', name: '咖啡', icon: '☕'),
    CategoryDef(id: 'snack', name: '零食', icon: '🍬'),
    CategoryDef(id: 'fruit', name: '水果', icon: '🍎'),
    CategoryDef(id: 'daily', name: '日用', icon: '🧴'),
    CategoryDef(id: 'other', name: '其他', icon: '📦'),
    // 新增类目（来自类目图）
    CategoryDef(id: 'grocery', name: '买菜', icon: '🥬'),
    CategoryDef(id: 'takeout', name: '外卖', icon: '🍱'),
    CategoryDef(id: 'vegetable', name: '蔬菜', icon: '🥦'),
    CategoryDef(id: 'drink', name: '饮品', icon: '🧃'),
    CategoryDef(id: 'clothing', name: '服饰', icon: '👔'),
    CategoryDef(id: 'phone', name: '话费', icon: '📱'),
    CategoryDef(id: 'rent', name: '房租', icon: '🏘️'),
    CategoryDef(id: 'mortgage', name: '房贷', icon: '🏦'),
    CategoryDef(id: 'housing2', name: '住房', icon: '🏡'),
    CategoryDef(id: 'gift_exp', name: '礼物', icon: '🎁'),
    CategoryDef(id: 'tobacco', name: '烟酒', icon: '🚬'),
    CategoryDef(id: 'express', name: '快递', icon: '📦'),
    CategoryDef(id: 'fandom', name: '追星', icon: '🌟'),
    CategoryDef(id: 'game', name: '游戏', icon: '🎲'),
    CategoryDef(id: 'digital', name: '数码', icon: '📲'),
    CategoryDef(id: 'movie', name: '电影票', icon: '🎬'),
    CategoryDef(id: 'car', name: '汽车', icon: '🚙'),
    CategoryDef(id: 'motorcycle', name: '摩托', icon: '🏍️'),
    CategoryDef(id: 'gas', name: '加油费', icon: '⛽'),
    CategoryDef(id: 'book', name: '书籍', icon: '📖'),
    CategoryDef(id: 'study', name: '学习', icon: '📓'),
    CategoryDef(id: 'pet', name: '宠物', icon: '🐶'),
    CategoryDef(id: 'water', name: '水费', icon: '💧'),
    CategoryDef(id: 'electric', name: '电费', icon: '⚡'),
    CategoryDef(id: 'gas_fee', name: '燃气费', icon: '🔥'),
    CategoryDef(id: 'childcare', name: '育儿', icon: '👶'),
    CategoryDef(id: 'elder', name: '长辈', icon: '👴'),
    CategoryDef(id: 'lease', name: '租赁', icon: '🔑'),
    CategoryDef(id: 'office', name: '办公', icon: '💼'),
    CategoryDef(id: 'repair', name: '维修', icon: '🔧'),
    CategoryDef(id: 'lottery', name: '彩票', icon: '🎟️'),
    CategoryDef(id: 'donation', name: '捐赠', icon: '💝'),
    CategoryDef(id: 'mahjong', name: '麻将', icon: '🀄'),
  ];

  static const List<CategoryDef> incomeCategories = [
    CategoryDef(id: 'salary', name: '工资', icon: '💰'),
    CategoryDef(id: 'bonus', name: '奖金', icon: '🎁'),
    CategoryDef(id: 'investment', name: '投资收益', icon: '📈'),
    CategoryDef(id: 'gift', name: '红包', icon: '🧧'),
    CategoryDef(id: 'refund', name: '退款', icon: '↩️'),
    CategoryDef(id: 'other_income', name: '其他', icon: '📦'),
    CategoryDef(id: 'cash_gift', name: '礼金', icon: '💵'),
    CategoryDef(id: 'lend', name: '借出', icon: '🤝'),
    CategoryDef(id: 'repay', name: '还款', icon: '↙️'),
    CategoryDef(id: 'transfer_in', name: '转账', icon: '💳'),
  ];

  static CategoryDef? findById(String id) {
    return [
      ...expenseCategories,
      ...incomeCategories,
    ].cast<CategoryDef?>().firstWhere((c) => c?.id == id, orElse: () => null);
  }
}
