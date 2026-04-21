import '../../domain/entities/entities.dart';

class AccountEntryModel extends AccountEntry {
  const AccountEntryModel({
    required super.id,
    required super.amount,
    required super.type,
    required super.category,
    required super.description,
    required super.date,
    required super.createdAt,
    super.syncStatus,
    super.assetId,
    super.originalAmount,
    super.originalCurrency,
    super.baseAmount,
    super.baseCurrency,
    super.fxRate,
    super.fxRateDate,
    super.fxRateSource,
    super.merchantRaw,
    super.merchantNormalized,
    super.sourceType,
    super.locale,
    super.countryCode,
  });

  factory AccountEntryModel.fromJson(Map<String, dynamic> json) {
    final entry = AccountEntry.fromJson(json);
    return AccountEntryModel.fromEntity(entry);
  }


  factory AccountEntryModel.fromEntity(AccountEntry entry) {
    return AccountEntryModel(
      id: entry.id,
      amount: entry.amount,
      type: entry.type,
      category: entry.category,
      description: entry.description,
      date: entry.date,
      createdAt: entry.createdAt,
      syncStatus: entry.syncStatus,
      assetId: entry.assetId,
      originalAmount: entry.originalAmount,
      originalCurrency: entry.originalCurrency,
      baseAmount: entry.baseAmount,
      baseCurrency: entry.baseCurrency,
      fxRate: entry.fxRate,
      fxRateDate: entry.fxRateDate,
      fxRateSource: entry.fxRateSource,
      merchantRaw: entry.merchantRaw,
      merchantNormalized: entry.merchantNormalized,
      sourceType: entry.sourceType,
      locale: entry.locale,
      countryCode: entry.countryCode,
    );
  }
}
