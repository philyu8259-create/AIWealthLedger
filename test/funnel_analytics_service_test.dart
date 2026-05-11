import 'package:ai_accounting_app/services/funnel_analytics_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'trackAppOpen records first open once and app opens each time',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = FunnelAnalyticsService(prefs);

      await service.trackAppOpen();
      await service.trackAppOpen();

      final names = service
          .recentEvents()
          .map((event) => event['name'])
          .toList();
      expect(names, ['first_open', 'app_open', 'app_open']);
    },
  );

  test(
    'first record event is only emitted once while counter increments',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = FunnelAnalyticsService(prefs);

      await service.trackFirstRecordCreated(source: 'manual_entry');
      await service.trackFirstRecordCreated(source: 'batch_entry');

      final names = service
          .recentEvents()
          .map((event) => event['name'])
          .toList();
      expect(names, ['first_record_created']);
      expect(service.counter('record_created'), 2);
    },
  );
}
