import 'package:flutter/material.dart';

/// V2 语义色常量
/// 规则：全工程不允许直接使用 hex 硬编码，统一通过此类引用
abstract final class AppColors {
  // ── 品牌主色 ──────────────────────────────────────────
  /// 蓝紫主色（品牌主色）
  static const Color primary = Color(0xFF4A47D8);

  /// 蓝紫深色（品牌主色 variant）
  static const Color primaryDark = Color(0xFF3A38C8);

  // ── 金融语义色 ──────────────────────────────────────────
  /// 上涨 / 盈利（按 A 股规则：红涨）
  static const Color marketUp = Color(0xFFF56C6C);

  /// 下跌 / 亏损（按 A 股规则：绿跌）
  static const Color marketDown = Color(0xFF67C23A);

  /// 上涨 / 盈利（按美股规则：绿涨）
  static const Color marketUpUs = Color(0xFF34A853);

  /// 下跌 / 亏损（按美股规则：红跌）
  static const Color marketDownUs = Color(0xFFEA4335);

  /// 上涨 / 盈利浅底（A 股）
  static const Color marketUpSoft = Color(0xFFFDECEA);

  /// 下跌 / 亏损浅底（A 股）
  static const Color marketDownSoft = Color(0xFFEAF7EE);

  /// 上涨 / 盈利浅底（美股）
  static const Color marketUpSoftUs = Color(0xFFEAF7EE);

  /// 下跌 / 亏损浅底（美股）
  static const Color marketDownSoftUs = Color(0xFFFDECEA);

  /// 根据市场语义返回涨跌颜色，避免把 A 股红绿逻辑误用到美股。
  static Color marketChangeColor({
    required num? value,
    required bool useUsSemantics,
  }) {
    if (value == null || value == 0) return disabled;
    final positive = value > 0;
    if (useUsSemantics) {
      return positive ? marketUpUs : marketDownUs;
    }
    return positive ? marketUp : marketDown;
  }

  /// 根据市场语义返回涨跌浅色背景，用于盈亏胶囊/标签。
  static Color marketChangeSoftColor({
    required num? value,
    required bool useUsSemantics,
  }) {
    if (value == null || value == 0) return const Color(0xFFF4F4F5);
    final positive = value > 0;
    if (useUsSemantics) {
      return positive ? marketUpSoftUs : marketDownSoftUs;
    }
    return positive ? marketUpSoft : marketDownSoft;
  }

  // ── 状态色 ─────────────────────────────────────────────
  /// 警告 / 注意（用于缓存、更新中状态）
  static const Color warning = Color(0xFFE6A23C);

  /// 失败 / 错误
  static const Color error = Color(0xFFF56C6C);

  /// 禁用 / 弱信息
  static const Color disabled = Color(0xFF909399);

  // ── 背景色 ─────────────────────────────────────────────
  /// 卡片背景
  static const Color cardBackground = Colors.white;

  /// 列表条目背景（深色分隔线）
  static const Color listDivider = Color(0xFFF2F4F7);

  /// Skeleton 骨架屏色
  static const Color skeleton = Color(0xFFEEF0F3);

  // ── UI/UX 进阶优化补充 ──────────────────────────────────────────

  /// 全局高级弥散阴影（替代原本生硬的纯黑高透明度阴影）
  static List<BoxShadow> get softShadow => [
    BoxShadow(
      color: const Color(0xFF1A1A2E).withValues(alpha: 0.04),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: const Color(0xFF1A1A2E).withValues(alpha: 0.02),
      blurRadius: 8,
      offset: const Offset(0, 4),
    ),
  ];

  /// 获取分类专属的主题色（建立用户的色彩肌肉记忆）
  static Color getCategoryColor(String id) {
    const map = {
      'food': Color(0xFFFF9800),
      'transport': Color(0xFF03A9F4),
      'shopping': Color(0xFFE91E63),
      'entertainment': Color(0xFF9C27B0),
      'housing': Color(0xFF00BCD4),
      'coffee': Color(0xFF795548),
      'fruit': Color(0xFF8BC34A),
      'grocery': Color(0xFFFFC107),
      'takeout': Color(0xFFFF5722),
      'daily': Color(0xFF607D8B),
      'salary': Color(0xFF4CAF50),
      'bonus': Color(0xFF009688),
      'health': Color(0xFFEF5350),
      'education': Color(0xFF5C6BC0),
      'beauty': Color(0xFFEC407A),
      'social': Color(0xFFAB47BC),
      'travel': Color(0xFF26A69A),
      'sports': Color(0xFF42A5F5),
      'snack': Color(0xFFFF7043),
      'vegetable': Color(0xFF66BB6A),
      'drink': Color(0xFF29B6F6),
      'clothing': Color(0xFF7E57C2),
      'phone': Color(0xFF5C6BC0),
      'rent': Color(0xFF26C6DA),
      'mortgage': Color(0xFF26A69A),
      'housing2': Color(0xFF00ACC1),
      'gift_exp': Color(0xFFFFCA28),
      'tobacco': Color(0xFF8D6E63),
      'express': Color(0xFF78909C),
      'fandom': Color(0xFFEC407A),
      'game': Color(0xFF7E57C2),
      'digital': Color(0xFF5C6BC0),
      'movie': Color(0xFF8E24AA),
      'car': Color(0xFF42A5F5),
      'motorcycle': Color(0xFF29B6F6),
      'gas': Color(0xFFFF7043),
      'book': Color(0xFF5C6BC0),
      'study': Color(0xFF7986CB),
      'pet': Color(0xFFFFB74D),
      'water': Color(0xFF26C6DA),
      'electric': Color(0xFFFFD54F),
      'gas_fee': Color(0xFFFF8A65),
      'childcare': Color(0xFF66BB6A),
      'elder': Color(0xFF8D6E63),
      'lease': Color(0xFF26A69A),
      'office': Color(0xFF78909C),
      'repair': Color(0xFF90A4AE),
      'lottery': Color(0xFFAB47BC),
      'donation': Color(0xFFEF5350),
      'mahjong': Color(0xFF8E24AA),
      'investment': Color(0xFF26A69A),
      'gift': Color(0xFFFF7043),
      'refund': Color(0xFF29B6F6),
      'other_income': Color(0xFF9E9E9E),
      'cash_gift': Color(0xFF66BB6A),
      'lend': Color(0xFF5C6BC0),
      'repay': Color(0xFF26A69A),
      'transfer_in': Color(0xFF42A5F5),
    };
    return map[id] ?? const Color(0xFF9E9E9E);
  }
}
