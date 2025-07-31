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
import 'package:thoughtecho/services/localsend/models/device.dart' as ls;
import 'package:thoughtecho/services/sync_protocol/sync_send_service.dart';
import 'package:thoughtecho/services/sync_protocol/models/device_info.dart' as sync;

/// 同步状态枚举
enum SyncStatus {
  idle,           // 空闲
  packaging,      // 打包中
  sending,        // 发送中
  receiving,      // 接收中
  merging,        // 合并中
  completed,      // 完成
  failed,         // 失败
}

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

  // 新的同步协议组件
  SyncSendService? _syncSendService;

  // 同步状态管理
  SyncStatus _syncStatus = SyncStatus.idle;
  String _syncStatusMessage = '';
  double _syncProgress = 0.0;

  // 状态访问器
  SyncStatus get syncStatus => _syncStatus;
  String get syncStatusMessage => _syncStatusMessage;
  double get syncProgress => _syncProgress;

  NoteSyncService({
    required BackupService backupService,
    required DatabaseService databaseService,
    required SettingsService settingsService,
    required AIAnalysisDatabaseService aiAnalysisDbService,
  })  : _backupService = backupService,
        _databaseService = databaseService {
    // 存储其他依赖，虽然当前没有直接使用，但为将来扩展保留
    // _settingsService = settingsService;
    // _aiAnalysisDbService = aiAnalysisDbService;
    debugPrint('NoteSyncService 构造函数完成');
  }

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

    try {
      debugPrint('开始初始化同步服务组件...');
      
      // 安全地初始化服务组件
      _server = SimpleServer();
      if (_server == null) {
        throw Exception('SimpleServer创建失败');
      }
      
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
      
      _syncSendService = SyncSendService();
      if (_syncSendService == null) {
        throw Exception('SyncSendService创建失败');
      }

      debugPrint('所有服务组件创建成功，开始启动服务器...');

      // 启动原有服务器监听文件接收
      await _server!.start(
        alias: 'ThoughtEcho-${DateTime.now().millisecondsSinceEpoch}',
        onFileReceived: (filePath) async {
          // 使用新的processSyncPackage方法处理接收到的文件
          await processSyncPackage(filePath);
        },
      );
      debugPrint('SimpleServer启动成功，端口: ${_server!.port}');

      // 启动LocalSend服务器
      await _localSendServer!.start(
        onFileReceived: (filePath) async {
          // 使用新的processSyncPackage方法处理接收到的文件
          await processSyncPackage(filePath);
        },
      );
      debugPrint('LocalSendServer启动成功，端口: ${_localSendServer!.port}');

      // 启动设备发现
      await _discoveryService!.startDiscovery();
      debugPrint('设备发现服务启动成功');

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
    _syncSendService?.dispose();

    _server = null;
    _localSendServer = null;
    _discoveryService = null;
    _syncSendService = null;

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
      final lsDevice = ls.Device(
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
        discoveryMethods: {const ls.MulticastDiscovery()},
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
  ls.DeviceType _convertDeviceType(dynamic deviceType) {
    if (deviceType == null) return ls.DeviceType.desktop;

    final typeStr = deviceType.toString().toLowerCase();
    switch (typeStr) {
      case 'mobile':
        return ls.DeviceType.mobile;
      case 'desktop':
        return ls.DeviceType.desktop;
      case 'web':
        return ls.DeviceType.web;
      case 'headless':
        return ls.DeviceType.headless;
      case 'server':
        return ls.DeviceType.server;
      default:
        return ls.DeviceType.desktop;
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

  /// 合并重复的笔记数据（增强版）
  Future<void> _mergeNoteData() async {
    try {
      debugPrint('开始智能笔记合并...');
      _updateSyncStatus(SyncStatus.merging, '正在检测重复笔记...', 0.1);
      
      // 1. 获取所有笔记并进行高级重复检测
      final allQuotes = await _databaseService.getAllQuotes();
      final duplicateGroups = await _detectDuplicatesAdvanced(allQuotes);
      
      _updateSyncStatus(SyncStatus.merging, '发现 ${duplicateGroups.length} 组重复笔记', 0.3);
      
      // 2. 逐组处理重复笔记
      int processedGroups = 0;
      int totalMerged = 0;
      
      for (final group in duplicateGroups) {
        if (group.length > 1) {
          await _mergeQuoteGroup(group);
          totalMerged += group.length - 1;
        }
        
        processedGroups++;
        final progress = 0.3 + (processedGroups / duplicateGroups.length * 0.4);
        _updateSyncStatus(SyncStatus.merging, 
          '正在合并重复笔记... ($processedGroups/${duplicateGroups.length})', progress);
      }
      
      debugPrint('笔记合并完成，合并了 $totalMerged 个重复笔记');
      _updateSyncStatus(SyncStatus.merging, '笔记合并完成，处理了 $totalMerged 个重复项', 0.8);
      
    } catch (e) {
      debugPrint('笔记合并失败: $e');
      _updateSyncStatus(SyncStatus.failed, '笔记合并失败: $e', 0.0);
      rethrow;
    }
  }

  /// 高级重复检测算法
  Future<List<List<dynamic>>> _detectDuplicatesAdvanced(List<dynamic> quotes) async {
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
  Future<List<dynamic>> _findSimilarQuotes(dynamic target, List<dynamic> allQuotes) async {
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
    final similarity = _calculateContentSimilarity(quote1.content, quote2.content);
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
    final words1 = _normalizeContent(content1).split(' ').where((w) => w.isNotEmpty).toSet();
    final words2 = _normalizeContent(content2).split(' ').where((w) => w.isNotEmpty).toSet();
    
    if (words1.isEmpty && words2.isEmpty) return 1.0;
    if (words1.isEmpty || words2.isEmpty) return 0.0;
    
    final intersection = words1.intersection(words2).length;
    final union = words1.union(words2).length;
    
    return intersection / union;
  }

  /// 合并一组重复笔记
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

    debugPrint('保留笔记: ${keepQuote.id}, 删除重复: ${duplicatesToDelete.map((q) => q.id).join(', ')}');

    // 删除重复笔记
    for (final duplicate in duplicatesToDelete) {
      await _databaseService.deleteQuote(duplicate.id);
    }
  }

  /// 创建同步包并发送到指定设备
  Future<String> createSyncPackage(Device targetDevice) async {
    if (_syncSendService == null) {
      throw Exception('同步服务未初始化');
    }

    try {
      // 1. 更新状态：开始打包
      _updateSyncStatus(SyncStatus.packaging, '正在打包数据...', 0.1);

      // 2. 使用备份服务创建数据包
      final backupPath = await _backupService.exportAllData(
        includeMediaFiles: true,
        onProgress: (current, total) {
          final progress = 0.1 + (current / total) * 0.4; // 10%-50%的进度用于打包
          _updateSyncStatus(SyncStatus.packaging, '正在打包数据... ($current/$total)', progress);
        },
      );

      // 3. 更新状态：开始发送
      _updateSyncStatus(SyncStatus.sending, '正在发送到目标设备...', 0.5);

      // 4. 转换设备信息
      final networkDevice = _convertToNetworkDevice(targetDevice);

      // 5. 发送文件
      final backupFile = File(backupPath);
      final sessionId = await _syncSendService!.sendFile(
        targetDevice: networkDevice,
        file: backupFile,
        onProgress: (progress, status) {
          final totalProgress = 0.5 + progress * 0.5; // 50%-100%的进度用于发送
          _updateSyncStatus(SyncStatus.sending, status, totalProgress);
        },
      );

      // 6. 完成
      _updateSyncStatus(SyncStatus.completed, '同步包发送完成', 1.0);

      // 7. 清理临时文件
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

  /// 处理接收到的同步包
  Future<void> processSyncPackage(String backupFilePath) async {
    try {
      // 1. 更新状态：开始合并
      _updateSyncStatus(SyncStatus.merging, '正在合并数据...', 0.1);

      // 2. 导入接收到的备份数据（不清空现有数据）
      await _backupService.importData(
        backupFilePath,
        clearExisting: false, // 关键：不清空现有数据，进行合并
        onProgress: (current, total) {
          final progress = 0.1 + (current / total) * 0.7; // 10%-80%的进度用于导入
          _updateSyncStatus(SyncStatus.merging, '正在导入数据... ($current/$total)', progress);
        },
      );

      // 3. 执行数据合并逻辑
      _updateSyncStatus(SyncStatus.merging, '正在处理重复数据...', 0.8);
      await _mergeNoteData();

      // 4. 完成
      _updateSyncStatus(SyncStatus.completed, '数据合并完成', 1.0);

    } catch (e) {
      _updateSyncStatus(SyncStatus.failed, '合并失败: $e', 0.0);
      rethrow;
    }
  }

  /// 更新同步状态
  void _updateSyncStatus(SyncStatus status, String message, double progress) {
    _syncStatus = status;
    _syncStatusMessage = message;
    _syncProgress = progress;
    notifyListeners();
    debugPrint('同步状态: $status - $message (${(progress * 100).toInt()}%)');
  }

  /// 转换设备信息格式
  sync.NetworkDevice _convertToNetworkDevice(Device device) {
    final deviceInfo = sync.DeviceInfo(
      alias: device.alias,
      version: '2.1',
      deviceModel: device.deviceModel ?? 'Unknown Device',
      deviceType: _convertToSyncDeviceType(device.deviceType),
      fingerprint: device.fingerprint,
      port: device.port,
      protocol: sync.ProtocolType.http,
      download: true,
    );

    return sync.NetworkDevice(
      ip: device.ip ?? '127.0.0.1',
      port: device.port,
      info: deviceInfo,
      https: false,
    );
  }

  /// 转换设备类型
  sync.DeviceType _convertToSyncDeviceType(DeviceType deviceType) {
    switch (deviceType) {
      case DeviceType.mobile:
        return sync.DeviceType.mobile;
      case DeviceType.desktop:
        return sync.DeviceType.desktop;
      case DeviceType.web:
        return sync.DeviceType.web;
      case DeviceType.headless:
        return sync.DeviceType.headless;
      case DeviceType.server:
        return sync.DeviceType.server;
    }
  }

  /// 发现附近的设备
  Future<List<Device>> discoverNearbyDevices() async {
    if (_discoveryService == null) {
      debugPrint('Discovery service not initialized');
      return [];
    }

    try {
      // 清空现有设备列表，重新开始发现
      _discoveryService!.clearDevices();

      // 发送设备公告，触发其他设备响应
      await _discoveryService!.announceDevice();

      // 等待一段时间收集响应
      await Future.delayed(const Duration(milliseconds: 2000));

      final devices = _discoveryService!.devices;
      debugPrint('发现 ${devices.length} 台设备');

      return devices;
    } catch (e) {
      debugPrint('设备发现失败: $e');
      return [];
    }
  }

  @override
  void dispose() {
    // 清理LocalSend资源
    _server?.stop();
    _localSendServer?.stop();
    _localSendProvider?.dispose();
    _syncSendService?.dispose();
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