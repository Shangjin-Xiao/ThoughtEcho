import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
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

/// WebDAV 同步状态枚举
enum WebDAVSyncStatus { idle, syncing, success, failed }

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
  bool get syncOnLaunch => _syncOnLaunch;
  bool get syncOnChange => _syncOnChange;
  bool get syncOnCellular => _syncOnCellular;
  bool get syncNotesOnlyOnCellular => _syncNotesOnlyOnCellular;

  // 定时器用于防抖
  Timer? _debounceTimer;

  // 冲突分类固定ID
  static const String conflictCategoryId = 'system_sync_conflicts_category';

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

    if (isSyncing) {
      logDebug('当前正在同步中，将此次同步请求加入排队队列');
      _hasPendingSync = true;
      return;
    }

    final password = await getPassword();
    if (_url.isEmpty ||
        _username.isEmpty ||
        password == null ||
        password.isEmpty) {
      logDebug('WebDAV 同步未完全配置，跳过同步');
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
      bool hasRemote = false;
      try {
        final checkRes = await dio.request(
          remoteSyncZipUrl,
          options: Options(
            method: 'PROPFIND',
            headers: {'Depth': '0'},
            validateStatus: (status) => status == 200 || status == 207,
          ),
        );
        if (checkRes.statusCode == 200 || checkRes.statusCode == 207) {
          hasRemote = true;
        }
      } catch (_) {
        // 云端文件不存在
      }

      if (hasRemote) {
        logDebug('发现云端备份文件，开始下载...');
        final downloadRes = await dio.get<List<int>>(
          remoteSyncZipUrl,
          options: Options(responseType: ResponseType.bytes),
        );

        if (downloadRes.statusCode == 200 && downloadRes.data != null) {
          // 解压 ZIP 提取 JSON
          final archive = ZipDecoder().decodeBytes(downloadRes.data!);
          final dataJsonFile = archive.findFile('backup_data.json');
          if (dataJsonFile != null) {
            final jsonStr = utf8.decode(dataJsonFile.content as List<int>);
            remoteData = json.decode(jsonStr) as Map<String, dynamic>;
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
        await dbService.importDataWithLWWMerge(
          remoteData,
          sourceDevice: 'WebDAV_Cloud',
        );
        dbService.refreshQuotes(); // 刷新 UI
      }

      // 5. 增量比对并同步大媒体附件 (Images, Videos, Audios)
      if (skipMedia) {
        logDebug('数据流量下跳过大媒体文件同步');
      } else {
        logDebug('开始同步本地与云端媒体文件...');
        await _syncMediaFiles(dio);
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

        // ZipFileEncoder 从磁盘流式打包，不全量入内存
        final encoder = ZipFileEncoder();
        encoder.create(tempZipPath);
        encoder.addFile(File(tempJsonPath), 'backup_data.json');
        encoder.closeSync();

        // 从文件流上传，无需把 ZIP 全部读入内存
        final zipFile = File(tempZipPath);
        await dio.put(
          remoteSyncZipUrl,
          data: zipFile.openRead(),
          options: Options(
            headers: {
              'Content-Type': 'application/zip',
              'Content-Length': await zipFile.length(),
            },
          ),
        );
      } finally {
        // 清理临时文件
        for (final path in [tempJsonPath, tempZipPath]) {
          final f = File(path);
          if (await f.exists()) await f.delete();
        }
      }

      // 7. 更新同步成功状态
      _lastSyncTime = DateTime.now().toUtc().toIso8601String();
      await _mmkv.setString('webdav_last_sync_time', _lastSyncTime);
      _syncStatus = WebDAVSyncStatus.success;
      _lastSyncError = ''; // 成功时清除上次错误
      await _mmkv.setString('webdav_sync_status', 'success');
      await _mmkv.setString('webdav_last_sync_error', '');

      logInfo('WebDAV 同步成功完成。冲突数: $_lastConflictCount');
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
      notifyListeners();
      if (_hasPendingSync) {
        _hasPendingSync = false;
        logDebug('检测到排队中的同步任务，开始执行追加同步...');
        Future.microtask(() => triggerSync(isBackground: isBackground));
      }
    }
  }

  /// 将异常转换为对用户安全、友好的错误摘要（不含 URL、密码等敏感信息）
  String _sanitizeSyncError(Object e) {
    final raw = e.toString();
    // HTTP 状态码识别
    final statusMatch = RegExp(r'status[Cc]ode[:\s]+(\d+)').firstMatch(raw);
    if (statusMatch != null) {
      final code = int.tryParse(statusMatch.group(1) ?? '');
      if (code == 401 || code == 403) return '认证失败，请检查用户名和密码';
      if (code == 404) return '服务器路径不存在，请检查地址配置';
      if (code == 507) return '服务器存储空间不足';
      if (code != null && code >= 500) return '服务器内部错误 ($code)';
      if (code != null) return 'HTTP 错误 ($code)';
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
    // 截取前 80 个字符，去掉可能含 URL 的部分
    final safe = raw.replaceAll(RegExp(r'https?://\S+'), '[服务器地址]');
    return safe.length > 80 ? '${safe.substring(0, 80)}…' : safe;
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

    final lastSync = DateTime.parse(lastSyncTimeStr).toUtc();

    // 查询自上次同步后，本地被修改过且没有被软删除的笔记
    final localQuotes = await db.query(
      'quotes',
      where: 'last_modified > ? AND is_deleted = 0',
      whereArgs: [lastSyncTimeStr],
    );

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

      final remoteModTime = DateTime.parse(remoteModStr).toUtc();
      final localModTime = DateTime.parse(
        localQuote['last_modified'] as String,
      ).toUtc();

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

    for (final quote in conflictingQuotes) {
      conflictsCloned++;
      await _cloneConflictQuote(
        db,
        quote,
        tagsMap[quote['id'] as String] ?? [],
      );
    }

    return conflictsCloned;
  }

  /// 克隆冲突的笔记，并将分类设为“同步冲突”
  Future<void> _cloneConflictQuote(
    Database db,
    Map<String, dynamic> localQuote,
    List<Map<String, Object?>> tags,
  ) async {
    try {
      // 1. 确保冲突分类在本地存在
      final catCheck = await db.query(
        'categories',
        where: 'id = ?',
        whereArgs: [conflictCategoryId],
      );

      if (catCheck.isEmpty) {
        await db.insert('categories', {
          'id': conflictCategoryId,
          'name': '同步冲突',
          'is_default': 0,
          'icon_name': 'warning_amber_rounded',
          'last_modified': DateTime.now().toUtc().toIso8601String(),
        });
      }

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
          if (delta is List && delta.isNotEmpty) {
            final first = delta.first;
            if (first is Map &&
                first.containsKey('insert') &&
                first['insert'] is String) {
              first['insert'] = '[冲突备份] ${first['insert']}';
              clonedQuote['delta_content'] = json.encode(delta);
            }
          }
        } catch (_) {}
      }

      await db.insert('quotes', clonedQuote);

      // 3. 复制对应的标签关联关系
      if (tags.isNotEmpty) {
        final batch = db.batch();
        for (final tag in tags) {
          batch.insert('quote_tags', {
            'quote_id': clonedId,
            'tag_id': tag['tag_id'],
          });
        }
        await batch.commit(noResult: true);
      }

      logDebug('已成功为冲突的笔记创建冲突隔离备份: $clonedId');
    } catch (e) {
      logDebug('克隆冲突笔记失败: $e');
    }
  }

  /// 增量比对并同步本地与云端媒体文件夹 (Images, Videos, Audios)
  Future<void> _syncMediaFiles(Dio dio) async {
    final appDir = await getApplicationDocumentsDirectory();
    final mediaRoot = Directory(p.join(appDir.path, 'media'));
    if (!await mediaRoot.exists()) return;

    // 1. 扫描本地所有存在的媒体文件
    final List<File> localFiles =
        mediaRoot.listSync(recursive: true).whereType<File>().toList();

    final Map<String, File> localMediaMap = {};
    for (final f in localFiles) {
      final relPath = p.relative(f.path, from: mediaRoot.path);
      // 标准化路径斜杠，防止 Windows 系统的反斜杠导致 WebDAV 匹配失败
      final stdPath = relPath.replaceAll('\\', '/');
      localMediaMap[stdPath] = f;
    }

    final subFolders = ['images', 'videos', 'audios'];
    final Set<String> remoteFilePaths = {};

    // 2. 并行扫描云端所有媒体子目录的文件列表，减少网络请求等待时间并防限流
    await Future.wait(subFolders.map((folder) async {
      final folderUrl = '${_url}thoughtecho/media/$folder/';
      try {
        final response = await dio.request(
          folderUrl,
          options: Options(
            method: 'PROPFIND',
            headers: {'Depth': '1'},
            validateStatus: (status) => status == 207 || status == 200,
          ),
        );

        if ((response.statusCode == 207 || response.statusCode == 200) &&
            response.data != null) {
          final dynamic rawData = response.data;
          final String xmlData = rawData is List<int>
              ? utf8.decode(rawData, allowMalformed: true)
              : rawData.toString();
          // 使用 namespace-agnostic 正则提取云端文件的相对路径 URL 尾部
          final hrefRegExp = RegExp(
            r'<[a-zA-Z0-9:]*href>([\s\S]*?)<\/[a-zA-Z0-9:]*href>',
          );
          final matches = hrefRegExp.allMatches(xmlData);

          for (final m in matches) {
            String href = Uri.decodeFull(m.group(1)?.trim() ?? '');
            if (href.endsWith('/') ||
                href.endsWith('/media') ||
                href.endsWith('/media/')) {
              continue; // 过滤目录自身
            }

            // 截取 media/ 后面的部分，如 images/123.png
            final mediaIdx = href.indexOf('media/');
            if (mediaIdx != -1) {
              final relPath = href.substring(mediaIdx + 6);
              remoteFilePaths.add(relPath);
            }
          }
        }
      } catch (e) {
        logDebug('获取云端媒体目录 ($folder) 列表失败: $e');
      }
    }));

    // 3. 上传本地独有文件到云端
    for (final entry in localMediaMap.entries) {
      final stdPath = entry.key;
      final file = entry.value;

      if (!remoteFilePaths.contains(stdPath)) {
        logDebug('上传本地附件到云端: $stdPath');
        final uploadUrl = '${_url}thoughtecho/media/$stdPath';
        try {
          final fileLen = await file.length();
          await dio.put(
            uploadUrl,
            data: file.openRead(),
            options: Options(headers: {'Content-Length': fileLen}),
          );
        } catch (e) {
          logDebug('上传附件失败 ($stdPath): $e');
        }
      }
    }

    // 4. 从云端同步本地缺失附件，或清理云端已废弃的孤儿附件（解决“无限复活”Bug）
    for (final stdPath in remoteFilePaths) {
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

          try {
            // 确保父目录存在
            await localTargetFile.parent.create(recursive: true);
            await dio.download(downloadUrl, localTargetFile.path);
          } catch (e) {
            logDebug('下载附件失败 ($stdPath): $e');
          }
        } else {
          // 数据库中已经没有任何笔记引用此文件（已被用户删除，且本地已被孤儿文件机制清理）
          // 此时绝不下载，并且主动在 WebDAV 上删除该文件以防越攒越多，彻底清理云端存储
          logDebug('从云端清理已无任何数据库引用的废弃附件: $stdPath');
          final deleteUrl = '${_url}thoughtecho/media/$stdPath';
          try {
            await dio.request(
              deleteUrl,
              options: Options(
                method: 'DELETE',
                validateStatus: (status) =>
                    status == 200 || status == 204 || status == 404,
              ),
            );
          } catch (e) {
            logDebug('从云端删除废弃附件失败 ($stdPath): $e');
          }
        }
      }
    }
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
      final dbVersion = await db.getVersion();
      sink.write(
        '{"metadata":${json.encode({
              'app': '心迹',
              'version': dbVersion,
              'exportTime': DateTime.now().toIso8601String()
            })},',
      );

      // categories — 数量有界，直接写入
      final categories = await db.query('categories');
      sink.write('"categories":${json.encode(categories)},');

      // quotes — 分页写入，每页批量查询对应 tag_ids（避免 N+1）
      sink.write('"quotes":[');
      const pageSize = 50;
      int offset = 0;
      bool isFirstQuote = true;
      while (true) {
        final page = await db.rawQuery(
          'SELECT * FROM quotes ORDER BY date DESC LIMIT ? OFFSET ?',
          [pageSize, offset],
        );
        if (page.isEmpty) break;

        // 批量查 tag 关联，避免逐条查询
        final ids = page.map((q) => q['id'] as String).toList();
        final placeholders = List.filled(ids.length, '?').join(',');
        final tagRows = await db.rawQuery(
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

        await sink.flush();
        offset += page.length;
        if (page.length < pageSize) break;
        // 让出 CPU，避免同步期间 UI 卡顿
        await Future.delayed(const Duration(milliseconds: 1));
      }
      sink.write('],');

      // tombstones — 三列短字符串，数量有界
      final tombstones = await db.query('quote_tombstones');
      sink.write('"tombstones":${json.encode(tombstones)}}');

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
