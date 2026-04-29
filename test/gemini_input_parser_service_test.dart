import 'package:ai_accounting_app/services/ai/input_parser_service.dart';
import 'package:ai_accounting_app/services/gemini_input_parser_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GeminiInputParserService fallback receipt parsing', () {
    test(
      'uses receipt grand total instead of subtotal or tax for service receipts',
      () {
        final service = GeminiInputParserService();

        final results = service.debugFallbackParse('''
STAR CAFE
Latte 4.50
Sandwich 8.00
Subtotal 12.50
Tax 1.03
Grand Total USD 13.53
Card **** 1234
Thank you
''');

        expect(results, hasLength(1));
        expect(results.single.amount, 13.53);
        expect(results.single.category, 'coffee');
        expect(results.single.type, 'expense');
        expect(results.single.note, 'STAR CAFE');
      },
    );

    test('splits itemized retail receipts into item rows', () {
      final service = GeminiInputParserService();

      final input = '''
Shopping Receipt
Store: FreshMart
Address: 123 Main St, Cityville
Date: 2024.10.05
Time: 14:30

Item        Quantity    Price
Apples      3           \$2.50
Milk        1           \$3.00
Bread       2           \$4.00

Subtotal: \$9.50
Tax: \$0.76
Total: \$10.26
Thank you for shopping!
''';

      final results = service.debugFallbackParse(input);

      expect(results, hasLength(3));
      expect(
        results.map((e) => e.note),
        containsAll(['Apples', 'Milk', 'Bread']),
      );
      expect(results.map((e) => e.amount), containsAll([2.50, 3.00, 4.00]));
      expect(results.every((e) => e.type == 'expense'), isTrue);
    });

    test('overrides model total when itemized receipt rows are visible', () {
      final service = GeminiInputParserService();

      final input = '''
Shopping Receipt
Store: FreshMart
Item        Quantity    Price
Apples      3           \$2.50
Milk        1           \$3.00
Bread       2           \$4.00
Subtotal: \$9.50
Tax: \$0.76
Total: \$10.26
''';

      final results = service.debugReconcileModelResults(input, const [
        ParsedResult(
          amount: 10.26,
          category: 'shopping',
          note: 'FreshMart',
          type: 'expense',
        ),
      ]);

      expect(results, hasLength(3));
      expect(results.map((e) => e.amount), containsAll([2.50, 3.00, 4.00]));
    });

    test('uses paid amount for ecommerce receipt text', () {
      final service = GeminiInputParserService();

      final results = service.debugFallbackParse('''
Online Store
Original Price 129.00
Discount 30.00
Amount Paid ₱99.00
Order No 202604290001
''');

      expect(results, hasLength(1));
      expect(results.single.amount, 99.00);
      expect(results.single.category, 'shopping');
      expect(results.single.note, 'Online Store');
    });

    test(
      'keeps travel order screenshots as confirmed purchases, not recommendations',
      () {
        final service = GeminiInputParserService();

        final results = service.debugFallbackParse('''
Feizhu Scenic Area Flagship Store confirmed
Universal Studios Grand Hotel
Room 1 night May 2 - May 3
Paid amount ¥2341.52
Book tickets

May 02 Beijing recommendations
Popular attractions
One day tour

Train ticket issued successfully
Shanghai South - Beijing South
2026-05-01 21:05 to 09:24
D10
Total ¥2652.00
Change ticket
Refund ticket
''');

        expect(results, hasLength(2));
        expect(results.map((e) => e.amount), containsAll([2341.52, 2652.00]));
        expect(results.any((e) => e.category == 'travel'), isTrue);
        expect(results.any((e) => e.category == 'transport'), isTrue);
      },
    );

    test('keeps natural language multi-transaction parsing', () {
      final service = GeminiInputParserService();

      final results = service.debugFallbackParse('coffee 5, lunch 12.50');

      expect(results.map((e) => e.amount), containsAll([5, 12.50]));
    });
  });
}
