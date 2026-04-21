import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config_service.dart';
import '../features/accounting/domain/entities/entities.dart';

/// 云端数据服务（阿里云函数计算 FC HTTP 触发器）
class CloudService {
  static CloudService? _instance;

  factory CloudService() {
    _instance ??= CloudService._();
    return _instance!;
  }

  CloudService._();

  Dio get _dio => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  String? get _baseUrl {
    final url = ConfigService.instance.aliyunFCApi;
    if (url.isEmpty) return null;
    return url;
  }

  bool get isConfigured => _baseUrl != null && _baseUrl!.isNotEmpty;

  String? get _phone {
    try {
      final prefs = GetIt.instance<SharedPreferences>();
      return prefs.getString('logged_in_phone');
    } catch (e) {
      return null;
    }
  }

  Map<String, String> get _headers {
    final phone = _phone;
    return {
      'Content-Type': 'application/json',
      if (phone != null && phone.isNotEmpty) 'X-User-Phone': phone,
    };
  }

  Future<Map<String, dynamic>?> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (!isConfigured) {
      debugPrint('[CloudService] not configured');
      try {
        File('/tmp/cloud_service_error.log').writeAsStringSync(
          '=== NOT CONFIGURED === method=$method path=$path baseUrl=$_baseUrl\n',
        );
      } catch (_) {}
      return null;
    }
    try {
      final url = '$_baseUrl$path';
      Response resp;
      if (method == 'GET') {
        resp = await _dio.get(url, options: Options(headers: _headers));
        debugPrint(
          '[CloudService] GET response: status=${resp.statusCode} data=${resp.data}',
        );
      } else if (method == 'POST') {
        resp = await _dio.post(
          url,
          data: jsonEncode(body ?? {}),
          options: Options(headers: _headers),
        );
        debugPrint(
          '[CloudService] POST resp status=${resp.statusCode} data_type=${resp.data?.runtimeType} data=${resp.data}',
        );
      } else if (method == 'PUT') {
        resp = await _dio.put(
          url,
          data: jsonEncode(body ?? {}),
          options: Options(headers: _headers),
        );
      } else if (method == 'DELETE') {
        resp = await _dio.delete(url, options: Options(headers: _headers));
        debugPrint(
          '[CloudService] DELETE response: status=${resp.statusCode} data=${resp.data}',
        );
      } else {
        return null;
      }
      final data = resp.data;
      if (data == null) {
        // FC 有时会返回空 body（HTTP 200 但 body=null）
        debugPrint(
          '[CloudService] resp.data is null (FC empty body). Treating as empty response.',
        );
        return {};
      }
      if (data is Map<String, dynamic>) {
        debugPrint(
          '[CloudService] data keys: ${data.keys.toList()}, success=${data['success']}, statusCode=${resp.statusCode}',
        );
        if (data['success'] == true || resp.statusCode == 200) {
          // GET /entries、/assets、/stock_positions 直接返回完整 body
          // FC 的 GET /entries 返回 {"entries": [...], "total": N}
          // FC 的 GET /assets 返回 {"assets": [...]}
          // FC 的 GET /stock_positions 返回 {"stock_positions": [...], "total": N}
          if (data.containsKey('entries') ||
              data.containsKey('assets') ||
              data.containsKey('stock_positions') ||
              data.containsKey('profile')) {
            return data;
          }
          // 优先返回 data['data']（新 FC 格式）
          if (data['data'] != null) {
            return data['data'] as Map<String, dynamic>;
          }
          // 兼容旧 FC: body 是 json.dumps() 后的字符串
          final body = data['body'];
          debugPrint('[CloudService] body type=${body.runtimeType} body=$body');
          if (body is String) {
            try {
              final parsed = jsonDecode(body);
              debugPrint('[CloudService] parsed=$parsed');
              if (parsed is Map<String, dynamic>) return parsed;
            } catch (e) {
              debugPrint('[CloudService] jsonDecode failed: $e');
            }
          } else if (body is Map<String, dynamic>) {
            debugPrint('[CloudService] body is already a Map');
            return body;
          }
          // body 也解析不了，返回空字典
          debugPrint('[CloudService] fallback: returning empty map');
          return {};
        } else {
          debugPrint('[CloudService] failed: ${data['msg'] ?? data['error']}');
          try {
            File('/tmp/cloud_service_error.log').writeAsStringSync(
              'failed: method=$method path=$path data=$data\n',
            );
          } catch (_) {}
          return null;
        }
      }
      // data 不是 Map（比如是 List），返回空字典避免崩溃
      debugPrint(
        '[CloudService] resp.data is ${data.runtimeType}, expected Map. Returning empty.',
      );
      return {};
    } catch (e, st) {
      debugPrint('[CloudService] _request error: $e');
      try {
        File('/tmp/cloud_service_error.log').writeAsStringSync(
          'error: $e\nstack: $st\nmethod: $method path=$path\n',
        );
      } catch (_) {}
      return null;
    }
  }

  // ══════════════════════════════════════════════════════

  Future<Map<String, dynamic>?> addEntry(AccountEntry entry) async {
    if (!isConfigured) return null;
    final phone = _phone;
    if (phone == null || phone.isEmpty) return null;
    try {
      return await _request(
        'POST',
        '/entries',
        body: {
          'entry_id': entry.id,
          'amount': entry.amount,
          'type': entry.type == EntryType.income ? 'income' : 'expense',
          'category': entry.category,
          'description': entry.description,
          'date': entry.date.toIso8601String(),
          'createdAt': entry.createdAt.toIso8601String(),
        },
      );
    } catch (e) {
      debugPrint('[CloudService] addEntry error: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getEntries() async {
    if (!isConfigured) return [];
    final phone = _phone;
    if (phone == null || phone.isEmpty) return [];
    try {
      final result = await _request('GET', '/entries', body: null);
      if (result != null && result.isNotEmpty) {
        final entries = result['entries'] as List? ?? [];
        return entries.cast<Map<String, dynamic>>();
      }
      return []; // 空响应视为成功但无数据
    } catch (e) {
      debugPrint('[CloudService] getEntries error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> updateEntry(AccountEntry entry) async {
    if (!isConfigured) return null;
    final phone = _phone;
    if (phone == null || phone.isEmpty) return null;
    try {
      return await _request(
        'PUT',
        '/entries/${entry.id}',
        body: {
          'amount': entry.amount,
          'type': entry.type == EntryType.income ? 'income' : 'expense',
          'category': entry.category,
          'description': entry.description,
          'date': entry.date.toIso8601String(),
        },
      );
    } catch (e) {
      debugPrint('[CloudService] updateEntry error: $e');
      return null;
    }
  }

  Future<bool> deleteEntry(String id) async {
    if (!isConfigured) return false;
    final phone = _phone;
    if (phone == null || phone.isEmpty) return false;
    try {
      final result = await _request('DELETE', '/entries/$id', body: null);
      return result != null;
    } catch (e) {
      debugPrint('[CloudService] deleteEntry error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (!isConfigured) {
      debugPrint('[CloudService] post not configured. baseUrl=$_baseUrl');
      return null;
    }
    return await _request('POST', path, body: body);
  }

  Future<Map<String, dynamic>?> get(String path) async {
    if (!isConfigured) return null;
    return await _request('GET', path, body: null);
  }

  Future<Map<String, dynamic>?> put(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (!isConfigured) return null;
    return await _request('PUT', path, body: body);
  }

  Future<bool> delete(String path) async {
    if (!isConfigured) {
      debugPrint('[CloudService] delete: not configured');
      return false;
    }
    try {
      final url = '$_baseUrl$path';
      debugPrint('[CloudService] DELETE $url');
      final resp = await _dio.delete(url, options: Options(headers: _headers));
      debugPrint(
        '[CloudService] DELETE status: ${resp.statusCode}, data: ${resp.data}',
      );
      // 只要 HTTP 200 就认为成功，不依赖 response body 里的 success 字段
      return resp.statusCode == 200;
    } catch (e) {
      debugPrint('[CloudService] delete error: $e');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════
  // VIP 档案读写（云端为权威）
  // ══════════════════════════════════════════════════════

  /// 获取云端 VIP 档案
  Future<Map<String, dynamic>?> getVipProfile() async {
    if (!isConfigured) return null;
    try {
      final result = await _request('GET', '/vip', body: null);
      if (result != null && result.containsKey('profile')) {
        final profile = result['profile'];
        if (profile == null) {
          return <String, dynamic>{};
        }
        if (profile is Map<String, dynamic>) {
          return profile;
        }
      }
      return result;
    } catch (e) {
      debugPrint('[CloudService] getVipProfile error: $e');
      return null;
    }
  }

  /// 同步 VIP 档案到云端
  /// 如果云端返回 403（订阅已过期），抛出异常供调用方处理
  Future<Map<String, dynamic>?> syncVipProfile({
    required String vipType,
    required int expireMs,
    String? receiptData,
  }) async {
    if (!isConfigured) return null;
    try {
      final result = await _request(
        'POST',
        '/vip/sync',
        body: {
          'vip_type': vipType,
          'vip_expire_ms': expireMs,
          ...?(receiptData == null ? null : {'receipt_data': receiptData}),
        },
      );
      if (result != null && result.containsKey('profile')) {
        return result['profile'] as Map<String, dynamic>;
      }
      return result;
    } catch (e) {
      debugPrint('[CloudService] syncVipProfile error: $e');
      return null;
    }
  }
}
