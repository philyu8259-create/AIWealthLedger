import 'package:ai_accounting_app/services/auto_bookkeeping_shortcut_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aiaccounting/auto_bookkeeping');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('consumePendingText emits shortcut text once', () async {
    var consumed = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'consumePendingText');
          if (consumed) return null;
          consumed = true;
          return '星巴克 36元';
        });

    final service = AutoBookkeepingShortcutService(channel: channel);
    final emitted = <String>[];
    final subscription = service.textRequests.listen(emitted.add);

    await service.consumePendingText();
    await service.consumePendingText();

    expect(emitted, ['星巴克 36元']);
    await subscription.cancel();
    await service.dispose();
  });

  test('native push handler ignores blank text', () async {
    final service = AutoBookkeepingShortcutService(channel: channel);
    final emitted = <String>[];
    final subscription = service.textRequests.listen(emitted.add);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(const MethodCall('recordText', '   ')),
          (_) {},
        );

    expect(emitted, isEmpty);
    await subscription.cancel();
    await service.dispose();
  });

  test('consumePendingText ignores missing Android native channel', () async {
    final service = AutoBookkeepingShortcutService(channel: channel);
    final emitted = <String>[];
    final subscription = service.textRequests.listen(emitted.add);

    await service.consumePendingText();

    expect(emitted, isEmpty);
    await subscription.cancel();
    await service.dispose();
  });
}
