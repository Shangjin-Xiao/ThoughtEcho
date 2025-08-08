import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/services/note_sync_service.dart';
import 'package:thoughtecho/services/localsend/models/device.dart';
import 'package:thoughtecho/utils/sync_network_tester.dart';

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
  bool _isInitializing = true;
  String _initializationError = '';
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
    
    // 检查服务状态并提供视觉反馈
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_syncService != null && _isInitializing) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('正在初始化同步服务...'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    });
  }

  Future<void> _initializeSyncService() async {
    if (!mounted) return; // 确保组件仍然挂载

    setState(() {
      _isInitializing = true;
      _initializationError = '';
    });

    try {
      final syncService = context.read<NoteSyncService>();
      _syncService = syncService; // 保存引用供dispose使用
      
      // 添加调试信息
      debugPrint('开始初始化同步服务...');
      
      await syncService.startServer();

      // 添加更多调试信息
      debugPrint('同步服务初始化成功，服务器已启动');
      
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });

        // 初始化完成后不自动开始设备发现，保持与测试期望一致
        // 用户可通过点击刷新按钮手动开始发现
        // _startDeviceDiscovery();
      }
    } catch (e) {
      debugPrint('启动同步服务失败: $e');
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _initializationError = e.toString();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('同步服务启动失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: '重试',
              onPressed: _initializeSyncService,
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _stopSyncService();
    super.dispose();
  }

  Future<void> _stopSyncService() async {
    try {
      // 优先使用保存的引用
      if (_syncService != null) {
        debugPrint('使用保存的引用停止同步服务...');
        await _syncService!.stopServer();
      } else {
        // 备用方案：通过context获取（但要小心context可能已失效）
        try {
          if (mounted) {
            final syncService = context.read<NoteSyncService>();
            debugPrint('使用context获取的引用停止同步服务...');
            await syncService.stopServer();
          }
        } catch (e) {
          debugPrint('通过context停止同步服务失败: $e');
        }
      }
      debugPrint('同步服务已停止');
    } catch (e) {
      debugPrint('停止同步服务失败: $e');
    } finally {
      _syncService = null; // 清理引用
    }
  }

  Future<void> _startDeviceDiscovery() async {
    if (_isScanning || !mounted) return;

    setState(() {
      _isScanning = true;
      _nearbyDevices.clear(); // 清空旧的设备列表
    });

    try {
      // 获取当前同步服务实例
      NoteSyncService? syncService;
      try {
        syncService = context.read<NoteSyncService>();
      } catch (e) {
        debugPrint('获取NoteSyncService失败: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('同步服务未就绪，请重新初始化'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
        setState(() {
          _isScanning = false;
        });
        return;
      }

      // 首先检查服务是否已初始化
      if (_isInitializing) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('同步服务正在初始化，请稍后再试'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
        setState(() {
          _isScanning = false;
        });
        return;
      }

      // 显示扫描开始提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('正在搜索附近设备...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      final devices = await syncService.discoverNearbyDevices();

      if (mounted) {
        setState(() {
          // 注意：discoverNearbyDevices() 返回的是不可修改列表，
          // 需要创建可修改副本以避免后续 clear() 操作失败
          _nearbyDevices = List<Device>.from(devices); // 创建可修改的副本
        });

        // 显示发现结果
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(devices.isEmpty ? '未发现附近设备' : '发现 ${devices.length} 台设备'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('设备发现失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('设备发现失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
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
    if (!mounted) return;

    setState(() {
      _isSending = true;
    });

    try {
      final syncService = context.read<NoteSyncService>();

      // 使用新的createSyncPackage方法
      final sessionId = await syncService.createSyncPackage(device);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('笔记发送成功！会话ID: ${sessionId.substring(0, 8)}...')),
        );
      }
    } catch (e) {
      debugPrint('发送笔记失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('发送失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
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

  /// 运行网络诊断
  Future<void> _runNetworkDiagnostics() async {
    try {
      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          title: Text('正在运行网络诊断...'),
          content: SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
        ),
      );

      // 如果发现服务未运行，提示用户先启用
      final syncService = _syncService;
      if (syncService == null) {
        if (mounted) {
          Navigator.of(context).pop();
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('提示'),
              content: const Text('同步服务尚未初始化，请返回重新进入同步页面后再试。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('确定'),
                ),
              ],
            ),
          );
        }
        return;
      }

      final results = await SyncNetworkTester.runFullNetworkTest();

      if (mounted) {
        Navigator.of(context).pop(); // 关闭加载对话框

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('网络诊断结果'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: ListView.builder(
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final result = results[index];
                  final allSuccess = result.steps.isNotEmpty && result.steps.every((s) => s.success);
                  return ExpansionTile(
                    title: Text(result.name),
                    subtitle: Text(allSuccess ? '✅ 通过' : '❌ 存在问题'),
                    children: result.steps.map((step) => ListTile(
                      leading: Icon(
                        step.success ? Icons.check_circle : Icons.error,
                        color: step.success ? Colors.green : Colors.red,
                      ),
                      title: Text(step.name),
                      subtitle: Text(step.details),
                      dense: true,
                    )).toList(),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('网络诊断失败: $e');
      if (mounted) {
        Navigator.of(context).pop(); // 关闭加载对话框
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('网络诊断失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
            icon: const Icon(Icons.network_check),
            onPressed: _runNetworkDiagnostics,
            tooltip: '网络诊断',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isScanning ? null : _startDeviceDiscovery,
            tooltip: '刷新设备列表',
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
            child: Column(
              children: [
                Row(
                  children: [
                    if (_isInitializing) ...[
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      const Text('正在启动同步服务...'),
                    ] else if (_initializationError.isNotEmpty) ...[
                      const Icon(Icons.error, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(child: Text('启动失败: $_initializationError', style: const TextStyle(color: Colors.red))),
                    ] else if (_isScanning) ...[
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

                // 同步状态显示
                Consumer<NoteSyncService>(
                  builder: (context, syncService, child) {
                    if (syncService.syncStatus != SyncStatus.idle) {
                      return Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _getSyncStatusColor(syncService.syncStatus),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            if (syncService.syncStatus == SyncStatus.packaging ||
                                syncService.syncStatus == SyncStatus.sending ||
                                syncService.syncStatus == SyncStatus.merging) ...[
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  value: syncService.syncProgress,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _getSyncStatusText(syncService.syncStatus),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (syncService.syncStatusMessage.isNotEmpty)
                                    Text(
                                      syncService.syncStatusMessage,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (syncService.syncProgress > 0 && syncService.syncProgress < 1)
                              Text(
                                '${(syncService.syncProgress * 100).toInt()}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
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

  /// 获取同步状态颜色
  Color _getSyncStatusColor(SyncStatus status) {
    switch (status) {
      case SyncStatus.idle:
        return Colors.grey;
      case SyncStatus.packaging:
        return Colors.blue;
      case SyncStatus.sending:
        return Colors.orange;
      case SyncStatus.receiving:
        return Colors.purple;
      case SyncStatus.merging:
        return Colors.indigo;
      case SyncStatus.completed:
        return Colors.green;
      case SyncStatus.failed:
        return Colors.red;
    }
  }

  /// 获取同步状态文本
  String _getSyncStatusText(SyncStatus status) {
    switch (status) {
      case SyncStatus.idle:
        return '空闲';
      case SyncStatus.packaging:
        return '正在打包数据';
      case SyncStatus.sending:
        return '正在发送';
      case SyncStatus.receiving:
        return '正在接收';
      case SyncStatus.merging:
        return '正在合并数据';
      case SyncStatus.completed:
        return '同步完成';
      case SyncStatus.failed:
        return '同步失败';
    }
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