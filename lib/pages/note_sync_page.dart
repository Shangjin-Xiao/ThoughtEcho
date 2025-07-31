import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/services/backup_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/ai_analysis_database_service.dart';
import 'package:thoughtecho/services/note_sync_service.dart';
import "package:thoughtecho/models/localsend_device.dart" as local_device;
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
  NoteSyncService? _syncService;
  bool _isInitialized = false;

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
      
      // Start server automatically when page opens
      await _syncService!.startServer();
      
      setState(() {
        _isInitialized = true;
      });

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('初始化同步服务失败: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _syncService?.dispose();
    super.dispose();
  }

  Future<void> _toggleServer() async {
    if (_syncService == null) return;

    try {
      if (_syncService!.isServerRunning) {
        await _syncService!.stopServer();
      } else {
        await _syncService!.startServer();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('服务器操作失败: $e')),
        );
      }
    }
  }

  Future<void> _discoverDevices() async {
    if (_syncService == null) return;
    await _syncService!.discoverDevices();
  }

  Future<void> _sendNotesToDevice(local_device.Device device) async {
    if (_syncService == null) return;

    try {
      // Get all notes from database
      final databaseService = Provider.of<DatabaseService>(context, listen: false);
      final notes = await databaseService.getAllNotes();
      
      if (notes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('没有笔记可发送')),
          );
        }
        return;
      }

      await _syncService!.sendNotesToDevice(device, notes);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功发送 ${notes.length} 条笔记到 ${device.alias}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送笔记失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _syncService == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('笔记同步'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('笔记同步'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ChangeNotifierProvider.value(
        value: _syncService!,
        child: Consumer<NoteSyncService>(
          builder: (context, syncService, child) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Server control section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '同步服务器',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                syncService.isServerRunning ? '服务器运行中' : '服务器已停止',
                                style: TextStyle(
                                  color: syncService.isServerRunning ? Colors.green : Colors.red,
                                ),
                              ),
                              ElevatedButton(
                                onPressed: _toggleServer,
                                child: Text(syncService.isServerRunning ? '停止服务器' : '启动服务器'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Device discovery section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '附近的设备',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              ElevatedButton.icon(
                                onPressed: syncService.isDiscovering ? null : _discoverDevices,
                                icon: syncService.isDiscovering 
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.refresh),
                                label: const Text('刷新'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            syncService.currentStatus.displayName,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Device list
                  Expanded(
                    child: syncService.discoveredDevices.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.devices, size: 64, color: Colors.grey),
                                SizedBox(height: 16),
                                Text(
                                  '未发现设备',
                                  style: TextStyle(color: Colors.grey),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  '点击刷新按钮搜索附近的设备',
                                  style: TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: syncService.discoveredDevices.length,
                            itemBuilder: (context, index) {
                              final device = syncService.discoveredDevices[index];
                              return Card(
                                child: ListTile(
                                  leading: Icon(
                                    _getDeviceIcon(device.deviceType),
                                    color: Colors.blue,
                                  ),
                                  title: Text(device.alias),
                                  subtitle: Text('${device.ip}:${device.port}'),
                                  trailing: ElevatedButton(
                                    onPressed: syncService.currentStatus == SyncStatus.sending 
                                        ? null 
                                        : () => _sendNotesToDevice(device),
                                    child: syncService.currentStatus == SyncStatus.sending
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Text('发送笔记'),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  IconData _getDeviceIcon(String deviceType) {
    switch (deviceType.toLowerCase()) {
      case 'mobile':
        return Icons.phone_android;
      case 'desktop':
        return Icons.computer;
      case 'laptop':
        return Icons.laptop;
      case 'tablet':
        return Icons.tablet;
      default:
        return Icons.device_unknown;
    }
  }
}