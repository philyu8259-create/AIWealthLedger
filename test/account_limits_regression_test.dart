import 'package:ai_accounting_app/features/accounting/domain/entities/entities.dart';
import 'package:ai_accounting_app/features/accounting/domain/repositories/account_entry_repository.dart';
import 'package:ai_accounting_app/features/accounting/domain/usecases/add_entry.dart';
import 'package:ai_accounting_app/features/accounting/domain/usecases/delete_entry.dart';
import 'package:ai_accounting_app/features/accounting/domain/usecases/get_entries_by_month.dart';
import 'package:ai_accounting_app/features/accounting/presentation/bloc/account_bloc.dart';
import 'package:ai_accounting_app/features/accounting/presentation/bloc/account_event.dart';
import 'package:ai_accounting_app/services/ai/input_parser_service.dart';
import 'package:ai_accounting_app/services/vip_service.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('account entry recording is unlimited', () {
    test('guest user can add after the old 20-entry threshold', () async {
      final bloc = await _makeBloc(totalEntries: 20, phone: null);

      bloc.add(AddAccountEntry(_entry('new-guest')));

      final state = await bloc.stream
          .firstWhere((s) => s.totalEntryCount == 21)
          .timeout(const Duration(seconds: 1));

      expect(state.totalEntryCount, 21);
      expect((bloc.repository as _FakeRepository).entries, hasLength(21));

      await bloc.close();
    });

    test(
      'logged-in free user can add after the old 50-entry threshold',
      () async {
        final bloc = await _makeBloc(totalEntries: 50, phone: '13800138000');

        bloc.add(AddAccountEntry(_entry('new-free-user')));

        final state = await bloc.stream
            .firstWhere((s) => s.totalEntryCount == 51)
            .timeout(const Duration(seconds: 1));

        expect(state.totalEntryCount, 51);
        expect((bloc.repository as _FakeRepository).entries, hasLength(51));

        await bloc.close();
      },
    );

    test('batch add can cross the old free-user threshold', () async {
      final bloc = await _makeBloc(totalEntries: 49, phone: '13800138000');

      bloc.add(
        AddMultipleAccountEntries([
          _entry('batch-50'),
          _entry('batch-51'),
          _entry('batch-52'),
        ]),
      );

      final state = await bloc.stream
          .firstWhere((s) => s.totalEntryCount == 52)
          .timeout(const Duration(seconds: 1));

      expect(state.totalEntryCount, 52);

      await bloc.close();
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
          .where(
            (entry) => entry.date.year == year && entry.date.month == month,
          )
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
