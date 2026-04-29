import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'config_service.dart';
import 'package:crypto/crypto.dart';

/// 阿里云短信认证服务 (Dypnsapi)
class AliyunSmsService {
  final Dio _dio;

  AliyunSmsService()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

  String get _backendApi => ConfigService.instance.aliyunFCApi;
  String get _accessKeyId {
    final smsKey = ConfigService.instance.env('ALIYUN_SMS_ACCESS_KEY_ID');
    return smsKey.isNotEmpty
        ? smsKey
        : ConfigService.instance.aliyunAccessKeyId;
  }

  String get _accessKeySecret {
    final smsSecret = ConfigService.instance.env(
      'ALIYUN_SMS_ACCESS_KEY_SECRET',
    );
    return smsSecret.isNotEmpty
        ? smsSecret
        : ConfigService.instance.aliyunAccessKeySecret;
  }

  String get _signName {
    final v = ConfigService.instance.env('ALIYUN_SMS_SIGN_NAME');
    return v.isEmpty ? '速通互联验证码' : v;
  }

  String get _templateCode {
    final v = ConfigService.instance.env('ALIYUN_SMS_TEMPLATE_CODE');
    return v.isEmpty ? '100001' : v;
  }

  /// 发送验证码
  /// 返回倒计时秒数，失败返回 -1
  Future<int> sendCode(String phoneNumber) async {
    final backendSeconds = await _sendCodeViaBackend(phoneNumber);
    if (backendSeconds > 0) return backendSeconds;

    if (_accessKeyId.isEmpty || _accessKeySecret.isEmpty) {
      debugPrint('[AliyunSmsService] AccessKey or Secret is empty');
      return -1;
    }
    try {
      final timestamp = _iso8601Utc();

      // 所有请求参数（含 SignatureNonce）
      final nonce = '${DateTime.now().millisecondsSinceEpoch}';
      final sortedParams = <String, String>{
        'AccessKeyId': _accessKeyId,
        'Action': 'SendSmsVerifyCode',
        'Format': 'JSON',
        'PhoneNumber': phoneNumber,
        'RegionId': 'cn-hangzhou',
        'SignName': _signName,
        'SignatureMethod': 'HMAC-SHA1',
        'SignatureNonce': nonce,
        'SignatureVersion': '1.0',
        'TemplateCode': _templateCode,
        'TemplateParam': '{"code":"##code##","min":"5"}',
        'Timestamp': timestamp,
        'Version': '2017-05-25',
      };

      // 计算签名
      final signature = _makeSignature(
        sortedParams,
        'GET',
        '/',
        _accessKeySecret,
      );
      sortedParams['Signature'] = signature;

      // GET 请求，参数放 query string
      final response = await _dio.get(
        'https://dypnsapi.aliyuncs.com/',
        queryParameters: sortedParams,
      );

      final result = response.data as Map<String, dynamic>;
      final code = result['Code'] as String?;
      final success = result['Success'] as bool?;

      if (code == 'OK' || success == true) {
        debugPrint('[AliyunSmsService] sendCode success');
        return 60;
      }
      debugPrint(
        '[AliyunSmsService] Send failed: $code - ${result['Message']}',
      );
      return -1;
    } catch (e) {
      debugPrint('[AliyunSmsService] Exception: $e');
      return -1;
    }
  }

  /// 验证验证码（调用阿里云 CheckSmsVerifyCode）
  Future<bool> verifyCode(String phoneNumber, String code) async {
    final backendValid = await _verifyCodeViaBackend(phoneNumber, code);
    if (backendValid) return true;

    if (_accessKeyId.isEmpty || _accessKeySecret.isEmpty) return false;
    try {
      final timestamp = _iso8601Utc();
      final nonce = '${DateTime.now().millisecondsSinceEpoch}';

      final sortedParams = <String, String>{
        'AccessKeyId': _accessKeyId,
        'Action': 'CheckSmsVerifyCode',
        'Format': 'JSON',
        'PhoneNumber': phoneNumber,
        'RegionId': 'cn-hangzhou',
        'SignatureMethod': 'HMAC-SHA1',
        'SignatureNonce': nonce,
        'SignatureVersion': '1.0',
        'Timestamp': timestamp,
        'VerifyCode': code,
        'Version': '2017-05-25',
      };

      final signature = _makeSignature(
        sortedParams,
        'GET',
        '/',
        _accessKeySecret,
      );
      sortedParams['Signature'] = signature;

      final response = await _dio.get(
        'https://dypnsapi.aliyuncs.com/',
        queryParameters: sortedParams,
      );

      final result = response.data as Map<String, dynamic>;
      final model = result['Model'] as Map<String, dynamic>?;
      final verifyResult = model?['VerifyResult'];
      final respCode = result['Code'] as String?;
      debugPrint('[AliyunSmsService] verifyCode status=$respCode');
      return verifyResult == 'PASS' || respCode == 'OK';
    } catch (e) {
      debugPrint('[AliyunSmsService] verifyCode exception: $e');
      return false;
    }
  }

  Future<int> _sendCodeViaBackend(String phoneNumber) async {
    final baseUrl = _backendApi.trim();
    if (baseUrl.isEmpty) return -1;

    try {
      final response = await _dio.post(
        '$baseUrl/sms/send',
        data: jsonEncode({'phone': phoneNumber}),
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      final result = _normalizeResponse(response.data);
      final message = result['message']?.toString() ?? '';
      final simulated = result['simulated'] == true;
      if (response.statusCode == 200 &&
          !simulated &&
          message.toLowerCase().contains('sms sent')) {
        debugPrint('[AliyunSmsService] backend sendCode success');
        return 60;
      }
      debugPrint(
        '[AliyunSmsService] backend sendCode unavailable: '
        'status=${response.statusCode} simulated=$simulated message=$message',
      );
      return -1;
    } catch (e) {
      debugPrint('[AliyunSmsService] backend sendCode exception: $e');
      return -1;
    }
  }

  Future<bool> _verifyCodeViaBackend(String phoneNumber, String code) async {
    final baseUrl = _backendApi.trim();
    if (baseUrl.isEmpty) return false;

    try {
      final response = await _dio.post(
        '$baseUrl/sms/verify',
        data: jsonEncode({'phone': phoneNumber, 'code': code}),
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      final result = _normalizeResponse(response.data);
      final valid = result['valid'] == true;
      debugPrint(
        '[AliyunSmsService] backend verifyCode status=${response.statusCode} valid=$valid',
      );
      return response.statusCode == 200 && valid;
    } catch (e) {
      debugPrint('[AliyunSmsService] backend verifyCode exception: $e');
      return false;
    }
  }

  Map<String, dynamic> _normalizeResponse(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.isNotEmpty) {
      final parsed = jsonDecode(data);
      if (parsed is Map<String, dynamic>) return parsed;
      if (parsed is Map) return Map<String, dynamic>.from(parsed);
    }
    return <String, dynamic>{};
  }

  /// 生成 ISO 8601 UTC 时间字符串
  String _iso8601Utc() {
    final t = DateTime.now().toUtc();
    return '${t.year}-${_p(t.month)}-${_p(t.day)}T'
        '${_p(t.hour)}:${_p(t.minute)}:${_p(t.second)}Z';
  }

  String _p(int n) => n.toString().padLeft(2, '0');

  /// 计算 Aliyun V1 签名
  /// method: GET, path: /
  String _makeSignature(
    Map<String, String> params,
    String method,
    String path,
    String secret,
  ) {
    // 1. 移除 Signature 后排序
    params.remove('Signature');
    final keys = params.keys.toList()..sort();

    // 2. 拼接成 URL query string（key=value&key=value）
    final sb = StringBuffer();
    for (int i = 0; i < keys.length; i++) {
      final k = keys[i];
      if (i > 0) sb.write('&');
      sb.write(Uri.encodeQueryComponent(k));
      sb.write('=');
      sb.write(Uri.encodeQueryComponent(params[k]!));
    }
    final queryString = sb.toString();

    // 3. 拼成 stringToSign: METHOD&path&queryString（全部 UTF-8 编码后 URIComponent）
    final stringToSign =
        '${Uri.encodeQueryComponent(method)}&${Uri.encodeQueryComponent(path)}&${Uri.encodeQueryComponent(queryString)}';

    // 4. HMAC-SHA1 + Base64
    final hmac = Hmac(sha1, utf8.encode('$secret&'));
    final digest = hmac.convert(utf8.encode(stringToSign));
    return base64Encode(digest.bytes);
  }
}
