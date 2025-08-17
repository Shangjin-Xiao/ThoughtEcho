import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:thoughtecho/services/backup_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/ai_analysis_database_service.dart';
import 'package:thoughtecho/services/thoughtecho_discovery_service.dart';
import 'package:thoughtecho/services/localsend/localsend_server.dart';
import 'package:thoughtecho/services/localsend/localsend_send_provider.dart';
import 'package:thoughtecho/services/localsend/models/device.dart';
import 'package:thoughtecho/services/localsend/constants.dart';
import 'package:thoughtecho/models/merge_report.dart';
import 'package:http/http.dart' as http;
import 'device_identity_manager.dart';
import 'package:thoughtecho/utils/app_logger.dart';

/// 同步状态枚举
enum SyncStatus {
  idle, // 空闲
  packaging, // 打包中
  sending, // 发送中
  receiving, // 接收中
  merging, // 合并中
  completed, // 完成
  failed, // 失败
}

/// 笔记同步服务 - 基于LocalSend的P2P同步功能
///
/// 集成LocalSend的核心功能，实现设备间的笔记数据同步
/// 使用备份还原机制进行数据传输和合并
class NoteSyncService extends ChangeNotifier {
  final BackupService _backupService;
  final DatabaseService _databaseService;
  final SettingsService _settingsService;
  // final AIAnalysisDatabaseService _aiAnalysisDbService;

  // LocalSend核心组件
  ThoughtEchoDiscoveryService? _discoveryService;
  LocalSendServer? _localSendServer;

  // LocalSend发送组件 (恢复使用优质的LocalSend代码)
  LocalSendProvider? _localSendProvider;

  // 同步状态管理
  SyncStatus _syncStatus = SyncStatus.idle;
  String _syncStatusMessage = '';
  double _syncProgress = 0.0;
  // UI节流：避免高频notify导致数字跳动与重建闪烁
  DateTime _lastUiNotify = DateTime.fromMillisecondsSinceEpoch(0);
  // 调整：进一步缩短 UI 通知节流时间以实现更实时的进度更新（用户期望更“实时”）
  static const int _minUiNotifyIntervalMs = 50; // ~20fps
  MergeReport? _lastMergeReport; // 新增：最近一次合并报告
  String? _currentReceiveSessionId; // 当前接收会话ID
  DateTime? _receiveStartTime;
  String? _receiveSenderAlias;
  int? _pendingReceiveTotalBytes; // 等待审批大小
  bool _awaitingUserApproval = false; // 是否处于接收审批阶段

  bool get awaitingUserApproval => _awaitingUserApproval;
  int? get pendingReceiveTotalBytes => _pendingReceiveTotalBytes;

  DateTime? _sendStartTime;
  String? _currentSendSessionId; // 当前发送会话ID

  // 状态访问器
  SyncStatus get syncStatus => _syncStatus;
  String get syncStatusMessage => _syncStatusMessage;
  double get syncProgress => _syncProgress;
  MergeReport? get lastMergeReport => _lastMergeReport;
  String? get receiveSenderAlias => _receiveSenderAlias;

  NoteSyncService({
    required BackupService backupService,
    required DatabaseService databaseService,
    required SettingsService settingsService,
    required AIAnalysisDatabaseService aiAnalysisDbService,
  })  : _backupService = backupService,
        _databaseService = databaseService,
        _settingsService = settingsService {
    debugPrint('NoteSyncService 构造函数完成');
  }
  bool get skipSyncConfirmation => _settingsService.syncSkipConfirm;

  /// 初始化同步服务
  Future<void> initialize() async {
    // 在打开同步页面时才启动服务器
    debugPrint(
        'NoteSyncService initialized, server will start when sync page opens');
  }

  /// 启动服务器（在打开同步页面时调用）
  Future<void> startServer() async {
    // 检查是否已经启动
    if (_localSendServer?.isRunning == true) {
      debugPrint('同步服务器已经启动，跳过重复启动');
      return;
    }

    // Check if we're running on web platform
    if (kIsWeb) {
      debugPrint('Note sync servers not supported on web platform');
      return;
    }

    try {
      debugPrint('开始初始化同步服务组件...');

      // 确保先清理之前的资源
      await stopServer();

      // 安全地初始化服务组件
      _discoveryService = ThoughtEchoDiscoveryService();
      if (_discoveryService == null) {
        throw Exception('ThoughtEchoDiscoveryService创建失败');
      }

      _localSendServer = LocalSendServer();
      if (_localSendServer == null) {
        throw Exception('LocalSendServer创建失败');
      }

      _localSendProvider = LocalSendProvider();
      if (_localSendProvider == null) {
        throw Exception('LocalSendProvider创建失败');
      }

      debugPrint('所有服务组件创建成功，开始启动服务器...');

      // 启动LocalSend服务器
      // ensure fingerprint ready before server start
      await DeviceIdentityManager.I.getFingerprint();
      await _localSendServer!.start(
        port: defaultPort, // 明确指定端口
        onFileReceived: (filePath) async {
          // 文件接收完毕后开始处理合并
          await processSyncPackage(filePath);
        },
        onReceiveProgress: (received, total) {
          // 接收端进度：0-100% 映射到 receiving 状态的 0-0.9，剩余0.9-1.0给合并阶段
          if (total > 0) {
            final ratio = received / total;
            // 仅当未进入合并阶段才更新为接收状态，避免覆盖后续合并状态
            if (_syncStatus == SyncStatus.idle ||
                _syncStatus == SyncStatus.receiving) {
              String extra = '';
              if (_receiveStartTime != null) {
                final elapsed = DateTime.now()
                        .difference(_receiveStartTime!)
                        .inMilliseconds /
                    1000.0;
                if (elapsed > 0.2) {
                  final speed = received / 1024 / 1024 / elapsed; // MB/s
                  final remaining = total - received;
                  final etaSec =
                      speed > 0 ? remaining / 1024 / 1024 / speed : 0;
                  extra =
                      ' | ${speed.toStringAsFixed(2)}MB/s | 剩余${etaSec < 1 ? '<1' : etaSec.toStringAsFixed(0)}s';
                }
              }
              _updateSyncStatus(
                SyncStatus.receiving,
                '正在接收${_receiveSenderAlias != null ? '（来自$_receiveSenderAlias）' : ''} ${(received / 1024 / 1024).toStringAsFixed(1)}MB / ${(total / 1024 / 1024).toStringAsFixed(1)}MB$extra',
                0.05 + ratio * 0.75, // 留出空间给合并
              );
            }
          }
        },
    onReceiveSessionCreated: (sid, totalBytes, alias) {
          _currentReceiveSessionId = sid;
          _receiveSenderAlias = alias;
          _receiveStartTime = DateTime.now();
          if (_syncStatus == SyncStatus.idle) {
      // 审批前不展示总大小，简化文案
      _updateSyncStatus(
        SyncStatus.receiving,
        '等待 $alias 发送数据...',
        0.02);
          }
        },
        onApprovalNeeded: (sid, totalBytes, alias) async {
          // 进入审批阶段，暂停进度显示（保持接收状态初始progress）
          _awaitingUserApproval = true;
          _pendingReceiveTotalBytes = totalBytes;
          _currentReceiveSessionId = sid;
            _receiveSenderAlias = alias;
          notifyListeners();
          // 等待 UI 调用 approve 或 reject
          final completer = Completer<bool>();
          _approvalWaiters[sid] = completer;
          return completer.future;
        },
      );
      final actualPort = _localSendServer!.port;
      debugPrint('LocalSendServer启动成功，端口: $actualPort');
      logInfo('sync_server_started port=$actualPort', source: 'LocalSend');

      // 设置设备发现服务的实际端口
      _discoveryService!.setServerPort(actualPort);

      // 启动设备发现
      await _discoveryService!.startDiscovery();
      debugPrint('设备发现服务启动成功');

      debugPrint(
          'ThoughtEcho sync server started on port ${_localSendServer?.port}');
    } catch (e) {
      logError('sync_server_start_fail $e', source: 'LocalSend');
      // Clean up on failure
      await stopServer();
      rethrow;
    }
  }

  // ===== 接收审批机制 =====
  final Map<String, Completer<bool>> _approvalWaiters = {};

  /// 用户批准接收
  void approveIncoming() {
    if (_currentReceiveSessionId != null) {
      final c = _approvalWaiters.remove(_currentReceiveSessionId!);
      c?.complete(true);
      _awaitingUserApproval = false;
      notifyListeners();
    }
  }

  /// 用户拒绝接收
  void rejectIncoming() {
    if (_currentReceiveSessionId != null) {
      final c = _approvalWaiters.remove(_currentReceiveSessionId!);
      c?.complete(false);
      _awaitingUserApproval = false;
      _updateSyncStatus(SyncStatus.failed, '已拒绝来自$_receiveSenderAlias 的同步', 0.0);
    }
  }

  /// 停止服务器（在关闭同步页面时调用）
  Future<void> stopServer() async {
    debugPrint('开始停止同步服务器...');

    try {
      // 停止LocalSendServer
      if (_localSendServer != null) {
        debugPrint('停止LocalSendServer...');
        await _localSendServer!.stop();
        debugPrint('LocalSendServer已停止');
      }
    } catch (e) {
      debugPrint('停止LocalSendServer时出错: $e');
    }

    try {
      // 停止设备发现服务
      if (_discoveryService != null) {
        debugPrint('停止设备发现服务...');
        await _discoveryService!.stopDiscovery();
        debugPrint('设备发现服务已停止');
      }
    } catch (e) {
      debugPrint('停止设备发现服务时出错: $e');
    }

    try {
      // 清理LocalSend发送服务
      if (_localSendProvider != null) {
        debugPrint('清理LocalSend发送服务...');
        _localSendProvider!.dispose();
        debugPrint('LocalSend发送服务已清理');
      }
    } catch (e) {
      debugPrint('清理LocalSend发送服务时出错: $e');
    }

    // 清空所有引用
    _localSendServer = null;
    _discoveryService = null;
    _localSendProvider = null;

    debugPrint('ThoughtEcho sync servers stopped and cleaned up');
  }

  /// 发送笔记数据到指定设备（统一使用createSyncPackage）
  Future<void> sendNotesToDevice(Device targetDevice) async {
    // 使用统一的createSyncPackage方法
  await createSyncPackage(targetDevice); // 使用默认包含媒体文件
  }

  /// (Deprecated) 旧receiveAndMerge逻辑已废弃，直接调用processSyncPackage
  @Deprecated('Legacy receive logic replaced by processSyncPackage; will be removed in future release')
  Future<void> receiveAndMergeNotes(String backupFilePath) =>
      processSyncPackage(backupFilePath);

  // 旧的重复检测与合并逻辑已不再需要 (LWW直接覆盖)。保留方法体空实现以避免潜在调用崩溃。
  @Deprecated('Legacy duplicate merge removed; kept as no-op for binary compatibility')
  // ignore: unused_element
  Future<void> _mergeNoteData() async {}

  /// 高级重复检测算法
  @Deprecated('Legacy advanced duplicate detection not used after LWW strategy')
  // ignore: unused_element
  Future<List<List<dynamic>>> _detectDuplicatesAdvanced(
      List<dynamic> quotes) async {
    final duplicateGroups = <List<dynamic>>[];
    final processed = <String>{};

    for (final quote in quotes) {
      if (processed.contains(quote.id)) continue;

      final duplicates = await _findSimilarQuotes(quote, quotes);
      if (duplicates.length > 1) {
        duplicateGroups.add(duplicates);
        processed.addAll(duplicates.map((q) => q.id));
      }
    }

    return duplicateGroups;
  }

  /// 查找相似笔记
  Future<List<dynamic>> _findSimilarQuotes(
      dynamic target, List<dynamic> allQuotes) async {
    final similar = [target];

    for (final quote in allQuotes) {
      if (quote.id == target.id) continue;

      if (await _areDuplicates(target, quote)) {
        similar.add(quote);
      }
    }

    return similar;
  }

  /// 判断两个笔记是否重复
  Future<bool> _areDuplicates(dynamic quote1, dynamic quote2) async {
    // 1. 精确内容匹配
    final normalizedContent1 = _normalizeContent(quote1.content);
    final normalizedContent2 = _normalizeContent(quote2.content);

    if (normalizedContent1 == normalizedContent2) {
      return true;
    }

    // 2. 富文本内容匹配
    if (quote1.deltaContent != null && quote2.deltaContent != null) {
      if (quote1.deltaContent == quote2.deltaContent) {
        return true;
      }
    }

    // 3. 内容相似度检测（90%以上相似度认为重复）
    final similarity =
        _calculateContentSimilarity(quote1.content, quote2.content);
    if (similarity > 0.9) {
      return true;
    }

    return false;
  }

  /// 标准化内容（去除空白字符和标点差异）
  String _normalizeContent(String content) {
    return content
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[^\w\s\u4e00-\u9fa5]'), '') // 保留中文字符
        .toLowerCase()
        .trim();
  }

  /// 计算内容相似度（Jaccard相似度）
  double _calculateContentSimilarity(String content1, String content2) {
    final words1 = _normalizeContent(content1)
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toSet();
    final words2 = _normalizeContent(content2)
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toSet();

    if (words1.isEmpty && words2.isEmpty) return 1.0;
    if (words1.isEmpty || words2.isEmpty) return 0.0;

    final intersection = words1.intersection(words2).length;
    final union = words1.union(words2).length;

    return intersection / union;
  }

  /// 合并一组重复笔记
  @Deprecated('Legacy merge duplicates function unused after LWW strategy')
  // ignore: unused_element
  Future<void> _mergeQuoteGroup(List<dynamic> duplicates) async {
    // 按优先级排序（最新时间、最丰富内容）
    duplicates.sort((a, b) {
      // 1. 优先保留有富文本内容的
      if (a.deltaContent != null && b.deltaContent == null) return -1;
      if (a.deltaContent == null && b.deltaContent != null) return 1;

      // 2. 优先保留内容更丰富的
      final aLength = a.content.length + (a.deltaContent?.length ?? 0);
      final bLength = b.content.length + (b.deltaContent?.length ?? 0);
      if (aLength != bLength) return bLength.compareTo(aLength);

      // 3. 优先保留更新时间的
      final timeA = DateTime.tryParse(a.date) ?? DateTime(1970);
      final timeB = DateTime.tryParse(b.date) ?? DateTime(1970);
      return timeB.compareTo(timeA);
    });

    final keepQuote = duplicates.first;
    final duplicatesToDelete = duplicates.skip(1).toList();

    debugPrint(
        '保留笔记: ${keepQuote.id}, 删除重复: ${duplicatesToDelete.map((q) => q.id).join(', ')}');

    // 删除重复笔记
    for (final duplicate in duplicatesToDelete) {
      await _databaseService.deleteQuote(duplicate.id);
    }
  }

  /// 创建同步包并发送到指定设备（若对方需要先审批，先走意向握手，再打包发送）
  /// [includeMediaFiles] 是否包含媒体文件（默认包含）
  Future<String> createSyncPackage(Device targetDevice, {bool includeMediaFiles = true}) async {
    if (_localSendProvider == null) {
      throw Exception('同步服务未初始化');
    }

    try {
      // 0. Preflight: ensure target /info reachable
      await _preflightCheck(targetDevice);

      // 0.1 发送意向握手（让对方先决定是否允许以及是否需要媒体）
      final approved = await _sendSyncIntent(targetDevice);
      if (!approved) {
        _updateSyncStatus(SyncStatus.failed, '对方拒绝同步请求', 0.0);
        throw Exception('对方拒绝同步请求');
      }

  // 1. 更新状态：开始打包（不显示大小/数量）
  _updateSyncStatus(SyncStatus.packaging, '正在打包数据...', 0.1);
      _currentSendSessionId = null;

      // 2. 使用备份服务创建数据包（隐藏具体数量，仅显示百分比）
      final backupPath = await _backupService.exportAllData(
        includeMediaFiles: includeMediaFiles,
        onProgress: (current, total) {
          final ratio = total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0;
            final progress = 0.1 + ratio * 0.4; // 10%-50%
          _updateSyncStatus(
              SyncStatus.packaging,
              '正在打包数据... ${(ratio * 100).toStringAsFixed(0)}%',
              progress);
        },
      );
      // 额外：打包完成后立即获取文件大小并校验
      final backupFile = File(backupPath);
      int size = 0;
      try {
        if (await backupFile.exists()) {
          size = await backupFile.length();
        }
      } catch (_) {}
      if (size == 0) {
        // 等待短暂时间再尝试（应对文件系统写入延迟）
        await Future.delayed(const Duration(milliseconds: 300));
        try {
          if (await backupFile.exists()) {
            size = await backupFile.length();
          }
        } catch (_) {}
      }
      logInfo('backup_zip_ready path=$backupPath size=$size',
          source: 'LocalSend');
      if (size == 0) {
        _updateSyncStatus(SyncStatus.failed, '备份文件大小为0，取消发送', 0.0);
        throw Exception('备份文件大小为0，可能生成失败');
      }

      // 3. 更新状态：开始发送
      _updateSyncStatus(SyncStatus.sending, '正在发送到目标设备...', 0.5);

      // 4. 发送文件 (使用LocalSend的优质代码)
      // 使用已验证的 backupFile
      final sessionId = await _localSendProvider!.startSession(
        target: targetDevice,
        files: [backupFile],
        background: true,
        onProgress: (sent, total) {
          // 打包阶段占 0-0.5 ，发送阶段占 0.5-0.9，余下 0.9-1.0 为完成收尾
          final ratio = total == 0 ? 0.0 : sent / total;
          _sendStartTime ??= DateTime.now();
          String extra = '';
          if (_sendStartTime != null) {
            final now = DateTime.now();
            final elapsed =
                now.difference(_sendStartTime!).inMilliseconds / 1000.0;
            if (elapsed > 0.2) {
              final speed = sent / 1024 / 1024 / elapsed; // MB/s 总平均
              final remaining = (total - sent).clamp(0, total);
              final etaSec = speed > 0 ? remaining / 1024 / 1024 / speed : 0;
              extra =
                  ' | ${speed.toStringAsFixed(2)}MB/s | 剩余${etaSec < 1 ? '<1' : etaSec.toStringAsFixed(0)}s';
            }
          }
          final progress = 0.5 + ratio * 0.4; // 线性映射
          _updateSyncStatus(
              SyncStatus.sending,
              '正在发送 ${(sent / 1024 / 1024).toStringAsFixed(1)}MB / ${(total / 1024 / 1024).toStringAsFixed(1)}MB$extra',
              progress);
        },
        onSessionCreated: (sid) {
          _currentSendSessionId = sid;
        },
      );

      // 5. 完成
      _updateSyncStatus(SyncStatus.completed, '发送完成', 1.0);

      // 6. 清理临时文件
      try {
        await backupFile.delete();
      } catch (e) {
        debugPrint('清理临时文件失败: $e');
      }

      return sessionId;
    } catch (e) {
      _updateSyncStatus(SyncStatus.failed, '发送失败: $e', 0.0);
      rethrow;
    }
  }

  /// 发送同步意向，返回是否获得对方批准
  Future<bool> _sendSyncIntent(Device target) async {
    if (skipSyncConfirmation) return true; // 全局跳过确认
    try {
      final uri = Uri.parse('http://${target.ip}:${target.port}/api/thoughtecho/v1/sync-intent');
      final fp = await DeviceIdentityManager.I.getFingerprint();
      final body = jsonEncode({
        'fingerprint': fp,
        'alias': 'ThoughtEcho',
      });
      final resp = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return true; // 回退：旧版本对方不支持则直接继续
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return data['approved'] != false;
    } catch (e) {
      // 容错：如果对方是旧版本（无该端点）继续旧流程
      return true;
    }
  }

  Future<void> setSkipSyncConfirmation(bool value) async {
    await _settingsService.setSyncSkipConfirm(value);
    notifyListeners();
  }

  /// 取消当前发送（仅在发送阶段有效）
  void cancelOngoingSend() {
    if (_syncStatus != SyncStatus.sending || _currentSendSessionId == null) {
      return;
    }
    try {
      _localSendProvider?.cancelSession(_currentSendSessionId!);
      _updateSyncStatus(SyncStatus.failed, '发送已取消', 0.0);
    } catch (e) {
      debugPrint('取消发送失败: $e');
    }
  }

  /// 取消接收（如果正在接收且尚未进入合并阶段）
  void cancelReceiving() {
    if (_syncStatus != SyncStatus.receiving || _currentReceiveSessionId == null) {
      return;
    }
    try {
      final rc = _localSendServer?.receiveController;
      rc?.cancelSession(_currentReceiveSessionId!);
      _updateSyncStatus(SyncStatus.failed, '接收已取消', 0.0);
    } catch (e) {
      debugPrint('取消接收失败: $e');
    }
  }

  Future<void> _preflightCheck(Device target) async {
    final client = http.Client();
    try {
      final infoUrlV2 =
          'http://${target.ip}:${target.port}/api/localsend/v2/info';
      final infoUrlV1 =
          'http://${target.ip}:${target.port}/api/localsend/v1/info';
      http.Response resp;
      try {
        resp = await client
            .get(Uri.parse(infoUrlV2))
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        resp = http.Response('', 404);
      }
      if (resp.statusCode == 404) {
        try {
          resp = await client
              .get(Uri.parse(infoUrlV1))
              .timeout(const Duration(seconds: 3));
        } catch (_) {
          // ignore
        }
      }
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        debugPrint('Preflight OK: ${resp.statusCode}');
      } else {
        debugPrint('Preflight warn: ${resp.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  /// 处理接收到的同步包
  /// 处理接收到的同步包 (使用LWW策略)
  Future<void> processSyncPackage(String backupFilePath) async {
    try {
      // 1. 更新状态：开始合并
  // 文案简化：去掉专业术语 LWW，避免用户困惑
  _updateSyncStatus(SyncStatus.merging, '正在合并数据...', 0.1);

      // 2. 使用新的统一 importData 接口（merge=true）
      final mergeReport = await _backupService.importData(
        backupFilePath,
        merge: true,
        clearExisting: false,
        sourceDevice: 'P2P同步',
        onProgress: (current, total) {
          final progress = 0.1 + (current / total) * 0.8;
          _updateSyncStatus(
              SyncStatus.merging, '正在导入数据... ($current/$total)', progress);
        },
      );
      _lastMergeReport = mergeReport; // 保存最近一次报告

      // 3. 显示合并结果
      final summary = mergeReport?.summary ?? '无报告';
      if (mergeReport?.hasErrors == true) {
        _updateSyncStatus(SyncStatus.failed, '合并出现错误: $summary', 0.0);
  debugPrint('合并错误: ${mergeReport?.errors}');
      } else {
        _updateSyncStatus(SyncStatus.completed, '合并完成: $summary', 1.0);
  debugPrint('合并成功: $summary');
        try {
          _databaseService.refreshAllData();
        } catch (e) {
          debugPrint('刷新数据库数据流失败: $e');
        }
      }
    } catch (e) {
      _updateSyncStatus(SyncStatus.failed, '合并失败: $e', 0.0);
      debugPrint('processSyncPackage失败: $e');
      rethrow;
    }
  }

  /// 更新同步状态
  void _updateSyncStatus(SyncStatus status, String message, double progress) {
    // 约束 progress 合法区间
    if (progress.isNaN || progress.isInfinite) progress = 0.0;
    if (progress < 0) progress = 0; else if (progress > 1) progress = 1;

    final now = DateTime.now();
    final statusChanged = status != _syncStatus;
    final messageChanged = message != _syncStatusMessage;
  final progressDelta = (progress - _syncProgress).abs();
    final timeDeltaMs = now.difference(_lastUiNotify).inMilliseconds;

    _syncStatus = status;
    _syncStatusMessage = message;
    _syncProgress = progress;

    // 通知策略：
  // 1. 状态或消息变化立即通知
  // 2. 进度变化累计 >=0.5% 或 距上次>=_minUiNotifyIntervalMs 才通知（更实时）
    final shouldNotify = statusChanged ||
        messageChanged ||
  progressDelta >= 0.002 || // 0.2% 进度变化就刷新
        timeDeltaMs >= _minUiNotifyIntervalMs ||
        progress >= 1.0 ||
        status == SyncStatus.failed ||
        status == SyncStatus.completed;
    if (shouldNotify) {
      _lastUiNotify = now;
      notifyListeners();
    }
    if (shouldNotify || statusChanged) {
      debugPrint('同步状态: $status - $message (${(_syncProgress * 100).toStringAsFixed(1)}%)');
    }
  }

  /// 发现附近的设备
  ///
  /// [timeout] 可选，单位为毫秒，表示等待远端设备响应的时间。默认使用
  /// `defaultDiscoveryTimeout`，在较慢或不稳定网络上建议增加该值。
  Future<List<Device>> discoverNearbyDevices({int? timeout}) async {
    if (_discoveryService == null) {
      debugPrint('Discovery service not initialized');
      return [];
    }

    try {
      // 清空现有设备列表，重新开始发现
      _discoveryService!.clearDevices();

      // 发送设备公告，触发其他设备响应
      await _discoveryService!.announceDevice();

      // 等待一段时间收集响应（使用可配置的超时时间）
      final waitMs = timeout ?? defaultDiscoveryTimeout;
      await Future.delayed(Duration(milliseconds: waitMs));

      return _discoveryService!.devices;
    } catch (e) {
      debugPrint('发现附近设备失败: $e');
      return [];
    }
  }

  /// 流式发现附近设备，实时推送列表更新。
  /// 返回 (Stream<List<Device>>, VoidCallback cancel) 二元组。
  ///  - stream: 订阅后会立即收到第一次空列表，然后设备变化时推送。
  ///  - cancel: 调用后提前结束等待并完成 stream。
  /// [timeout] 总等待时长毫秒。
  (Stream<List<Device>>, VoidCallback) discoverNearbyDevicesStream(
      {int? timeout}) {
    if (_discoveryService == null) {
      final controller = StreamController<List<Device>>();
      // 立即关闭
      controller.close();
      return (controller.stream, () {});
    }

    final waitMs = timeout ?? defaultDiscoveryTimeout;
    final controller = StreamController<List<Device>>();
    bool cancelled = false;
    Timer? periodic;
    Timer? endTimer;

    // 清空 & 首次公告
    _discoveryService!.clearDevices();
    _discoveryService!.announceDevice();

    void emit() {
      if (!controller.isClosed) {
        controller.add(_discoveryService!.devices);
      }
    }

    // 周期性广播（提升发现概率）和推送更新
    periodic = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (cancelled) return;
      await _discoveryService!.announceDevice();
      emit();
    });

    // 快速轮询前几秒（前 5 秒每 1s 更新一次）
    int fastTicks = 0;
    Timer.periodic(const Duration(seconds: 1), (t) {
      if (cancelled || t.isActive == false) return;
      fastTicks++;
      emit();
      if (fastTicks >= 5) t.cancel();
    });

    // 最终超时结束
    endTimer = Timer(Duration(milliseconds: waitMs), () {
      if (cancelled) return;
      cancelled = true;
      emit();
      controller.close();
      periodic?.cancel();
    });

    // 初始立即一次
    emit();

    void cancel() {
      if (cancelled) return;
      cancelled = true;
      periodic?.cancel();
      endTimer?.cancel();
      if (!controller.isClosed) {
        emit();
        controller.close();
      }
    }

    controller.onCancel = cancel;

    return (controller.stream, cancel);
  }

  @override
  void dispose() {
    // 清理LocalSend资源
    _localSendServer?.stop();
    _localSendProvider?.dispose();
    super.dispose();
  }
}

// CrossFile模型（简化版）
class CrossFile {
  final String path;
  final String name;
  final int size;

  CrossFile({
    required this.path,
    required this.name,
    required this.size,
  });

  factory CrossFile.fromFile(File file) {
    return CrossFile(
      path: file.path,
      name: file.path.split('/').last,
      size: file.lengthSync(),
    );
  }
}
