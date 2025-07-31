import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:thoughtecho/services/backup_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/ai_analysis_database_service.dart';
import 'package:thoughtecho/models/localsend_device.dart';
import 'package:thoughtecho/services/localsend_simple_server.dart';
import 'package:thoughtecho/services/thoughtecho_discovery_service.dart';
import 'package:thoughtecho/services/localsend/localsend_server.dart';
import 'package:thoughtecho/services/localsend/localsend_send_provider.dart';
import "package:common/model/device.dart" as common;
import '../models/note.dart';
import 'package:logging/logging.dart';

final _logger = Logger('NoteSyncService');

/// 笔记同步服务 - 基于LocalSend的P2P同步功能
/// 
/// 集成LocalSend的核心功能，实现设备间的笔记数据同步
/// 使用备份还原机制进行数据传输和合并
class NoteSyncService extends ChangeNotifier {
  final BackupService _backupService;
  final DatabaseService _databaseService;

  // LocalSend核心组件
  SimpleServer? _server;
  ThoughtEchoDiscoveryService? _discoveryService;
  LocalSendServer? _localSendServer;
  LocalSendProvider? _localSendProvider;

  // 状态管理
  bool _isServerRunning = false;
  bool _isDiscovering = false;
  List<Device> _discoveredDevices = [];
  SyncStatus _currentStatus = SyncStatus.idle;

  // Getters
  bool get isServerRunning => _isServerRunning;
  bool get isDiscovering => _isDiscovering;
  List<Device> get discoveredDevices => List.unmodifiable(_discoveredDevices);
  SyncStatus get currentStatus => _currentStatus;

  NoteSyncService({
    required BackupService backupService,
    required DatabaseService databaseService,
    required SettingsService settingsService,
    required AIAnalysisDatabaseService aiAnalysisDbService,
  })  : _backupService = backupService,
        _databaseService = databaseService;

  /// 初始化同步服务
  Future<void> initialize() async {
    try {
      _localSendProvider = LocalSendProvider();
      _localSendServer = LocalSendServer();
      _logger.info('NoteSyncService initialized');
    } catch (e) {
      _logger.severe('Failed to initialize NoteSyncService: $e');
      rethrow;
    }
  }

  /// 启动服务器（在打开同步页面时调用）
  Future<void> startServer() async {
    if (_isServerRunning || _localSendServer == null) return;

    try {
      await _localSendServer!.start();
      _isServerRunning = true;
      _currentStatus = SyncStatus.serverStarted;
      notifyListeners();
      _logger.info('LocalSend server started');
    } catch (e) {
      _logger.severe('Failed to start server: $e');
      _currentStatus = SyncStatus.error;
      notifyListeners();
      rethrow;
    }
  }

  /// 停止服务器
  Future<void> stopServer() async {
    if (!_isServerRunning || _localSendServer == null) return;

    try {
      await _localSendServer!.stop();
      _isServerRunning = false;
      _currentStatus = SyncStatus.serverStopped;
      notifyListeners();
      _logger.info('LocalSend server stopped');
    } catch (e) {
      _logger.severe('Failed to stop server: $e');
    }
  }

  /// 发现附近设备
  Future<void> discoverDevices() async {
    if (_isDiscovering) return;

    _isDiscovering = true;
    _currentStatus = SyncStatus.discovering;
    _discoveredDevices.clear();
    notifyListeners();

    try {
      // 执行网络扫描
      await _performNetworkScan();
      
      _currentStatus = SyncStatus.discoveryComplete;
      _logger.info('Device discovery completed. Found ${_discoveredDevices.length} devices');
    } catch (e) {
      _logger.severe('Device discovery failed: $e');
      _currentStatus = SyncStatus.error;
    } finally {
      _isDiscovering = false;
      notifyListeners();
    }
  }

  /// 执行网络扫描
  Future<void> _performNetworkScan() async {
    final interfaces = await NetworkInterface.list();
    final localIp = _getLocalIp(interfaces);
    
    if (localIp == null) {
      _logger.warning('No local IP found for scanning');
      return;
    }

    final networkBase = localIp.substring(0, localIp.lastIndexOf('.'));
    
    // 并行扫描网络设备
    final futures = <Future>[];
    for (int i = 1; i <= 254; i++) {
      final targetIp = '$networkBase.$i';
      if (targetIp != localIp) {
        futures.add(_scanDevice(targetIp));
      }
    }
    
    await Future.wait(futures).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _logger.info('Network scan timeout reached');
        return [];
      },
    );
  }

  /// 扫描特定设备
  Future<void> _scanDevice(String ip) async {
    try {
      final socket = await Socket.connect(ip, 53317)
          .timeout(const Duration(milliseconds: 500));
      await socket.close();
      
      // 获取设备信息
      final deviceInfo = await _getDeviceInfo(ip);
      if (deviceInfo != null) {
        _discoveredDevices.add(deviceInfo);
        notifyListeners();
      }
    } catch (e) {
      // 设备不可用或未运行LocalSend
    }
  }

  /// 获取设备信息
  Future<Device?> _getDeviceInfo(String ip) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('http://$ip:53317/api/v1/info'))
          .timeout(const Duration(seconds: 2));
      final response = await request.close();
      
      if (response.statusCode == 200) {
        final data = await response.transform(utf8.decoder).join();
        final json = jsonDecode(data) as Map<String, dynamic>;
        
        return Device(
          ip: ip,
          alias: json['alias'] as String? ?? 'Unknown Device',
          port: 53317,
          deviceType: json['deviceType'] as String? ?? 'mobile',
          fingerprint: json['fingerprint'] as String? ?? '',
        );
      }
    } catch (e) {
      // 获取设备信息失败
    }
    return null;
  }

  /// 发送笔记到目标设备
  Future<void> sendNotesToDevice(Device target, List<Note> notes) async {
    if (_localSendProvider == null) {
      throw StateError('Service not initialized');
    }

    _currentStatus = SyncStatus.sending;
    notifyListeners();

    try {
      // 转换笔记格式
      final noteFiles = notes.map((note) => NoteFile(
        id: note.id,
        title: note.title,
        content: note.content,
        createdAt: note.createdAt,
        updatedAt: note.updatedAt,
      )).toList();

      // 使用通用Device格式
      final commonDevice = common.Device(
        ip: target.ip,
        port: target.port,
        https: false,
        alias: target.alias,
        version: '2.0',
        deviceModel: 'ThoughtEcho',
        deviceType: target.deviceType,
        fingerprint: target.fingerprint,
      );

      // 开始发送会话
      final sessionId = await _localSendProvider!.startSession(
        target: commonDevice,
        notes: noteFiles,
      );

      // 监控会话进度
      await _monitorSendSession(sessionId);
      
      _currentStatus = SyncStatus.sendComplete;
      _logger.info('Successfully sent ${notes.length} notes to ${target.alias}');
    } catch (e) {
      _logger.severe('Failed to send notes: $e');
      _currentStatus = SyncStatus.error;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  /// 监控发送会话进度
  Future<void> _monitorSendSession(String sessionId) async {
    while (true) {
      final session = _localSendProvider!.getSession(sessionId);
      if (session == null) break;

      if (session.status.isFinished || session.status.isCanceled) {
        break;
      }

      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// 获取本地IP地址
  String? _getLocalIp(List<NetworkInterface> interfaces) {
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback && address.type == InternetAddressType.IPv4) {
          return address.address;
        }
      }
    }
    return null;
  }

  /// 清理资源
  @override
  void dispose() {
    stopServer();
    _localSendProvider?.dispose();
    super.dispose();
  }
}

/// 同步状态枚举
enum SyncStatus {
  idle,
  discovering,
  discoveryComplete,
  serverStarted,
  serverStopped,
  sending,
  sendComplete,
  receiving,
  receiveComplete,
  error,
}

extension SyncStatusExtension on SyncStatus {
  String get displayName {
    switch (this) {
      case SyncStatus.idle:
        return '空闲';
      case SyncStatus.discovering:
        return '正在发现设备...';
      case SyncStatus.discoveryComplete:
        return '设备发现完成';
      case SyncStatus.serverStarted:
        return '服务器已启动';
      case SyncStatus.serverStopped:
        return '服务器已停止';
      case SyncStatus.sending:
        return '正在发送笔记...';
      case SyncStatus.sendComplete:
        return '发送完成';
      case SyncStatus.receiving:
        return '正在接收笔记...';
      case SyncStatus.receiveComplete:
        return '接收完成';
      case SyncStatus.error:
        return '发生错误';
    }
  }
}