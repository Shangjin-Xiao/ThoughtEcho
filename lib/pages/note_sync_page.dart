import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/services/backup_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/ai_analysis_database_service.dart';
import 'package:thoughtecho/services/note_sync_service.dart';
import 'package:thoughtecho/models/localsend_device.dart';

/// 笔记同步页面
/// 
/// 提供设备发现、笔记发送和接收功能的用户界面
class NoteSyncPage extends StatefulWidget {
  const NoteSyncPage({super.key});

  @override
  State<NoteSyncPage> createState() => _NoteSyncPageState();
}

class _NoteSyncPageState extends State<NoteSyncPage> {
  bool _isSending = false;
  bool _isScanning = false;
  List<Device> _nearbyDevices = [];
  NoteSyncService? _syncService;

  @override
  void initState() {
    super.initState();
    _initializeSyncService();
  }

  Future<void> _initializeSyncService() async {
    try {
      // Get services from Provider
      final databaseService = Provider.of<DatabaseService>(context, listen: false);
      final settingsService = Provider.of<SettingsService>(context, listen: false);
      final aiAnalysisDbService = Provider.of<AIAnalysisDatabaseService>(context, listen: false);
      
      // Create backup service
      final backupService = BackupService(
        databaseService: databaseService,
        settingsService: settingsService,
        aiAnalysisDbService: aiAnalysisDbService,
      );
      
      // Initialize the sync service
      _syncService = NoteSyncService(
        backupService: backupService,
        databaseService: databaseService,
        settingsService: settingsService,
        aiAnalysisDbService: aiAnalysisDbService,
      );
      
      await _syncService!.initialize();
      await _syncService!.startServer();
      
      // Start scanning for devices
      _startDeviceScan();
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('启动同步服务失败: $e')),
        );
      }
    }
  }

  Future<void> _startDeviceScan() async {
    if (_syncService == null) return;
    
    setState(() {
      _isScanning = true;
    });

    try {
      final devices = await _syncService!.discoverNearbyDevices();
      setState(() {
        _nearbyDevices = devices;
        _isScanning = false;
      });
    } catch (e) {
      setState(() {
        _isScanning = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('搜索设备失败: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _syncService?.stopServer();
    super.dispose();
  }

  Future<void> _sendNotesToDevice(Device device) async {
    setState(() {
      _isSending = true;
    });

    try {
      // Send notes using the sync service
      await _syncService!.sendNotesToDevice(device);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('笔记发送成功！')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('笔记同步'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isScanning ? null : _startDeviceScan,
          ),
        ],
      ),
      body: Column(
        children: [
          // 状态指示器
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                if (_isScanning) ...[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  const Text('正在搜索附近设备...'),
                ] else ...[
                  Icon(
                    Icons.devices,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text('发现 ${_nearbyDevices.length} 台设备'),
                ],
              ],
            ),
          ),

          // 设备列表
          Expanded(
            child: _nearbyDevices.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.devices_other, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          '未发现附近设备',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '确保目标设备也打开了ThoughtEcho\n并且在同一网络中',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _nearbyDevices.length,
                    itemBuilder: (context, index) {
                      final device = _nearbyDevices[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            child: Icon(
                              _getDeviceIcon(device.deviceType),
                              color: Colors.white,
                            ),
                          ),
                          title: Text(device.alias),
                          subtitle: Text('${device.ip}:${device.port}'),
                          trailing: _isSending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : IconButton(
                                  icon: const Icon(Icons.send),
                                  onPressed: () => _sendNotesToDevice(device),
                                ),
                        ),
                      );
                    },
                  ),
          ),

          // 底部说明
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '使用说明',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '• 点击设备右侧的发送按钮来分享你的笔记\n'
                      '• 接收到的笔记会自动与现有笔记合并\n'
                      '• 重复的笔记会保留最新版本\n'
                      '• 确保两台设备都连接到同一WiFi网络',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getDeviceIcon(DeviceType deviceType) {
    switch (deviceType) {
      case DeviceType.mobile:
        return Icons.smartphone;
      case DeviceType.desktop:
        return Icons.computer;
      case DeviceType.web:
        return Icons.web;
      case DeviceType.server:
        return Icons.dns;
      case DeviceType.headless:
        return Icons.memory;
    }
  }
}