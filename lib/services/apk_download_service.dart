import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/app_logger.dart';

/// APK下载和安装服务
class ApkDownloadService {
  static const String _notificationChannelId = 'apk_download_channel';
  static const String _notificationChannelName = 'APK下载';
  static const String _notificationChannelDescription = 'APK文件下载进度通知';

  static Dio? _dio;
  static FlutterLocalNotificationsPlugin? _notificationsPlugin;
  static int? _currentNotificationId;

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
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
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
          _showErrorDialog(context, '无法获取下载目录');
        }
        return;
      }

      // 生成文件名
      final fileName = 'ThoughtEcho_$version.apk';
      final filePath = '${downloadDir.path}/$fileName';

      // 检查文件是否已存在
      final file = File(filePath);
      if (await file.exists()) {
        // 文件已存在，直接安装
        if (context.mounted) {
          await _installApk(context, filePath);
        }
        return;
      }

      // 开始下载
      if (context.mounted) {
        _showDownloadDialog(context, apkUrl, filePath, version);
      }
    } catch (e) {
      logError('APK下载失败: $e');
      if (context.mounted) {
        _showErrorDialog(context, '下载失败: $e');
      }
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('下载APK'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('正在下载 ThoughtEcho $version...'),
              const SizedBox(height: 8),
              const Text(
                '请勿关闭应用，下载完成后将自动开始安装',
                style: TextStyle(fontSize: 12, color: Colors.grey),
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
              child: const Text('取消'),
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
    try {
      // 创建通知渠道
      await _createNotificationChannel();

      // 生成通知ID
      _currentNotificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // 显示初始通知
      await _showDownloadNotification('开始下载 ThoughtEcho $version', 0);

      final response = await dio.download(
        apkUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = (received / total * 100).round();
            _showDownloadNotification(
              '下载中... $progress%',
              progress,
            );
          }
        },
      );

      if (response.statusCode == 200) {
        // 下载完成
        await _showDownloadNotification('下载完成，正在安装...', 100);

        // 关闭下载对话框
        if (context.mounted) {
          Navigator.of(context).pop();
        }

        // 安装APK
        if (context.mounted) {
          await _installApk(context, filePath);
        }
      } else {
        throw Exception('下载失败: $response.statusCode');
      }
    } catch (e) {
      logError('下载过程出错: $e');

      // 显示错误通知
      await _showDownloadNotification('下载失败: $e', -1);

      if (context.mounted) {
        Navigator.of(context).pop(); // 关闭下载对话框
        _showErrorDialog(context, '下载失败: $e');
      }
    }
  }

  /// 安装APK文件
  static Future<void> _installApk(BuildContext context, String filePath) async {
    try {
      final result = await OpenFile.open(filePath);

      if (result.type == ResultType.done) {
        // 安装成功或文件已打开
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('APK文件已准备就绪，请在系统安装程序中完成安装'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        // 安装失败
        logError('APK安装失败: ${result.message}');
        if (context.mounted) {
          _showErrorDialog(context, '无法打开APK文件: ${result.message}');
        }
      }
    } catch (e) {
      logError('APK安装过程出错: $e');
      if (context.mounted) {
        _showErrorDialog(context, '安装失败: $e');
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
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  /// 显示下载通知
  static Future<void> _showDownloadNotification(
      String message, int progress) async {
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
      'APK下载',
      message,
      details,
    );
  }

  /// 显示权限对话框
  static void _showPermissionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('需要存储权限'),
          content: const Text('下载APK文件需要存储权限。请在设置中允许应用访问存储空间。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                openAppSettings();
              },
              child: const Text('去设置'),
            ),
          ],
        );
      },
    );
  }

  /// 显示错误对话框
  static void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('错误'),
          content: Text(message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('确定'),
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
