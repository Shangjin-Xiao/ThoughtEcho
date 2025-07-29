import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:thoughtecho/common/model/device.dart';
import 'package:thoughtecho/services/localsend/provider/network/nearby_devices_provider.dart';
import 'package:thoughtecho/services/localsend/provider/network/server/server_provider.dart';
import 'package:thoughtecho/services/localsend/provider/selection/send_provider.dart';
import 'package:thoughtecho/services/backup_restore_service.dart'; // 假设这是您的备份服务

/// 笔记同步页面
/// 
/// 提供设备发现、笔记发送和接收功能的用户界面
class NoteSyncPage extends ConsumerStatefulWidget {
  const NoteSyncPage({super.key});

  @override
  ConsumerState<NoteSyncPage> createState() => _NoteSyncPageState();
}

class _NoteSyncPageState extends ConsumerState<NoteSyncPage> {
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    // WidgetsBinding.instance.addPostFrameCallback((_) => _initializeSyncService());
  }

  Future<void> _initializeSyncService() async {
    try {
      // Start the server
      await ref.notifier(serverProvider).startServerFromSettings();
      // Start listening for devices
      ref.redux(nearbyDevicesProvider).dispatchAsync(StartMulticastListener());
      // Trigger a scan
      ref.redux(nearbyDevicesProvider).dispatch(StartMulticastScan());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('启动同步服务失败: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    // Stop the server when the page is disposed
    ref.notifier(serverProvider).stopServer();
    super.dispose();
  }

  Future<void> _sendNotesToDevice(Device device) async {
    setState(() {
      _isSending = true;
    });

    try {
      // 1. Use the backup service to create a temporary file
      final backupService = BackupRestoreService(); // 您可能需要通过依赖注入获取此服务
      final backupFile = await backupService.createBackupFile(); // 假设此方法返回一个File对象

      if (backupFile == null) {
        throw Exception('创建备份文件失败');
      }

      // 2. Use the send_provider to send the file
      await ref.redux(sendProvider).dispatchAsync(
            SendAction(
              target: device,
              files: [backupFile],
              showInHistory: true,
            ),
          );

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
    final nearbyDevicesState = ref.watch(nearbyDevicesProvider);
    final nearbyDevices = nearbyDevicesState.devices.values.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('笔记同步'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: nearbyDevicesState.runningIps.isNotEmpty
                ? null
                : () => ref.redux(nearbyDevicesProvider).dispatch(StartMulticastScan()),
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
                if (nearbyDevicesState.runningIps.isNotEmpty) ...[
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
                  Text('发现 ${nearbyDevices.length} 台设备'),
                ],
              ],
            ),
          ),

          // 设备列表
          Expanded(
            child: nearbyDevices.isEmpty
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
                    itemCount: nearbyDevices.length,
                    itemBuilder: (context, index) {
                      final device = nearbyDevices[index];
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