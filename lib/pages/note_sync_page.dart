import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
  List<Device> _nearbyDevices = [];
  bool _isScanning = false;
  bool _isSending = false;
  NoteSyncService? _syncService;

  @override
  void initState() {
    super.initState();
    _initializeSyncService();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 在这里安全地获取NoteSyncService的引用
    _syncService = context.read<NoteSyncService>();
  }

  Future<void> _initializeSyncService() async {
    try {
      final syncService = context.read<NoteSyncService>();
      await syncService.startServer();
      _startDeviceDiscovery();
    } catch (e) {
      debugPrint('启动同步服务失败: $e');
    }
  }

  @override
  void dispose() {
    _stopSyncService();
    super.dispose();
  }

  Future<void> _stopSyncService() async {
    try {
      // 使用保存的引用而不是context.read
      if (_syncService != null) {
        await _syncService!.stopServer();
      }
    } catch (e) {
      debugPrint('停止同步服务失败: $e');
    }
  }

  Future<void> _startDeviceDiscovery() async {
    setState(() {
      _isScanning = true;
    });

    try {
      final syncService = context.read<NoteSyncService>();
      final devices = await syncService.discoverNearbyDevices();
      if (mounted) {
        setState(() {
          _nearbyDevices = devices;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('设备发现失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  Future<void> _sendNotesToDevice(Device device) async {
    setState(() {
      _isSending = true;
    });

    try {
      final syncService = context.read<NoteSyncService>();
      await syncService.sendNotesToDevice(device);
      
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
            onPressed: _isScanning ? null : _startDeviceDiscovery,
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