import 'dart:io';

import 'package:flutter/services.dart';

class NativeSpeechService {
  NativeSpeechService({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.aiaccounting/native_speech');

  final MethodChannel _channel;

  Future<bool> get isAvailable async {
    if (!Platform.isAndroid) return false;
    try {
      final available = await _channel.invokeMethod<bool>(
        'isSpeechRecognitionAvailable',
      );
      return available ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<String?> startRecognition({required String? locale}) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('startSpeechRecognition', {
        'locale': locale,
      });
    } on PlatformException {
      rethrow;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> stopRecognition() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopSpeechRecognition');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<bool> startPcmRecording() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('startPcmRecording') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<Uint8List> stopPcmRecording() async {
    if (!Platform.isAndroid) return Uint8List(0);
    try {
      return await _channel.invokeMethod<Uint8List>('stopPcmRecording') ??
          Uint8List(0);
    } on MissingPluginException {
      return Uint8List(0);
    }
  }
}
