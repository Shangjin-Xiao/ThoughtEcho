import 'dart:async';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';
import '../utils/version_utils.dart';

/// Release 资产里标识 32 位包的命名片段（arm32 / armeabi-v7a / arm32Compat 等）。
final RegExp _arm32AssetPattern = RegExp(
  r'arm32|armeabi|v7a',
  caseSensitive: false,
);

/// Release 资产里标识 64 位包的命名片段（arm64 / arm64-v8a / standard64 等）。
final RegExp _arm64AssetPattern = RegExp(
  r'arm64|v8a|standard64',
  caseSensitive: false,
);

/// 从 Release 资产列表里挑出与设备 ABI 匹配的 APK。
///
/// [deviceAbis] 为设备支持的 ABI 列表（`Build.SUPPORTED_ABIS`）。传空列表表示
/// 无法确定架构（非 Android 平台或读取失败），此时退回"第一个 APK"的旧行为。
///
/// 选择优先级：
/// 1. 文件名标记与设备架构一致的包；
/// 2. 没有任何架构标记的通用包（兼容 3.7.0 及更早的 `app-release.apk`）；
/// 3. 设备支持 arm64 时可退而使用 32 位包（arm64 设备能跑 armeabi-v7a）。
///
/// 注意第 3 条不可反向：**32 位设备绝不能拿到只含 arm64-v8a 的包**，装上会因为
/// 找不到 native 库而崩溃，此时返回 null，让 UI 回退到浏览器打开 Release 页面。
String? selectApkAssetUrl(
  List<dynamic>? assets,
  List<String> deviceAbis,
) {
  if (assets == null) return null;

  final supportsArm64 = deviceAbis.any((abi) => abi.contains('arm64'));
  final abiKnown = deviceAbis.isNotEmpty;

  String? arm64Url;
  String? arm32Url;
  String? genericUrl;
  String? firstApkUrl;

  for (final asset in assets) {
    if (asset is! Map) continue;
    final name = asset['name'] as String?;
    final url = asset['browser_download_url'] as String?;
    if (name == null || url == null) continue;
    if (!name.toLowerCase().endsWith('.apk')) continue;

    firstApkUrl ??= url;

    if (_arm32AssetPattern.hasMatch(name)) {
      arm32Url ??= url;
    } else if (_arm64AssetPattern.hasMatch(name)) {
      arm64Url ??= url;
    } else {
      genericUrl ??= url;
    }
  }

  // 无法判断设备架构时保持旧行为，避免误判导致拿不到更新。
  if (!abiKnown) return firstApkUrl;

  if (supportsArm64) {
    return arm64Url ?? genericUrl ?? arm32Url;
  }
  // 32 位设备：只接受 32 位包或无标记的通用包。
  return arm32Url ?? genericUrl;
}

/// 版本信息模型
class VersionInfo {
  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final String? apkDownloadUrl; // 新增：APK直接下载链接
  final String releaseNotes;
  final DateTime publishedAt;
  final bool hasUpdate;

  VersionInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    this.apkDownloadUrl,
    required this.releaseNotes,
    required this.publishedAt,
    required this.hasUpdate,
  });

  /// [deviceAbis] 传入设备支持的 ABI 列表以挑选架构匹配的 APK；
  /// 省略时退回"第一个 APK"的旧行为。
  factory VersionInfo.fromJson(
    Map<String, dynamic> json,
    String currentVersion, {
    List<String> deviceAbis = const [],
  }) {
    final latestVersion = json['tag_name'] as String? ?? '';
    final hasUpdate = compareVersions(currentVersion, latestVersion) < 0;

    final apkDownloadUrl = selectApkAssetUrl(
      json['assets'] as List<dynamic>?,
      deviceAbis,
    );

    return VersionInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      downloadUrl: json['html_url'] as String? ?? '',
      apkDownloadUrl: apkDownloadUrl,
      releaseNotes: json['body'] as String? ?? '',
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? '') ??
          DateTime.now(),
      hasUpdate: hasUpdate,
    );
  }
}

/// 版本检查结果
enum VersionCheckResult { hasUpdate, noUpdate, error, timeout }

/// GitHub版本检查服务
class VersionCheckService {
  static const String _githubApiUrl =
      'https://api.github.com/repos/Shangjin-Xiao/ThoughtEcho/releases/latest';
  static const Duration _defaultTimeout = Duration(seconds: 10);
  static const Duration _backgroundCheckDelay = Duration(seconds: 5);

  static Dio? _dio;
  static DateTime? _lastCheckTime;
  static VersionInfo? _cachedVersionInfo;
  static const Duration _cacheValidDuration = Duration(hours: 1);
  static List<String>? _cachedDeviceAbis;

  /// 读取设备支持的 ABI，用于挑选架构匹配的 APK。
  ///
  /// 非 Android 平台或读取失败时返回空列表，调用方据此退回旧的选包行为。
  /// 结果在进程内缓存——设备架构不会变。
  static Future<List<String>> getDeviceAbis() async {
    if (_cachedDeviceAbis != null) return _cachedDeviceAbis!;

    if (defaultTargetPlatform != TargetPlatform.android) {
      return _cachedDeviceAbis = const [];
    }

    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final abis = List<String>.unmodifiable(androidInfo.supportedAbis);
      logDebug('设备支持的 ABI: ${abis.join(", ")}');
      return _cachedDeviceAbis = abis;
    } catch (e) {
      // 读不到就当作未知架构，走旧逻辑，不要因此阻断更新检查。
      logDebug('读取设备 ABI 失败，回退到默认选包逻辑: $e');
      return _cachedDeviceAbis = const [];
    }
  }

  /// 获取Dio实例
  static Dio get dio {
    if (_dio == null) {
      _dio = Dio();
      _dio!.options.connectTimeout = _defaultTimeout;
      _dio!.options.receiveTimeout = _defaultTimeout;
      _dio!.options.sendTimeout = _defaultTimeout;

      // 添加日志拦截器
      _dio!.interceptors.add(
        LogInterceptor(
          requestBody: false,
          responseBody: false,
          requestHeader: false,
          responseHeader: false,
          error: true,
          logPrint: (obj) => logDebug('[VersionCheck] $obj'),
        ),
      );
    }
    return _dio!;
  }

  /// 检查版本更新（手动检查）
  static Future<VersionInfo> checkForUpdates({
    Duration? timeout,
    bool forceRefresh = false,
  }) async {
    try {
      // 如果有缓存且未过期，且不是强制刷新，则返回缓存
      if (!forceRefresh &&
          _cachedVersionInfo != null &&
          _lastCheckTime != null) {
        final cacheAge = DateTime.now().difference(_lastCheckTime!);
        if (cacheAge < _cacheValidDuration) {
          logDebug('使用缓存的版本信息');
          return _cachedVersionInfo!;
        }
      }

      logDebug('开始检查版本更新...');
      logDebug('请求URL: $_githubApiUrl');

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      logDebug('当前应用版本: $currentVersion');

      final response = await dio.get(
        _githubApiUrl,
        options: Options(
          receiveTimeout: timeout ?? _defaultTimeout,
          headers: {
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': 'ThoughtEcho-App',
          },
        ),
      );

      logDebug('GitHub API响应状态码: ${response.statusCode}');

      if (response.statusCode == 200 && response.data != null) {
        final versionInfo = VersionInfo.fromJson(
          response.data,
          currentVersion,
          deviceAbis: await getDeviceAbis(),
        );

        // 更新缓存
        _cachedVersionInfo = versionInfo;
        _lastCheckTime = DateTime.now();

        logDebug(
          '版本检查完成: 当前版本 $currentVersion, 最新版本 ${versionInfo.latestVersion}, 有更新: ${versionInfo.hasUpdate}',
        );
        return versionInfo;
      } else {
        throw Exception('GitHub API响应异常: ${response.statusCode}');
      }
    } on DioException catch (e) {
      logDebug('版本检查网络错误: ${e.message}');
      logDebug(
        '错误详情: ${e.response?.statusCode} - ${e.response?.statusMessage}',
      );

      // 处理超时错误
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        throw VersionCheckTimeoutException('版本检查超时，请检查网络连接');
      }

      if (e.response?.statusCode == 404) {
        // 404错误特殊处理 - 可能是仓库没有releases
        throw VersionCheckException(
          '暂无可用的版本更新信息。这可能是因为：\n1. 仓库还没有发布任何版本\n2. 网络连接问题\n\n您可以访问项目主页查看最新信息。',
        );
      } else {
        throw VersionCheckNetworkException('网络连接失败: ${e.message}');
      }
    } catch (e) {
      logDebug('版本检查失败: $e');
      throw VersionCheckException('版本检查失败: $e');
    }
  }

  /// 后台静默检查版本更新
  static Future<void> backgroundCheckForUpdates({
    Function(VersionInfo)? onUpdateAvailable,
    Duration delay = _backgroundCheckDelay,
  }) async {
    // 延迟执行，避免影响应用启动
    await Future.delayed(delay);

    try {
      logDebug('开始后台版本检查...');
      final versionInfo = await checkForUpdates();

      if (versionInfo.hasUpdate && onUpdateAvailable != null) {
        logDebug('检测到新版本: ${versionInfo.latestVersion}');
        onUpdateAvailable(versionInfo);
      } else {
        logDebug('当前已是最新版本');
      }
    } catch (e) {
      // 后台检查失败时静默处理，不影响用户体验
      logDebug('后台版本检查失败: $e');
    }
  }

  /// 检查是否应该忽略某个版本
  static Future<bool> shouldIgnoreVersion(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ignoredVersion = prefs.getString('ignored_update_version');
      return ignoredVersion == version;
    } catch (e) {
      logDebug('检查忽略版本失败: $e');
      return false;
    }
  }

  /// 永久忽略某个版本
  static Future<void> ignoreVersion(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ignored_update_version', version);
      logDebug('已永久忽略版本: $version');
    } catch (e) {
      logDebug('保存忽略版本失败: $e');
    }
  }

  /// 清除忽略的版本记录
  static Future<void> clearIgnoredVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('ignored_update_version');
      logDebug('已清除忽略版本记录');
    } catch (e) {
      logDebug('清除忽略版本记录失败: $e');
    }
  }

  /// 清除缓存
  static void clearCache() {
    _cachedVersionInfo = null;
    _lastCheckTime = null;
  }

  /// 释放资源
  static void dispose() {
    _dio?.close();
    _dio = null;
    clearCache();
  }
}

/// 版本检查异常基类
class VersionCheckException implements Exception {
  final String message;
  VersionCheckException(this.message);

  @override
  String toString() => message;
}

/// 版本检查超时异常
class VersionCheckTimeoutException extends VersionCheckException {
  VersionCheckTimeoutException(super.message);
}

/// 版本检查网络异常
class VersionCheckNetworkException extends VersionCheckException {
  VersionCheckNetworkException(super.message);
}
