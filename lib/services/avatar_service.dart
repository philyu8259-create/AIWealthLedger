import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/app_flavor.dart';
import 'app_profile_service.dart';

class AvatarService extends ChangeNotifier {
  static const _keyAvatarPath = 'custom_avatar_path';
  static const _keyAvatarBackupBase64 = 'custom_avatar_backup_base64';
  static const _keyAvatarBackupExt = 'custom_avatar_backup_ext';

  final SharedPreferences _prefs;
  final ImagePicker _picker = ImagePicker();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  File? _avatarFile;
  bool _isLoading = false;
  String? _errorMsg;

  bool get _isIntl {
    if (GetIt.instance.isRegistered<AppProfileService>()) {
      return GetIt.instance<AppProfileService>().flavor.isIntl;
    }
    return AppFlavorX.current.isIntl;
  }

  String _message(String zh, String en) => _isIntl ? en : zh;

  AvatarService(this._prefs) {
    _init();
  }

  Future<void> _init() async {
    await _loadAvatar();
  }

  File? get avatarFile => _avatarFile;
  bool get isLoading => _isLoading;
  String? get errorMsg => _errorMsg;
  bool get hasCustomAvatar => _avatarFile != null && _avatarFile!.existsSync();

  /// 加载本地头像
  Future<void> _loadAvatar() async {
    final path = _prefs.getString(_keyAvatarPath);
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (await file.exists()) {
        _avatarFile = file;
        notifyListeners();
      } else {
        final restored = await _restoreFromSecureBackup();
        if (!restored) {
          await _prefs.remove(_keyAvatarPath);
          _avatarFile = null;
          notifyListeners();
        } else {
          notifyListeners();
        }
      }
      return;
    }

    final restored = await _restoreFromSecureBackup();
    if (restored) {
      notifyListeners();
    }
  }

  /// 从相册选择图片
  Future<bool> pickFromGallery() async {
    try {
      _setLoading(true);
      _clearError();

      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 70,
      );

      if (image == null) {
        _setLoading(false);
        return false;
      }

      // 检查文件大小（最大5MB）
      final file = File(image.path);
      final sizeInBytes = await file.length();
      final sizeInMB = sizeInBytes / (1024 * 1024);

      if (sizeInMB > 5) {
        _setError(
          _message(
            '图片大小超过5MB，请选择更小的图片',
            'Image size exceeds 5MB. Please choose a smaller image.',
          ),
        );
        _setLoading(false);
        return false;
      }

      // 直接保存头像（不裁剪）
      await _saveAvatar(file);
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(_message('选择图片失败: $e', 'Failed to pick image: $e'));
      _setLoading(false);
      return false;
    }
  }

  /// 拍照
  Future<bool> takePhoto() async {
    try {
      _setLoading(true);
      _clearError();

      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 70,
      );

      if (image == null) {
        _setLoading(false);
        return false;
      }

      // 直接保存头像（不裁剪）
      await _saveAvatar(File(image.path));
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(_message('拍照失败: $e', 'Failed to take photo: $e'));
      _setLoading(false);
      return false;
    }
  }

  /// 保存头像到本地
  Future<void> _saveAvatar(File file) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final filePath = file.path;
      final dotIndex = filePath.lastIndexOf('.');
      final ext = dotIndex >= 0 ? filePath.substring(dotIndex) : '.jpg';
      final fileName = 'avatar_${DateTime.now().millisecondsSinceEpoch}$ext';
      final newPath = '${appDir.path}/$fileName';

      final bytes = await file.readAsBytes();
      final savedFile = await File(newPath).writeAsBytes(bytes, flush: true);

      await _prefs.setString(_keyAvatarPath, newPath);
      await _secureStorage.write(
        key: _keyAvatarBackupBase64,
        value: base64Encode(bytes),
      );
      await _secureStorage.write(key: _keyAvatarBackupExt, value: ext);

      _avatarFile = savedFile;
      notifyListeners();
    } catch (e) {
      _setError(_message('保存头像失败: $e', 'Failed to save avatar: $e'));
      rethrow;
    }
  }

  Future<bool> _restoreFromSecureBackup() async {
    try {
      final base64 = await _secureStorage.read(key: _keyAvatarBackupBase64);
      if (base64 == null || base64.isEmpty) return false;

      final ext = await _secureStorage.read(key: _keyAvatarBackupExt) ?? '.jpg';
      final bytes = base64Decode(base64);
      final appDir = await getApplicationDocumentsDirectory();
      final newPath =
          '${appDir.path}/avatar_restore_${DateTime.now().millisecondsSinceEpoch}$ext';
      final savedFile = await File(newPath).writeAsBytes(bytes, flush: true);

      await _prefs.setString(_keyAvatarPath, newPath);
      _avatarFile = savedFile;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 恢复默认头像
  Future<void> restoreDefault() async {
    try {
      _setLoading(true);
      _clearError();

      // 删除本地文件
      if (_avatarFile != null) {
        try {
          await _avatarFile!.delete();
        } catch (_) {}
      }

      // 清除 SharedPreferences
      await _prefs.remove(_keyAvatarPath);
      await _secureStorage.delete(key: _keyAvatarBackupBase64);
      await _secureStorage.delete(key: _keyAvatarBackupExt);

      // 更新状态
      _avatarFile = null;
      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError(
        _message('恢复默认头像失败: $e', 'Failed to restore default avatar: $e'),
      );
      _setLoading(false);
    }
  }

  /// 清除头像（退出登录时调用）
  Future<void> clearAvatar() async {
    await restoreDefault();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String msg) {
    _errorMsg = msg;
    notifyListeners();
  }

  void _clearError() {
    _errorMsg = null;
    notifyListeners();
  }
}
