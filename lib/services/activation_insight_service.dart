import '../features/accounting/domain/entities/entities.dart';

class ActivationInsight {
  const ActivationInsight({required this.title, required this.subtitle});

  final String title;
  final String subtitle;
}

typedef CategoryNameResolver = String Function(String categoryId);

class ActivationInsightService {
  const ActivationInsightService._();

  static ActivationInsight build({
    required List<AccountEntry> existingEntries,
    required List<AccountEntry> savedEntries,
    required DateTime now,
    required String localeLanguageCode,
    required CategoryNameResolver categoryName,
  }) {
    final isZh = localeLanguageCode == 'zh';
    final allEntries = [...existingEntries, ...savedEntries];
    final savedExpense = savedEntries
        .where((entry) => entry.type == EntryType.expense)
        .toList();

    if (allEntries.length < 3) {
      return ActivationInsight(
        title: isZh
            ? '已记录 ${savedEntries.length} 笔，画像开始建立'
            : 'Saved ${savedEntries.length} record(s). Your picture is starting',
        subtitle: isZh
            ? '继续记录 3 天后，我会给你第一份消费结构和趋势提醒。'
            : 'Keep logging for 3 days to unlock your first spending structure and trend signal.',
      );
    }

    if (savedExpense.isNotEmpty) {
      final categoryId = savedExpense.first.category;
      final categoryTotal = _monthExpense(allEntries, now, categoryId);
      final monthTotal = _monthExpense(allEntries, now, null);
      final share = monthTotal <= 0 ? 0 : (categoryTotal / monthTotal) * 100;
      final category = categoryName(categoryId);
      final savedAmount = savedExpense.fold<double>(
        0,
        (sum, entry) => sum + entry.amount,
      );
      final previousSameCategory = existingEntries
          .where(
            (entry) =>
                entry.type == EntryType.expense &&
                entry.category == categoryId &&
                _isSameMonth(entry.date, now),
          )
          .toList();
      final average = previousSameCategory.isEmpty
          ? null
          : previousSameCategory.fold<double>(
                  0,
                  (sum, entry) => sum + entry.amount,
                ) /
                previousSameCategory.length;

      if (average != null && average > 0) {
        final diff = ((savedAmount / savedExpense.length) - average) / average;
        if (diff.abs() >= 0.15) {
          final percent = (diff.abs() * 100).round();
          return ActivationInsight(
            title: isZh ? '$category 已更新' : '$category updated',
            subtitle: isZh
                ? '这笔比你本月同类平均${diff > 0 ? '高' : '低'} $percent%，继续记录会让提醒更准。'
                : 'This spending is $percent% ${diff > 0 ? 'above' : 'below'} your monthly average for this category.',
          );
        }
      }

      return ActivationInsight(
        title: isZh ? '$category 占比已更新' : '$category share updated',
        subtitle: isZh
            ? '$category 约占本月支出的 ${share.toStringAsFixed(0)}%，继续记录会让预算风险更清楚。'
            : '$category is about ${share.toStringAsFixed(0)}% of this month’s spending. Keep logging to sharpen budget risk.',
      );
    }

    final thisWeek = _weekExpense(allEntries, now, 0);
    final lastWeek = _weekExpense(allEntries, now, -7);
    if (lastWeek > 0) {
      final diff = ((thisWeek - lastWeek) / lastWeek) * 100;
      return ActivationInsight(
        title: isZh ? '本周趋势已更新' : 'Weekly trend updated',
        subtitle: isZh
            ? '本周净支出较上周${diff >= 0 ? '高' : '低'} ${diff.abs().toStringAsFixed(0)}%。'
            : 'This week’s spending is ${diff.abs().toStringAsFixed(0)}% ${diff >= 0 ? 'higher' : 'lower'} than last week.',
      );
    }

    return ActivationInsight(
      title: isZh ? '新的月度画像已更新' : 'Monthly picture updated',
      subtitle: isZh
          ? '继续记录几天后，消费趋势和预算提醒会更准确。'
          : 'Keep logging for a few days to make trend and budget signals sharper.',
    );
  }

  static double _monthExpense(
    List<AccountEntry> entries,
    DateTime now,
    String? categoryId,
  ) {
    return entries
        .where((entry) {
          if (entry.type != EntryType.expense) return false;
          if (!_isSameMonth(entry.date, now)) return false;
          if (categoryId != null && entry.category != categoryId) return false;
          return true;
        })
        .fold<double>(0, (sum, entry) => sum + entry.amount);
  }

  static double _weekExpense(
    List<AccountEntry> entries,
    DateTime now,
    int dayOffset,
  ) {
    final target = now.add(Duration(days: dayOffset));
    final start = DateTime(
      target.year,
      target.month,
      target.day,
    ).subtract(Duration(days: target.weekday - 1));
    final end = start.add(const Duration(days: 7));
    return entries
        .where(
          (entry) =>
              entry.type == EntryType.expense &&
              !entry.date.isBefore(start) &&
              entry.date.isBefore(end),
        )
        .fold<double>(0, (sum, entry) => sum + entry.amount);
  }

  static bool _isSameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;
}
