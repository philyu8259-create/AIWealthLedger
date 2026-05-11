import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class AutoBookkeepingShortcutService with WidgetsBindingObserver {
  AutoBookkeepingShortcutService({
    MethodChannel channel = const MethodChannel(
      'com.aiaccounting/auto_bookkeeping',
    ),
  }) : _channel = channel {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  final MethodChannel _channel;
  final _textRequests = StreamController<String>.broadcast();
  bool _observingLifecycle = false;

  Stream<String> get textRequests => _textRequests.stream;

  void start() {
    if (_observingLifecycle) return;
    _observingLifecycle = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(consumePendingText());
  }

  Future<void> consumePendingText() async {
    final text = await _channel.invokeMethod<String>('consumePendingText');
    _emitIfUseful(text);
  }

  Future<void> dispose() async {
    if (_observingLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
      _observingLifecycle = false;
    }
    await _textRequests.close();
    _channel.setMethodCallHandler(null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(consumePendingText());
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'recordText':
        _emitIfUseful(call.arguments as String?);
      default:
        throw MissingPluginException('Unsupported method ${call.method}');
    }
  }

  void _emitIfUseful(String? text) {
    final trimmed = text?.trim();
    if (trimmed == null || trimmed.isEmpty || _textRequests.isClosed) return;
    _textRequests.add(trimmed);
  }
}
