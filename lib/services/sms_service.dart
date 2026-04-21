import 'dart:convert';
import 'package:dio/dio.dart';
import 'config_service.dart';

/// 短信验证码服务
/// 调阿里云 FC 上的 /sms/send 和 /sms/verify 接口
class SmsService {
  Dio get _dio => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  String? get _baseUrl {
    final url = ConfigService.instance.env('ALIYUN_FC_API');
    return url.isNotEmpty ? url : null;
  }

  bool get isConfigured => _baseUrl != null && _baseUrl!.isNotEmpty;

  /// 发送验证码
  /// 返回 {simulated: bool, message: string}
  Future<Map<String, dynamic>> sendCode(String phone) async {
    if (!isConfigured) {
      // 未配置 FC 时，返回模拟成功
      return {'simulated': true, 'message': 'SMS not configured (simulated)'};
    }
    try {
      final resp = await _dio.post(
        '$_baseUrl/sms/send',
        data: jsonEncode({'phone': phone}),
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      return resp.data as Map<String, dynamic>;
    } catch (e) {
      return {'simulated': false, 'error': e.toString()};
    }
  }

  /// 验证验证码
  /// 返回 {valid: bool, reason?: string}
  Future<Map<String, dynamic>> verifyCode(String phone, String code) async {
    if (!isConfigured) {
      // 未配置时，模拟验证（任意6位数字都能过）
      return {'valid': code.length == 6};
    }
    try {
      final resp = await _dio.post(
        '$_baseUrl/sms/verify',
        data: jsonEncode({'phone': phone, 'code': code}),
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      return resp.data as Map<String, dynamic>;
    } catch (e) {
      return {'valid': false, 'error': e.toString()};
    }
  }
}
