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

  String get _accessKeyId =>
      ConfigService.instance.env('ALIYUN_SMS_ACCESS_KEY_ID');
  String get _accessKeySecret =>
      ConfigService.instance.env('ALIYUN_SMS_ACCESS_KEY_SECRET');
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
    debugPrint('[AliyunSmsService] sendCode called, keyId=$_accessKeyId');
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

      debugPrint('[AliyunSmsService] timestamp=$timestamp');

      // GET 请求，参数放 query string
      final response = await _dio.get(
        'https://dypnsapi.aliyuncs.com/',
        queryParameters: sortedParams,
      );

      debugPrint('[AliyunSmsService] Response: ${response.data}');

      final result = response.data as Map<String, dynamic>;
      final code = result['Code'] as String?;
      final success = result['Success'] as bool?;

      if (code == 'OK' || success == true) {
        final model = result['Model'] as Map<String, dynamic>?;
        final verifyCode = model?['VerifyCode'] as String?;
        debugPrint('[AliyunSmsService] VerifyCode: $verifyCode');
        return 60;
      }
      debugPrint('[AliyunSmsService] Send failed: $code - ${result['Message']}');
      return -1;
    } catch (e) {
      debugPrint('[AliyunSmsService] Exception: $e');
      return -1;
    }
  }

  /// 验证验证码（调用阿里云 CheckSmsVerifyCode）
  Future<bool> verifyCode(String phoneNumber, String code) async {
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

      debugPrint('[AliyunSmsService] verifyCode response: ${response.data}');
      final result = response.data as Map<String, dynamic>;
      debugPrint('[AliyunSmsService] verifyCode result map: $result');
      final model = result['Model'] as Map<String, dynamic>?;
      debugPrint('[AliyunSmsService] model: $model');
      final verifyResult = model?['VerifyResult'];
      debugPrint(
        '[AliyunSmsService] VerifyResult raw: $verifyResult (type: ${verifyResult.runtimeType})',
      );
      final respCode = result['Code'] as String?;
      return verifyResult == 'PASS' || respCode == 'OK';
    } catch (e) {
      debugPrint('[AliyunSmsService] verifyCode exception: $e');
      return false;
    }
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
