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
import 'package:device_info_plus/device_info_plus.dart';

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
  // 调整：进一步缩短 UI 通知节流时间以实现更实时的进度更新（用户期望更"实时"）
  static const int _minUiNotifyIntervalMs = 50; // ~20fps
  
  // 速度计算相关（滑动窗口）
  final List<_SpeedSample> _speedSamples = [];
  static const int _maxSpeedSamples = 10; // 保留最近10个样本
  DateTime? _lastProgressTime;
  int? _lastProgressBytes;
  MergeReport? _lastMergeReport; // 新增：最近一次合并报告
  String? _currentReceiveSessionId; // 当前接收会话ID
  String? _receiveSenderAlias;
  int? _pendingReceiveTotalBytes; // 等待审批大小
  bool _awaitingUserApproval = false; // 是否处于接收审批阶段
  bool _awaitingPeerApproval = false; // 发送端等待对方审批

  bool get awaitingUserApproval => _awaitingUserApproval;
  int? get pendingReceiveTotalBytes => _pendingReceiveTotalBytes;
  bool get awaitingPeerApproval => _awaitingPeerApproval;
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
    AppLogger.d('NoteSyncService 构造函数完成', source: 'NoteSyncService');
  }
  bool get skipSyncConfirmation => _settingsService.syncSkipConfirm;

  /// 初始化同步服务
  Future<void> initialize() async {
    // 在打开同步页面时才启动服务器
    AppLogger.d(
        'NoteSyncService initialized, server will start when sync page opens');
  }

  /// 启动服务器（在打开同步页面时调用）
  Future<void> startServer() async {
    // 检查是否已经启动
    if (_localSendServer?.isRunning == true) {
      AppLogger.i('同步服务器已经启动，跳过重复启动', source: 'NoteSyncService');
      return;
    }

    // Check if we're running on web platform
    if (kIsWeb) {
      AppLogger.w('Note sync servers not supported on web platform',
          source: 'NoteSyncService');
      return;
    }

    try {
      AppLogger.i('开始初始化同步服务组件...', source: 'NoteSyncService');

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

      AppLogger.i('所有服务组件创建成功，开始启动服务器...', source: 'NoteSyncService');

      // 启动LocalSend服务器
      // ensure fingerprint ready before server start
      await DeviceIdentityManager.I.getFingerprint();
      await _localSendServer!.start(
        port: defaultPort, // 明确指定端口
        onFileReceived: (filePath) async {
          // 文件接收完毕后开始处理合并
          await processSyncPackage(filePath);
        },
        onReceiveProgress: _handleReceiveProgress,
        onReceiveSessionCreated: _handleReceiveSessionCreated,
        onApprovalNeeded: (sid, totalBytes, alias) async {
          // 如果设置了跳过确认,直接批准
          if (skipSyncConfirmation) {
            return true;
          }
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
      AppLogger.i('LocalSendServer启动成功，端口: $actualPort',
          source: 'NoteSyncService');
      logInfo('sync_server_started port=$actualPort', source: 'LocalSend');

      // 设置设备发现服务的实际端口
      _discoveryService!.setServerPort(actualPort);

      // 启动设备发现
      await _discoveryService!.startDiscovery();
      AppLogger.i('设备发现服务启动成功', source: 'NoteSyncService');
      AppLogger.i(
          'ThoughtEcho sync server started on port ${_localSendServer?.port}',
          source: 'NoteSyncService');
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
      _updateSyncStatus(
          SyncStatus.failed, '已拒绝来自$_receiveSenderAlias 的同步', 0.0);
    }
  }

  /// 停止服务器（在关闭同步页面时调用）
  Future<void> stopServer() async {
    AppLogger.i('开始停止同步服务器...', source: 'NoteSyncService');

    try {
      // 停止LocalSendServer
      if (_localSendServer != null) {
        AppLogger.d('停止LocalSendServer...', source: 'NoteSyncService');
        await _localSendServer!.stop();
        AppLogger.i('LocalSendServer已停止', source: 'NoteSyncService');
      }
    } catch (e) {
      AppLogger.e('停止LocalSendServer时出错: $e',
          error: e, source: 'NoteSyncService');
    }

    try {
      // 停止设备发现服务
      if (_discoveryService != null) {
        await _discoveryService!.stopDiscovery();
        AppLogger.i('设备发现服务已停止', source: 'NoteSyncService');
      }
    } catch (e) {
      AppLogger.e('停止设备发现服务时出错: $e', error: e, source: 'NoteSyncService');
    }

    try {
      // 清理LocalSend发送服务
      if (_localSendProvider != null) {
        AppLogger.d('清理LocalSend发送服务...', source: 'NoteSyncService');
        _localSendProvider!.dispose();
        AppLogger.i('LocalSend发送服务已清理', source: 'NoteSyncService');
      }
    } catch (e) {
      AppLogger.e('清理LocalSend发送服务时出错: $e',
          error: e, source: 'NoteSyncService');
    }

    // 清空所有引用
    _localSendServer = null;
    _discoveryService = null;
    _localSendProvider = null;

    AppLogger.i('ThoughtEcho sync servers stopped and cleaned up',
        source: 'NoteSyncService');
  }

  /// 发送笔记数据到指定设备（统一使用createSyncPackage）
  Future<void> sendNotesToDevice(Device targetDevice) async {
    // 使用统一的createSyncPackage方法
    await createSyncPackage(targetDevice); // 使用默认包含媒体文件
  }

  /// (Deprecated) 旧receiveAndMerge逻辑已废弃，直接调用processSyncPackage
  @Deprecated(
      'Legacy receive logic replaced by processSyncPackage; will be removed in future release')
  Future<void> receiveAndMergeNotes(String backupFilePath) =>
      processSyncPackage(backupFilePath);

  /// 创建同步包并发送到指定设备（若对方需要先审批，先走意向握手，再打包发送）
  /// [includeMediaFiles] 是否包含媒体文件（默认包含）
  Future<String> createSyncPackage(Device targetDevice,
      {bool includeMediaFiles = true}) async {
    if (_localSendProvider == null) {
      throw Exception('同步服务未初始化');
    }

    try {
      // 0. Preflight: ensure target /info reachable
      await _preflightCheck(targetDevice);

      // 0.1 发送意向握手（让对方先决定是否允许以及是否需要媒体）
      _setAwaitingPeerApproval(true);
      _updateSyncStatus(SyncStatus.packaging, '等待对方确认同步请求...', 0.02);
      final approved = await _sendSyncIntent(targetDevice);
      if (!approved) {
        _updateSyncStatus(SyncStatus.failed, '对方拒绝同步请求', 0.0);
        throw Exception('对方拒绝同步请求');
      }
      _setAwaitingPeerApproval(false);

      // 1. 更新状态：开始打包（不显示大小/数量）
      _updateSyncStatus(SyncStatus.packaging, '正在打包数据...', 0.1);
      _currentSendSessionId = null;

      // 2. 使用备份服务创建数据包（隐藏具体数量，仅显示百分比）
      final backupPath = await _backupService.exportAllData(
        includeMediaFiles: includeMediaFiles,
        onProgress: (current, total) {
          final ratio = total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0;
          final progress = 0.1 + ratio * 0.4; // 10%-50%
          _updateSyncStatus(SyncStatus.packaging,
              '正在打包数据... ${(ratio * 100).toStringAsFixed(0)}%', progress);
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
      _resetSpeedTracking(); // 重置速度跟踪
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
          final now = DateTime.now();
          _addSpeedSample(sent, now);
          final speed = _calculateAverageSpeed(); // bytes/s
          
          String extra = '';
          if (speed > 1024 * 100) { // 速度 > 100KB/s 时才显示
            final speedMBps = speed / 1024 / 1024;
            final remaining = (total - sent).clamp(0, total);
            final etaSec = remaining / speed;
            extra = ' | ${speedMBps.toStringAsFixed(2)}MB/s | 剩余${etaSec < 1 ? '<1' : etaSec.toStringAsFixed(0)}s';
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
        AppLogger.w('清理临时文件失败: $e', error: e, source: 'NoteSyncService');
      }

      return sessionId;
    } catch (e) {
      _setAwaitingPeerApproval(false);
      _updateSyncStatus(SyncStatus.failed, '发送失败: $e', 0.0);
      rethrow;
    }
  }

  void _setAwaitingPeerApproval(bool value) {
    if (_awaitingPeerApproval == value) return;
    _awaitingPeerApproval = value;
    notifyListeners();
  }

  /// 发送同步意向，返回是否获得对方批准
  Future<bool> _sendSyncIntent(Device target) async {
    // 注意：即使本地设置了 skipSyncConfirmation，我们仍然需要发送 intent
    // 以便接收方知道即将到来的同步，并且接收方可以根据自己的设置决定是否需要审批
    try {
      final uri = Uri.parse(
          'http://${target.ip}:${target.port}/api/thoughtecho/v1/sync-intent');
      final fp = await DeviceIdentityManager.I.getFingerprint();
      // 直接使用 discoveryService 的设备型号，它已经正确地从设备信息中获取
      String alias = 'ThoughtEcho';
      try {
        if (_discoveryService != null) {
          // 先尝试从 _deviceModel 字段（这是真实的设备型号）
          final reflectModel = await _getDiscoveryDeviceModel();
          if (reflectModel.isNotEmpty) {
            alias = reflectModel;
          } else {
            // Fallback: 查找本机设备项
            final self = _discoveryService!.devices.firstWhere(
              (d) => d.fingerprint == fp,
              orElse: () => Device(
                signalingId: null,
                ip: null,
                version: '',
                port: _localSendServer?.port ?? defaultPort,
                https: false,
                fingerprint: fp,
                alias: 'ThoughtEcho',
                deviceModel: null,
                deviceType: DeviceType.desktop,
                download: false,
                discoveryMethods: const {},
              ),
            );
            if ((self.deviceModel ?? '').trim().isNotEmpty) {
              alias = self.deviceModel!.trim();
            } else if ((self.alias).trim().isNotEmpty) {
              alias = self.alias.trim();
            }
          }
        }
      } catch (_) {
        // 忽略，Fallback 保持 ThoughtEcho
      }
      final body = jsonEncode({'fingerprint': fp, 'alias': alias});
      final resp = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 10)); // 增加超时时间以等待用户审批
      if (resp.statusCode != 200) return true; // 回退：旧版本对方不支持则直接继续
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return data['approved'] != false;
    } catch (e) {
      // 容错：如果对方是旧版本（无该端点）或超时，继续旧流程
      AppLogger.w('发送同步意向失败: $e', error: e, source: 'NoteSyncService');
      return true;
    }
  }

  /// 通过反射获取 discoveryService 的真实设备型号
  Future<String> _getDiscoveryDeviceModel() async {
    try {
      // discoveryService 内部有 _deviceModel 字段但未公开
      // 这里通过一个间接方式：让 discovery 服务暴露该字段或使用公共接口
      // 临时方案：直接访问（需要添加 getter）
      // 由于无法直接访问私有字段，改为通过 DeviceInfoPlugin 直接获取
      if (kIsWeb) return 'Web';
      
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        final brand = info.brand.trim();
        final m = info.model.trim();
        return [brand, m].where((e) => e.isNotEmpty).join(' ');
      } else if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        final name = info.name.trim();
        final machine = info.utsname.machine.trim();
        return name.isNotEmpty && machine.isNotEmpty
            ? '$name ($machine)'
            : (name.isNotEmpty ? name : machine);
      } else if (Platform.isMacOS) {
        final info = await plugin.macOsInfo;
        return info.model.trim().isEmpty ? 'macOS' : info.model.trim();
      } else if (Platform.isWindows) {
        final info = await plugin.windowsInfo;
        return info.computerName.trim().isEmpty
            ? 'Windows'
            : info.computerName.trim();
      } else if (Platform.isLinux) {
        final info = await plugin.linuxInfo;
        return info.prettyName.trim().isEmpty
            ? 'Linux'
            : info.prettyName.trim();
      }
      return Platform.operatingSystem;
    } catch (e) {
      return '';
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
      AppLogger.e('取消发送失败: $e', error: e, source: 'NoteSyncService');
    }
  }

  /// 取消接收（如果正在接收且尚未进入合并阶段）
  void cancelReceiving() {
    if (_syncStatus != SyncStatus.receiving ||
        _currentReceiveSessionId == null) {
      return;
    }
    try {
      final rc = _localSendServer?.receiveController;
      rc?.cancelSession(_currentReceiveSessionId!);
      _updateSyncStatus(SyncStatus.failed, '接收已取消', 0.0);
    } catch (e) {
      AppLogger.e('取消接收失败: $e', error: e, source: 'NoteSyncService');
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
        AppLogger.d('Preflight OK: ${resp.statusCode}',
            source: 'NoteSyncService');
      } else {
        AppLogger.w('Preflight warn: ${resp.statusCode}',
            source: 'NoteSyncService');
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
        AppLogger.e('合并错误: ${mergeReport?.errors}', source: 'NoteSyncService');
      } else {
        _updateSyncStatus(SyncStatus.completed, '合并完成: $summary', 1.0);
        AppLogger.i('合并成功: $summary', source: 'NoteSyncService');
        try {
          _databaseService.refreshAllData();
        } catch (e) {
          AppLogger.w('刷新数据库数据流失败: $e', error: e, source: 'NoteSyncService');
        }
      }
    } catch (e) {
      _updateSyncStatus(SyncStatus.failed, '合并失败: $e', 0.0);
      AppLogger.e('processSyncPackage失败: $e',
          error: e, source: 'NoteSyncService');
      rethrow;
    }
  }

  /// 更新同步状态
  void _updateSyncStatus(SyncStatus status, String message, double progress) {
    // 约束 progress 合法区间
    if (progress.isNaN || progress.isInfinite) {
      progress = 0.0;
    }
    if (progress < 0) {
      progress = 0;
    } else if (progress > 1) {
      progress = 1;
    }

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
      AppLogger.d(
          '同步状态: $status - $message (${(_syncProgress * 100).toStringAsFixed(1)}%)',
          source: 'NoteSyncService');
    }
  }

  /// 发现附近的设备
  ///
  /// [timeout] 可选，单位为毫秒，表示等待远端设备响应的时间。默认使用
  /// `defaultDiscoveryTimeout`，在较慢或不稳定网络上建议增加该值。
  Future<List<Device>> discoverNearbyDevices({int? timeout}) async {
    if (_discoveryService == null) {
      AppLogger.w('Discovery service not initialized',
          source: 'NoteSyncService');
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
      AppLogger.e('发现附近设备失败: $e', error: e, source: 'NoteSyncService');
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
    Timer? fastTimer; // 快速轮询定时器

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
      try {
        await _discoveryService!.announceDevice();
        emit();
      } catch (e) {
        // 忽略公告错误，避免中断流
      }
    });

    // 快速轮询前几秒（前 5 秒每 1s 更新一次）
    int fastTicks = 0;
    fastTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (cancelled) {
        t.cancel();
        return;
      }
      fastTicks++;
      emit();
      if (fastTicks >= 5) {
        t.cancel();
        fastTimer = null;
      }
    });

    // 最终超时结束
    endTimer = Timer(Duration(milliseconds: waitMs), () {
      if (cancelled) return;
      cancelled = true;
      emit();
      controller.close();
      periodic?.cancel();
      fastTimer?.cancel();
    });

    // 初始立即一次
    emit();

    void cancel() {
      if (cancelled) return;
      cancelled = true;
      periodic?.cancel();
      endTimer?.cancel();
      fastTimer?.cancel();
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

  /// 计算滑动窗口平均速度 (bytes/second)
  double _calculateAverageSpeed() {
    if (_speedSamples.isEmpty) return 0.0;
    
    // 移除过期样本（超过5秒的）
    final now = DateTime.now();
    _speedSamples.removeWhere((s) => 
      now.difference(s.timestamp).inMilliseconds > 5000);
    
    if (_speedSamples.isEmpty) return 0.0;
    
    // 计算总字节数和总时间
    final totalBytes = _speedSamples.fold<int>(0, (sum, s) => sum + s.bytes);
    final earliest = _speedSamples.first.timestamp;
    final latest = _speedSamples.last.timestamp;
    final duration = latest.difference(earliest).inMilliseconds / 1000.0;
    
    if (duration < 0.1) return 0.0; // 避免除以很小的数
    
    return totalBytes / duration;
  }

  /// 添加速度样本
  void _addSpeedSample(int currentBytes, DateTime timestamp) {
    if (_lastProgressBytes != null && _lastProgressTime != null) {
      final deltaBytes = currentBytes - _lastProgressBytes!;
      if (deltaBytes > 0) {
        _speedSamples.add(_SpeedSample(
          bytes: deltaBytes,
          timestamp: timestamp,
        ));
        
        // 限制样本数量
        while (_speedSamples.length > _maxSpeedSamples) {
          _speedSamples.removeAt(0);
        }
      }
    }
    
    _lastProgressBytes = currentBytes;
    _lastProgressTime = timestamp;
  }

  /// 重置速度跟踪
  void _resetSpeedTracking() {
    _speedSamples.clear();
    _lastProgressTime = null;
    _lastProgressBytes = null;
  }

  bool _isReceiveEligibleState() {
    return _syncStatus == SyncStatus.idle ||
        _syncStatus == SyncStatus.receiving ||
        _syncStatus == SyncStatus.failed ||
        _syncStatus == SyncStatus.completed;
  }

  void _handleReceiveSessionCreated(
    String sessionId,
    int totalBytes,
    String senderAlias,
  ) {
    _currentReceiveSessionId = sessionId;
    _receiveSenderAlias = senderAlias;
    _pendingReceiveTotalBytes = totalBytes > 0 ? totalBytes : null;
    _resetSpeedTracking();

    if (_isReceiveEligibleState()) {
      final displayAlias = senderAlias.isEmpty ? '对方' : senderAlias;
      _updateSyncStatus(
        SyncStatus.receiving,
        '等待 $displayAlias 发送数据...',
        0.02,
      );
    } else {
      // 仍然需要同步 alias 信息供 UI 展示
      notifyListeners();
    }
  }

  void _handleReceiveProgress(int received, int total) {
    if (total <= 0) {
      return;
    }
    if (!_isReceiveEligibleState()) {
      return;
    }

    final ratio = received / total;
    final now = DateTime.now();
    _addSpeedSample(received, now);
    final speed = _calculateAverageSpeed();

    String extra = '';
    if (speed > 1024 * 100) {
      final speedMBps = speed / 1024 / 1024;
      final remaining = total - received;
      final etaSec = remaining / speed;
      extra =
          ' | ${speedMBps.toStringAsFixed(2)}MB/s | 剩余${etaSec < 1 ? '<1' : etaSec.toStringAsFixed(0)}s';
    }

    _updateSyncStatus(
      SyncStatus.receiving,
      '正在接收${_receiveSenderAlias != null ? '（来自$_receiveSenderAlias）' : ''} ${(received / 1024 / 1024).toStringAsFixed(1)}MB / ${(total / 1024 / 1024).toStringAsFixed(1)}MB$extra',
      0.05 + ratio * 0.75,
    );
  }

  @visibleForTesting
  void debugHandleReceiveSessionCreated(
          String sessionId, int totalBytes, String senderAlias) =>
      _handleReceiveSessionCreated(sessionId, totalBytes, senderAlias);

  @visibleForTesting
  void debugHandleReceiveProgress(int received, int total) =>
      _handleReceiveProgress(received, total);
}

/// 速度样本（用于滑动窗口平均）
class _SpeedSample {
  final int bytes;
  final DateTime timestamp;

  _SpeedSample({
    required this.bytes,
    required this.timestamp,
  });
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
