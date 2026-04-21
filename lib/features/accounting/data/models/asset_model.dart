import '../../domain/entities/entities.dart';

class AssetModel extends Asset {
  const AssetModel({
    required super.id,
    required super.name,
    required super.type,
    required super.balance,
    super.currency,
    super.locale,
    super.countryCode,
    required super.createdAt,
    super.syncStatus,
    super.description,
  });

  factory AssetModel.fromJson(Map<String, dynamic> json) {
    final createdAt = json['createdAt'] is int
        ? DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int)
        : DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now();
    return AssetModel(
      id: json['id'] as String,
      name: json['name'] as String,
      type: AssetType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => AssetType.other,
      ),
      balance: (json['balance'] as num).toDouble(),
      currency: (json['currency'] as String?) ?? 'CNY',
      locale: (json['locale'] as String?) ?? 'zh-CN',
      countryCode: (json['countryCode'] as String?) ?? 'CN',
      createdAt: createdAt,
      syncStatus: json['syncStatus'] == 'synced'
          ? SyncStatus.synced
          : SyncStatus.pending,
      description: json['description'] as String?,
    );
  }


  factory AssetModel.fromEntity(Asset asset) {
    return AssetModel(
      id: asset.id,
      name: asset.name,
      type: asset.type,
      balance: asset.balance,
      currency: asset.currency,
      locale: asset.locale,
      countryCode: asset.countryCode,
      createdAt: asset.createdAt,
      syncStatus: asset.syncStatus,
      description: asset.description,
    );
  }
}
