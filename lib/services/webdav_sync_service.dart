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
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import '../models/merge_report.dart';
import '../services/connectivity_service.dart';
import '../services/assistant_data_sync_service.dart';
import '../services/chat_session_service.dart'
    show ChatMessageShardDescriptor, parseChatMessageShardDescriptors;
import '../services/database_service.dart';
import '../services/media_fingerprint_cache.dart';
import '../services/media_reference_service.dart';
import '../services/app_preferences_service.dart';
import '../utils/app_logger.dart';
import '../utils/bounded_executor.dart';
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

// A size rejection must fail sync, rather than archive and overwrite remote
// data through the corrupted-file recovery path.
class _RemoteSyncSizeLimitException extends StateError {
  _RemoteSyncSizeLimitException([
    super.message = '云端同步文件超过 32 MiB，已停止同步',
  ]);
}

class _RemoteSyncJsonOutput extends OutputMemoryStream {
  void _checkAdditionalBytes(int count) {
    if (length + count > WebDAVSyncService._maxRemoteSyncBytes) {
      throw _RemoteSyncSizeLimitException();
    }
  }

  @override
  void writeByte(int value) {
    _checkAdditionalBytes(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _checkAdditionalBytes(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _checkAdditionalBytes(stream.length);
    super.writeStream(stream);
  }
}

class _RemoteSyncJsonSink extends ByteConversionSink {
  _RemoteSyncJsonSink(this.output);

  final _RemoteSyncJsonOutput output;

  @override
  void add(List<int> chunk) => output.writeBytes(chunk);

  @override
  void close() {}
}

/// Remote media resource metadata extracted from WebDAV PROPFIND responses.
class RemoteMediaFileInfo {
  const RemoteMediaFileInfo({this.length, this.etag, this.lastModified});

  final int? length;
  final String? etag;
  final DateTime? lastModified;
}

class _RemoteChatShardInfo {
  const _RemoteChatShardInfo({this.length, this.lastModified});

  final int? length;
  final DateTime? lastModified;
}

// Retained as an internal backward-compatible alias for RemoteMediaFileInfo.
// ignore: unused_element
typedef _RemoteMediaFileInfo = RemoteMediaFileInfo;

class WebDAVSyncService extends ChangeNotifier {
  static final WebDAVSyncService _instance = WebDAVSyncService._internal();
  factory WebDAVSyncService() => _instance;

  WebDAVSyncService._internal() {
    _initSettings();
  }

  @visibleForTesting
  WebDAVSyncService.forTesting() : this._internal();

  // 核心存储与安全服务
  final AppPreferencesService _mmkv = AppPreferencesService();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  AssistantDataSyncService? _assistantDataSync;

  /// 挂载对话记录与长期记忆同步编排服务。
  void attachAssistantDataSync(AssistantDataSyncService? service) {
    _assistantDataSync = service;
  }

  // WebDAV 状态
  WebDAVSyncStatus _syncStatus = WebDAVSyncStatus.idle;
  String _lastSyncTime = '';
  int _lastConflictCount = 0;
  bool _hasPendingSync = false; // 是否有排队中的同步任务
  int _pendingSyncRetryCount = 0; // 失败后追加同步的重试计数（指数退避）
  static const int _maxPendingSyncRetries = 3;
  static const int _maxMediaDownloadConcurrency = 4;

  @visibleForTesting
  static int? mediaDownloadConcurrencyForTesting;

  // Sync ZIPs contain JSON only; media is transferred separately. Bound both
  // archive parsing and expanded JSON before allocating strings or objects.
  static const int _maxRemoteSyncBytes = 32 * 1024 * 1024;
  static const int _defaultChatShardThresholdBytes = 24 * 1024 * 1024;
  static const int _defaultMaxChatShardJsonBytes = 8 * 1024 * 1024;
  static const Duration _defaultChatShardStaleCleanupMinAge = Duration(
    hours: 24,
  );
  static const String _pendingChatShardCleanupKey =
      'webdav_pending_chat_shard_cleanup';
  static final RegExp _remoteChatShardFileNamePattern = RegExp(
    r'^shard_[0-9a-f]{64}\.zip$',
  );

  @visibleForTesting
  static int? chatShardThresholdBytesForTesting;

  @visibleForTesting
  static int? maxChatShardJsonBytesForTesting;

  @visibleForTesting
  static Duration? chatShardStaleCleanupMinAgeForTesting;

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
  static const String _passwordStorageKey = 'webdav_password';

  /// 匹配残留的单次/多重编码路径遍历片段（%2e/%2f/%5c，大小写不敏感）。
  /// 静态化避免在多重编码循环检测中每次重复构造。
  static final RegExp _encodedTraversalPattern = RegExp(
    r'%2[ef]|%5c',
    caseSensitive: false,
  );

  // Bound network buffering and XML work independently of server-supplied headers.
  static const int _maxPropfindBytes = 8 * 1024 * 1024;
  static const int _maxPropfindXmlEvents = 100000;
  static const int _maxPropfindDepth = 64;
  static final RegExp _propfindStatusPattern = RegExp(
    r'^HTTP/\d(?:\.\d)?\s+(\d{3})\b',
    caseSensitive: false,
  );

  static final RegExp _errorStatusCodeRegExp = RegExp(
    r'status[Cc]ode[:\s]+(\d+)|status code[:\s]+(\d+)|HTTP\s+(\d+)',
    caseSensitive: false,
  );

  static final RegExp _serverUrlPattern = RegExp(r'https?://[^\s]+');

  static final RegExp _colonOrDotPattern = RegExp(r'[:.]');

  static final RegExp _syncZipSuffixPattern = RegExp(r'thoughtecho_sync\.zip$');

  static final RegExp _sha256HexPattern = RegExp(r'^[0-9a-fA-F]{64}$');
  static final RegExp _md5HexPattern = RegExp(r'^[0-9a-fA-F]{32}$');
  static const Duration _remoteTimestampSkewTolerance = Duration(seconds: 2);

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
      return await _secureStorage.read(key: _passwordStorageKey);
    } catch (_) {
      logError('读取 WebDAV 密码失败', source: 'WebDAVSyncService');
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
    final previousScope = MediaFingerprintCache.buildRemoteScope(
      serverUrl: _url,
      username: _username,
    );
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
      'webdav_sync_notes_only_on_cellular',
      _syncNotesOnlyOnCellular,
    );

    if (password != null) {
      await _secureStorage.write(
        key: _passwordStorageKey,
        value: password.trim(),
      );
    }

    final nextScope = MediaFingerprintCache.buildRemoteScope(
      serverUrl: _url,
      username: _username,
    );
    if (previousScope != nextScope) {
      await _resetMediaFingerprintBaselinesForScopeChange(nextScope);
    }

    notifyListeners();
  }

  Future<void> _resetMediaFingerprintBaselinesForScopeChange(
    String? nextScope,
  ) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      MediaFingerprintCache.resetBaselinesOnScopeChangeSync(
        appDir,
        nextScope: nextScope,
      );
    } catch (e) {
      logDebug('切换 WebDAV 目标时清理媒体指纹基线跳过: $e', source: 'WebDAVSyncService');
    }
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

    // 计算 Basic Auth 头并安全及时清理敏感字节数据
    final basicAuth = buildBasicAuthHeader(requestUsername, requestPassword);
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
      final response = await _requestPropfind(
        dio,
        cleanUrl,
        depth: '0',
        validateStatus: (status) => status != null && status < 500,
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

    Directory? workDir;
    Future<Directory> ensureWorkDir() async =>
        workDir ??= await _createSyncWorkDirectory();

    try {
      // 0. 先确认本地主库可用（必要时会等待/重新初始化）。若主库启动失败，
      // 在这里整体失败并记录一次错误，而不是在后续每个媒体文件上各抛一次。
      // ensureReadyDatabase() 会等待进行中的初始化完成（并传播失败），且在数据
      // 目录迁移持有关闭状态时直接拒绝，不会重新打开旧路径数据库。
      final dbService = DatabaseService();
      final localDb = await dbService.ensureReadyDatabase();

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
      var remoteSyncFile = await _getRemoteSyncFileMetadata(
        dio,
        remoteSyncZipUrl,
      );

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
            remoteData = await compute(_decodeAndValidateRemoteSyncZip, bytes);
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
            remoteSyncFile = await _getRemoteSyncFileMetadata(
              dio,
              remoteSyncZipUrl,
            );
          }
        }
      }

      // 2b. 若云端主索引引用了对话消息分片，先在写入任何本地数据库前逐片下载并完成哈希与 32 MiB 解压校验
      final remoteChatShards = _extractRemoteChatShards(remoteData);
      final verifiedRemoteChatShardPaths = <String>[];
      if (remoteChatShards.isNotEmpty && _assistantDataSync != null) {
        final syncWorkDir = await ensureWorkDir();
        for (var i = 0; i < remoteChatShards.length; i++) {
          final shardPath = await _downloadAndVerifyChatShard(
            dio,
            shard: remoteChatShards[i],
            workDir: syncWorkDir,
            index: i,
          );
          verifiedRemoteChatShardPaths.add(shardPath);
        }
      }

      // 3. 如果两端都有数据，进行冲突检测与克隆
      if (remoteData != null && _lastSyncTime.isNotEmpty) {
        logDebug('进行同步冲突检测与隔离...');
        _lastConflictCount = await _detectAndCloneConflicts(
          dbService,
          remoteData,
          _lastSyncTime,
        );
      }

      // 4. 合并云端数据到本地数据库（固定顺序：笔记 → 对话 → 记忆）
      AssistantSyncStats? assistantMergeStats;
      Map<String, dynamic>? preservedRemoteAgentMemory;
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

        if (_assistantDataSync != null) {
          assistantMergeStats = await _assistantDataSync!.mergeSections(
            remoteData,
            throwOnError: true,
            chatMessageShardPaths: verifiedRemoteChatShardPaths,
          );
        }

        final rawRemoteMemory = remoteData['agent_memory'];
        if (rawRemoteMemory is Map) {
          preservedRemoteAgentMemory = rawRemoteMemory is Map<String, dynamic>
              ? rawRemoteMemory
              : rawRemoteMemory.map((k, v) => MapEntry(k.toString(), v));
        }
      }

      // 5. 增量比对并同步大媒体附件 (Images, Videos, Audios)
      int mediaFailureCount = 0;
      if (skipMedia) {
        logDebug('数据流量下跳过大媒体文件同步');
      } else {
        logDebug('开始同步本地与云端媒体文件...');
        mediaFailureCount = await _syncMediaFiles(dio);
      }

      // 6. 流式写入本地数据到临时文件并上传（超大对话记录自动切分为内容寻址分片，且上传前强制自检 <= 32 MiB）
      logDebug('打包本地最新数据上传云端...');
      // 工作文件放在应用支持目录下、每轮同步独立的子目录中。
      final syncWorkDir = await ensureWorkDir();
      final tempJsonPath = p.join(
        syncWorkDir.path,
        'thoughtecho_webdav_sync.json',
      );
      final tempZipPath = p.join(
        syncWorkDir.path,
        'thoughtecho_webdav_sync.zip',
      );
      final uploadDb = localDb.isOpen ? localDb : await dbService.safeDatabase;
      final forceSkipMemory =
          assistantMergeStats?.memorySkippedBecauseDisabled ?? false;
      await _writeLocalDataToTempJson(
        uploadDb,
        tempJsonPath,
        preservedRemoteAgentMemory: preservedRemoteAgentMemory,
        forceSkipLocalMemoryExport: forceSkipMemory,
      );

      final effectiveShardThreshold =
          chatShardThresholdBytesForTesting ?? _defaultChatShardThresholdBytes;
      final effectiveMaxShardJsonBytes =
          maxChatShardJsonBytesForTesting ?? _defaultMaxChatShardJsonBytes;
      var uploadedChatShards = const <ChatMessageShardDescriptor>[];
      if (_assistantDataSync != null &&
          await File(tempJsonPath).length() > effectiveShardThreshold) {
        uploadedChatShards = await _buildLocalChatShardArchives(
          syncWorkDir,
          maxShardJsonBytes: effectiveMaxShardJsonBytes,
        );
        if (uploadedChatShards.isNotEmpty) {
          await _writeLocalDataToTempJson(
            uploadDb,
            tempJsonPath,
            preservedRemoteAgentMemory: preservedRemoteAgentMemory,
            forceSkipLocalMemoryExport: forceSkipMemory,
            chatMessageShards: uploadedChatShards,
          );
        }
      }

      await packSyncZip(tempJsonPath, tempZipPath);

      final effectiveShardCleanupMinAge =
          chatShardStaleCleanupMinAgeForTesting ??
              _defaultChatShardStaleCleanupMinAge;
      final shardRefreshMaxAge = Duration(
        milliseconds: effectiveShardCleanupMinAge.inMilliseconds ~/ 2,
      );
      final previousRemoteShardFileSet = <String>{
        for (final s in remoteChatShards) s.file,
      };
      final chatShardsDirUrl = '${_url}thoughtecho/chat_shards/';
      if (uploadedChatShards.isNotEmpty) {
        await _ensureDirectoryExists(dio, chatShardsDirUrl);
        final existingRemoteChatShardListing = await _listRemoteChatShardFiles(
          dio,
          chatShardsDirUrl,
        );
        final serverNowUtc = existingRemoteChatShardListing.serverTimeUtc;
        for (final shard in uploadedChatShards) {
          final localShardZip = File(shard.localPath!);
          final localLen = await localShardZip.length();
          final existingInfo = existingRemoteChatShardListing.files[shard.file];
          final existingModifiedUtc = existingInfo?.lastModified?.toUtc();
          // 仅当分片已在拉取到的上一版云端主包清单中活跃引用，且服务端同时返回了可信时钟与修改时间、
          // 且距今未达半衰期时才复用跳过 PUT；新引入或跨内联恢复的分片一律重新 PUT 刷新服务端 mtime 租约。
          final isFreshEnoughToReuse = previousRemoteShardFileSet
                  .contains(shard.file) &&
              existingInfo != null &&
              existingInfo.length == localLen &&
              serverNowUtc != null &&
              existingModifiedUtc != null &&
              shardRefreshMaxAge > Duration.zero &&
              !serverNowUtc.isBefore(existingModifiedUtc) &&
              serverNowUtc.difference(existingModifiedUtc) < shardRefreshMaxAge;
          if (isFreshEnoughToReuse) {
            continue;
          }
          await dio.put(
            '$chatShardsDirUrl${shard.file}',
            data: localShardZip.openRead(),
            options: Options(
              headers: <String, Object>{
                Headers.contentTypeHeader: 'application/zip',
                Headers.contentLengthHeader: localLen,
              },
            ),
          );
        }
      }

      final uploadedMainSnapshot = await _uploadSyncZipWithConflictProtection(
        dio,
        remoteSyncZipUrl,
        File(tempZipPath),
        remoteSyncFile,
      );

      final activeShardFileSet = <String>{
        for (final s in uploadedChatShards) s.file,
      };
      final retiredFromPreviousManifest = <String>{
        for (final s in remoteChatShards)
          if (!activeShardFileSet.contains(s.file)) s.file,
      };
      final hadPendingShardCleanup =
          _mmkv.getBool(_pendingChatShardCleanupKey) ?? false;
      if (uploadedChatShards.isNotEmpty ||
          remoteChatShards.isNotEmpty ||
          hadPendingShardCleanup) {
        final hasRemainingStaleCandidates = await _cleanupStaleRemoteChatShards(
          dio,
          chatShardsDirUrl,
          remoteSyncZipUrl: remoteSyncZipUrl,
          expectedMainEtag: uploadedMainSnapshot.etag,
          expectedMainContentLength: uploadedMainSnapshot.contentLength,
          expectedMainSha256: uploadedMainSnapshot.sha256Hex,
          expectedMainMd5: uploadedMainSnapshot.md5Hex,
          activeShardFiles: activeShardFileSet,
          protectedShardFiles: retiredFromPreviousManifest,
          staleMinAge: effectiveShardCleanupMinAge,
        );
        await _mmkv.setBool(
          _pendingChatShardCleanupKey,
          hasRemainingStaleCandidates,
        );
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
      if (workDir != null) {
        // 清理本轮同步的工作目录（含完整笔记或对话分片快照，必须删除）
        await _cleanupSyncWorkDirectory(workDir!);
      }
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
          Future.delayed(delay, () => triggerSync(isBackground: isBackground));
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
  static String buildBasicAuthHeader(String username, String password) {
    final credentialsBytes = Uint8List.fromList(
      utf8.encode('$username:$password'),
    );
    try {
      return 'Basic ${base64Encode(credentialsBytes)}';
    } finally {
      credentialsBytes.fillRange(0, credentialsBytes.length, 0);
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
    final statusMatch = _errorStatusCodeRegExp.firstMatch(raw);
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
    final safe = raw.replaceAll(_serverUrlPattern, '[服务器地址]');
    return safe.length > 80 ? '${safe.substring(0, 80)}…' : safe;
  }

  Future<_RemoteSyncFileMetadata> _getRemoteSyncFileMetadata(
    Dio dio,
    String fileUrl,
  ) async {
    try {
      final response = await _requestPropfind(
        dio,
        fileUrl,
        depth: '0',
        validateStatus: (status) =>
            status == 200 || status == 207 || status == 404,
      );

      if (response.statusCode == 404) {
        return const _RemoteSyncFileMetadata(exists: false);
      }
      if (response.statusCode != 200 && response.statusCode != 207) {
        return const _RemoteSyncFileMetadata(exists: false);
      }

      final body = response.data ?? '';
      final targetResponse = _findTargetSyncFilePropfindResponse(body, fileUrl);
      if (targetResponse == null) {
        return const _RemoteSyncFileMetadata(exists: false);
      }
      final lastModifiedHeader = response.headers.value('last-modified');
      final xmlLastModified = _extractFirstXmlTagValue(
        targetResponse,
        'getlastmodified',
      );
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

  static Future<Response<String>> _requestPropfind(
    Dio dio,
    String url, {
    required String depth,
    required ValidateStatus validateStatus,
  }) {
    final cancelToken = CancelToken();
    return dio.request<String>(
      url,
      options: Options(
        method: 'PROPFIND',
        headers: {'Depth': depth},
        responseType: ResponseType.plain,
        validateStatus: validateStatus,
      ),
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        if (received > _maxPropfindBytes || total > _maxPropfindBytes) {
          cancelToken.cancel('WebDAV listing exceeds size limit');
        }
      },
    );
  }

  static Iterable<XmlElement> _parsePropfindResponses(String xmlData) {
    if (xmlData.length > _maxPropfindBytes ||
        utf8.encode(xmlData).length > _maxPropfindBytes) {
      throw const FormatException('WebDAV listing exceeds size limit');
    }
    if (xmlData.trim().isEmpty) return const [];

    // Validate the entire listing before exposing any entries to upload decisions.
    // Pull parsing consumes each token once, even when closing tags are missing.
    final events = <XmlEvent>[];
    var depth = 0;
    try {
      for (final event in parseEvents(
        xmlData,
        validateNesting: true,
        validateDocument: true,
      )) {
        if (events.length >= _maxPropfindXmlEvents) {
          throw const FormatException('WebDAV listing exceeds XML event limit');
        }
        if (event is XmlDoctypeEvent) {
          throw const FormatException('WebDAV listing must not contain a DTD');
        }
        if (event is XmlStartElementEvent) {
          if (depth + 1 > _maxPropfindDepth) {
            throw const FormatException(
              'WebDAV listing exceeds XML depth limit',
            );
          }
          if (!event.isSelfClosing) depth++;
        } else if (event is XmlEndElementEvent) {
          depth--;
        }
        events.add(event);
      }
      final document = XmlDocument(const XmlNodeDecoder().convert(events));
      final responses = document.descendantElements.where(
        (element) => element.name.local.toLowerCase() == 'response',
      );
      return responses.isEmpty ? [document.rootElement] : responses;
    } on XmlParserException {
      throw const FormatException('Invalid WebDAV XML listing');
    } on XmlTagException {
      throw const FormatException('Invalid WebDAV XML listing');
    }
  }

  static XmlElement? _findTargetSyncFilePropfindResponse(
    String xmlData,
    String fileUrl,
  ) {
    final targetPath = _normalizedUriPath(fileUrl);
    if (targetPath == null || targetPath.endsWith('/')) return null;

    for (final block in _parsePropfindResponses(xmlData)) {
      if (block.descendantElements.any(
        (element) => element.name.local.toLowerCase() == 'collection',
      )) {
        continue;
      }
      if (!_propfindResponseHasSuccessStatus(block)) continue;

      final href = _extractFirstXmlTagValue(block, 'href');
      if (href == null) continue;

      final hrefPath = _normalizedUriPath(href);
      if (hrefPath == targetPath) return block;
    }

    return null;
  }

  static bool _propfindResponseHasSuccessStatus(XmlElement responseBlock) {
    var hasStatus = false;
    for (final element in responseBlock.descendantElements.where(
      (element) => element.name.local.toLowerCase() == 'status',
    )) {
      final match = _propfindStatusPattern.firstMatch(element.innerText.trim());
      final code = int.tryParse(match?.group(1) ?? '');
      if (code == null) continue;
      hasStatus = true;
      if (code >= 200 && code < 300) return true;
    }
    return !hasStatus;
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

  static const String _syncWorkDirName = 'webdav_sync_tmp';

  /// 在应用支持目录下创建本轮同步专用的工作目录，并清理崩溃遗留的旧目录。
  /// 调用方持有 [_isSyncExecuting] 互斥锁，因此不会误删正在使用的目录。
  Future<Directory> _createSyncWorkDirectory() async {
    final supportDir = await getApplicationSupportDirectory();
    final root = Directory(p.join(supportDir.path, _syncWorkDirName));
    if (await root.exists()) {
      await for (final entity in root.list()) {
        try {
          await entity.delete(recursive: true);
        } catch (e) {
          logWarning(
            '清理遗留的 WebDAV 同步工作文件失败: ${entity.path}, $e',
            source: 'WebDAVSyncService',
          );
        }
      }
    } else {
      await root.create(recursive: true);
    }
    return root.createTemp('run_');
  }

  static const int _maxWorkDirCleanupRetries = 3;

  /// 删除本轮同步工作目录。失败时以 error 级别上报（附路径与堆栈），
  /// 并按指数退避安排有上限的重试；下次同步开始时也会再次清理遗留目录。
  /// 笔记数据此时已上传成功，因此不让清理失败改写同步结果。
  Future<void> _cleanupSyncWorkDirectory(
    Directory workDir, {
    int attempt = 0,
  }) async {
    try {
      if (await workDir.exists()) await workDir.delete(recursive: true);
    } catch (e, stack) {
      final canRetry = attempt < _maxWorkDirCleanupRetries;
      logError(
        '清理 WebDAV 同步工作目录失败: ${workDir.path}'
        '（第 ${attempt + 1} 次${canRetry ? '，稍后重试' : '，已达重试上限，等待下次同步清理'}）',
        error: e,
        stackTrace: stack,
        source: 'WebDAVSyncService',
      );
      if (canRetry) {
        _scheduleWorkDirCleanupRetry(
          workDir,
          nextAttempt: attempt + 1,
          delay: Duration(seconds: 5 * (1 << attempt)),
        );
      }
    }
  }

  /// 安排一次清理重试。若到期时有同步正在执行，不丢弃本次重试，
  /// 而是按相同间隔顺延（不计入重试次数），直到同步结束后再删除。
  void _scheduleWorkDirCleanupRetry(
    Directory workDir, {
    required int nextAttempt,
    required Duration delay,
  }) {
    Future<void>.delayed(delay, () async {
      if (_isSyncExecuting) {
        _scheduleWorkDirCleanupRetry(
          workDir,
          nextAttempt: nextAttempt,
          delay: delay,
        );
        return;
      }
      await _cleanupSyncWorkDirectory(workDir, attempt: nextAttempt);
    });
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

  static final DateTime _deterministicArchiveModTime = DateTime(2020, 1, 1);
  static const int _deterministicArchiveFileMode = 0x81a4; // 0o100644

  /// 把本地数据 JSON 打包成上传用的同步 ZIP。
  ///
  /// ZipFileEncoder.addFile 是异步的：不 await 会在条目真正写入前就 closeSync，
  /// 产出一个不含 backup_data.json 的空包并推到云端，导致所有设备此后都报
  /// “云端同步文件缺少 backup_data.json”且无法自愈。
  /// 当 [deterministic] 为 `true` 时固定归档条目的修改时间与权限位，确保相同 JSON
  /// 内容在跨时间、跨平台上产出完全一致的内容寻址 SHA-256。
  @visibleForTesting
  static Future<void> packSyncZip(
    String jsonPath,
    String zipPath, {
    bool deterministic = false,
  }) async {
    final jsonFile = File(jsonPath);
    if (!await jsonFile.exists()) {
      throw StateError('待打包的本地同步数据文件不存在: $jsonPath');
    }
    final jsonLength = await jsonFile.length();
    if (jsonLength > _maxRemoteSyncBytes) {
      throw _RemoteSyncSizeLimitException(
        '本地同步数据超过 32 MiB 上限，已中止上传以防损坏云端备份',
      );
    }
    final encoder = ZipFileEncoder();
    encoder.create(
      zipPath,
      modified: deterministic ? _deterministicArchiveModTime : null,
    );
    try {
      if (deterministic) {
        final fileStream = InputFileStream(jsonFile.path);
        try {
          final archiveFile = ArchiveFile.stream(
            'backup_data.json',
            fileStream,
          )
            ..lastModTime = 0
            ..mode = _deterministicArchiveFileMode;
          encoder.addArchiveFile(archiveFile);
        } finally {
          await fileStream.close();
        }
      } else {
        await encoder.addFile(jsonFile, 'backup_data.json');
      }
    } finally {
      encoder.closeSync();
    }

    final zipLength = await File(zipPath).length();
    if (zipLength > _maxRemoteSyncBytes) {
      throw _RemoteSyncSizeLimitException(
        '本地同步压缩包超过 32 MiB 上限，已中止上传',
      );
    }

    // 上传前自检，杜绝把不含数据条目或展开超限的包推到云端污染其他设备
    _assertSyncZipContainsBackupData(zipPath);
  }

  /// 上传前校验本地打好的同步包确实含有数据条目且未超出 32 MiB 解压预算
  static void _assertSyncZipContainsBackupData(String zipPath) {
    final inputStream = InputFileStream(zipPath);
    try {
      final directory = ZipDirectory()..read(inputStream);
      ZipFile? dataJsonFile;
      for (final header in directory.fileHeaders) {
        final file = header.file;
        if (file != null && _isBackupDataEntryName(file.filename)) {
          dataJsonFile = file;
          break;
        }
      }
      if (dataJsonFile == null) {
        throw StateError('本地打包的同步文件缺少 backup_data.json，已中止上传');
      }
      if (dataJsonFile.uncompressedSize > _maxRemoteSyncBytes ||
          (dataJsonFile.header?.uncompressedSize ?? 0) > _maxRemoteSyncBytes) {
        throw _RemoteSyncSizeLimitException(
          '本地同步文件解压大小超过 32 MiB 上限，已中止上传',
        );
      }
    } finally {
      inputStream.closeSync();
    }
  }

  @visibleForTesting
  static Map<String, dynamic> decodeAndValidateRemoteSyncZipForTesting(
    List<int> bytes,
  ) =>
      _decodeAndValidateRemoteSyncZip(bytes);

  static Uint8List _decompressSyncZipJsonBytes(List<int> bytes) {
    if (bytes.length > _maxRemoteSyncBytes) {
      throw _RemoteSyncSizeLimitException();
    }
    final directory = ZipDirectory();
    try {
      // ZipDecoder eagerly expands Unix symlink entries. Read metadata only,
      // then decompress just the selected JSON member under the output budget.
      directory.read(InputMemoryStream(bytes));
    } catch (e) {
      throw _CorruptedRemoteSyncFileException('不是有效的 ZIP 文件 ($e)');
    }

    ZipFile? dataJsonFile;
    for (final header in directory.fileHeaders) {
      final file = header.file;
      if (file != null && _isBackupDataEntryName(file.filename)) {
        dataJsonFile = file;
        break;
      }
    }
    if (dataJsonFile == null) {
      throw const _CorruptedRemoteSyncFileException('缺少 backup_data.json');
    }
    if (dataJsonFile.uncompressedSize > _maxRemoteSyncBytes ||
        dataJsonFile.header!.uncompressedSize > _maxRemoteSyncBytes) {
      throw _RemoteSyncSizeLimitException();
    }

    try {
      final output = _RemoteSyncJsonOutput();
      if (dataJsonFile.compressionMethod == CompressionType.deflate) {
        // archive 4.0.9's native decodeStream buffers all chunks before writing
        // to OutputStream. Use dart:io's incremental sink to stop expansion as
        // soon as the actual byte budget is exceeded, even with forged sizes.
        final input = dataJsonFile.getStream(decompress: false);
        final sink = ZLibCodec(raw: true)
            .decoder
            .startChunkedConversion(_RemoteSyncJsonSink(output));
        while (!input.isEOS) {
          sink.add(input.readBytes(1024).toUint8List());
        }
        sink.close();
      } else {
        // Stored and BZip2 entries write directly to the bounded output.
        dataJsonFile.decompress(output);
      }
      return output.getBytes();
    } on _RemoteSyncSizeLimitException {
      rethrow;
    } catch (e) {
      throw _CorruptedRemoteSyncFileException('数据条目解压失败 ($e)');
    }
  }

  static Map<String, dynamic> _decodeAndValidateRemoteSyncZip(List<int> bytes) {
    final jsonBytes = _decompressSyncZipJsonBytes(bytes);
    final Object? decoded;
    try {
      decoded = json.decode(utf8.decode(jsonBytes));
    } catch (e) {
      throw _CorruptedRemoteSyncFileException('数据文件不是有效 JSON ($e)');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const _CorruptedRemoteSyncFileException('云端同步数据不是有效对象');
    }
    _validateRemoteSyncData(decoded);
    return decoded;
  }

  static Uint8List _decodeAndValidateRemoteChatShardZipToBytes(
    List<int> bytes,
  ) {
    final jsonBytes = _decompressSyncZipJsonBytes(bytes);
    final Object? decoded;
    try {
      decoded = json.decode(utf8.decode(jsonBytes));
    } catch (e) {
      throw FormatException('云端对话分片不是有效 JSON ($e)');
    }
    if (decoded is! Map<String, dynamic> || decoded['messages'] is! List) {
      throw const FormatException('云端对话分片结构无效');
    }
    return jsonBytes;
  }

  /// 把无法解析的云端文件改名归档，避免重建时直接丢弃用户数据。
  /// 归档失败不阻断同步（本地数据本身才是权威副本）。
  Future<void> _archiveCorruptedRemoteSyncFile(Dio dio, String fileUrl) async {
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
          _colonOrDotPattern,
          '-',
        );
    final destination = fileUrl.replaceFirst(
      _syncZipSuffixPattern,
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
      logWarning('归档损坏的云端同步文件失败，将直接以本地数据覆盖: $e', source: 'WebDAVSyncService');
    }
  }

  static void _validateRemoteSyncData(Map<String, dynamic> data) {
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

    final chat = data['chat'];
    if (chat != null && chat is! Map) {
      throw const _CorruptedRemoteSyncFileException('云端同步对话数据格式无效');
    }
    if (chat is Map) {
      final chatMap = chat is Map<String, dynamic>
          ? chat
          : chat.map((k, v) => MapEntry(k.toString(), v));
      try {
        parseChatMessageShardDescriptors(chatMap);
      } on FormatException catch (e) {
        throw _CorruptedRemoteSyncFileException(e.message);
      }
    }

    final agentMemory = data['agent_memory'];
    if (agentMemory != null && agentMemory is! Map) {
      throw const _CorruptedRemoteSyncFileException('云端同步记忆数据格式无效');
    }
  }

  Future<
      ({
        String? etag,
        int contentLength,
        String sha256Hex,
        String md5Hex,
      })> _uploadSyncZipWithConflictProtection(
    Dio dio,
    String fileUrl,
    File zipFile,
    _RemoteSyncFileMetadata remoteSyncFile,
  ) async {
    final fileBytes = await zipFile.readAsBytes();
    final fileLen = fileBytes.length;
    final sha256Hex = sha256.convert(fileBytes).toString().toLowerCase();
    final md5Hex = md5.convert(fileBytes).toString().toLowerCase();
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
      final response = await dio.put<void>(
        fileUrl,
        data: Stream<List<int>>.value(fileBytes),
        options: Options(headers: headers),
      );
      final responseEtag = response.headers.value('etag')?.trim();
      return (
        etag: (responseEtag != null && responseEtag.isNotEmpty)
            ? responseEtag
            : null,
        contentLength: fileLen,
        sha256Hex: sha256Hex,
        md5Hex: md5Hex,
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

  static String? _extractFirstXmlTagValue(
    XmlElement response,
    String localName,
  ) {
    for (final element in response.descendantElements) {
      if (element.name.local.toLowerCase() == localName) {
        final trimmed = element.innerText.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      }
    }
    return null;
  }

  /// 确保 WebDAV 上特定目录存在，如果不存在则自动创建
  Future<void> _ensureDirectoryExists(Dio dio, String folderUrl) async {
    try {
      final response = await _requestPropfind(
        dio,
        folderUrl,
        depth: '0',
        validateStatus: (status) => status != null && status < 500,
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
      localQuotes.addAll(
        await db.query(
          'quotes',
          where: 'id IN ($placeholders)',
          whereArgs: chunk,
        ),
      );
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
          // 本轮每个本地快照只备份一次，避免重复云端 ID 放大正文和标签写入。
          localQuotesMap.remove(quoteId);
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
        clonedQuote['delta_content'] = prependConflictPrefixToDelta(
          clonedQuote['delta_content'] as String,
        );
      }

      batch.insert('quotes', clonedQuote);

      // 3. 复制对应的标签关联关系
      if (tags.isNotEmpty) {
        if (tags.length == 1) {
          batch.insert(
              'quote_tags',
              {
                'quote_id': clonedId,
                'tag_id': tags.first['tag_id'],
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
        } else {
          const chunkSize = 400;
          for (var i = 0; i < tags.length; i += chunkSize) {
            final end =
                (i + chunkSize < tags.length) ? i + chunkSize : tags.length;
            final chunk = tags.sublist(i, end);
            final valuePlaceholders = List.filled(
              chunk.length,
              '(?, ?)',
            ).join(', ');
            final args = <Object?>[];
            for (final tag in chunk) {
              args.addAll([clonedId, tag['tag_id']]);
            }
            batch.rawInsert(
              'INSERT OR IGNORE INTO quote_tags (quote_id, tag_id) VALUES $valuePlaceholders',
              args,
            );
          }
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
        ? await mediaRoot
            .list(recursive: true)
            .where((entity) => entity is File)
            .cast<File>()
            .toList()
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

    final remoteScope = MediaFingerprintCache.buildRemoteScope(
      serverUrl: _url,
      username: _username,
    );
    final fingerprintCache = MediaFingerprintCache(
      directory: appDir,
      remoteScope: remoteScope,
    );
    try {
      await fingerprintCache.load();
    } catch (e) {
      logWarning('加载媒体指纹缓存失败，本轮将按无缓存继续同步: $e', source: 'WebDAVSyncService');
    }
    fingerprintCache.pruneMissingFiles(localMediaMap.keys);

    try {
      final remoteMediaDetails = <String, RemoteMediaFileInfo>{};
      final failedRemoteMediaFolders = <String>{};

      // 2. 并行扫描云端所有媒体子目录的文件列表，减少网络请求等待时间并防限流
      await Future.wait(
        _mediaSubFolders.map((folder) async {
          final folderUrl = '${_url}thoughtecho/media/$folder/';
          try {
            final response = await _requestPropfind(
              dio,
              folderUrl,
              depth: '1',
              validateStatus: (status) => status == 207 || status == 200,
            );

            if ((response.statusCode == 207 || response.statusCode == 200) &&
                response.data != null) {
              final extracted = _extractRemoteMediaDetails(response.data!);
              remoteMediaDetails.addAll(extracted);
            }
          } catch (e) {
            failedRemoteMediaFolders.add(folder);
            failureCount++;
            logWarning(
              '获取云端媒体目录 ($folder) 列表失败，该目录本轮不同步: $e',
              source: 'WebDAVSyncService',
            );
          }
        }),
      );

      // 3. 上传本地独有或发生变更的文件到云端（三层增量判定）
      for (final entry in localMediaMap.entries) {
        final stdPath = entry.key;
        final file = entry.value;
        try {
          final mediaFolder = _mediaFolderFromRelativePath(stdPath);
          if (mediaFolder != null &&
              failedRemoteMediaFolders.contains(mediaFolder)) {
            logDebug('跳过附件上传，等待下次成功获取远端目录后再增量判断: $stdPath');
            continue;
          }

          final preStat = await file.stat();
          if (preStat.type != FileSystemEntityType.file) {
            throw FileSystemException('本地媒体文件不可用', file.path);
          }
          final fileLen = preStat.size;
          final preMtimeUtc = preStat.modified.toUtc();

          final shouldUpload = await _shouldUploadMediaFileThreeTier(
            stdPath: stdPath,
            localFile: file,
            localSize: fileLen,
            remoteMediaDetails: remoteMediaDetails,
            fingerprintCache: fingerprintCache,
            localLastModifiedOverride: preMtimeUtc,
          );
          if (shouldUpload) {
            final remoteInfo = remoteMediaDetails[stdPath];
            final String reason;
            if (remoteInfo == null) {
              reason = '远端不存在';
            } else if (remoteInfo.length != fileLen) {
              reason = '远端大小不一致，本地=$fileLen, 远端=${remoteInfo.length}';
            } else {
              reason = '远端指纹或修改时间不一致';
            }
            logDebug('上传本地附件到云端: $stdPath ($reason)');

            // 上传前固定文件大小、修改时间与 SHA-256 快照；若上传过程中文件被覆写，
            // 绝不把未上传的新内容误记为已同步基线。
            final uploadSnapshot = await fingerprintCache.getOrCompute(
              stdPath,
              file,
              knownSize: fileLen,
              knownLastModified: preMtimeUtc,
            );

            final uploadUrl =
                '${_url}thoughtecho/media/${_encodeMediaPath(stdPath)}';
            final putResponse = await dio.put(
              uploadUrl,
              data: file.openRead(),
              options: Options(headers: {Headers.contentLengthHeader: fileLen}),
            );
            try {
              final postStat = await file.stat();
              final snapshotUnchanged =
                  postStat.type == FileSystemEntityType.file &&
                      postStat.size == fileLen &&
                      postStat.modified.toUtc().millisecondsSinceEpoch ==
                          preMtimeUtc.millisecondsSinceEpoch;
              if (!snapshotUnchanged) {
                logWarning(
                  '上传期间本地附件已变更，保留待同步状态以便下轮重传: $stdPath',
                  source: 'WebDAVSyncService',
                );
              } else {
                final responseEtag = _getHeaderCaseInsensitive(
                  putResponse.headers.map,
                  'etag',
                );
                final strongResponseEtag =
                    MediaFingerprintCache.cleanStrongEtag(responseEtag);
                final effectiveEtag = strongResponseEtag ??
                    await _fetchRemoteStrongEtagAfterPut(
                      dio,
                      uploadUrl,
                      expectedSize: fileLen,
                      expectedSha256: uploadSnapshot.sha256,
                      expectedMd5: uploadSnapshot.md5,
                    );
                await fingerprintCache.markSynced(
                  stdPath,
                  file,
                  remoteEtag: effectiveEtag,
                  knownSha256: uploadSnapshot.sha256,
                  knownMd5: uploadSnapshot.md5,
                  knownSize: fileLen,
                  knownLastModified: preMtimeUtc,
                );
              }
            } catch (e) {
              logWarning(
                '更新上传附件指纹缓存失败 ($stdPath): $e',
                source: 'WebDAVSyncService',
              );
            }
          } else {
            final existing = fingerprintCache.peek(stdPath);
            if (existing != null && existing.syncedSha256 == null) {
              fingerprintCache.putEntry(
                stdPath,
                existing.copyWith(syncedSha256: existing.sha256),
              );
            }
          }
        } catch (e) {
          failureCount++;
          logWarning('上传附件失败 ($stdPath): $e', source: 'WebDAVSyncService');
        }
      }

      // 4. 从云端同步本地缺失附件，或清理云端已废弃的孤儿附件（解决“无限复活”Bug）
      final missingRemoteFiles = remoteMediaDetails.keys
          .where((stdPath) => !localMediaMap.containsKey(stdPath))
          .toList(growable: false);

      if (missingRemoteFiles.isNotEmpty) {
        final Set<String> referencedTailSet;
        try {
          referencedTailSet =
              await MediaReferenceService.getAllReferencedMediaTailSet();
        } catch (e) {
          failureCount++;
          logWarning('检查或下载附件失败 (preload): $e', source: 'WebDAVSyncService');
          return failureCount;
        }

        final filesToDownload = <String>[];
        for (final stdPath in missingRemoteFiles) {
          final isReferenced = referencedTailSet.contains(stdPath) ||
              referencedTailSet.contains('media/$stdPath');

          if (isReferenced) {
            filesToDownload.add(stdPath);
          } else {
            // 远端媒体删除需要完整可信的元数据与引用关系。为避免同步包损坏、
            // 合并失败或新设备初次同步时误删云端附件，这里只跳过不再主动删除。
            logDebug('跳过云端未引用附件删除，等待后续本地清理策略处理: $stdPath');
          }
        }

        if (filesToDownload.isNotEmpty) {
          final concurrency = mediaDownloadConcurrencyForTesting ??
              _maxMediaDownloadConcurrency;
          final executor = BoundedExecutor(maxConcurrency: concurrency);

          final results = await executor.map(
            filesToDownload,
            (stdPath) => _downloadAndVerifyMediaFile(
              dio,
              stdPath: stdPath,
              appDir: appDir,
              remoteInfo: remoteMediaDetails[stdPath],
              fingerprintCache: fingerprintCache,
            ),
          );

          for (final success in results) {
            if (!success) {
              failureCount++;
            }
          }
        }
      }
    } finally {
      try {
        await fingerprintCache.save();
      } catch (e) {
        logWarning('保存媒体指纹缓存失败: $e', source: 'WebDAVSyncService');
      }
    }

    return failureCount;
  }

  Future<bool> _downloadAndVerifyMediaFile(
    Dio dio, {
    required String stdPath,
    required Directory appDir,
    RemoteMediaFileInfo? remoteInfo,
    MediaFingerprintCache? fingerprintCache,
  }) async {
    // 下载落盘的目标路径（本机 media 目录下的绝对路径）
    final localFileFullPath = p.join(
      appDir.path,
      'media',
      stdPath.replaceAll('/', p.separator),
    );
    final localTargetFile = File(localFileFullPath);
    final downloadUrl = '${_url}thoughtecho/media/${_encodeMediaPath(stdPath)}';

    // 该云端媒体在本地数据库有笔记引用，需从云端下载（如新设备登录同步）
    logDebug('从云端下载本地缺失且被引用的合法附件: $stdPath');

    // 先下载到 .tmp 临时文件 + 哈希校验后再原子改名：中断的下载绝不能留下半截文件——
    // 残缺文件下次同步会因"大小与远端不一致"被误判为本地更新而反向上传，
    // 覆盖云端完好的原件；校验失败时也绝不能覆盖已有目标文件
    final tmpFile = File('${localTargetFile.path}.tmp');
    try {
      // 确保父目录存在
      await localTargetFile.parent.create(recursive: true);
      final downloadResponse = await dio.download(downloadUrl, tmpFile.path);

      // 1. 校验下载文件长度与远端一致性
      final downloadedLen = await tmpFile.length();
      final expectedSize = remoteInfo?.length;
      if (expectedSize != null &&
          expectedSize > 0 &&
          downloadedLen != expectedSize) {
        throw Exception('下载附件长度不一致: 本地=$downloadedLen, 期望=$expectedSize');
      }
      if (downloadedLen == 0) {
        throw Exception('下载附件为空文件');
      }

      // 2. 完整哈希与 ETag 比对校验
      final verifiedDigests = await _verifyDownloadedFileHashWithDigests(
        tmpFile,
        remoteEtag: remoteInfo?.etag,
        responseHeaders: downloadResponse.headers.map,
      );

      // 3. 原子改名/替换
      try {
        await tmpFile.rename(localTargetFile.path);
      } catch (_) {
        await tmpFile.copy(localTargetFile.path);
        await tmpFile.delete();
      }

      if (fingerprintCache != null) {
        try {
          final headerEtag = _getHeaderCaseInsensitive(
            downloadResponse.headers.map,
            'etag',
          );
          final effectiveEtag =
              (headerEtag != null && headerEtag.trim().isNotEmpty)
                  ? headerEtag
                  : remoteInfo?.etag;
          final localMtime = await localTargetFile.lastModified();
          await fingerprintCache.markSynced(
            stdPath,
            localTargetFile,
            remoteEtag: effectiveEtag,
            knownSha256: verifiedDigests.sha256,
            knownMd5: verifiedDigests.md5,
            knownSize: downloadedLen,
            knownLastModified: localMtime,
          );
        } catch (e) {
          logWarning(
            '更新下载附件指纹缓存失败 ($stdPath): $e',
            source: 'WebDAVSyncService',
          );
        }
      }
      return true;
    } catch (e) {
      logWarning('下载附件失败 ($stdPath): $e', source: 'WebDAVSyncService');
      try {
        if (await tmpFile.exists()) await tmpFile.delete();
      } catch (_) {}
      return false;
    }
  }

  static Map<String, int?> _extractRemoteMediaFiles(String xmlData) {
    final details = _extractRemoteMediaDetails(xmlData);
    return details.map((key, value) => MapEntry(key, value.length));
  }

  static DateTime? _parseRemoteHttpDate(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      return HttpDate.parse(trimmed).toUtc();
    } catch (_) {
      return DateTime.tryParse(trimmed)?.toUtc();
    }
  }

  static Map<String, RemoteMediaFileInfo> _extractRemoteMediaDetails(
    String xmlData,
  ) {
    final files = <String, RemoteMediaFileInfo>{};

    for (final block in _parsePropfindResponses(xmlData)) {
      final href = _extractFirstXmlTagValue(block, 'href');
      if (href == null) continue;

      final relPath = _mediaRelativePathFromHref(href);
      if (relPath == null) continue;

      files[relPath] = RemoteMediaFileInfo(
        length: int.tryParse(
          _extractFirstXmlTagValue(block, 'getcontentlength') ?? '',
        ),
        etag: _extractFirstXmlTagValue(block, 'getetag'),
        lastModified: _parseRemoteHttpDate(
          _extractFirstXmlTagValue(block, 'getlastmodified'),
        ),
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

  static String? _parseExpectedSha256Hex(String raw) {
    var s = raw.trim();
    if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
      s = s.substring(1, s.length - 1).trim();
    }
    if (s.toLowerCase().startsWith('sha256=')) {
      s = s.substring(7).trim();
      if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
        s = s.substring(1, s.length - 1).trim();
      }
    }
    if (s.isEmpty) return null;
    if (_sha256HexPattern.hasMatch(s)) {
      return s.toLowerCase();
    }
    try {
      final decoded = base64.decode(s);
      if (decoded.length == 32) {
        return _bytesToHex(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static String? _parseExpectedMd5Hex(String raw) {
    var s = raw.trim();
    if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
      s = s.substring(1, s.length - 1).trim();
    }
    if (s.isEmpty) return null;
    if (_md5HexPattern.hasMatch(s)) {
      return s.toLowerCase();
    }
    try {
      final decoded = base64.decode(s);
      if (decoded.length == 16) {
        return _bytesToHex(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static String _bytesToHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static Future<({String? sha256, String? md5})>
      _verifyDownloadedFileHashWithDigests(
    File file, {
    String? remoteEtag,
    Map<String, List<String>>? responseHeaders,
  }) async {
    String? computedSha256;
    String? computedMd5;
    var hasVerifiedCryptoHash = false;

    Future<String> ensureSha256() async {
      if (computedSha256 != null) return computedSha256!;
      final digest = await sha256.bind(file.openRead()).first;
      computedSha256 = digest.toString().toLowerCase();
      return computedSha256!;
    }

    Future<String> ensureMd5() async {
      if (computedMd5 != null) return computedMd5!;
      final digest = await md5.bind(file.openRead()).first;
      computedMd5 = digest.toString().toLowerCase();
      return computedMd5!;
    }

    // 1. 显式 SHA-256 校验头（64 位 Hex 或 32 字节 Base64，支持引号与 sha256= 前缀）
    for (final headerName in const ['x-checksum-sha256', 'x-amz-meta-sha256']) {
      final rawHeader = _getHeaderCaseInsensitive(responseHeaders, headerName);
      if (rawHeader == null) continue;
      final expectedSha256 = _parseExpectedSha256Hex(rawHeader);
      if (expectedSha256 == null) {
        throw FormatException('下载附件校验头格式无效 ($headerName)');
      }
      final localSha256 = await ensureSha256();
      if (localSha256 != expectedSha256) {
        throw Exception(
          '下载附件 SHA-256 哈希比对失败: 本地=$localSha256, 远端=$expectedSha256',
        );
      }
      hasVerifiedCryptoHash = true;
    }

    // 2. 显式 Content-MD5 校验头（32 位 Hex 或 16 字节 RFC-1864 Base64）
    final rawContentMd5 = _getHeaderCaseInsensitive(
      responseHeaders,
      'content-md5',
    );
    if (rawContentMd5 != null) {
      final expectedMd5 = _parseExpectedMd5Hex(rawContentMd5);
      if (expectedMd5 == null) {
        throw const FormatException('下载附件校验头格式无效 (content-md5)');
      }
      final localMd5 = await ensureMd5();
      if (localMd5 != expectedMd5) {
        throw Exception('下载附件 MD5 哈希比对失败: 本地=$localMd5, 远端=$expectedMd5');
      }
      hasVerifiedCryptoHash = true;
    }

    // 3. ETag 校验：严格区分强 ETag 与弱 ETag（W/"..."），且非十六进制串绝不误作密码学哈希
    final rawHeaderEtag = _getHeaderCaseInsensitive(responseHeaders, 'etag');
    final strongHeaderEtag = MediaFingerprintCache.cleanStrongEtag(
      rawHeaderEtag,
    );
    final strongRemoteEtag = MediaFingerprintCache.cleanStrongEtag(remoteEtag);

    if (strongHeaderEtag != null && strongRemoteEtag != null) {
      final bothHexHashes = (_sha256HexPattern.hasMatch(strongHeaderEtag) &&
              _sha256HexPattern.hasMatch(strongRemoteEtag)) ||
          (_md5HexPattern.hasMatch(strongHeaderEtag) &&
              _md5HexPattern.hasMatch(strongRemoteEtag));
      final etagMismatch = bothHexHashes
          ? strongHeaderEtag.toLowerCase() != strongRemoteEtag.toLowerCase()
          : strongHeaderEtag != strongRemoteEtag;
      if (etagMismatch) {
        throw Exception(
          '下载附件 ETag 比对不一致: 响应头=$strongHeaderEtag, 目录=$strongRemoteEtag',
        );
      }
    }

    final strongCandidate = strongHeaderEtag ?? strongRemoteEtag;
    if (!hasVerifiedCryptoHash && strongCandidate != null) {
      if (_sha256HexPattern.hasMatch(strongCandidate)) {
        final expectedSha256 = strongCandidate.toLowerCase();
        final localSha256 = await ensureSha256();
        if (localSha256 != expectedSha256) {
          throw Exception(
            '下载附件 SHA-256 哈希比对失败: 本地=$localSha256, 远端=$expectedSha256',
          );
        }
        hasVerifiedCryptoHash = true;
      } else if (_md5HexPattern.hasMatch(strongCandidate)) {
        final expectedMd5 = strongCandidate.toLowerCase();
        final localMd5 = await ensureMd5();
        if (localMd5 != expectedMd5) {
          throw Exception('下载附件 MD5 哈希比对失败: 本地=$localMd5, 远端=$expectedMd5');
        }
        hasVerifiedCryptoHash = true;
      }
    }

    if (!hasVerifiedCryptoHash) {
      final hasWeakEtag = MediaFingerprintCache.isWeakEtag(rawHeaderEtag) ||
          MediaFingerprintCache.isWeakEtag(remoteEtag);
      if (hasWeakEtag && strongCandidate == null) {
        logDebug('下载附件仅提供弱 ETag，无法进行内容哈希校验，已放行下载', source: 'WebDAVSyncService');
      } else if (strongCandidate != null) {
        logDebug('下载附件强 ETag 为非哈希标识，跳过哈希校验并放行下载', source: 'WebDAVSyncService');
      } else {
        logDebug(
          '下载附件未提供哈希校验头或强 ETag，跳过哈希校验并放行下载',
          source: 'WebDAVSyncService',
        );
      }
    }

    return (sha256: computedSha256, md5: computedMd5);
  }

  static Future<void> _verifyDownloadedFileHash(
    File file, {
    String? remoteEtag,
    Map<String, List<String>>? responseHeaders,
  }) async {
    await _verifyDownloadedFileHashWithDigests(
      file,
      remoteEtag: remoteEtag,
      responseHeaders: responseHeaders,
    );
  }

  static String _encodeMediaPath(String stdPath) =>
      stdPath.split('/').map(Uri.encodeComponent).join('/');

  static String? _mediaRelativePathFromHref(String href) {
    final trimmed = href.trim();
    if (trimmed.isEmpty) return null;

    // 剥离 query 参数和 fragment（注意不能用 Uri.tryParse(...).path，因为其会自动规范化并折叠 ../ 路径段，导致越界逃逸校验失效）
    var rawPath = trimmed.split('?').first.split('#').first;
    final schemeIndex = rawPath.indexOf('://');
    if (schemeIndex != -1) {
      final pathStart = rawPath.indexOf('/', schemeIndex + 3);
      rawPath = pathStart != -1 ? rawPath.substring(pathStart) : '';
    }
    if (rawPath.isEmpty) return null;

    String decodedPath;
    try {
      decodedPath = Uri.decodeComponent(rawPath);
    } catch (_) {
      decodedPath = Uri.decodeFull(rawPath);
    }

    // 循环检查或解码，防范多重编码（如 %252e%252e、%252f、%255c）绕过路径遍历检查
    var current = decodedPath;
    while (true) {
      if (_encodedTraversalPattern.hasMatch(current)) {
        return null;
      }
      try {
        final next = Uri.decodeComponent(current);
        if (next == current) break;
        current = next;
      } catch (_) {
        break;
      }
    }

    // 身份口径必须用单次解码值：_encodeMediaPath 会把文件名中的 '%' 编码为
    // '%25'（如本地 images/%41.png 上传为 images/%2541.png），单次解码才能
    // 还原出与本地一致的键；完全解码会得到 images/A.png，导致远端清单键与
    // 本地键对不上而重复上传/下载失败。穿越防护不依赖此选择：上面的循环在
    // 每次解码前都会检查残留的 %2e/%2f/%5c（含多重编码），有残留直接返回 null。
    final normalizedPath = decodedPath.replaceAll('\\', '/');
    if (normalizedPath.endsWith('/')) return null;

    final rawSegments = normalizedPath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();

    for (var i = 0; i < rawSegments.length - 1; i++) {
      if (rawSegments[i] == 'media' &&
          _mediaSubFolders.contains(rawSegments[i + 1])) {
        final relativeSegments = rawSegments.sublist(i + 1);
        final rawRelativePath = relativeSegments.join('/');
        if (rawRelativePath.contains('\u0000') ||
            p.posix.isAbsolute(rawRelativePath)) {
          return null;
        }

        final normalizedRelative = p.posix.normalize(rawRelativePath);
        if (normalizedRelative == '.' ||
            normalizedRelative == '..' ||
            normalizedRelative.startsWith('../')) {
          return null;
        }

        final expectedPrefix = '${rawSegments[i + 1]}/';
        if (!normalizedRelative.startsWith(expectedPrefix)) {
          return null;
        }

        return normalizedRelative;
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
    // 远端没报出大小（PROPFIND 未返回 getcontentlength）时无从比较，
    // 按「可能不一致」处理并重传，宁可多传一次也不留下漏同步的媒体文件。
    if (remoteSize == null) return true;

    return remoteSize != localSize;
  }

  bool _headersConflictWithUploadSnapshot(
    Map<String, List<String>>? headers, {
    int? expectedSize,
    required String expectedSha256,
    String? expectedMd5,
  }) {
    if (expectedSize != null) {
      final headerLenRaw =
          _getHeaderCaseInsensitive(headers, Headers.contentLengthHeader);
      final headerLen =
          headerLenRaw != null ? int.tryParse(headerLenRaw) : null;
      if (headerLen != null && headerLen != expectedSize) {
        return true;
      }
    }
    for (final headerName in const [
      'x-checksum-sha256',
      'x-amz-meta-sha256',
    ]) {
      final raw = _getHeaderCaseInsensitive(headers, headerName);
      if (raw == null) continue;
      final parsed = _parseExpectedSha256Hex(raw);
      if (parsed == null || parsed != expectedSha256.toLowerCase()) {
        return true;
      }
    }
    final rawMd5 = _getHeaderCaseInsensitive(headers, 'content-md5');
    if (rawMd5 != null && expectedMd5 != null) {
      final parsedMd5 = _parseExpectedMd5Hex(rawMd5);
      if (parsedMd5 == null || parsedMd5 != expectedMd5.toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  Future<String?> _fetchRemoteStrongEtagAfterPut(
    Dio dio,
    String uploadUrl, {
    required int expectedSize,
    required String expectedSha256,
    String? expectedMd5,
  }) async {
    try {
      final response = await _requestPropfind(
        dio,
        uploadUrl,
        depth: '0',
        validateStatus: (status) =>
            status == 200 || status == 207 || status == 404 || status == 405,
      );
      if (response.statusCode == 200 || response.statusCode == 207) {
        final body = response.data ?? '';
        final targetResponse = _findTargetSyncFilePropfindResponse(
          body,
          uploadUrl,
        );
        final xmlLen = targetResponse != null
            ? int.tryParse(
                _extractFirstXmlTagValue(targetResponse, 'getcontentlength') ??
                    '',
              )
            : null;
        if (xmlLen != null && xmlLen != expectedSize) {
          return null;
        }
        // PROPFIND 响应头中的 Content-Length 是 XML 响应体字节数而非远端文件大小（文件大小已由上方 getcontentlength 校验）
        if (_headersConflictWithUploadSnapshot(
          response.headers.map,
          expectedSha256: expectedSha256,
          expectedMd5: expectedMd5,
        )) {
          return null;
        }
        final headerEtag = MediaFingerprintCache.cleanStrongEtag(
          _getHeaderCaseInsensitive(response.headers.map, 'etag'),
        );
        final xmlEtag = targetResponse != null
            ? MediaFingerprintCache.cleanStrongEtag(
                _extractFirstXmlTagValue(targetResponse, 'getetag'),
              )
            : null;
        final resolved = xmlEtag ?? headerEtag;
        if (resolved != null) return resolved;
      }
    } catch (e) {
      logDebug('上传后 PROPFIND 读取远端强 ETag 失败: $e', source: 'WebDAVSyncService');
    }

    try {
      final headResponse = await dio.head<void>(
        uploadUrl,
        options: Options(
          validateStatus: (status) =>
              status != null && status >= 200 && status < 500,
        ),
      );
      if (headResponse.statusCode != null &&
          headResponse.statusCode! >= 200 &&
          headResponse.statusCode! < 300) {
        if (_headersConflictWithUploadSnapshot(
          headResponse.headers.map,
          expectedSize: expectedSize,
          expectedSha256: expectedSha256,
          expectedMd5: expectedMd5,
        )) {
          return null;
        }
        return MediaFingerprintCache.cleanStrongEtag(
          _getHeaderCaseInsensitive(headResponse.headers.map, 'etag'),
        );
      }
    } catch (e) {
      logDebug('上传后 HEAD 读取远端强 ETag 失败: $e', source: 'WebDAVSyncService');
    }

    return null;
  }

  static Future<bool> _shouldUploadMediaFileThreeTier({
    required String stdPath,
    required File localFile,
    required int localSize,
    required Map<String, RemoteMediaFileInfo> remoteMediaDetails,
    required MediaFingerprintCache fingerprintCache,
    DateTime? localLastModifiedOverride,
  }) async {
    // L1：远端缺失、缺少大小或大小不一致 -> 立即需要上传（0 次哈希计算）
    final remoteInfo = remoteMediaDetails[stdPath];
    if (remoteInfo == null ||
        remoteInfo.length == null ||
        remoteInfo.length != localSize) {
      return true;
    }

    // L2：仅当本地已有确认同步基线且 stat 未变时，才可依据修改时间快速跳过（0 次哈希计算）
    final localLastModifiedUtc =
        (localLastModifiedOverride ?? await localFile.lastModified()).toUtc();
    final remoteLastModifiedUtc = remoteInfo.lastModified?.toUtc();
    final cachedBefore = fingerprintCache.peek(stdPath);
    final localMtimeMs = localLastModifiedUtc.millisecondsSinceEpoch;
    final hasSyncedBaseline = cachedBefore != null &&
        cachedBefore.syncedSha256 != null &&
        cachedBefore.fileSize == localSize &&
        cachedBefore.lastModifiedEpochMs == localMtimeMs &&
        cachedBefore.sha256 == cachedBefore.syncedSha256;

    if (remoteLastModifiedUtc != null &&
        !localLastModifiedUtc.isAfter(
          remoteLastModifiedUtc.add(_remoteTimestampSkewTolerance),
        ) &&
        hasSyncedBaseline) {
      return false;
    }

    // L3：计算或复用本地指纹缓存，依据强 ETag 基线、已知摘要形式或安全降级策略裁决
    final cleanStrongEtag = MediaFingerprintCache.cleanStrongEtag(
      remoteInfo.etag,
    );

    if (cleanStrongEtag != null &&
        cachedBefore != null &&
        cachedBefore.fileSize == localSize &&
        cachedBefore.lastModifiedEpochMs == localMtimeMs &&
        cachedBefore.syncedRemoteEtag == cleanStrongEtag &&
        cachedBefore.syncedSha256 != null &&
        cachedBefore.syncedSha256 == cachedBefore.sha256) {
      return false;
    }

    final looksLikeSha256 =
        cleanStrongEtag != null && _sha256HexPattern.hasMatch(cleanStrongEtag);
    final looksLikeMd5 =
        cleanStrongEtag != null && _md5HexPattern.hasMatch(cleanStrongEtag);

    final entry = await fingerprintCache.getOrCompute(
      stdPath,
      localFile,
      knownSize: localSize,
      knownLastModified: localLastModifiedUtc,
      requireMd5:
          looksLikeMd5 && cachedBefore?.syncedRemoteEtag != cleanStrongEtag,
    );

    if (cleanStrongEtag != null) {
      if (entry.syncedRemoteEtag == cleanStrongEtag &&
          entry.syncedSha256 != null &&
          entry.syncedSha256 == entry.sha256) {
        return false;
      }

      if (looksLikeSha256 &&
          entry.sha256.toLowerCase() == cleanStrongEtag.toLowerCase()) {
        fingerprintCache.putEntry(
          stdPath,
          entry.copyWith(
            syncedSha256: entry.sha256,
            syncedRemoteEtag: cleanStrongEtag,
          ),
        );
        return false;
      }
      if (looksLikeMd5 &&
          entry.md5 != null &&
          entry.md5!.toLowerCase() == cleanStrongEtag.toLowerCase()) {
        fingerprintCache.putEntry(
          stdPath,
          entry.copyWith(
            syncedSha256: entry.sha256,
            syncedRemoteEtag: cleanStrongEtag,
          ),
        );
        return false;
      }

      return true;
    }

    // 安全降级：服务端缺少强 ETag 或仅返回弱 ETag (W/"...")
    if (entry.syncedSha256 != null) {
      return entry.sha256 != entry.syncedSha256;
    }
    if (remoteLastModifiedUtc != null &&
        localLastModifiedUtc.isAfter(
          remoteLastModifiedUtc.add(_remoteTimestampSkewTolerance),
        )) {
      return true;
    }

    // 对端无可用强 ETag 且修改时间缺失或处于 2 秒容差内，文件大小一致且尚无本地同步基线：
    // 将当前 SHA-256 写入同步基线，以便后续检测同尺寸原地修改；本次保守跳过避免全量重传。
    fingerprintCache.putEntry(
      stdPath,
      entry.copyWith(syncedSha256: entry.sha256),
    );
    return false;
  }

  static String? _mediaFolderFromRelativePath(String stdPath) {
    final segments = stdPath.split('/');
    final firstSegment = segments.isEmpty ? null : segments.first;
    return _mediaSubFolders.contains(firstSegment) ? firstSegment : null;
  }

  @visibleForTesting
  static String? prependConflictPrefixToDelta(String? deltaContent) {
    if (deltaContent == null || deltaContent.trim().isEmpty) {
      return deltaContent;
    }
    try {
      final decoded = json.decode(deltaContent);
      if (decoded is List) {
        final list = List<dynamic>.from(decoded);
        list.insert(0, {'insert': '[冲突备份] '});
        return json.encode(list);
      } else if (decoded is Map && decoded['ops'] is List) {
        final map = Map<String, dynamic>.from(decoded);
        final ops = List<dynamic>.from(map['ops'] as List);
        ops.insert(0, {'insert': '[冲突备份] '});
        map['ops'] = ops;
        return json.encode(map);
      } else {
        logWarning('冲突笔记 Delta 结构不支持加前缀，返回原内容', source: 'WebDAVSyncService');
      }
    } catch (e, stack) {
      logError(
        '冲突笔记 Delta 内容加前缀失败: ${e.runtimeType}',
        error: e.runtimeType.toString(),
        stackTrace: stack,
        source: 'WebDAVSyncService',
      );
    }
    return deltaContent;
  }

  @visibleForTesting
  static Map<String, int?> extractRemoteMediaFilesForTesting(String xmlData) {
    return _extractRemoteMediaFiles(xmlData);
  }

  @visibleForTesting
  static Map<String, RemoteMediaFileInfo> extractRemoteMediaDetailsForTesting(
    String xmlData,
  ) {
    return _extractRemoteMediaDetails(xmlData);
  }

  @visibleForTesting
  static DateTime? parseRemoteHttpDateForTesting(String? raw) {
    return _parseRemoteHttpDate(raw);
  }

  @visibleForTesting
  static Map<String, String?> extractRemoteMediaEtagsForTesting(
    String xmlData,
  ) {
    final details = _extractRemoteMediaDetails(xmlData);
    return details.map((key, value) => MapEntry(key, value.etag));
  }

  @visibleForTesting
  static String? mediaRelativePathFromHrefForTesting(String href) {
    return _mediaRelativePathFromHref(href);
  }

  @visibleForTesting
  static String encodeMediaPathForTesting(String stdPath) {
    return _encodeMediaPath(stdPath);
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
  static Future<bool> shouldUploadMediaFileWithCacheForTesting({
    required String stdPath,
    required File localFile,
    required int localSize,
    required Map<String, RemoteMediaFileInfo> remoteMediaDetails,
    required MediaFingerprintCache fingerprintCache,
    DateTime? localLastModifiedOverride,
  }) {
    return _shouldUploadMediaFileThreeTier(
      stdPath: stdPath,
      localFile: localFile,
      localSize: localSize,
      remoteMediaDetails: remoteMediaDetails,
      fingerprintCache: fingerprintCache,
      localLastModifiedOverride: localLastModifiedOverride,
    );
  }

  @visibleForTesting
  static Future<void> verifyDownloadedFileHashForTesting(
    File file, {
    String? remoteEtag,
    Map<String, List<String>>? responseHeaders,
  }) {
    return _verifyDownloadedFileHash(
      file,
      remoteEtag: remoteEtag,
      responseHeaders: responseHeaders,
    );
  }

  @visibleForTesting
  static String? mediaFolderFromRelativePathForTesting(String stdPath) {
    return _mediaFolderFromRelativePath(stdPath);
  }

  @visibleForTesting
  void setUrlForTesting(String url) {
    _url = url.endsWith('/') ? url : '$url/';
  }

  @visibleForTesting
  void setUsernameForTesting(String username) {
    _username = username.trim();
  }

  @visibleForTesting
  Future<int> syncMediaFilesForTesting(Dio dio) => _syncMediaFiles(dio);

  @visibleForTesting
  Future<bool> downloadMediaFileForTesting(
    Dio dio, {
    required String stdPath,
    required Directory appDir,
    RemoteMediaFileInfo? remoteInfo,
    MediaFingerprintCache? fingerprintCache,
  }) {
    return _downloadAndVerifyMediaFile(
      dio,
      stdPath: stdPath,
      appDir: appDir,
      remoteInfo: remoteInfo,
      fingerprintCache: fingerprintCache,
    );
  }

  static List<ChatMessageShardDescriptor> _extractRemoteChatShards(
    Map<String, dynamic>? remoteData,
  ) {
    if (remoteData == null) return const <ChatMessageShardDescriptor>[];
    final rawChat = remoteData['chat'];
    if (rawChat is! Map) return const <ChatMessageShardDescriptor>[];
    final chatMap = rawChat is Map<String, dynamic>
        ? rawChat
        : rawChat.map((k, v) => MapEntry(k.toString(), v));
    return parseChatMessageShardDescriptors(chatMap);
  }

  Future<List<ChatMessageShardDescriptor>> _buildLocalChatShardArchives(
    Directory workDir, {
    required int maxShardJsonBytes,
  }) async {
    final assistantSync = _assistantDataSync;
    if (assistantSync == null) return const <ChatMessageShardDescriptor>[];
    final rawShardFiles = await assistantSync.exportChatMessageShardJsonFiles(
      workDir,
      maxShardJsonBytes: maxShardJsonBytes,
    );
    if (rawShardFiles.isEmpty) return const <ChatMessageShardDescriptor>[];

    final descriptors = <ChatMessageShardDescriptor>[];
    for (var i = 0; i < rawShardFiles.length; i++) {
      final rawFile = rawShardFiles[i];
      final tempShardZipPath = p.join(workDir.path, 'chat_shard_tmp_$i.zip');
      try {
        await packSyncZip(
          rawFile.path,
          tempShardZipPath,
          deterministic: true,
        );
      } finally {
        if (await rawFile.exists()) {
          await rawFile.delete();
        }
      }
      final tempZipFile = File(tempShardZipPath);
      final digest = await sha256.bind(tempZipFile.openRead()).first;
      final shaHex = digest.toString().toLowerCase();
      final finalName = 'shard_$shaHex.zip';
      final finalZipPath = p.join(workDir.path, finalName);
      if (await File(finalZipPath).exists()) {
        await tempZipFile.delete();
      } else {
        await tempZipFile.rename(finalZipPath);
      }
      descriptors.add(
        ChatMessageShardDescriptor(
          file: finalName,
          sha256: shaHex,
          localPath: finalZipPath,
        ),
      );
    }
    return descriptors;
  }

  Future<String> _downloadAndVerifyChatShard(
    Dio dio, {
    required ChatMessageShardDescriptor shard,
    required Directory workDir,
    required int index,
  }) async {
    if (!_remoteChatShardFileNamePattern.hasMatch(shard.file)) {
      throw StateError('非法的云端对话分片文件名');
    }
    final shardUrl = '${_url}thoughtecho/chat_shards/${shard.file}';
    final cancelToken = CancelToken();
    final res = await dio.get<List<int>>(
      shardUrl,
      cancelToken: cancelToken,
      options: Options(responseType: ResponseType.bytes),
      onReceiveProgress: (received, total) {
        if (received > _maxRemoteSyncBytes || total > _maxRemoteSyncBytes) {
          cancelToken.cancel('WebDAV chat shard exceeds 32 MiB limit');
        }
      },
    );
    if (res.statusCode != 200 || res.data == null) {
      throw StateError('下载云端对话分片失败 (${res.statusCode})');
    }
    final bytes = res.data!;
    if (bytes.length > _maxRemoteSyncBytes) {
      throw _RemoteSyncSizeLimitException();
    }
    final expectedHeaderLen = _contentLengthFromHeaders(res.headers);
    if (expectedHeaderLen != null && expectedHeaderLen != bytes.length) {
      throw StateError('云端对话分片下载不完整');
    }
    final actualSha = sha256.convert(bytes).toString().toLowerCase();
    if (actualSha != shard.sha256) {
      throw StateError('云端对话分片 SHA-256 校验不一致');
    }
    final Uint8List verifiedJsonBytes;
    try {
      verifiedJsonBytes = await compute(
        _decodeAndValidateRemoteChatShardZipToBytes,
        bytes,
      );
    } on _CorruptedRemoteSyncFileException catch (e) {
      // 分片文件损坏或下载截断时直接中止本轮同步，不触发主同步包归档覆盖。
      throw StateError('云端对话分片损坏 (${e.reason})');
    }
    final localJsonPath = p.join(
      workDir.path,
      'verified_remote_chat_shard_$index.json',
    );
    await File(localJsonPath).writeAsBytes(verifiedJsonBytes, flush: true);
    return localJsonPath;
  }

  Future<
      ({
        bool listedSuccessfully,
        Map<String, _RemoteChatShardInfo> files,
        DateTime? serverTimeUtc,
      })> _listRemoteChatShardFiles(
    Dio dio,
    String chatShardsDirUrl,
  ) async {
    final result = <String, _RemoteChatShardInfo>{};
    try {
      final response = await _requestPropfind(
        dio,
        chatShardsDirUrl,
        depth: '1',
        validateStatus: (status) =>
            status == 200 || status == 207 || status == 404,
      );
      final serverTimeUtc = _parseRemoteHttpDate(
        response.headers.value('date'),
      )?.toUtc();
      if (response.statusCode == 404) {
        return (
          listedSuccessfully: true,
          files: result,
          serverTimeUtc: serverTimeUtc,
        );
      }
      if (response.statusCode != 200 && response.statusCode != 207) {
        return (
          listedSuccessfully: false,
          files: result,
          serverTimeUtc: serverTimeUtc,
        );
      }
      final body = response.data ?? '';
      for (final block in _parsePropfindResponses(body)) {
        if (block.descendantElements.any(
          (element) => element.name.local.toLowerCase() == 'collection',
        )) {
          continue;
        }
        if (!_propfindResponseHasSuccessStatus(block)) continue;
        final href = _extractFirstXmlTagValue(block, 'href');
        if (href == null) continue;
        final normalizedPath = _normalizedUriPath(href);
        if (normalizedPath == null) continue;
        final fileName = p.posix.basename(normalizedPath);
        if (!_remoteChatShardFileNamePattern.hasMatch(fileName)) continue;
        final length = int.tryParse(
          _extractFirstXmlTagValue(block, 'getcontentlength') ?? '',
        );
        final lastModified = _parseRemoteHttpDate(
          _extractFirstXmlTagValue(block, 'getlastmodified'),
        );
        result[fileName] = _RemoteChatShardInfo(
          length: length,
          lastModified: lastModified,
        );
      }
      return (
        listedSuccessfully: true,
        files: result,
        serverTimeUtc: serverTimeUtc,
      );
    } catch (e) {
      logDebug('列举云端对话分片目录失败: $e', source: 'WebDAVSyncService');
      return (listedSuccessfully: false, files: result, serverTimeUtc: null);
    }
  }

  /// 清理已退役且超过跨端保护宽限期的孤儿分片，返回是否仍余待后续轮次清理的候选分片。
  ///
  /// 安全门禁：
  /// 1. 始终在主同步包发布后重新列举 `chat_shards/` 目录，绝不复用上传前的旧目录快照；
  /// 2. 仅依据 WebDAV 服务端自身 HTTP `Date` 响应头时钟与分片 `getlastmodified` 计算年龄，
  ///    绝不回退使用可能存在大幅偏差的本机时钟；
  /// 3. 真正发起 `DELETE` 前再次复核云端 `thoughtecho_sync.zip` 的指纹（ETag / 大小）仍与本轮刚发布的快照一致，
  ///    一旦检测到另一台客户端在此期间已发布新主包，立即中止删除，由新主包持有方接管分片生命周期。
  Future<bool> _cleanupStaleRemoteChatShards(
    Dio dio,
    String chatShardsDirUrl, {
    required String remoteSyncZipUrl,
    required String? expectedMainEtag,
    required int expectedMainContentLength,
    required String expectedMainSha256,
    required String expectedMainMd5,
    required Set<String> activeShardFiles,
    required Set<String> protectedShardFiles,
    required Duration staleMinAge,
  }) async {
    try {
      final listing = await _listRemoteChatShardFiles(dio, chatShardsDirUrl);
      if (!listing.listedSuccessfully) {
        return true;
      }
      final serverNowUtc = listing.serverTimeUtc;
      var hasUncleanedInactiveShard = false;
      final staleCandidates = <String>[];
      for (final entry in listing.files.entries) {
        final fileName = entry.key;
        if (activeShardFiles.contains(fileName) ||
            !_remoteChatShardFileNamePattern.hasMatch(fileName)) {
          continue;
        }
        final modifiedUtc = entry.value.lastModified?.toUtc();
        if (protectedShardFiles.contains(fileName)) {
          if (modifiedUtc != null) {
            hasUncleanedInactiveShard = true;
          }
          continue;
        }
        if (modifiedUtc == null || serverNowUtc == null) {
          continue;
        }
        if (serverNowUtc.isBefore(modifiedUtc) ||
            serverNowUtc.difference(modifiedUtc) < staleMinAge) {
          hasUncleanedInactiveShard = true;
          continue;
        }
        staleCandidates.add(fileName);
      }

      if (staleCandidates.isEmpty) {
        return hasUncleanedInactiveShard;
      }

      // 执行物理删除前复核云端主包未被其他设备并发更新覆盖：
      // 仅信任本轮 PUT 直接返回的 ETag 与本地上传包自身的精确字节长度/哈希，绝不在 PUT 后用额外 PROPFIND 补采指纹。
      final latestMainMeta = await _getRemoteSyncFileMetadata(
        dio,
        remoteSyncZipUrl,
      );
      if (!latestMainMeta.exists) {
        return true;
      }
      if (expectedMainEtag != null && expectedMainEtag.isNotEmpty) {
        if (latestMainMeta.etag == null ||
            latestMainMeta.etag != expectedMainEtag) {
          // 云端主包已被其他设备更新（或无法校验 ETag 一致性），立即放弃本轮删除。
          return false;
        }
        if (latestMainMeta.contentLength != null &&
            latestMainMeta.contentLength != expectedMainContentLength) {
          return false;
        }
      } else {
        if (latestMainMeta.contentLength == null) {
          // PUT 未返回 ETag 且 PROPFIND 亦未提供字节长度时，无法确认主包归属，延后清理。
          return true;
        }
        if (latestMainMeta.contentLength != expectedMainContentLength) {
          return false;
        }
        final strongLatestEtag = MediaFingerprintCache.cleanStrongEtag(
          latestMainMeta.etag,
        );
        if (strongLatestEtag != null) {
          if (_sha256HexPattern.hasMatch(strongLatestEtag) &&
              strongLatestEtag.toLowerCase() != expectedMainSha256) {
            return false;
          }
          if (_md5HexPattern.hasMatch(strongLatestEtag) &&
              strongLatestEtag.toLowerCase() != expectedMainMd5) {
            return false;
          }
        }
      }

      for (final fileName in staleCandidates) {
        try {
          final res = await dio.delete(
            '$chatShardsDirUrl$fileName',
            options: Options(
              validateStatus: (status) => status != null && status < 500,
            ),
          );
          final code = res.statusCode ?? 0;
          if (code >= 400 && code != 404) {
            hasUncleanedInactiveShard = true;
          }
        } catch (e) {
          hasUncleanedInactiveShard = true;
          logDebug('清理过期云端对话分片跳过 ($fileName): $e', source: 'WebDAVSyncService');
        }
      }
      return hasUncleanedInactiveShard;
    } catch (e) {
      logDebug('清理云端旧对话分片跳过: $e', source: 'WebDAVSyncService');
      return true;
    }
  }

  /// 流式写入本地同步数据到临时 JSON 文件
  ///
  /// 格式与 [DatabaseBackupService.exportDataAsMap] 兼容：
  /// `{ metadata, categories, quotes: [...], tombstones }`
  /// 笔记按每页 50 条分页查询，避免全表入内存。
  Future<void> _writeLocalDataToTempJson(
    Database db,
    String filePath, {
    Map<String, dynamic>? preservedRemoteAgentMemory,
    bool forceSkipLocalMemoryExport = false,
    List<ChatMessageShardDescriptor>? chatMessageShards,
  }) async {
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
          final tagRows = await txn.query(
            'quote_tags',
            columns: ['quote_id', 'tag_id'],
            where: 'quote_id IN ($placeholders)',
            whereArgs: ids,
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

        // tombstones — 三列短字符串，数量有界（顶层 `}` 延后到对话/记忆追加后闭合）
        final tombstones = await txn.query('quote_tombstones');
        sink.write('"tombstones":${json.encode(tombstones)}');
      });

      await _assistantDataSync?.writeSections(
        sink,
        preservedRemoteAgentMemory: preservedRemoteAgentMemory,
        forceSkipLocalMemoryExport: forceSkipLocalMemoryExport,
        chatMessageShards: chatMessageShards,
      );
      sink.write('}');
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
