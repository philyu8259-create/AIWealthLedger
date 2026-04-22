import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';

import 'package:ai_accounting_app/features/accounting/domain/entities/entities.dart';
import 'package:ai_accounting_app/features/accounting/domain/repositories/account_entry_repository.dart';
import 'package:ai_accounting_app/features/accounting/domain/usecases/add_entry.dart';
import 'package:ai_accounting_app/features/accounting/domain/usecases/delete_entry.dart';
import 'package:ai_accounting_app/features/accounting/domain/usecases/get_entries_by_month.dart';
import 'package:ai_accounting_app/features/accounting/presentation/bloc/account_bloc.dart';
import 'package:ai_accounting_app/features/accounting/presentation/bloc/account_event.dart';
import 'package:ai_accounting_app/l10n/app_string_keys.dart';
import 'package:ai_accounting_app/l10n/app_strings.dart';
import 'package:ai_accounting_app/services/ai/input_parser_service.dart';
import 'package:ai_accounting_app/services/vip_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
  InAppPurchasePlatform.instance = _FakeInAppPurchasePlatform();

  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('account entry limits', () {
    test('guest user is blocked once total entries reaches 20', () async {
      final bloc = await _makeBloc(totalEntries: 20, phone: null);

      bloc.add(AddAccountEntry(_entry('new-guest')));

      final state = await bloc.stream
          .firstWhere((s) => s.showLoginLimitDialog)
          .timeout(const Duration(seconds: 1));

      expect(state.showLoginLimitDialog, isTrue);
      expect(state.showVipLimitDialog, isFalse);
      expect((bloc.repository as _FakeRepository).entries, hasLength(20));

      await bloc.close();
    });

    test('logged-in non-vip user is blocked once total entries reaches 50', () async {
      final bloc = await _makeBloc(totalEntries: 50, phone: '13800138000');

      bloc.add(AddAccountEntry(_entry('new-free-user')));

      final state = await bloc.stream
          .firstWhere((s) => s.showVipLimitDialog)
          .timeout(const Duration(seconds: 1));

      expect(state.showVipLimitDialog, isTrue);
      expect(state.showLoginLimitDialog, isFalse);
      expect((bloc.repository as _FakeRepository).entries, hasLength(50));

      await bloc.close();
    });

    test('guest user can still add the 20th entry when currently at 19', () async {
      final bloc = await _makeBloc(totalEntries: 19, phone: null);

      bloc.add(AddAccountEntry(_entry('guest-20th')));

      final state = await bloc.stream
          .firstWhere((s) => s.totalEntryCount == 20)
          .timeout(const Duration(seconds: 1));

      expect(state.showLoginLimitDialog, isFalse);
      expect(state.showVipLimitDialog, isFalse);
      expect((bloc.repository as _FakeRepository).entries, hasLength(20));

      await bloc.close();
    });

    test('logged-in non-vip user can still add the 50th entry when currently at 49', () async {
      final bloc = await _makeBloc(totalEntries: 49, phone: '13800138000');

      bloc.add(AddAccountEntry(_entry('free-user-50th')));

      final state = await bloc.stream
          .firstWhere((s) => s.totalEntryCount == 50)
          .timeout(const Duration(seconds: 1));

      expect(state.showVipLimitDialog, isFalse);
      expect(state.showLoginLimitDialog, isFalse);
      expect((bloc.repository as _FakeRepository).entries, hasLength(50));

      await bloc.close();
    });
  });

  group('localized limit copy', () {
    test('zh strings exist for guest and vip limit dialogs', () {
      final zh = AppStrings.forLocale(const Locale('zh'));

      expect(
        zh.text(AppStringKeys.homeLoginPromptTitle),
        '登录后可继续记账',
      );
      expect(
        zh.text(AppStringKeys.homeLoginPromptContent),
        contains('20 条账单'),
      );
      expect(
        zh.text(AppStringKeys.homeVipUpgradeContent),
        contains('50 条账单'),
      );
    });

    test('en strings exist for guest and vip limit dialogs', () {
      final en = AppStrings.forLocale(const Locale('en'));

      expect(
        en.text(AppStringKeys.homeLoginPromptTitle),
        'Sign in to keep adding entries',
      );
      expect(
        en.text(AppStringKeys.homeLoginPromptContent),
        contains('20 entries'),
      );
      expect(
        en.text(AppStringKeys.homeVipUpgradeContent),
        contains('50 entries'),
      );
    });
  });
}

Future<AccountBloc> _makeBloc({
  required int totalEntries,
  required String? phone,
}) async {
  final initialValues = <String, Object>{};
  if (phone != null) {
    initialValues['logged_in_phone'] = phone;
  }
  SharedPreferences.setMockInitialValues(initialValues);
  final prefs = await SharedPreferences.getInstance();
  final vipService = VipService(prefs);
  final repository = _FakeRepository(
    entries: List.generate(totalEntries, (index) => _entry('seed-$index')),
    phone: phone,
  );

  return AccountBloc(
    getEntriesByMonth: GetEntriesByMonth(repository),
    addEntry: AddEntry(repository),
    deleteEntry: DeleteEntry(repository),
    inputParserService: const _FakeInputParserService(),
    vipService: vipService,
    repository: repository,
  );
}

AccountEntry _entry(String id) {
  final now = DateTime(2026, 4, 22, 12, 0, 0);
  return AccountEntry(
    id: id,
    amount: 12.34,
    type: EntryType.expense,
    category: 'food',
    description: 'test entry',
    date: now,
    createdAt: now,
  );
}

class _FakeInputParserService implements InputParserService {
  const _FakeInputParserService();

  @override
  Future<List<ParsedResult>> parseInput(String input) async => const [];
}

class _FakeInAppPurchasePlatform extends InAppPurchasePlatform {
  final StreamController<List<PurchaseDetails>> _controller =
      StreamController<List<PurchaseDetails>>.broadcast();

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _controller.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    return ProductDetailsResponse(productDetails: const [], notFoundIDs: []);
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    return true;
  }

  @override
  Future<bool> buyConsumable({
    required PurchaseParam purchaseParam,
    bool autoConsume = true,
  }) async {
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {}

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {}

  @override
  Future<String> countryCode() async => 'CN';
}

class _FakeRepository implements AccountEntryRepository {
  _FakeRepository({required List<AccountEntry> entries, required this.phone})
    : entries = List<AccountEntry>.from(entries);

  final String? phone;
  final List<AccountEntry> entries;

  @override
  Future<Either<String, AccountEntry>> addEntry(AccountEntry entry) async {
    entries.insert(0, entry);
    return Right(entry);
  }

  @override
  Future<Either<String, void>> deleteEntry(String id) async {
    entries.removeWhere((entry) => entry.id == id);
    return const Right(null);
  }

  @override
  Future<Either<String, List<AccountEntry>>> getEntries() async {
    return Right(List<AccountEntry>.from(entries));
  }

  @override
  Future<Either<String, List<AccountEntry>>> getEntriesByMonth(
    int year,
    int month,
  ) async {
    return Right(
      entries
          .where((entry) => entry.date.year == year && entry.date.month == month)
          .toList(),
    );
  }

  @override
  String? getCurrentPhone() => phone;

  @override
  bool isDemoAccount() => false;

  @override
  Future<Either<String, AccountEntry>> updateEntry(AccountEntry entry) async {
    final index = entries.indexWhere((item) => item.id == entry.id);
    if (index >= 0) {
      entries[index] = entry;
    }
    return Right(entry);
  }
}
