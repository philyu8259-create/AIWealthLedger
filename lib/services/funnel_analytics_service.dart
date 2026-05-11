import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef FunnelLocaleProvider = FunnelLocaleSnapshot Function();

class FunnelLocaleSnapshot {
  const FunnelLocaleSnapshot({required this.languageCode, this.countryCode});

  final String languageCode;
  final String? countryCode;
}

class FunnelStepSummary {
  const FunnelStepSummary({
    required this.eventName,
    required this.label,
    required this.count,
    required this.conversionFromPrevious,
  });

  final String eventName;
  final String label;
  final int count;
  final double? conversionFromPrevious;
}

class FunnelAnalyticsService {
  FunnelAnalyticsService(
    this._prefs, {
    FunnelLocaleProvider? localeProvider,
    MethodChannel? attributionChannel,
  }) : _localeProvider = localeProvider ?? _defaultLocaleSnapshot,
       _attributionChannel =
           attributionChannel ??
           const MethodChannel('com.aiaccounting/apple_ads_attribution');

  static const _eventsKey = 'funnel_events_v1';
  static const _firstOpenAtKey = 'funnel_first_open_at_v1';
  static const _firstRecordAtKey = 'funnel_first_record_at_v1';
  static const _attributionTokenKey = 'apple_ads_attribution_token_v1';
  static const _attributionFetchedAtKey = 'apple_ads_attribution_fetched_at_v1';
  static const _attributionStatusKey = 'apple_ads_attribution_status_v1';
  static const _attributionPayloadKey = 'apple_ads_attribution_payload_v1';
  static const _maxStoredEvents = 240;

  final SharedPreferences _prefs;
  final FunnelLocaleProvider _localeProvider;
  final MethodChannel _attributionChannel;

  static const List<(String, String)> _defaultFunnelSteps = [
    ('app_open', 'Open App'),
    ('onboarding_viewed', 'See Onboarding'),
    ('onboarding_completed', 'Enter App'),
    ('first_record_created', 'First Record'),
    ('paywall_viewed', 'See Paywall'),
    ('subscription_cta_tapped', 'Tap Purchase'),
    ('subscription_checkout_started', 'Start Checkout'),
    ('subscription_purchased', 'Purchase'),
  ];

  Future<void> trackAppOpen() async {
    final now = DateTime.now();
    if (!_prefs.containsKey(_firstOpenAtKey)) {
      await _prefs.setString(_firstOpenAtKey, now.toIso8601String());
      await track('first_open', properties: {'source': 'app_launch'});
    }
    await track('app_open', properties: {'source': 'app_launch'});
  }

  Future<void> trackFirstRecordCreated({
    required String source,
    int? totalEntryCount,
  }) async {
    await incrementCounter('record_created');
    if (_prefs.containsKey(_firstRecordAtKey)) return;

    final now = DateTime.now();
    await _prefs.setString(_firstRecordAtKey, now.toIso8601String());
    await track(
      'first_record_created',
      properties: {
        'source': source,
        if (totalEntryCount != null) 'total_entry_count': '$totalEntryCount',
      },
    );
  }

  Future<void> incrementCounter(String name, {int by = 1}) async {
    final key = 'funnel_counter_$name';
    await _prefs.setInt(key, (_prefs.getInt(key) ?? 0) + by);
  }

  Future<void> track(
    String name, {
    Map<String, String> properties = const {},
  }) async {
    final mergedProperties = {..._sourceProperties(), ...properties};
    final event = <String, Object>{
      'name': name,
      'timestamp': DateTime.now().toIso8601String(),
      if (mergedProperties.isNotEmpty) 'properties': mergedProperties,
    };

    final events = _readEvents();
    events.add(event);
    final trimmed = events.length <= _maxStoredEvents
        ? events
        : events.sublist(events.length - _maxStoredEvents);

    await _prefs.setString(_eventsKey, jsonEncode(trimmed));
    debugPrint(
      '[Funnel] $name ${mergedProperties.isEmpty ? '' : mergedProperties}',
    );
  }

  List<Map<String, Object?>> recentEvents() {
    return _readEvents()
        .map((event) => Map<String, Object?>.from(event))
        .toList(growable: false);
  }

  List<FunnelStepSummary> funnelSummary() {
    final counts = <String, int>{};
    for (final event in _readEvents()) {
      final name = event['name'];
      if (name is String) counts[name] = (counts[name] ?? 0) + 1;
    }

    int? previousCount;
    final summary = <FunnelStepSummary>[];
    for (final (eventName, label) in _defaultFunnelSteps) {
      final count = counts[eventName] ?? 0;
      summary.add(
        FunnelStepSummary(
          eventName: eventName,
          label: label,
          count: count,
          conversionFromPrevious: previousCount == null
              ? null
              : (previousCount == 0 ? 0 : count / previousCount),
        ),
      );
      previousCount = count;
    }
    return summary;
  }

  String exportCsv() {
    final buffer = StringBuffer()
      ..writeln(
        'timestamp,event,locale_country,locale_language,ad_country_or_region,campaign_id,ad_group_id,keyword_id,properties_json',
      );

    for (final event in recentEvents()) {
      final properties = _eventProperties(event);
      buffer.writeln(
        [
          event['timestamp'] ?? '',
          event['name'] ?? '',
          properties['locale_country'] ?? '',
          properties['locale_language'] ?? '',
          properties['ad_country_or_region'] ?? '',
          properties['campaign_id'] ?? '',
          properties['ad_group_id'] ?? '',
          properties['keyword_id'] ?? '',
          jsonEncode(properties),
        ].map((value) => _escapeCsv('$value')).join(','),
      );
    }

    return buffer.toString();
  }

  Map<String, String> sourceSummary() => _sourceProperties();

  int counter(String name) => _prefs.getInt('funnel_counter_$name') ?? 0;

  Future<void> refreshAttributionContext() async {
    if (kIsWeb || !Platform.isIOS) {
      await _prefs.setString(_attributionStatusKey, 'unsupported_platform');
      return;
    }

    try {
      final token = await _attributionChannel.invokeMethod<String>(
        'getAttributionToken',
      );
      if (token == null || token.isEmpty) {
        await _prefs.setString(_attributionStatusKey, 'empty_token');
        return;
      }

      await _prefs.setString(_attributionTokenKey, token);
      await _prefs.setString(
        _attributionFetchedAtKey,
        DateTime.now().toIso8601String(),
      );
      await _prefs.setString(_attributionStatusKey, 'token_available');
      await track(
        'apple_ads_attribution_token_received',
        properties: {'token_length': '${token.length}'},
      );
    } on MissingPluginException {
      await _prefs.setString(_attributionStatusKey, 'missing_plugin');
    } on PlatformException catch (error) {
      await _prefs.setString(_attributionStatusKey, 'error_${error.code}');
    } catch (_) {
      await _prefs.setString(_attributionStatusKey, 'unknown_error');
    }
  }

  Future<void> saveAttributionPayload(Map<String, Object?> payload) async {
    await _prefs.setString(_attributionPayloadKey, jsonEncode(payload));
    await _prefs.setString(_attributionStatusKey, 'payload_available');
  }

  String? get attributionToken => _prefs.getString(_attributionTokenKey);

  String get attributionStatus =>
      _prefs.getString(_attributionStatusKey) ?? 'not_requested';

  List<Map<String, Object?>> _readEvents() {
    final raw = _prefs.getString(_eventsKey);
    if (raw == null || raw.isEmpty) return <Map<String, Object?>>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, Object?>>[];
      return decoded
          .whereType<Map>()
          .map((event) => Map<String, Object?>.from(event))
          .toList();
    } catch (_) {
      return <Map<String, Object?>>[];
    }
  }

  Map<String, String> _sourceProperties() {
    final locale = _localeProvider();
    final properties = <String, String>{
      'locale_language': locale.languageCode,
      if (locale.countryCode != null && locale.countryCode!.isNotEmpty)
        'locale_country': locale.countryCode!,
      'platform': _platformLabel(),
      'apple_ads_attribution_status': attributionStatus,
      if (_prefs.containsKey(_attributionTokenKey))
        'apple_ads_token_available': 'true',
    };

    final fetchedAt = _prefs.getString(_attributionFetchedAtKey);
    if (fetchedAt != null) properties['apple_ads_token_fetched_at'] = fetchedAt;

    final payload = _readAttributionPayload();
    void copyPayloadValue(String sourceKey, String targetKey) {
      final value = payload[sourceKey];
      if (value != null) properties[targetKey] = '$value';
    }

    copyPayloadValue('countryOrRegion', 'ad_country_or_region');
    copyPayloadValue('campaignId', 'campaign_id');
    copyPayloadValue('adGroupId', 'ad_group_id');
    copyPayloadValue('keywordId', 'keyword_id');
    copyPayloadValue('adId', 'ad_id');
    copyPayloadValue('claimType', 'claim_type');
    copyPayloadValue('conversionType', 'conversion_type');
    copyPayloadValue('supplyPlacement', 'supply_placement');

    return properties;
  }

  Map<String, Object?> _readAttributionPayload() {
    final raw = _prefs.getString(_attributionPayloadKey);
    if (raw == null || raw.isEmpty) return <String, Object?>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, Object?>{};
      return Map<String, Object?>.from(decoded);
    } catch (_) {
      return <String, Object?>{};
    }
  }

  Map<String, Object?> _eventProperties(Map<String, Object?> event) {
    final rawProperties = event['properties'];
    if (rawProperties is! Map) return <String, Object?>{};
    return Map<String, Object?>.from(rawProperties);
  }

  static FunnelLocaleSnapshot _defaultLocaleSnapshot() {
    final locale = PlatformDispatcher.instance.locale;
    return FunnelLocaleSnapshot(
      languageCode: locale.languageCode,
      countryCode: locale.countryCode,
    );
  }

  static String _platformLabel() {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
