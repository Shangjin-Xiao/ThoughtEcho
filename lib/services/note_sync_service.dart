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
import 'package:http/http.dart' as http;

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
  late final SimpleServer _server;

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
    // 初始化LocalSend组件
    _server = SimpleServer();
    
    // 启动服务器监听文件接收
    await _server.start(
      alias: 'ThoughtEcho-${DateTime.now().millisecondsSinceEpoch}',
      onFileReceived: (filePath) async {
        // 接收到文件后自动导入
        await receiveAndMergeNotes(filePath);
      },
    );
  }

  /// 发送笔记数据到指定设备
  Future<void> sendNotesToDevice(Device targetDevice) async {
    try {
      // 1. 使用备份服务创建数据包
      final backupPath = await _backupService.exportAllData(
        includeMediaFiles: true,
        onProgress: (current, total) {
          // 发送进度通知
          notifyListeners();
        },
      );

      // 2. 使用HTTP发送备份文件
      final backupFile = File(backupPath);
      
      // 构建上传URL
      final url = 'http://${targetDevice.ip}:${targetDevice.port}/api/localsend/v2/upload';
      
      // 创建multipart请求
      final request = http.MultipartRequest('POST', Uri.parse(url));
      request.files.add(await http.MultipartFile.fromPath('file', backupFile.path));
      
      // 发送文件
      final response = await request.send();
      
      if (response.statusCode != 200) {
        throw Exception('发送失败: ${response.statusCode}');
      }
      
    } catch (e) {
      debugPrint('发送笔记失败: $e');
      rethrow;
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
    // 简化的设备发现 - 扫描本地网络
    final devices = <Device>[];
    
    try {
      // 获取本地IP
      final interfaces = await NetworkInterface.list();
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            // 扫描同网段设备
            final subnet = addr.address.substring(0, addr.address.lastIndexOf('.'));
            
            for (int i = 1; i <= 254; i++) {
              final targetIp = '$subnet.$i';
              if (targetIp != addr.address) {
                // 尝试连接设备
                try {
                  final response = await http.get(
                    Uri.parse('http://$targetIp:53318/api/localsend/v2/info'),
                  ).timeout(const Duration(seconds: 1));
                  
                  if (response.statusCode == 200) {
                    final deviceInfo = jsonDecode(response.body);
                    devices.add(Device(
                      signalingId: null,
                      ip: targetIp,
                      version: deviceInfo['version'] ?? '2.0',
                      port: 53317,
                      https: false,
                      fingerprint: deviceInfo['fingerprint'] ?? '',
                      alias: deviceInfo['alias'] ?? 'Unknown Device',
                      deviceModel: deviceInfo['deviceModel'],
                      deviceType: DeviceType.desktop,
                      download: true,
                      discoveryMethods: {HttpDiscovery(ip: targetIp)},
                    ));
                  }
                } catch (e) {
                  // 忽略连接失败的设备
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('设备发现失败: $e');
    }
    
    return devices;
  }

  @override
  void dispose() {
    // 清理LocalSend资源
    _server.stop();
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