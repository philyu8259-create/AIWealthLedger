import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../l10n/app_string_keys.dart';
import '../../../../l10n/app_strings.dart';
import '../../../../services/avatar_service.dart';
import '../../../../services/injection.dart';
import 'press_feedback.dart';

// 头像 Tile（带迷你相机图标）
class AvatarTile extends StatelessWidget {
  final String displayName;
  final String appVersion;
  final bool isLoggedIn;
  final VoidCallback? onTap;

  const AvatarTile({
    super.key,
    required this.displayName,
    required this.appVersion,
    required this.isLoggedIn,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final avatarService = getIt<AvatarService>();

    return ListenableBuilder(
      listenable: avatarService,
      builder: (context, _) {
        return Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: PressFeedback(
            onTap: onTap,
            child: Row(
              children: [
                // 头像（带迷你相机图标）
                SizedBox(
                  width: 60,
                  height: 60,
                  child: Stack(
                    children: [
                      // 头像图片
                      Container(
                        width: 60,
                        height: 60,
                        decoration: const BoxDecoration(
                          color: Color(0xFF4A47D8),
                          shape: BoxShape.circle,
                        ),
                        child: avatarService.hasCustomAvatar
                            ? ClipOval(
                                child: Image.file(
                                  avatarService.avatarFile!,
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Center(
                                      child: Text(
                                        '👤',
                                        style: TextStyle(fontSize: 28),
                                      ),
                                    );
                                  },
                                ),
                              )
                            : const Center(
                                child: Text(
                                  '👤',
                                  style: TextStyle(fontSize: 28),
                                ),
                              ),
                      ),
                      // 加载状态
                      if (avatarService.isLoading)
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      // 迷你相机图标（右上角）
                      Positioned(
                        right: 0,
                        top: 0,
                        child: PressFeedback(
                          onTap: () => _showAvatarActionSheet(context),
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.3),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.camera_alt,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // 名称和版本号
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF303133),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        appVersion,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF909399),
                        ),
                      ),
                    ],
                  ),
                ),
                // 箭头
                if (!isLoggedIn)
                  const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: Color(0xFF999999),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAvatarActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => const AvatarActionSheet(),
    );
  }
}

// 头像操作底部菜单
class AvatarActionSheet extends StatelessWidget {
  const AvatarActionSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final avatarService = getIt<AvatarService>();
    final t = AppStrings.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖动条
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // 从相册选择
          AvatarActionTile(
            icon: Icons.photo_library,
            title: t.text(AppStringKeys.avatarChooseFromLibrary),
            onTap: () async {
              Navigator.pop(context);
              final success = await avatarService.pickFromGallery();
              if (!success && avatarService.errorMsg != null) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(avatarService.errorMsg!)),
                  );
                }
              }
            },
          ),
          // 拍照
          AvatarActionTile(
            icon: Icons.camera_alt,
            title: t.text(AppStringKeys.avatarTakePhoto),
            onTap: () async {
              Navigator.pop(context);
              final success = await avatarService.takePhoto();
              if (!success && avatarService.errorMsg != null) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(avatarService.errorMsg!)),
                  );
                }
              }
            },
          ),
          // 查看大图
          if (avatarService.hasCustomAvatar)
            AvatarActionTile(
              icon: Icons.visibility,
              title: t.text(AppStringKeys.avatarViewFullImage),
              onTap: () {
                Navigator.pop(context);
                _showAvatarPreview(context, avatarService.avatarFile!);
              },
            ),
          // 恢复默认头像
          if (avatarService.hasCustomAvatar)
            AvatarActionTile(
              icon: Icons.refresh,
              title: t.text(AppStringKeys.avatarRestoreDefault),
              titleColor: const Color(0xFFF56C6C),
              onTap: () async {
                Navigator.pop(context);
                await avatarService.restoreDefault();
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(
                    SnackBar(
                      content: Text(
                        t.text(AppStringKeys.avatarRestoreSuccess),
                      ),
                    ),
                  );
                }
              },
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showAvatarPreview(BuildContext context, File file) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: PressFeedback(
          onTap: () => Navigator.pop(ctx),
          child: Center(
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(file, fit: BoxFit.cover),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 头像操作项
class AvatarActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color? titleColor;
  final VoidCallback onTap;

  const AvatarActionTile({
    super.key,
    required this.icon,
    required this.title,
    this.titleColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressFeedback(
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(icon, size: 24, color: titleColor ?? const Color(0xFF303133)),
            const SizedBox(width: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                color: titleColor ?? const Color(0xFF303133),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
