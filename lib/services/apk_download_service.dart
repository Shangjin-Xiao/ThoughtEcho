import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../gen_l10n/app_localizations.dart';
import '../utils/app_logger.dart';

/// APK下载和安装服务
class ApkDownloadService {
  static const String _notificationChannelId = 'apk_download_channel';
  static const String _notificationChannelName = 'APK Download';
  static const String _notificationChannelDescription =
      'APK file download progress notifications';

  static Dio? _dio;
  static FlutterLocalNotificationsPlugin? _notificationsPlugin;
  static int? _currentNotificationId;

  // 缓存的本地化字符串，用于通知（因为通知无法访问 BuildContext）
  static String? _cachedNotificationTitle;
  static String? _cachedDownloadStarted;
  static String? _cachedDownloadProgress;
  static String? _cachedDownloadComplete;
  // Removed unused failed cache placeholder

  /// 获取Dio实例
  static Dio get dio {
    if (_dio == null) {
      _dio = Dio();
      _dio!.options.connectTimeout = const Duration(seconds: 30);
      _dio!.options.receiveTimeout = const Duration(seconds: 30);
      _dio!.options.sendTimeout = const Duration(seconds: 30);
    }
    return _dio!;
  }

  /// 获取通知插件实例
  static FlutterLocalNotificationsPlugin get notificationsPlugin {
    if (_notificationsPlugin == null) {
      _notificationsPlugin = FlutterLocalNotificationsPlugin();

      // 初始化通知
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const iosSettings = DarwinInitializationSettings();
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      _notificationsPlugin!.initialize(initSettings);
    }
    return _notificationsPlugin!;
  }

  /// 下载并安装APK文件
  static Future<void> downloadAndInstallApk(
    BuildContext context,
    String apkUrl,
    String version,
  ) async {
    try {
      // 检查存储权限
      final hasPermission = await _checkStoragePermission();
      if (!hasPermission) {
        if (context.mounted) {
          _showPermissionDialog(context);
        }
        return;
      }

      // 获取下载目录
      final downloadDir = await _getDownloadDirectory();
      if (downloadDir == null) {
        if (context.mounted) {
          final l10n = AppLocalizations.of(context);
          _showErrorDialog(context, l10n.cannotGetDownloadDir);
        }
        return;
      }

      // 生成文件名（采用固定名称，避免旧安装包堆积）
      const fileName = 'ThoughtEcho_latest.apk';
      final filePath = '${downloadDir.path}/$fileName';

      // 检查并清理同名旧文件，确保下载的是最新的
      final file = File(filePath);
      if (await file.exists()) {
        try {
          logDebug('清理已存在的同名安装包: $filePath');
          await file.delete();
        } catch (e) {
          logError('清理旧安装包失败: $e');
        }
      }

      // 开始下载
      if (context.mounted) {
        _showDownloadDialog(context, apkUrl, filePath, version);
      }
    } catch (e) {
      logError('APK下载失败: $e');
      if (context.mounted) {
        final l10n = AppLocalizations.of(context);
        _showErrorDialog(context, l10n.apkDownloadFailed(e.toString()));
      }
    }
  }

  /// 清理下载目录中的所有旧安装包
  static Future<void> cleanupApkFiles() async {
    try {
      final downloadDir = await _getDownloadDirectory();
      if (downloadDir == null) return;

      if (await downloadDir.exists()) {
        final List<FileSystemEntity> files = downloadDir.listSync();
        // 清理目录下所有 APK 文件，因为这是应用私有下载目录，不应包含其他重要文件
        for (var file in files) {
          if (file is File && file.path.toLowerCase().endsWith('.apk')) {
            try {
              logDebug('启动清理旧安装包: ${file.path}');
              await file.delete();
            } catch (e) {
              logError('删除旧安装包失败: ${file.path}, $e');
            }
          }
        }
      }
    } catch (e) {
      logError('清理安装包目录失败: $e');
    }
  }

  /// 检查存储权限
  static Future<bool> _checkStoragePermission() async {
    if (Platform.isAndroid) {
      // Android 13+ 需要请求通知权限用于下载进度
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }

      // 检查存储权限
      var status = await Permission.storage.status;
      if (status.isDenied) {
        status = await Permission.storage.request();
      }

      // Android 13+ 可能需要媒体权限
      if (status.isDenied) {
        status = await Permission.manageExternalStorage.status;
        if (status.isDenied) {
          status = await Permission.manageExternalStorage.request();
        }
      }

      return status.isGranted;
    }
    return true;
  }

  /// 获取下载目录
  static Future<Directory?> _getDownloadDirectory() async {
    try {
      if (Platform.isAndroid) {
        // 优先使用外部下载目录
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          final downloadDir = Directory('${externalDir.path}/Download');
          if (!await downloadDir.exists()) {
            await downloadDir.create(recursive: true);
          }
          return downloadDir;
        }

        // 回退到应用文档目录
        final appDir = await getApplicationDocumentsDirectory();
        final downloadDir = Directory('${appDir.path}/downloads');
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }
        return downloadDir;
      } else {
        // iOS或其他平台
        final appDir = await getApplicationDocumentsDirectory();
        final downloadDir = Directory('${appDir.path}/downloads');
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }
        return downloadDir;
      }
    } catch (e) {
      logError('获取下载目录失败: $e');
      return null;
    }
  }

  /// 显示下载对话框
  static void _showDownloadDialog(
    BuildContext context,
    String apkUrl,
    String filePath,
    String version,
  ) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.apkDownloadTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(l10n.apkDownloading(version)),
              const SizedBox(height: 8),
              Text(
                l10n.apkDownloadHint,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                // 取消下载
                dio.close(force: true);
                Navigator.of(dialogContext).pop();
              },
              child: Text(l10n.cancel),
            ),
          ],
        );
      },
    );

    // 开始下载
    _startDownload(context, apkUrl, filePath, version);
  }

  /// 开始下载
  static Future<void> _startDownload(
    BuildContext context,
    String apkUrl,
    String filePath,
    String version,
  ) async {
    // 缓存本地化字符串用于通知
    final l10n = AppLocalizations.of(context);
    _cachedNotificationTitle = l10n.apkNotificationTitle;
    _cachedDownloadStarted = l10n.apkDownloadStarted(version);
    _cachedDownloadComplete = l10n.apkDownloadComplete;

    try {
      // 创建通知渠道
      await _createNotificationChannel();

      // 生成通知ID
      _currentNotificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // 显示初始通知
      await _showDownloadNotification(_cachedDownloadStarted!, 0);

      final response = await dio.download(
        apkUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = (received / total * 100).round();
            _cachedDownloadProgress = l10n.apkDownloadProgress(progress);
            _showDownloadNotification(_cachedDownloadProgress!, progress);
          }
        },
      );

      if (response.statusCode == 200) {
        // 下载完成
        await _showDownloadNotification(_cachedDownloadComplete!, 100);

        // 关闭下载对话框
        if (context.mounted) {
          Navigator.of(context).pop();
        }

        // 安装APK
        if (context.mounted) {
          await _installApk(context, filePath);
        }
      } else {
        throw Exception('Download failed: ${response.statusCode}');
      }
    } catch (e) {
      logError('下载过程出错: $e');

      // 显示错误通知
      if (context.mounted) {
        final errorL10n = AppLocalizations.of(context);
        await _showDownloadNotification(
          errorL10n.apkDownloadFailed(e.toString()),
          -1,
        );
        if (!context.mounted) return;
        Navigator.of(context).pop(); // 关闭下载对话框
        if (context.mounted) {
          _showErrorDialog(context, errorL10n.apkDownloadFailed(e.toString()));
        }
      } else {
        await _showDownloadNotification('Download failed: $e', -1);
      }
    }
  }

  /// 安装APK文件
  static Future<void> _installApk(BuildContext context, String filePath) async {
    final l10n = AppLocalizations.of(context);
    try {
      // Android 8.0+ 需要请求安装权限
      if (Platform.isAndroid) {
        final installStatus = await Permission.requestInstallPackages.status;
        if (installStatus.isDenied) {
          final result = await Permission.requestInstallPackages.request();
          if (result.isDenied) {
            if (context.mounted) {
              _showInstallPermissionDialog(context);
            }
            return;
          }
        }
      }

      final result = await OpenFile.open(filePath);

      if (result.type == ResultType.done) {
        // 安装成功或文件已打开
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.apkInstallReady),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        // 安装失败
        logError('APK安装失败: ${result.message}');
        if (context.mounted) {
          _showErrorDialog(context, l10n.apkOpenFailed(result.message));
        }
      }
    } catch (e) {
      logError('APK安装过程出错: $e');
      if (context.mounted) {
        _showErrorDialog(context, l10n.apkInstallFailed(e.toString()));
      }
    }
  }

  /// 创建通知渠道
  static Future<void> _createNotificationChannel() async {
    const androidChannel = AndroidNotificationChannel(
      _notificationChannelId,
      _notificationChannelName,
      description: _notificationChannelDescription,
      importance: Importance.low,
      showBadge: false,
      enableVibration: false,
      playSound: false,
    );

    await notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(androidChannel);
  }

  /// 显示下载通知
  static Future<void> _showDownloadNotification(
    String message,
    int progress,
  ) async {
    final androidDetails = AndroidNotificationDetails(
      _notificationChannelId,
      _notificationChannelName,
      channelDescription: _notificationChannelDescription,
      importance: Importance.low,
      priority: Priority.low,
      showProgress: progress >= 0 && progress < 100,
      maxProgress: 100,
      progress: progress,
      ongoing: progress >= 0 && progress < 100,
      autoCancel: progress == 100,
      onlyAlertOnce: true,
    );

    const iosDetails = DarwinNotificationDetails();

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await notificationsPlugin.show(
      _currentNotificationId ?? 0,
      _cachedNotificationTitle ?? 'APK Download',
      message,
      details,
    );
  }

  /// 显示权限对话框
  static void _showPermissionDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.storagePermissionRequired),
          content: Text(l10n.storagePermissionDesc),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                openAppSettings();
              },
              child: Text(l10n.goToSettings),
            ),
          ],
        );
      },
    );
  }

  /// 显示安装权限对话框
  static void _showInstallPermissionDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.installPermissionRequired),
          content: Text(l10n.installPermissionDesc),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                openAppSettings();
              },
              child: Text(l10n.goToSettings),
            ),
          ],
        );
      },
    );
  }

  /// 显示错误对话框
  static void _showErrorDialog(BuildContext context, String message) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.errorTitle),
          content: Text(message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.confirm),
            ),
          ],
        );
      },
    );
  }

  /// 清理资源
  static void dispose() {
    _dio?.close();
    _dio = null;
    _notificationsPlugin = null;
  }
}
