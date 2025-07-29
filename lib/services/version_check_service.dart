import 'dart:async';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../utils/app_logger.dart';

/// 版本信息模型
class VersionInfo {
  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final String releaseNotes;
  final DateTime publishedAt;
  final bool hasUpdate;

  VersionInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.publishedAt,
    required this.hasUpdate,
  });

  factory VersionInfo.fromJson(Map<String, dynamic> json, String currentVersion) {
    final latestVersion = json['tag_name'] as String? ?? '';
    final hasUpdate = VersionInfo._compareVersions(currentVersion, latestVersion) < 0;
    
    return VersionInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      downloadUrl: json['html_url'] as String? ?? '',
      releaseNotes: json['body'] as String? ?? '',
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? '') ?? DateTime.now(),
      hasUpdate: hasUpdate,
    );
  }

  /// 比较版本号
  /// 返回值：-1表示version1 < version2，0表示相等，1表示version1 > version2
  static int _compareVersions(String version1, String version2) {
    // 移除版本号前缀（如 v1.0.0 -> 1.0.0）
    final v1 = version1.replaceFirst(RegExp(r'^v'), '');
    final v2 = version2.replaceFirst(RegExp(r'^v'), '');
    
    final v1Parts = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final v2Parts = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    
    // 确保两个版本号有相同的长度
    final maxLength = v1Parts.length > v2Parts.length ? v1Parts.length : v2Parts.length;
    while (v1Parts.length < maxLength) {
      v1Parts.add(0);
    }
    while (v2Parts.length < maxLength) {
      v2Parts.add(0);
    }
    
    for (int i = 0; i < maxLength; i++) {
      if (v1Parts[i] < v2Parts[i]) return -1;
      if (v1Parts[i] > v2Parts[i]) return 1;
    }
    
    return 0;
  }
}

/// 版本检查结果
enum VersionCheckResult {
  hasUpdate,
  noUpdate,
  error,
  timeout,
}

/// GitHub版本检查服务
class VersionCheckService {
  static const String _githubApiUrl = 'https://api.github.com/repos/Shangjin-Xiao/ThoughtEcho/releases/latest';
  static const Duration _defaultTimeout = Duration(seconds: 10);
  static const Duration _backgroundCheckDelay = Duration(seconds: 5);
  
  static Dio? _dio;
  static DateTime? _lastCheckTime;
  static VersionInfo? _cachedVersionInfo;
  static const Duration _cacheValidDuration = Duration(hours: 1);

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
      if (!forceRefresh && _cachedVersionInfo != null && _lastCheckTime != null) {
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
      ).timeout(timeout ?? _defaultTimeout);

      logDebug('GitHub API响应状态码: ${response.statusCode}');

      if (response.statusCode == 200 && response.data != null) {
        final versionInfo = VersionInfo.fromJson(response.data, currentVersion);

        // 更新缓存
        _cachedVersionInfo = versionInfo;
        _lastCheckTime = DateTime.now();

        logDebug('版本检查完成: 当前版本 $currentVersion, 最新版本 ${versionInfo.latestVersion}, 有更新: ${versionInfo.hasUpdate}');
        return versionInfo;
      } else {
        throw Exception('GitHub API响应异常: ${response.statusCode}');
      }
    } on TimeoutException {
      logDebug('版本检查超时');
      throw VersionCheckTimeoutException('版本检查超时，请检查网络连接');
    } on DioException catch (e) {
      logDebug('版本检查网络错误: ${e.message}');
      logDebug('错误详情: ${e.response?.statusCode} - ${e.response?.statusMessage}');

      if (e.response?.statusCode == 404) {
        // 404错误特殊处理 - 可能是仓库没有releases
        throw VersionCheckException('暂无可用的版本更新信息。这可能是因为：\n1. 仓库还没有发布任何版本\n2. 网络连接问题\n\n您可以访问项目主页查看最新信息。');
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
