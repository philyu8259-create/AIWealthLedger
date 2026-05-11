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

  test('funnel summary calculates step counts and conversion rates', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = FunnelAnalyticsService(
      prefs,
      localeProvider: () =>
          const FunnelLocaleSnapshot(languageCode: 'en', countryCode: 'US'),
    );

    await service.track('app_open');
    await service.track('onboarding_viewed');
    await service.track('onboarding_completed');
    await service.trackFirstRecordCreated(source: 'manual_entry');
    await service.track('paywall_viewed');

    final summary = service.funnelSummary();

    expect(summary.first.eventName, 'app_open');
    expect(summary.first.count, 1);
    expect(
      summary
          .singleWhere((step) => step.eventName == 'first_record_created')
          .conversionFromPrevious,
      1,
    );
    expect(
      summary
          .singleWhere((step) => step.eventName == 'subscription_purchased')
          .conversionFromPrevious,
      0,
    );
  });

  test(
    'track appends locale and attribution context to event properties',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = FunnelAnalyticsService(
        prefs,
        localeProvider: () =>
            const FunnelLocaleSnapshot(languageCode: 'zh', countryCode: 'CN'),
      );

      await service.saveAttributionPayload({
        'campaignId': 123,
        'adGroupId': 456,
        'keywordId': 789,
        'countryOrRegion': 'US',
      });
      await service.track('paywall_viewed');

      final event = service.recentEvents().single;
      final properties = Map<String, Object?>.from(event['properties']! as Map);
      expect(properties['locale_language'], 'zh');
      expect(properties['locale_country'], 'CN');
      expect(properties['ad_country_or_region'], 'US');
      expect(properties['campaign_id'], '123');
      expect(properties['ad_group_id'], '456');
      expect(properties['keyword_id'], '789');
    },
  );

  test('exportCsv includes funnel source columns', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = FunnelAnalyticsService(
      prefs,
      localeProvider: () =>
          const FunnelLocaleSnapshot(languageCode: 'en', countryCode: 'US'),
    );

    await service.saveAttributionPayload({'keywordId': 123222});
    await service.track(
      'subscription_purchased',
      properties: {'plan': 'yearly'},
    );

    final csv = service.exportCsv();

    expect(
      csv.split('\n').first,
      'timestamp,event,locale_country,locale_language,ad_country_or_region,campaign_id,ad_group_id,keyword_id,properties_json',
    );
    expect(csv, contains('subscription_purchased'));
    expect(csv, contains('123222'));
  });
}
