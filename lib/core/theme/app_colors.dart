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
}
