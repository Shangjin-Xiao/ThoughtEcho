import 'dart:async';
import 'dart:io';
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
import '../../common/lib/model/device.dart' as common;


/// 笔记同步服务 - 基于LocalSend的P2P同步功能
/// 
/// 集成LocalSend的核心功能，实现设备间的笔记数据同步
/// 使用备份还原机制进行数据传输和合并
class NoteSyncService extends ChangeNotifier {
  final BackupService _backupService;
  final DatabaseService _databaseService;
  // final SettingsService _settingsService;
  // final AIAnalysisDatabaseService _aiAnalysisDbService;

  // LocalSend核心组件
  SimpleServer? _server;
  ThoughtEchoDiscoveryService? _discoveryService;
  LocalSendServer? _localSendServer;
  LocalSendProvider? _localSendProvider;

  NoteSyncService({
    required BackupService backupService,
    required DatabaseService databaseService,
    required SettingsService settingsService,
    required AIAnalysisDatabaseService aiAnalysisDbService,
  })  : _backupService = backupService,
        _databaseService = databaseService;
        // _settingsService = settingsService,
        // _aiAnalysisDbService = aiAnalysisDbService;

  /// 初始化同步服务
  Future<void> initialize() async {
    // 在打开同步页面时才启动服务器
    debugPrint('NoteSyncService initialized, server will start when sync page opens');
  }

  /// 启动服务器（在打开同步页面时调用）
  Future<void> startServer() async {
    if (_server?.isRunning == true || _localSendServer?.isRunning == true) return;

    // Check if we're running on web platform
    if (kIsWeb) {
      debugPrint('Note sync servers not supported on web platform');
      return;
    }

    _server = SimpleServer();
    _discoveryService = ThoughtEchoDiscoveryService();
    _localSendServer = LocalSendServer();
    _localSendProvider = LocalSendProvider();

    try {
      // 启动原有服务器监听文件接收
      await _server!.start(
        alias: 'ThoughtEcho-${DateTime.now().millisecondsSinceEpoch}',
        onFileReceived: (filePath) async {
          // 接收到文件后自动导入
          await receiveAndMergeNotes(filePath);
        },
      );

      // 启动LocalSend服务器
      await _localSendServer!.start(
        onFileReceived: (filePath) async {
          // 接收到文件后自动导入
          await receiveAndMergeNotes(filePath);
        },
      );

      // 启动设备发现
      await _discoveryService!.startDiscovery();

      debugPrint('ThoughtEcho servers started:');
      debugPrint('  - Simple server on port ${_server?.port}');
      debugPrint('  - LocalSend server on port ${_localSendServer?.port}');
    } catch (e) {
      debugPrint('Failed to start servers: $e');
      // Clean up on failure
      await stopServer();
      rethrow;
    }
  }

  /// 停止服务器（在关闭同步页面时调用）
  Future<void> stopServer() async {
    await _server?.stop();
    await _localSendServer?.stop();
    await _discoveryService?.stopDiscovery();

    _server = null;
    _localSendServer = null;
    _discoveryService = null;

    debugPrint('ThoughtEcho sync servers stopped');
  }

  /// 发送笔记数据到指定设备
  Future<void> sendNotesToDevice(Device targetDevice) async {
    if (_localSendProvider == null) {
      throw Exception('LocalSend服务未初始化');
    }

    try {
      // 1. 使用备份服务创建数据包
      final backupPath = await _backupService.exportAllData(
        includeMediaFiles: true,
        onProgress: (current, total) {
          // 发送进度通知
          notifyListeners();
        },
      );

      // 2. 创建LocalSend设备对象
      final lsDevice = common.Device(
        signalingId: null,
        ip: targetDevice.ip,
        version: '2.1',
        port: targetDevice.port,
        https: false,
        fingerprint: targetDevice.fingerprint,
        alias: targetDevice.alias,
        deviceModel: targetDevice.deviceModel,
        deviceType: _convertDeviceType(targetDevice.deviceType),
        download: true,
        discoveryMethods: {const common.MulticastDiscovery()},
      );

      // 3. 使用LocalSend发送文件
      final backupFile = File(backupPath);
      final sessionId = await _localSendProvider!.startSession(
        target: lsDevice,
        files: [backupFile],
        background: true,
      );

      debugPrint('LocalSend文件发送会话已启动: $sessionId');

    } catch (e) {
      debugPrint('发送笔记失败: $e');
      rethrow;
    }
  }

  /// 转换设备类型
  common.DeviceType _convertDeviceType(dynamic deviceType) {
    if (deviceType == null) return common.DeviceType.desktop;

    final typeStr = deviceType.toString().toLowerCase();
    switch (typeStr) {
      case 'mobile':
        return common.DeviceType.mobile;
      case 'desktop':
        return common.DeviceType.desktop;
      case 'web':
        return common.DeviceType.web;
      case 'headless':
        return common.DeviceType.headless;
      case 'server':
        return common.DeviceType.server;
      default:
        return common.DeviceType.desktop;
    }
  }

  /// 接收并合并笔记数据
  Future<void> receiveAndMergeNotes(String backupFilePath) async {
    try {
      // 1. 导入接收到的备份数据（不清空现有数据）
      await _backupService.importData(
        backupFilePath,
        clearExisting: false, // 关键：不清空现有数据，进行合并
        onProgress: (current, total) {
          notifyListeners();
        },
      );

      // 2. 执行数据合并逻辑
      await _mergeNoteData();
      
    } catch (e) {
      debugPrint('接收笔记失败: $e');
      rethrow;
    }
  }

  /// 合并重复的笔记数据
  Future<void> _mergeNoteData() async {
    // 实现智能合并逻辑
    // 1. 检测重复笔记（基于内容哈希或时间戳）
    final allQuotes = await _databaseService.getAllQuotes();
    final duplicateGroups = <String, List<dynamic>>{};
    
    // 按内容分组检测重复
    for (final quote in allQuotes) {
      final content = quote.content;
      final contentHash = content.hashCode.toString();
      
      if (duplicateGroups.containsKey(contentHash)) {
        duplicateGroups[contentHash]!.add(quote);
      } else {
        duplicateGroups[contentHash] = [quote];
      }
    }
    
    // 2. 合并冲突的笔记 - 保留最新版本
    for (final group in duplicateGroups.values) {
      if (group.length > 1) {
        // 按更新时间排序，保留最新的
        group.sort((a, b) {
          final timeA = DateTime.tryParse(a.date) ?? DateTime(1970);
          final timeB = DateTime.tryParse(b.date) ?? DateTime(1970);
          return timeB.compareTo(timeA);
        });
        
        // 删除重复的旧版本
        for (int i = 1; i < group.length; i++) {
          await _databaseService.deleteQuote(group[i].id);
        }
      }
    }
  }

  /// 发现附近的设备
  Future<List<Device>> discoverNearbyDevices() async {
    // 使用UDP组播发现设备
    if (_discoveryService != null) {
      return _discoveryService!.devices;
    }
    return [];
  }

  @override
  void dispose() {
    // 清理LocalSend资源
    _server?.stop();
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