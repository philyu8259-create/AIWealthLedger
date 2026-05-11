import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FunnelAnalyticsService {
  FunnelAnalyticsService(this._prefs);

  static const _eventsKey = 'funnel_events_v1';
  static const _firstOpenAtKey = 'funnel_first_open_at_v1';
  static const _firstRecordAtKey = 'funnel_first_record_at_v1';
  static const _maxStoredEvents = 240;

  final SharedPreferences _prefs;

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
    final event = <String, Object>{
      'name': name,
      'timestamp': DateTime.now().toIso8601String(),
      if (properties.isNotEmpty) 'properties': properties,
    };

    final events = _readEvents();
    events.add(event);
    final trimmed = events.length <= _maxStoredEvents
        ? events
        : events.sublist(events.length - _maxStoredEvents);

    await _prefs.setString(_eventsKey, jsonEncode(trimmed));
    debugPrint('[Funnel] $name ${properties.isEmpty ? '' : properties}');
  }

  List<Map<String, Object?>> recentEvents() {
    return _readEvents()
        .map((event) => Map<String, Object?>.from(event))
        .toList(growable: false);
  }

  int counter(String name) => _prefs.getInt('funnel_counter_$name') ?? 0;

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
}
