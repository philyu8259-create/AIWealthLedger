import 'package:flutter_test/flutter_test.dart';

import 'package:ai_accounting_app/features/accounting/domain/entities/entities.dart';
import 'package:ai_accounting_app/services/retention_prompt_service.dart';

void main() {
  test('asks users to complete today when no entry exists after evening', () {
    final prompt = RetentionPromptService.build(
      entries: [_entry('yesterday', DateTime(2026, 5, 21, 20))],
      now: DateTime(2026, 5, 22, 20),
      localeLanguageCode: 'en',
    );

    expect(prompt?.kind, RetentionPromptKind.eveningCatchup);
    expect(prompt?.title, contains('today'));
  });

  test('generates a three-day report prompt from three active days', () {
    final prompt = RetentionPromptService.build(
      entries: [
        _entry('d1', DateTime(2026, 5, 20, 10)),
        _entry('d2', DateTime(2026, 5, 21, 11)),
        _entry('d3', DateTime(2026, 5, 22, 12)),
      ],
      now: DateTime(2026, 5, 22, 12),
      localeLanguageCode: 'zh',
    );

    expect(prompt?.kind, RetentionPromptKind.threeDayReport);
    expect(prompt?.title, contains('3 天'));
  });

  test('generates a weekly summary prompt after seven active days', () {
    final prompt = RetentionPromptService.build(
      entries: [
        for (var i = 0; i < 7; i += 1)
          _entry('d$i', DateTime(2026, 5, 16 + i, 12)),
      ],
      now: DateTime(2026, 5, 22, 12),
      localeLanguageCode: 'en',
    );

    expect(prompt?.kind, RetentionPromptKind.weeklySummary);
    expect(prompt?.title, contains('weekly'));
  });
}

AccountEntry _entry(String id, DateTime date) {
  return AccountEntry(
    id: id,
    amount: 10,
    type: EntryType.expense,
    category: 'food',
    description: 'food',
    date: date,
    createdAt: date,
  );
}
