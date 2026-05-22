import 'package:flutter_test/flutter_test.dart';

import 'package:ai_accounting_app/features/accounting/domain/entities/entities.dart';
import 'package:ai_accounting_app/services/activation_insight_service.dart';

void main() {
  test('builds category-share feedback after saving an expense', () {
    final now = DateTime(2026, 5, 22, 12);
    final entries = [
      _entry('food-old', 62, 'food', now.subtract(const Duration(days: 1))),
      _entry('transport-old', 38, 'transport', now),
    ];
    final saved = [_entry('food-new', 100, 'food', now)];

    final insight = ActivationInsightService.build(
      existingEntries: entries,
      savedEntries: saved,
      now: now,
      localeLanguageCode: 'en',
      categoryName: (id) => id == 'food' ? 'Food' : id,
    );

    expect(insight.title, contains('Food'));
    expect(insight.subtitle, contains('spending'));
    expect(insight.subtitle, contains('%'));
  });

  test('prompts users toward a three-day report while data is thin', () {
    final now = DateTime(2026, 5, 22, 12);
    final saved = [_entry('first', 28, 'coffee', now)];

    final insight = ActivationInsightService.build(
      existingEntries: const [],
      savedEntries: saved,
      now: now,
      localeLanguageCode: 'zh',
      categoryName: (_) => '咖啡',
    );

    expect(insight.title, contains('已记录'));
    expect(insight.subtitle, contains('3 天'));
  });
}

AccountEntry _entry(String id, double amount, String category, DateTime date) {
  return AccountEntry(
    id: id,
    amount: amount,
    type: EntryType.expense,
    category: category,
    description: category,
    date: date,
    createdAt: date,
  );
}
