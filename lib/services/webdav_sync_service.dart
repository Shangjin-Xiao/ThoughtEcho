import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../services/connectivity_service.dart';
import '../services/database_service.dart';
import '../services/media_reference_service.dart';
import '../services/mmkv_service.dart';
import '../utils/app_logger.dart';
import '../utils/lww_utils.dart';

/// WebDAV 同步状态枚举
enum WebDAVSyncStatus { idle, syncing, success, failed }

class _RemoteSyncFileMetadata {
  const _RemoteSyncFileMetadata({
    required this.exists,
    this.etag,
    this.contentLength,
    this.lastModified,
  });

  final bool exists;
  final String? etag;
  final int? contentLength;
  final String? lastModified;
}

/// 云端同步文件无法解析（非法 ZIP、缺少数据条目、JSON 结构损坏）。
/// 这类文件不含任何可合并的数据，因此允许用本地数据重建，避免同步永久卡死。
class _CorruptedRemoteSyncFileException implements Exception {
  const _CorruptedRemoteSyncFileException(this.reason);

  final String reason;

  @override
  String toString() => '云端同步文件损坏: $reason';
}

class _RemoteMediaFileInfo {
  const _RemoteMediaFileInfo({this.length, this.etag});

  final int? length;
  final String? etag;
}

class WebDAVSyncService extends ChangeNotifier {
  static final WebDAVSyncService _instance = WebDAVSyncService._internal();
  factory WebDAVSyncService() => _instance;

  WebDAVSyncService._internal() {
    _initSettings();
  }

  // 核心存储与安全服务
  final MMKVService _mmkv = MMKVService();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // WebDAV 状态
  WebDAVSyncStatus _syncStatus = WebDAVSyncStatus.idle;
  String _lastSyncTime = '';
  int _lastConflictCount = 0;
  bool _hasPendingSync = false; // 是否有排队中的同步任务
  int _pendingSyncRetryCount = 0; // 失败后追加同步的重试计数（指数退避）
  static const int _maxPendingSyncRetries = 3;
  bool _isSyncExecuting = false; // 独占同步/上传互斥锁，防止并发重入
  String _lastSyncError = ''; // 最近一次失败的错误摘要（对用户安全）

  WebDAVSyncStatus get syncStatus => _syncStatus;
  String get lastSyncTime => _lastSyncTime;
  int get lastConflictCount => _lastConflictCount;
  bool get isSyncing => _syncStatus == WebDAVSyncStatus.syncing;
  String get lastSyncError => _lastSyncError;

  // 配置缓存字段
  bool _enabled = false;
  String _provider = 'custom'; // nutstore, nextcloud, infinicloud, custom
  String _url = '';
  String _username = '';
  bool _syncOnLaunch = true;
  bool _syncOnChange = true;

  bool _syncOnCellular = false;
  bool _syncNotesOnlyOnCellular = false;

  bool get enabled => _enabled;
  String get provider => _provider;
  String get url => _url;
  String get username => _username;
  bool get syncOnOpenOrForeground => _syncOnLaunch;
  bool get syncOnLaunch => _syncOnLaunch;
  bool get syncOnChange => _syncOnChange;
  bool get syncOnCellular => _syncOnCellular;
  bool get syncNotesOnlyOnCellular => _syncNotesOnlyOnCellular;

  // 定时器用于防抖
  Timer? _debounceTimer;

  // 冲突分类固定ID
  static const String conflictCategoryId = 'system_sync_conflicts_category';
  static const Set<String> _mediaSubFolders = {'images', 'videos', 'audios'};

  /// 初始化设置，从 MMKV 中读取缓存配置
  void _initSettings() {
    _enabled = _mmkv.getBool('webdav_enabled') ?? false;
    _provider = _mmkv.getString('webdav_provider') ?? 'custom';
    _url = _mmkv.getString('webdav_url') ?? '';
    _username = _mmkv.getString('webdav_username') ?? '';
    _syncOnLaunch = _mmkv.getBool('webdav_sync_on_launch') ?? true;
    _syncOnChange = _mmkv.getBool('webdav_sync_on_change') ?? true;
    _syncOnCellular = _mmkv.getBool('webdav_sync_on_cellular') ?? false;
    _syncNotesOnlyOnCellular =
        _mmkv.getBool('webdav_sync_notes_only_on_cellular') ?? false;
    _lastSyncTime = _mmkv.getString('webdav_last_sync_time') ?? '';
    _lastSyncError = _mmkv.getString('webdav_last_sync_error') ?? '';
    // 若上次状态为 failed，恢复失败状态显示
    if ((_mmkv.getString('webdav_sync_status') ?? '') == 'failed' &&
        _lastSyncTime.isEmpty) {
      _syncStatus = WebDAVSyncStatus.failed;
    }

    // 如果是首次使用，且预设是坚果云，自动填入坚果云的地址
    if (_url.isEmpty && _provider == 'nutstore') {
      _url = 'https://dav.jianguoyun.com/dav/';
    }
  }

  /// 获取保存的安全密码/Token
  Future<String?> getPassword() async {
    try {
      return await _secureStorage.read(key: 'webdav_password');
    } catch (e) {
      logError('读取 WebDAV 密码失败', error: e, source: 'WebDAVSyncService');
      return null;
    }
  }

  /// 保存配置
  Future<void> saveSettings({
    required bool enabled,
    required String provider,
    required String url,
    required String username,
    String? password,
    required bool syncOnLaunch,
    required bool syncOnChange,
    required bool syncOnCellular,
    required bool syncNotesOnlyOnCellular,
  }) async {
    _enabled = enabled;
    _provider = provider;
    _url = url.trim();
    if (_enabled &&
        _url.isNotEmpty &&
        !_url.toLowerCase().startsWith('https://')) {
      throw Exception('HTTPS is required to protect WebDAV credentials');
    }
    if (!_url.endsWith('/')) _url = '$_url/';
    _username = username.trim();
    _syncOnLaunch = syncOnLaunch;
    _syncOnChange = syncOnChange;
    _syncOnCellular = syncOnCellular;
    _syncNotesOnlyOnCellular = syncNotesOnlyOnCellular;

    await _mmkv.setBool('webdav_enabled', _enabled);
    await _mmkv.setString('webdav_provider', _provider);
    await _mmkv.setString('webdav_url', _url);
    await _mmkv.setString('webdav_username', _username);
    await _mmkv.setBool('webdav_sync_on_launch', _syncOnLaunch);
    await _mmkv.setBool('webdav_sync_on_change', _syncOnChange);
    await _mmkv.setBool('webdav_sync_on_cellular', _syncOnCellular);
    await _mmkv.setBool(
        'webdav_sync_notes_only_on_cellular', _syncNotesOnlyOnCellular);

    if (password != null) {
      await _secureStorage.write(
        key: 'webdav_password',
        value: password.trim(),
      );
    }

    notifyListeners();
  }

  /// 创建配置好的 Dio 实例用于 WebDAV 请求
  Future<Dio> _createDio(
    String requestUrl,
    String requestUsername,
    String requestPassword,
  ) async {
    if (!requestUrl.toLowerCase().startsWith('https://')) {
      throw Exception('HTTPS is required to protect WebDAV credentials');
    }

    final dio = Dio();
    dio.options.connectTimeout = const Duration(seconds: 15);
    dio.options.receiveTimeout = const Duration(seconds: 20);
    dio.options.sendTimeout = const Duration(seconds: 20);

    // 禁用自动跟随重定向，通过拦截器手动处理安全跳转，防止 HTTPS 向 HTTP 降级泄露凭据
    dio.options.followRedirects = false;

    dio.options.validateStatus = (status) {
      return status != null &&
          (status >= 200 && status < 300 ||
              status == 301 ||
              status == 302 ||
              status == 307 ||
              status == 308);
    };

    // 计算 Basic Auth 头
    final basicAuth =
        'Basic ${base64Encode(utf8.encode('$requestUsername:$requestPassword'))}';
    dio.options.headers = {'Authorization': basicAuth, 'Accept': '*/*'};

    dio.interceptors.add(
      InterceptorsWrapper(
        onResponse: (response, handler) async {
          final status = response.statusCode;
          if (status == 301 ||
              status == 302 ||
              status == 307 ||
              status == 308) {
            // 检查防重定向死循环
            final redirectCount =
                (response.requestOptions.extra['redirects'] as int?) ?? 0;
            if (redirectCount >= 5) {
              return handler.reject(
                DioException(
                  requestOptions: response.requestOptions,
                  error: 'Redirect limit exceeded',
                ),
              );
            }

            final location = response.headers.value('location');
            if (location != null && location.isNotEmpty) {
              final resolvedUri = response.requestOptions.uri.resolve(location);
              if (resolvedUri.scheme != 'https') {
                return handler.reject(
                  DioException(
                    requestOptions: response.requestOptions,
                    error: 'HTTPS is required to protect WebDAV credentials',
                  ),
                );
              }

              // 手动跟随安全的 HTTPS 重定向
              try {
                final newOptions = response.requestOptions.copyWith(
                  path: resolvedUri.toString(),
                );
                newOptions.extra['redirects'] = redirectCount + 1;

                // 如果跨域，则移除认证以防跨域凭据泄露
                if (resolvedUri.origin != response.requestOptions.uri.origin) {
                  newOptions.headers.remove('Authorization');
                }

                final newResponse = await dio.fetch(newOptions);
                return handler.resolve(newResponse);
              } catch (e) {
                if (e is DioException) {
                  return handler.reject(e);
                }
                return handler.reject(
                  DioException(
                    requestOptions: response.requestOptions,
                    error: e.toString(),
                  ),
                );
              }
            }
            // 收到 3xx 但没有合法的 location 跳转时，显式拒绝（防止全局 validateStatus 放行导致无声失败）
            return handler.reject(
              DioException(
                requestOptions: response.requestOptions,
                error: 'Redirect failed: Missing or invalid Location header',
              ),
            );
          }
          return handler.next(response);
        },
      ),
    );

    return dio;
  }

  /// 测试 WebDAV 连接
  Future<bool> testConnection(
    String testUrl,
    String testUsername,
    String testPassword,
  ) async {
    try {
      String cleanUrl = testUrl.trim();
      if (!cleanUrl.endsWith('/')) cleanUrl = '$cleanUrl/';

      final dio = await _createDio(cleanUrl, testUsername, testPassword);

      // 发送 PROPFIND 请求获取根目录信息，验证凭证和地址是否有效
      final response = await dio.request(
        cleanUrl,
        options: Options(
          method: 'PROPFIND',
          headers: {'Depth': '0'},
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      return response.statusCode == 200 || response.statusCode == 207;
    } catch (e) {
      logError('WebDAV 测试连接失败', error: e, source: 'WebDAVSyncService');
      return false;
    }
  }

  /// 触发网络数据同步
  /// [isBackground] - 是否为后台静默同步（不报错弹窗，仅记录日志）
  Future<void> triggerSync({bool isBackground = false}) async {
    if (!_enabled) return;

    if (isSyncing || _isSyncExecuting) {
      logDebug('当前正在同步中，将此次同步请求加入排队队列');
      _hasPendingSync = true;
      return;
    }
    _isSyncExecuting = true;

    final password = await getPassword();
    if (_url.isEmpty ||
        _username.isEmpty ||
        password == null ||
        password.isEmpty) {
      logDebug('WebDAV 同步未完全配置，跳过同步');
      _isSyncExecuting = false;
      return;
    }

    // 移动数据网络检测与过滤策略
    final isCellular = await ConnectivityService().isCellularConnection();
    bool skipMedia = false;
    if (isCellular) {
      if (_syncNotesOnlyOnCellular) {
        logInfo('当前处于移动数据网络下且启用“仅同步笔记”，将跳过大媒体文件同步');
        skipMedia = true;
      } else if (!_syncOnCellular) {
        logInfo('当前处于移动数据网络下且未允许流量同步，跳过 WebDAV 同步');
        _isSyncExecuting = false;
        return;
      }
    }

    _syncStatus = WebDAVSyncStatus.syncing;
    _lastConflictCount = 0;
    notifyListeners();

    try {
      final dio = await _createDio(_url, _username, password);

      // 1. 确保服务器同步目录结构存在 (/thoughtecho/ 和 /thoughtecho/media/ 等)
      await _ensureDirectoryExists(dio, '${_url}thoughtecho/');
      await _ensureDirectoryExists(dio, '${_url}thoughtecho/media/');
      await _ensureDirectoryExists(dio, '${_url}thoughtecho/media/images/');
      await _ensureDirectoryExists(dio, '${_url}thoughtecho/media/videos/');
      await _ensureDirectoryExists(dio, '${_url}thoughtecho/media/audios/');

      final remoteSyncZipUrl = '${_url}thoughtecho/thoughtecho_sync.zip';

      // 2. 检查云端备份是否存在并下载
      Map<String, dynamic>? remoteData;
      bool remoteSyncFileCorrupted = false;
      var remoteSyncFile =
          await _getRemoteSyncFileMetadata(dio, remoteSyncZipUrl);

      if (remoteSyncFile.exists) {
        logDebug('发现云端备份文件，开始下载...');
        final downloadRes = await dio.get<List<int>>(
          remoteSyncZipUrl,
          options: Options(responseType: ResponseType.bytes),
        );

        if (downloadRes.statusCode == 200 && downloadRes.data != null) {
          final bytes = downloadRes.data!;
          final expectedLength = remoteSyncFile.contentLength ??
              _contentLengthFromHeaders(downloadRes.headers);
          if (expectedLength != null && expectedLength != bytes.length) {
            throw StateError(
              '云端同步文件下载不完整，期望 $expectedLength 字节，实际 ${bytes.length} 字节',
            );
          }
          try {
            remoteData = _decodeAndValidateRemoteSyncZip(bytes);
          } on _CorruptedRemoteSyncFileException catch (e) {
            // 损坏的云端文件里没有任何可合并的数据，若继续抛错，每次同步都会
            // 卡在同一处、永远无法自愈。这里改为归档损坏文件并用本地数据重建。
            remoteData = null;
            remoteSyncFileCorrupted = true;
            logWarning(
              '云端同步文件无法解析（${e.reason}），将归档损坏文件并用本地数据重建',
              source: 'WebDAVSyncService',
            );
            await _archiveCorruptedRemoteSyncFile(dio, remoteSyncZipUrl);
            // 归档可能已把原文件移走，重新探测状态，避免上传时用错
            // If-Match / If-None-Match 前置条件导致 412。
            remoteSyncFile =
                await _getRemoteSyncFileMetadata(dio, remoteSyncZipUrl);
          }
        }
      }

      final dbService = DatabaseService();

      // 3. 如果两端都有数据，进行冲突检测与克隆
      if (remoteData != null && _lastSyncTime.isNotEmpty) {
        logDebug('进行同步冲突检测与隔离...');
        _lastConflictCount = await _detectAndCloneConflicts(
          dbService,
          remoteData,
          _lastSyncTime,
        );
      }

      // 4. 合并云端数据到本地数据库
      if (remoteData != null) {
        logDebug('开始执行 LWW 本地智能合并...');
        final mergeReport = await dbService.importDataWithLWWMerge(
          remoteData,
          sourceDevice: 'WebDAV_Cloud',
        );
        if (mergeReport.hasErrors) {
          throw StateError('云端数据合并失败: ${mergeReport.errors.join('; ')}');
        }
        dbService.refreshQuotes(); // 刷新 UI
      }

      // 5. 增量比对并同步大媒体附件 (Images, Videos, Audios)
      int mediaFailureCount = 0;
      if (skipMedia) {
        logDebug('数据流量下跳过大媒体文件同步');
      } else {
        logDebug('开始同步本地与云端媒体文件...');
        mediaFailureCount = await _syncMediaFiles(dio);
      }

      // 6. 流式写入本地数据到临时文件并上传（避免全量数据入内存）
      logDebug('打包本地最新数据上传云端...');
      final tempDir = await getTemporaryDirectory();
      final tempJsonPath = p.join(
        tempDir.path,
        'thoughtecho_webdav_sync.json',
      );
      final tempZipPath = p.join(
        tempDir.path,
        'thoughtecho_webdav_sync.zip',
      );
      try {
        // 分页流式写入 JSON 到临时文件
        await _writeLocalDataToTempJson(dbService.database, tempJsonPath);

        await packSyncZip(tempJsonPath, tempZipPath);

        await _uploadSyncZipWithConflictProtection(
          dio,
          remoteSyncZipUrl,
          File(tempZipPath),
          remoteSyncFile,
        );
      } finally {
        // 清理临时文件
        for (final path in [tempJsonPath, tempZipPath]) {
          final f = File(path);
          if (await f.exists()) await f.delete();
        }
      }

      // 7. 更新同步状态。笔记数据已完整同步，水位线可以前推；
      // 但媒体附件传输失败绝不能对用户谎报"成功"（下次同步会自动增量重试）
      _lastSyncTime = DateTime.now().toUtc().toIso8601String();
      await _mmkv.setString('webdav_last_sync_time', _lastSyncTime);
      if (mediaFailureCount > 0) {
        _syncStatus = WebDAVSyncStatus.failed;
        _lastSyncError = '笔记数据已同步，但 $mediaFailureCount 个媒体附件传输失败，将在下次同步自动重试';
        await _mmkv.setString('webdav_sync_status', 'failed');
        await _mmkv.setString('webdav_last_sync_error', _lastSyncError);
        logWarning(
          'WebDAV 同步部分完成：$mediaFailureCount 个媒体附件传输失败。冲突数: $_lastConflictCount',
          source: 'WebDAVSyncService',
        );
      } else {
        _syncStatus = WebDAVSyncStatus.success;
        _lastSyncError = ''; // 成功时清除上次错误
        _pendingSyncRetryCount = 0;
        await _mmkv.setString('webdav_sync_status', 'success');
        await _mmkv.setString('webdav_last_sync_error', '');

        logInfo(
          'WebDAV 同步成功完成。冲突数: $_lastConflictCount'
          '${remoteSyncFileCorrupted ? '（本轮已用本地数据重建损坏的云端同步文件）' : ''}',
        );
      }
    } catch (e, stack) {
      logError(
        'WebDAV 同步失败',
        error: e,
        stackTrace: stack,
        source: 'WebDAVSyncService',
      );
      _syncStatus = WebDAVSyncStatus.failed;
      _lastSyncError = _sanitizeSyncError(e);
      await _mmkv.setString('webdav_sync_status', 'failed');
      await _mmkv.setString('webdav_last_sync_error', _lastSyncError);
    } finally {
      _isSyncExecuting = false;
      notifyListeners();
      if (_hasPendingSync) {
        _hasPendingSync = false;
        if (_syncStatus == WebDAVSyncStatus.success) {
          logDebug('检测到排队中的同步任务，开始执行追加同步...');
          Future.microtask(() => triggerSync(isBackground: isBackground));
        } else if (_pendingSyncRetryCount < _maxPendingSyncRetries) {
          // 失败后的追加同步必须退避：立即重试会在 ETag 冲突等场景下
          // 形成无延迟的无限循环（每轮全量下载+合并+媒体扫描）
          final delay = Duration(seconds: 5 * (1 << _pendingSyncRetryCount));
          _pendingSyncRetryCount++;
          logDebug(
            '同步未成功，${delay.inSeconds}s 后重试排队任务（第 $_pendingSyncRetryCount/$_maxPendingSyncRetries 次）',
          );
          Future.delayed(
            delay,
            () => triggerSync(isBackground: isBackground),
          );
        } else {
          _pendingSyncRetryCount = 0;
          logWarning(
            '追加同步重试已达上限（$_maxPendingSyncRetries 次），放弃本轮排队任务，等待下次手动或定时同步',
            source: 'WebDAVSyncService',
          );
        }
      }
    }
  }

  @visibleForTesting
  static String sanitizeSyncErrorForTesting(Object e) =>
      _instance._sanitizeSyncError(e);

  /// 将异常转换为对用户安全、友好的错误摘要（不含 URL、密码等敏感信息）
  String _sanitizeSyncError(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) return '认证失败，请检查用户名和密码';
      if (code == 404) return '服务器路径不存在，请检查地址配置';
      if (code == 507) return '服务器存储空间不足';
      if (code != null && code >= 500) return '服务器内部错误 ($code)';
      if (code != null && code >= 400) return 'HTTP 错误 ($code)';
    }

    final raw = e.toString();
    // HTTP 状态码识别
    final statusMatch = RegExp(
            r'status[Cc]ode[:\s]+(\d+)|status code[:\s]+(\d+)|HTTP\s+(\d+)',
            caseSensitive: false)
        .firstMatch(raw);
    if (statusMatch != null) {
      final matchedStr =
          statusMatch.group(1) ?? statusMatch.group(2) ?? statusMatch.group(3);
      final code = int.tryParse(matchedStr ?? '');
      if (code == 401 || code == 403) return '认证失败，请检查用户名和密码';
      if (code == 404) return '服务器路径不存在，请检查地址配置';
      if (code == 507) return '服务器存储空间不足';
      if (code != null && code >= 500) return '服务器内部错误 ($code)';
      if (code != null && code >= 400) return 'HTTP 错误 ($code)';
    }
    // 网络类错误
    if (raw.contains('SocketException') ||
        raw.contains('NetworkException') ||
        raw.contains('Connection refused') ||
        raw.contains('Failed host lookup')) {
      return '无法连接到服务器，请检查网络和地址';
    }
    if (raw.contains('HandshakeException') ||
        raw.contains('CERTIFICATE') ||
        raw.contains('certificate')) {
      return 'SSL 证书验证失败';
    }
    if (raw.contains('TimeoutException') || raw.contains('timed out')) {
      return '连接超时，请检查网络';
    }
    if (raw.contains('DioException') || raw.contains('DioError')) {
      return '网络请求失败，请稍后重试';
    }
    // 脱敏替换，包含包含用户名密码的 URL
    final safe = raw.replaceAll(RegExp(r'https?://[^\s]+'), '[服务器地址]');
    return safe.length > 80 ? '${safe.substring(0, 80)}…' : safe;
  }

  Future<_RemoteSyncFileMetadata> _getRemoteSyncFileMetadata(
    Dio dio,
    String fileUrl,
  ) async {
    try {
      final response = await dio.request(
        fileUrl,
        options: Options(
          method: 'PROPFIND',
          headers: {'Depth': '0'},
          responseType: ResponseType.plain,
          validateStatus: (status) =>
              status == 200 || status == 207 || status == 404,
        ),
      );

      if (response.statusCode == 404) {
        return const _RemoteSyncFileMetadata(exists: false);
      }
      if (response.statusCode != 200 && response.statusCode != 207) {
        return const _RemoteSyncFileMetadata(exists: false);
      }

      final body = response.data?.toString() ?? '';
      final targetResponse = _findTargetSyncFilePropfindResponse(body, fileUrl);
      if (targetResponse == null) {
        return const _RemoteSyncFileMetadata(exists: false);
      }
      final lastModifiedHeader = response.headers.value('last-modified');
      final xmlLastModified =
          _extractFirstXmlTagValue(targetResponse, 'getlastmodified');
      final lastModified =
          (xmlLastModified != null && xmlLastModified.isNotEmpty)
              ? xmlLastModified
              : lastModifiedHeader;

      return _RemoteSyncFileMetadata(
        exists: true,
        etag: _extractFirstXmlTagValue(targetResponse, 'getetag'),
        contentLength: int.tryParse(
          _extractFirstXmlTagValue(targetResponse, 'getcontentlength') ?? '',
        ),
        lastModified: lastModified,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const _RemoteSyncFileMetadata(exists: false);
      }
      rethrow;
    }
  }

  int? _contentLengthFromHeaders(Headers headers) {
    final value = headers.value(Headers.contentLengthHeader);
    if (value == null || value.isEmpty) return null;
    return int.tryParse(value);
  }

  static String? _findTargetSyncFilePropfindResponse(
    String xmlData,
    String fileUrl,
  ) {
    if (xmlData.trim().isEmpty) return null;

    final targetPath = _normalizedUriPath(fileUrl);
    if (targetPath == null || targetPath.endsWith('/')) return null;

    final responseRegExp = RegExp(
      r'<(?:[a-zA-Z0-9_.-]+:)?response\b[\s\S]*?<\/(?:[a-zA-Z0-9_.-]+:)?response>',
      caseSensitive: false,
    );
    final hrefRegExp = RegExp(
      r'<(?:[a-zA-Z0-9_.-]+:)?href>([\s\S]*?)<\/(?:[a-zA-Z0-9_.-]+:)?href>',
      caseSensitive: false,
    );
    final collectionRegExp = RegExp(
      r'<(?:[a-zA-Z0-9_.-]+:)?collection\s*/?>',
      caseSensitive: false,
    );

    final responses = responseRegExp.allMatches(xmlData).toList();
    final responseBlocks = responses.isEmpty
        ? <String>[xmlData]
        : responses.map((m) => m[0]!).toList();

    for (final block in responseBlocks) {
      if (collectionRegExp.hasMatch(block)) continue;
      if (!_propfindResponseHasSuccessStatus(block)) continue;

      final hrefMatch = hrefRegExp.firstMatch(block);
      if (hrefMatch == null) continue;

      final hrefPath = _normalizedUriPath(hrefMatch.group(1) ?? '');
      if (hrefPath == targetPath) return block;
    }

    return null;
  }

  static bool _propfindResponseHasSuccessStatus(String responseBlock) {
    final statusRegExp = RegExp(
      r'<(?:[a-zA-Z0-9_.-]+:)?status>\s*HTTP/\d(?:\.\d)?\s+(\d{3})[\s\S]*?<\/(?:[a-zA-Z0-9_.-]+:)?status>',
      caseSensitive: false,
    );
    final statusCodes = statusRegExp
        .allMatches(responseBlock)
        .map((match) => int.tryParse(match.group(1) ?? ''))
        .whereType<int>()
        .toList();

    if (statusCodes.isEmpty) return true;
    return statusCodes.any((code) => code >= 200 && code < 300);
  }

  static String? _normalizedUriPath(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    final rawPath = uri?.path ?? trimmed;
    String decodedPath;
    try {
      decodedPath = Uri.decodeComponent(rawPath);
    } catch (_) {
      decodedPath = Uri.decodeFull(rawPath);
    }

    var normalized = decodedPath.replaceAll('\\', '/');
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  /// 是否为同步包中的数据条目。兼容旧版本/其他导出路径产生的
  /// `data.json` 与带目录前缀的条目名。
  static bool _isBackupDataEntryName(String name) {
    final posixName = name.replaceAll('\\', '/');
    return posixName == 'backup_data.json' ||
        posixName == 'data.json' ||
        posixName.endsWith('/backup_data.json') ||
        posixName.endsWith('/data.json');
  }

  /// 把本地数据 JSON 打包成上传用的同步 ZIP。
  ///
  /// ZipFileEncoder.addFile 是异步的：不 await 会在条目真正写入前就 closeSync，
  /// 产出一个不含 backup_data.json 的空包并推到云端，导致所有设备此后都报
  /// “云端同步文件缺少 backup_data.json”且无法自愈。
  @visibleForTesting
  static Future<void> packSyncZip(String jsonPath, String zipPath) async {
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    try {
      await encoder.addFile(File(jsonPath), 'backup_data.json');
    } finally {
      encoder.closeSync();
    }

    // 上传前自检，杜绝把不含数据条目的包推到云端污染其他设备
    _assertSyncZipContainsBackupData(zipPath);
  }

  /// 上传前校验本地打好的同步包确实含有数据条目
  static void _assertSyncZipContainsBackupData(String zipPath) {
    final inputStream = InputFileStream(zipPath);
    try {
      final hasData = ZipDecoder()
          .decodeStream(inputStream)
          .any((file) => _isBackupDataEntryName(file.name));
      if (!hasData) {
        throw StateError('本地打包的同步文件缺少 backup_data.json，已中止上传');
      }
    } finally {
      inputStream.closeSync();
    }
  }

  @visibleForTesting
  static Map<String, dynamic> decodeAndValidateRemoteSyncZipForTesting(
    List<int> bytes,
  ) =>
      _instance._decodeAndValidateRemoteSyncZip(bytes);

  Map<String, dynamic> _decodeAndValidateRemoteSyncZip(List<int> bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw _CorruptedRemoteSyncFileException('不是有效的 ZIP 文件 ($e)');
    }

    ArchiveFile? dataJsonFile;
    for (final file in archive) {
      if (file.isFile && _isBackupDataEntryName(file.name)) {
        dataJsonFile = file;
        break;
      }
    }
    if (dataJsonFile == null) {
      throw const _CorruptedRemoteSyncFileException('缺少 backup_data.json');
    }

    final Object? decoded;
    try {
      decoded = json.decode(utf8.decode(dataJsonFile.content));
    } catch (e) {
      throw _CorruptedRemoteSyncFileException('数据文件不是有效 JSON ($e)');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const _CorruptedRemoteSyncFileException('云端同步数据不是有效对象');
    }
    _validateRemoteSyncData(decoded);
    return decoded;
  }

  /// 把无法解析的云端文件改名归档，避免重建时直接丢弃用户数据。
  /// 归档失败不阻断同步（本地数据本身才是权威副本）。
  Future<void> _archiveCorruptedRemoteSyncFile(Dio dio, String fileUrl) async {
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-');
    final destination = fileUrl.replaceFirst(
      RegExp(r'thoughtecho_sync\.zip$'),
      'thoughtecho_sync.corrupted-$stamp.zip',
    );
    try {
      await dio.request(
        fileUrl,
        options: Options(
          method: 'MOVE',
          headers: {'Destination': destination, 'Overwrite': 'F'},
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      logInfo('已归档损坏的云端同步文件', source: 'WebDAVSyncService');
    } catch (e) {
      logWarning(
        '归档损坏的云端同步文件失败，将直接以本地数据覆盖: $e',
        source: 'WebDAVSyncService',
      );
    }
  }

  void _validateRemoteSyncData(Map<String, dynamic> data) {
    final categories = data['categories'];
    final quotes = data['quotes'];
    if (categories is! List || quotes is! List) {
      throw const _CorruptedRemoteSyncFileException(
        '云端同步数据缺少 categories 或 quotes 列表',
      );
    }

    for (final category in categories) {
      if (category is! Map) {
        throw const _CorruptedRemoteSyncFileException('云端同步分类数据格式无效');
      }
    }

    for (final quote in quotes) {
      if (quote is! Map) {
        throw const _CorruptedRemoteSyncFileException('云端同步笔记数据格式无效');
      }
    }

    final tombstones = data['tombstones'];
    if (tombstones != null && tombstones is! List) {
      throw const _CorruptedRemoteSyncFileException('云端同步墓碑数据格式无效');
    }
    if (tombstones is List) {
      for (final tombstone in tombstones) {
        if (tombstone is! Map) {
          throw const _CorruptedRemoteSyncFileException('云端同步墓碑记录格式无效');
        }
      }
    }
  }

  Future<void> _uploadSyncZipWithConflictProtection(
    Dio dio,
    String fileUrl,
    File zipFile,
    _RemoteSyncFileMetadata remoteSyncFile,
  ) async {
    final fileLen = await zipFile.length();
    final headers = <String, Object>{
      Headers.contentTypeHeader: 'application/zip',
      Headers.contentLengthHeader: fileLen,
    };

    if (remoteSyncFile.exists) {
      if (remoteSyncFile.etag != null && remoteSyncFile.etag!.isNotEmpty) {
        headers['If-Match'] = remoteSyncFile.etag!;
      } else if (remoteSyncFile.lastModified != null &&
          remoteSyncFile.lastModified!.isNotEmpty) {
        headers['If-Unmodified-Since'] = remoteSyncFile.lastModified!;
      } else {
        logWarning(
          '云端同步文件未提供 ETag 与 Last-Modified 标头，执行上传前预检以防止覆盖冲突',
          source: 'WebDAVSyncService',
        );
        final preflightMeta = await _getRemoteSyncFileMetadata(dio, fileUrl);
        if (preflightMeta.exists) {
          if (preflightMeta.etag != null ||
              (remoteSyncFile.contentLength != null &&
                  preflightMeta.contentLength !=
                      remoteSyncFile.contentLength)) {
            _hasPendingSync = true;
            throw StateError('云端同步文件在上传前检测到已被更新，将重新拉取合并后再上传');
          }
        }
      }
    } else {
      headers['If-None-Match'] = '*';
    }

    try {
      await dio.put(
        fileUrl,
        data: zipFile.openRead(),
        options: Options(headers: headers),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 409 || status == 412) {
        _hasPendingSync = true;
        throw StateError('云端同步文件已被其他设备更新，将重新拉取合并后再上传');
      }
      rethrow;
    }
  }

  String? _extractFirstXmlTagValue(String xmlData, String localName) {
    final regExp = RegExp(
      '<(?:[a-zA-Z0-9_.-]+:)?$localName>([\\s\\S]*?)'
      '</(?:[a-zA-Z0-9_.-]+:)?$localName>',
      caseSensitive: false,
    );
    return regExp.firstMatch(xmlData)?.group(1)?.trim();
  }

  /// 确保 WebDAV 上特定目录存在，如果不存在则自动创建
  Future<void> _ensureDirectoryExists(Dio dio, String folderUrl) async {
    try {
      final response = await dio.request(
        folderUrl,
        options: Options(
          method: 'PROPFIND',
          headers: {'Depth': '0'},
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      // 404 说明目录不存在，发起创建目录请求
      if (response.statusCode == 404) {
        logDebug('创建 WebDAV 目录: $folderUrl');
        await dio.request(
          folderUrl,
          options: Options(
            method: 'MKCOL',
            validateStatus: (status) =>
                status == 201 || status == 405, // 405 表示已存在
          ),
        );
      }
    } catch (e) {
      // 捕获目录检查与创建错误，防止因单级目录问题阻断后续流程
      logDebug('检查目录存在失败 ($folderUrl): $e');
    }
  }

  /// 冲突检测，对两端都修改过的笔记的本地版进行“同步冲突”分类克隆
  Future<int> _detectAndCloneConflicts(
    DatabaseService dbService,
    Map<String, dynamic> remoteData,
    String lastSyncTimeStr,
  ) async {
    if (lastSyncTimeStr.isEmpty) return 0;

    final db = dbService.database;
    final remoteQuotes = remoteData['quotes'] as List?;
    if (remoteQuotes == null || remoteQuotes.isEmpty) return 0;

    final lastSync = LWWUtils.parseTimestamp(lastSyncTimeStr);

    // 查询自上次同步后，本地被修改过且没有被软删除的笔记。
    // 注意：不能用 SQL 字符串比较 last_modified —— 历史数据中 UTC（带Z）与
    // 本地时区（无Z）格式混杂，字典序比较会漏检，导致本地编辑未备份即被覆盖。
    // 因此先取元数据在 Dart 侧用统一的时间戳解析语义过滤。
    final allLocalMeta = await db.query(
      'quotes',
      columns: ['id', 'last_modified'],
      where: 'is_deleted = 0',
    );
    final modifiedIds = <String>[];
    for (final row in allLocalMeta) {
      final modTime = LWWUtils.parseTimestamp(row['last_modified'] as String?);
      if (modTime.isAfter(lastSync)) {
        modifiedIds.add(row['id'] as String);
      }
    }
    if (modifiedIds.isEmpty) return 0;

    final localQuotes = <Map<String, Object?>>[];
    // 按块查询以避免超过 SQLite 参数数量限制
    for (var i = 0; i < modifiedIds.length; i += 900) {
      final end = (i + 900 < modifiedIds.length) ? i + 900 : modifiedIds.length;
      final chunk = modifiedIds.sublist(i, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      localQuotes.addAll(await db.query(
        'quotes',
        where: 'id IN ($placeholders)',
        whereArgs: chunk,
      ));
    }

    if (localQuotes.isEmpty) return 0;

    final localQuotesMap = {
      for (final q in localQuotes) (q['id'] as String): q,
    };

    int conflictsCloned = 0;

    final List<Map<String, dynamic>> conflictingQuotes = [];

    // 比对云端对应笔记的修改时间
    for (final rq in remoteQuotes) {
      final rqMap = Map<String, dynamic>.from(rq as Map<String, dynamic>);
      final quoteId = rqMap['id'] as String?;
      if (quoteId == null) continue;

      final localQuote = localQuotesMap[quoteId];
      if (localQuote == null) continue;

      final remoteModStr = rqMap['last_modified']?.toString() ??
          rqMap['lastModified']?.toString() ??
          '';
      if (remoteModStr.isEmpty) continue;

      // 用容错解析：云端单条脏时间戳不应让整个同步流程永久失败
      // （解析失败返回 Unix 纪元 → isAfter(lastSync) 为 false → 该条跳过冲突判定）
      final remoteModTime = LWWUtils.parseTimestamp(remoteModStr);
      final localModTime = LWWUtils.parseTimestamp(
        localQuote['last_modified'] as String?,
      );

      // 如果两边都有修改，且内容不同，则判定为冲突
      if (localModTime.isAfter(lastSync) && remoteModTime.isAfter(lastSync)) {
        final localContent = localQuote['content'] as String? ?? '';
        final remoteContent = rqMap['content'] as String? ?? '';

        if (localContent != remoteContent) {
          conflictingQuotes.add(localQuote);
        }
      }
    }

    if (conflictingQuotes.isEmpty) return 0;

    // 批量预取所有冲突笔记的标签，消除 N+1 查询
    final Map<String, List<Map<String, Object?>>> tagsMap = {};
    final batchQuery = db.batch();

    // 按块处理以避免超过 900 个参数的 SQLite 限制
    for (var i = 0; i < conflictingQuotes.length; i += 900) {
      final end = (i + 900 < conflictingQuotes.length)
          ? i + 900
          : conflictingQuotes.length;
      final chunk = conflictingQuotes
          .sublist(i, end)
          .map((q) => q['id'] as String)
          .toList();
      final placeholders = List.filled(chunk.length, '?').join(',');
      batchQuery.query(
        'quote_tags',
        where: 'quote_id IN ($placeholders)',
        whereArgs: chunk,
      );
    }

    final results = await batchQuery.commit();
    for (final chunkResult in results) {
      final tagsList = chunkResult as List<Object?>;
      for (final tagObj in tagsList) {
        final tag = tagObj as Map<String, Object?>;
        final qId = tag['quote_id'] as String;
        tagsMap.putIfAbsent(qId, () => []).add(tag);
      }
    }

    // 在循环前提前确保冲突分类存在，避免 N+1 查询
    await _ensureConflictCategoryExists(db);

    final cloneBatch = db.batch();
    for (final quote in conflictingQuotes) {
      conflictsCloned++;
      _cloneConflictQuote(
        cloneBatch,
        quote,
        tagsMap[quote['id'] as String] ?? [],
      );
    }

    if (conflictingQuotes.isNotEmpty) {
      await cloneBatch.commit(noResult: true);
    }

    return conflictsCloned;
  }

  Future<void> _ensureConflictCategoryExists(Database db) async {
    final catCheck = await db.query(
      'categories',
      where: 'id = ?',
      whereArgs: [conflictCategoryId],
    );

    if (catCheck.isEmpty) {
      // 分类名称使用固定的内部标识符存库，UI 展示时应通过 l10n 映射
      // 以避免在非中文环境下因数据库存储中文名导致的国际化不一致问题
      await db.insert('categories', {
        'id': conflictCategoryId,
        'name': 'sync_conflict',
        'is_default': 0,
        'icon_name': 'warning_amber_rounded',
        'last_modified': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }

  /// 克隆冲突的笔记，并将分类设为“同步冲突”
  void _cloneConflictQuote(
    Batch batch,
    Map<String, dynamic> localQuote,
    List<Map<String, Object?>> tags,
  ) {
    try {
      // 分类已在调用方确保存在，无需在此重复查询

      // 2. 拷贝笔记元数据
      final String clonedId = const Uuid().v4();
      final clonedQuote = Map<String, dynamic>.from(localQuote);

      clonedQuote['id'] = clonedId;
      clonedQuote['category_id'] = conflictCategoryId;
      clonedQuote['last_modified'] = DateTime.now().toUtc().toIso8601String();
      clonedQuote['content'] = '[冲突备份] ${clonedQuote['content']}';

      // 富文本 Quill Delta JSON 插入前缀
      if (clonedQuote['delta_content'] != null &&
          (clonedQuote['delta_content'] as String).isNotEmpty) {
        try {
          final delta = json.decode(clonedQuote['delta_content'] as String);
          if (delta is List) {
            delta.insert(0, {'insert': '[冲突备份] '});
            clonedQuote['delta_content'] = json.encode(delta);
          }
        } catch (_) {}
      }

      batch.insert('quotes', clonedQuote);

      // 3. 复制对应的标签关联关系
      if (tags.isNotEmpty) {
        for (final tag in tags) {
          batch.insert('quote_tags', {
            'quote_id': clonedId,
            'tag_id': tag['tag_id'],
          });
        }
      }

      logDebug('已准备为冲突的笔记创建冲突隔离备份: $clonedId');
    } catch (e) {
      // 升级为 Warning：克隆失败会导致用户以为冲突已备份但实际没有，需要明确记录
      logWarning('克隆冲突笔记准备失败，冲突数据未被备份: $e', source: 'WebDAVSyncService');
    }
  }

  /// 增量比对并同步本地与云端媒体文件夹 (Images, Videos, Audios)
  ///
  /// 返回失败数（目录扫描失败/上传失败/下载失败之和）。调用方必须根据
  /// 返回值决定同步状态 —— 失败绝不能被静默吞掉后仍报告"同步成功"。
  Future<int> _syncMediaFiles(Dio dio) async {
    int failureCount = 0;
    final appDir = await getApplicationDocumentsDirectory();
    final mediaRoot = Directory(p.join(appDir.path, 'media'));

    // 1. 扫描本地所有存在的媒体文件
    final List<File> localFiles = await mediaRoot.exists()
        ? mediaRoot.listSync(recursive: true).whereType<File>().toList()
        : <File>[];

    final Map<String, File> localMediaMap = {};
    for (final f in localFiles) {
      // 跳过中断下载残留的临时文件，避免把残缺内容上传到云端
      if (f.path.endsWith('.tmp') || f.path.endsWith('.part')) continue;
      final relPath = p.relative(f.path, from: mediaRoot.path);
      // 标准化路径斜杠，防止 Windows 系统的反斜杠导致 WebDAV 匹配失败
      final stdPath = relPath.replaceAll('\\', '/');
      localMediaMap[stdPath] = f;
    }

    final remoteMediaFiles = <String, int?>{};
    final remoteMediaEtags = <String, String?>{};
    final failedRemoteMediaFolders = <String>{};

    // 2. 并行扫描云端所有媒体子目录的文件列表，减少网络请求等待时间并防限流
    await Future.wait(_mediaSubFolders.map((folder) async {
      final folderUrl = '${_url}thoughtecho/media/$folder/';
      try {
        final response = await dio.request(
          folderUrl,
          options: Options(
            method: 'PROPFIND',
            headers: {'Depth': '1'},
            responseType: ResponseType.plain,
            validateStatus: (status) => status == 207 || status == 200,
          ),
        );

        if ((response.statusCode == 207 || response.statusCode == 200) &&
            response.data != null) {
          final dynamic rawData = response.data;
          final String xmlData = rawData is List<int>
              ? utf8.decode(rawData, allowMalformed: true)
              : rawData.toString();
          final extracted = _extractRemoteMediaDetails(xmlData);
          for (final entry in extracted.entries) {
            remoteMediaFiles[entry.key] = entry.value.length;
            remoteMediaEtags[entry.key] = entry.value.etag;
          }
        }
      } catch (e) {
        failedRemoteMediaFolders.add(folder);
        failureCount++;
        logWarning('获取云端媒体目录 ($folder) 列表失败，该目录本轮不同步: $e',
            source: 'WebDAVSyncService');
      }
    }));

    // 3. 上传本地独有文件到云端
    for (final entry in localMediaMap.entries) {
      final stdPath = entry.key;
      final file = entry.value;
      final fileLen = await file.length();
      final mediaFolder = _mediaFolderFromRelativePath(stdPath);
      if (mediaFolder != null &&
          failedRemoteMediaFolders.contains(mediaFolder)) {
        logDebug('跳过附件上传，等待下次成功获取远端目录后再增量判断: $stdPath');
        continue;
      }

      if (_shouldUploadMediaFile(stdPath, fileLen, remoteMediaFiles)) {
        final remoteSize = remoteMediaFiles[stdPath];
        final reason = remoteMediaFiles.containsKey(stdPath)
            ? '远端大小不一致，本地=$fileLen, 远端=$remoteSize'
            : '远端不存在';
        logDebug('上传本地附件到云端: $stdPath ($reason)');
        final uploadUrl = '${_url}thoughtecho/media/$stdPath';
        try {
          await dio.put(
            uploadUrl,
            data: file.openRead(),
            options: Options(
              headers: {Headers.contentLengthHeader: fileLen},
            ),
          );
        } catch (e) {
          failureCount++;
          logWarning('上传附件失败 ($stdPath): $e', source: 'WebDAVSyncService');
        }
      }
    }

    // 4. 从云端同步本地缺失附件，或清理云端已废弃的孤儿附件（解决“无限复活”Bug）
    for (final stdPath in remoteMediaFiles.keys) {
      if (!localMediaMap.containsKey(stdPath)) {
        // 拼接成 MediaReferenceService 能够识别的标准本地完整路径或数据库存储相对路径
        final localFileFullPath = p.join(
          appDir.path,
          'media',
          stdPath.replaceAll('/', p.separator),
        );

        // 校验该云端文件是否在本地数据库中仍有被引用
        final refCount = await MediaReferenceService.getReferenceCount(
          localFileFullPath,
        );

        if (refCount > 0) {
          // 该云端媒体在本地数据库有笔记引用，需从云端下载（如新设备登录同步）
          logDebug('从云端下载本地缺失且被引用的合法附件: $stdPath');
          final downloadUrl = '${_url}thoughtecho/media/$stdPath';
          final localTargetFile = File(localFileFullPath);

          // 先下载到 .tmp 临时文件 + 哈希校验后再原子改名：中断的下载绝不能留下半截文件——
          // 残缺文件下次同步会因"大小与远端不一致"被误判为本地更新而反向上传，
          // 覆盖云端完好的原件
          final tmpFile = File('${localTargetFile.path}.tmp');
          try {
            // 确保父目录存在
            await localTargetFile.parent.create(recursive: true);
            final downloadResponse =
                await dio.download(downloadUrl, tmpFile.path);

            // 1. 校验下载文件长度与远端一致性
            final downloadedLen = await tmpFile.length();
            final expectedSize = remoteMediaFiles[stdPath];
            if (expectedSize != null &&
                expectedSize > 0 &&
                downloadedLen != expectedSize) {
              throw Exception('下载附件长度不一致: 本地=$downloadedLen, 期望=$expectedSize');
            }
            if (downloadedLen == 0) {
              throw Exception('下载附件为空文件');
            }

            // 2. 完整哈希与 ETag 比对校验
            await _verifyDownloadedFileHash(
              tmpFile,
              remoteEtag: remoteMediaEtags[stdPath],
              responseHeaders: downloadResponse.headers.map,
            );

            // 3. 原子改名/替换
            try {
              await tmpFile.rename(localTargetFile.path);
            } catch (_) {
              await tmpFile.copy(localTargetFile.path);
              await tmpFile.delete();
            }
          } catch (e) {
            failureCount++;
            logWarning('下载附件失败 ($stdPath): $e', source: 'WebDAVSyncService');
            try {
              if (await tmpFile.exists()) await tmpFile.delete();
            } catch (_) {}
          }
        } else {
          // 远端媒体删除需要完整可信的元数据与引用关系。为避免同步包损坏、
          // 合并失败或新设备初次同步时误删云端附件，这里只跳过不再主动删除。
          logDebug('跳过云端未引用附件删除，等待后续本地清理策略处理: $stdPath');
        }
      }
    }

    return failureCount;
  }

  static Map<String, int?> _extractRemoteMediaFiles(String xmlData) {
    final details = _extractRemoteMediaDetails(xmlData);
    return details.map((key, value) => MapEntry(key, value.length));
  }

  static Map<String, _RemoteMediaFileInfo> _extractRemoteMediaDetails(
    String xmlData,
  ) {
    final files = <String, _RemoteMediaFileInfo>{};
    final responseRegExp = RegExp(
      r'<(?:[a-zA-Z0-9_.-]+:)?response\b[\s\S]*?<\/(?:[a-zA-Z0-9_.-]+:)?response>',
      caseSensitive: false,
    );
    final hrefRegExp = RegExp(
      r'<(?:[a-zA-Z0-9_.-]+:)?href>([\s\S]*?)<\/(?:[a-zA-Z0-9_.-]+:)?href>',
      caseSensitive: false,
    );
    final lengthRegExp = RegExp(
      r'<(?:[a-zA-Z0-9_.-]+:)?getcontentlength>(\d+)<\/(?:[a-zA-Z0-9_.-]+:)?getcontentlength>',
      caseSensitive: false,
    );
    final etagRegExp = RegExp(
      r'<(?:[a-zA-Z0-9_.-]+:)?getetag>([\s\S]*?)<\/(?:[a-zA-Z0-9_.-]+:)?getetag>',
      caseSensitive: false,
    );

    final responses = responseRegExp.allMatches(xmlData).toList();
    final responseBlocks = responses.isEmpty
        ? <String>[xmlData]
        : responses.map((m) => m[0]!).toList();

    for (final block in responseBlocks) {
      final hrefMatch = hrefRegExp.firstMatch(block);
      if (hrefMatch == null) continue;

      final relPath = _mediaRelativePathFromHref(hrefMatch.group(1) ?? '');
      if (relPath == null) continue;

      final lengthMatch = lengthRegExp.firstMatch(block);
      final etagMatch = etagRegExp.firstMatch(block);

      files[relPath] = _RemoteMediaFileInfo(
        length:
            lengthMatch == null ? null : int.tryParse(lengthMatch.group(1)!),
        etag: etagMatch?.group(1),
      );
    }

    return files;
  }

  static String? _getHeaderCaseInsensitive(
    Map<String, List<String>>? headers,
    String headerName,
  ) {
    if (headers == null) return null;
    final lowerName = headerName.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lowerName) {
        return entry.value.firstOrNull;
      }
    }
    return null;
  }

  static Future<void> _verifyDownloadedFileHash(
    File file, {
    String? remoteEtag,
    Map<String, List<String>>? responseHeaders,
  }) async {
    // 从 HTTP 响应头大小写不敏感查找哈希或 ETag
    final headerHash =
        _getHeaderCaseInsensitive(responseHeaders, 'x-checksum-sha256') ??
            _getHeaderCaseInsensitive(responseHeaders, 'x-amz-meta-sha256') ??
            _getHeaderCaseInsensitive(responseHeaders, 'content-md5') ??
            _getHeaderCaseInsensitive(responseHeaders, 'etag');

    final targetCandidate = _cleanHashString(headerHash ?? remoteEtag);
    if (targetCandidate == null || targetCandidate.isEmpty) {
      // 远端未提供 Hash/ETag，免去高昂全量哈希计算，降低内存开销与 CPU 占用
      return;
    }

    final cleanTarget = targetCandidate.toLowerCase();
    if (cleanTarget.length == 64) {
      // 64 位 Hex（标准的 SHA-256）：流式计算 SHA-256 避免全量读取载入内存
      final digest = await sha256.bind(file.openRead()).first;
      final localSha256 = digest.toString().toLowerCase();
      if (localSha256 != cleanTarget) {
        throw Exception(
            '下载附件 SHA-256 哈希比对失败: 本地=$localSha256, 远端=$cleanTarget');
      }
    } else if (cleanTarget.length == 32) {
      // 32 位 Hex（标准的 MD5）：流式计算 MD5
      final digest = await md5.bind(file.openRead()).first;
      final localMd5 = digest.toString().toLowerCase();
      if (localMd5 != cleanTarget) {
        throw Exception('下载附件 MD5 哈希比对失败: 本地=$localMd5, 远端=$cleanTarget');
      }
    } else {
      final headerEtag = _getHeaderCaseInsensitive(responseHeaders, 'etag');
      final cleanHeaderEtag = _cleanHashString(headerEtag);
      final dirEtag = _cleanHashString(remoteEtag);
      if (cleanHeaderEtag != null && dirEtag != null) {
        if (cleanHeaderEtag.toLowerCase() != dirEtag.toLowerCase()) {
          throw Exception('下载附件 ETag 比对不一致: 响应头=$cleanHeaderEtag, 目录=$dirEtag');
        }
      }
    }
  }

  static String? _cleanHashString(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.startsWith('W/')) s = s.substring(2).trim();
    if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
      s = s.substring(1, s.length - 1);
    }
    return s.isEmpty ? null : s;
  }

  static String? _mediaRelativePathFromHref(String href) {
    final trimmed = href.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    final rawPath = uri?.path ?? trimmed;
    String decodedPath;
    try {
      decodedPath = Uri.decodeComponent(rawPath);
    } catch (_) {
      decodedPath = Uri.decodeFull(rawPath);
    }

    final normalizedPath = decodedPath.replaceAll('\\', '/');
    if (normalizedPath.endsWith('/')) return null;

    final segments = normalizedPath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();
    for (var i = 0; i < segments.length - 1; i++) {
      if (segments[i] == 'media' &&
          _mediaSubFolders.contains(segments[i + 1])) {
        final relativeSegments = segments.sublist(i + 1);
        if (relativeSegments.any((segment) =>
            segment == '.' || segment == '..' || segment.contains('\u0000'))) {
          return null;
        }
        return relativeSegments.join('/');
      }
    }
    return null;
  }

  static bool _shouldUploadMediaFile(
    String stdPath,
    int localSize,
    Map<String, int?> remoteMediaFiles,
  ) {
    if (!remoteMediaFiles.containsKey(stdPath)) return true;

    final remoteSize = remoteMediaFiles[stdPath];
    // TODO(media-sync): 当前仅以文件大小作为差异判断依据（历史设计）。
    // 文件大小相同但内容不同的媒体文件（如相同尺寸的不同图片）会漏同步。
    // 后续可引入 MD5/SHA1 内容哈希或 ETag 校验作为更精确的对比手段。
    return remoteSize != null && remoteSize != localSize;
  }

  static String? _mediaFolderFromRelativePath(String stdPath) {
    final segments = stdPath.split('/');
    final firstSegment = segments.isEmpty ? null : segments.first;
    return _mediaSubFolders.contains(firstSegment) ? firstSegment : null;
  }

  @visibleForTesting
  static Map<String, int?> extractRemoteMediaFilesForTesting(String xmlData) {
    return _extractRemoteMediaFiles(xmlData);
  }

  @visibleForTesting
  static String? mediaRelativePathFromHrefForTesting(String href) {
    return _mediaRelativePathFromHref(href);
  }

  @visibleForTesting
  static bool isTargetSyncFilePropfindResponseForTesting(
    String xmlData,
    String fileUrl,
  ) {
    return _findTargetSyncFilePropfindResponse(xmlData, fileUrl) != null;
  }

  @visibleForTesting
  static bool shouldUploadMediaFileForTesting(
    String stdPath,
    int localSize,
    Map<String, int?> remoteMediaFiles,
  ) {
    return _shouldUploadMediaFile(stdPath, localSize, remoteMediaFiles);
  }

  @visibleForTesting
  static String? mediaFolderFromRelativePathForTesting(String stdPath) {
    return _mediaFolderFromRelativePath(stdPath);
  }

  /// 流式写入本地同步数据到临时 JSON 文件
  ///
  /// 格式与 [DatabaseBackupService.exportDataAsMap] 兼容：
  /// `{ metadata, categories, quotes: [...], tombstones }`
  /// 笔记按每页 50 条分页查询，避免全表入内存。
  Future<void> _writeLocalDataToTempJson(
    Database db,
    String filePath,
  ) async {
    final sink = File(filePath).openWrite(encoding: utf8);
    try {
      await db.transaction((txn) async {
        final dbVersion = await txn.getVersion();
        sink.write(
          '{"metadata":${json.encode({
                'app': '心迹',
                'version': dbVersion,
                'exportTime': DateTime.now().toIso8601String()
              })},',
        );

        // categories — 一致性快照读取
        final categories = await txn.query('categories');
        sink.write('"categories":${json.encode(categories)},');

        // quotes & quote_tags — 事务内一致性分页读取
        sink.write('"quotes":[');
        const pageSize = 50;
        int offset = 0;
        bool isFirstQuote = true;
        while (true) {
          final page = await txn.rawQuery(
            'SELECT * FROM quotes ORDER BY date DESC LIMIT ? OFFSET ?',
            [pageSize, offset],
          );
          if (page.isEmpty) break;

          // 批量查 tag 关联，避免逐条查询
          final ids = page.map((q) => q['id'] as String).toList();
          final placeholders = List.filled(ids.length, '?').join(',');
          final tagRows = await txn.rawQuery(
            'SELECT quote_id, tag_id FROM quote_tags WHERE quote_id IN ($placeholders)',
            ids,
          );
          final tagsByQuoteId = <String, List<String>>{};
          for (final t in tagRows) {
            tagsByQuoteId
                .putIfAbsent(t['quote_id'] as String, () => [])
                .add(t['tag_id'] as String);
          }

          for (final q in page) {
            if (!isFirstQuote) sink.write(',');
            isFirstQuote = false;
            final m = Map<String, dynamic>.from(q);
            m['tag_ids'] = (tagsByQuoteId[q['id'] as String] ?? []).join(',');
            sink.write(json.encode(m));
          }

          offset += page.length;
          if (page.length < pageSize) break;
        }
        sink.write('],');

        // tombstones — 三列短字符串，数量有界
        final tombstones = await txn.query('quote_tombstones');
        sink.write('"tombstones":${json.encode(tombstones)}}');
      });

      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  /// 供 UI 层侦听数据库修改并静默防抖同步
  void handleNoteChanged() {
    if (!_enabled || !_syncOnChange) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 4), () {
      logDebug('检测到笔记改变，触发后台自动同步...');
      triggerSync(isBackground: true);
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
