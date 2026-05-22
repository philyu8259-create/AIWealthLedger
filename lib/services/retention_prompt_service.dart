import '../features/accounting/domain/entities/entities.dart';

enum RetentionPromptKind { eveningCatchup, threeDayReport, weeklySummary }

class RetentionPrompt {
  const RetentionPrompt({
    required this.kind,
    required this.title,
    required this.subtitle,
  });

  final RetentionPromptKind kind;
  final String title;
  final String subtitle;
}

class RetentionPromptService {
  const RetentionPromptService._();

  static RetentionPrompt? build({
    required List<AccountEntry> entries,
    required DateTime now,
    required String localeLanguageCode,
  }) {
    if (entries.isEmpty) return null;
    final isZh = localeLanguageCode == 'zh';
    final activeDays = _activeDayKeys(entries).length;

    if (activeDays >= 7) {
      return RetentionPrompt(
        kind: RetentionPromptKind.weeklySummary,
        title: isZh ? '本周总结已准备好' : 'Your weekly summary is ready',
        subtitle: isZh
            ? '查看本周消费结构，找出最值得调整的一类支出。'
            : 'Review this week’s spending structure and spot the category worth adjusting.',
      );
    }

    if (activeDays >= 3) {
      return RetentionPrompt(
        kind: RetentionPromptKind.threeDayReport,
        title: isZh ? '已连续形成 3 天画像' : 'Your 3-day picture is ready',
        subtitle: isZh
            ? '现在可以查看初步消费结构和趋势提醒。'
            : 'You can now review early spending structure and trend signals.',
      );
    }

    if (now.hour >= 19 && !_hasEntryOnDay(entries, now)) {
      return RetentionPrompt(
        kind: RetentionPromptKind.eveningCatchup,
        title: isZh ? '今晚补一笔，明天趋势更准' : 'Add today’s spending before tomorrow',
        subtitle: isZh
            ? '补上今天的账单，我会继续完善你的消费画像。'
            : 'Catch up on today so your trend stays accurate.',
      );
    }

    return null;
  }

  static Set<String> _activeDayKeys(List<AccountEntry> entries) {
    return entries.map((entry) {
      final d = entry.date;
      return '${d.year}-${d.month}-${d.day}';
    }).toSet();
  }

  static bool _hasEntryOnDay(List<AccountEntry> entries, DateTime day) {
    return entries.any(
      (entry) =>
          entry.date.year == day.year &&
          entry.date.month == day.month &&
          entry.date.day == day.day,
    );
  }
}
