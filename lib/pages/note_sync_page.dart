import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:thoughtecho/services/note_sync_service.dart';
import 'package:thoughtecho/services/localsend/models/device.dart';
import 'package:thoughtecho/utils/sync_network_tester.dart';
import 'package:thoughtecho/services/device_identity_manager.dart';

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
  bool _isSending = false; // 是否存在发送任务（全局禁用其他按钮用）
  String? _sendingFingerprint; // 当前正在发送的设备指纹，仅该行显示加载指示
  bool _isInitializing = true;
  String _initializationError = '';
  NoteSyncService? _syncService;
  String? _localFingerprint; // 本机完整指纹
  String? _localShortFingerprint; // 本机短指纹 #XXXXXX
  // 流式发现新增字段
  StreamSubscription<List<Device>>? _discoverySub;
  VoidCallback? _cancelDiscovery;
  int _discoveryRemainingMs = 0;
  Timer? _discoveryCountdownTimer;
  static const int _uiDiscoveryTimeoutMs =
      30000; // 与 defaultDiscoveryTimeout 对齐
  bool _syncDialogVisible = false;
  bool _sendIncludeMedia = true; // 发送时是否包含媒体文件（用户可选）
  // 旧的接收确认弹窗标记已移除；审批与进度合并为单一对话框
  
  // 还原模式枚举（备份还原页中支持 LWW 合并导入，此处复用时可参考）
  // enum RestoreMode { overwrite, merge }

  @override
  void initState() {
    super.initState();
    _initializeSyncService();
  _loadLocalFingerprint();
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

        // 初始化完成后立即开始设备发现（用户期望：进入页面即开始发现）
        // 使用微任务确保状态更新后再启动，避免与初始化状态冲突
        Future.microtask(() {
          if (mounted) {
            _startDeviceDiscovery();
          }
        });
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

  Future<void> _loadLocalFingerprint() async {
    try {
      // 延迟到下一帧，避免与Provider读取竞争
      await Future.delayed(Duration.zero);
      final fp = await DeviceIdentityManager.I.getFingerprint();
      if (!mounted) return;
      setState(() {
        _localFingerprint = fp;
        _localShortFingerprint = _shortFingerprint(fp);
      });
    } catch (_) {
      // 忽略失败，保持为空
    }
  }

  @override
  void dispose() {
    // 取消流式发现资源
    _cancelDiscovery?.call();
    _discoverySub?.cancel();
    _discoveryCountdownTimer?.cancel();
    _stopSyncService();
    super.dispose();
  }

  /// 返回拦截：根据当前状态提示用户
  Future<bool> _onWillPop() async {
    // 如果没有初始化或已经出错，直接允许返回
    final syncService = _syncService;
    final busySync = syncService != null &&
        (syncService.syncStatus == SyncStatus.packaging ||
            syncService.syncStatus == SyncStatus.sending ||
            syncService.syncStatus == SyncStatus.receiving ||
            syncService.syncStatus == SyncStatus.merging);
    final busy = _isScanning || _isSending || busySync;
    if (!busy) return true; // 空闲直接返回

    // 弹出确认对话框
    final shouldLeave = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: const Text('确认离开'),
              content: Text(busySync
                  ? '当前正在进行同步操作（${_getSyncStatusText(syncService.syncStatus)}），离开将中断过程并停止服务器，确认要返回吗？'
                  : _isScanning
                      ? '当前正在发现设备，离开将停止发现并关闭服务器，确认返回吗？'
                      : '当前正在发送数据，离开将中断发送并关闭服务器，确认返回吗？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('确定'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (shouldLeave) {
      // 清理扫描与服务
      _cancelDeviceDiscovery();
      await _stopSyncService();
      return true;
    }
    return false;
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
      _discoveryRemainingMs = _uiDiscoveryTimeoutMs;
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

      // 使用流式发现
      final (stream, cancel) = syncService.discoverNearbyDevicesStream(
          timeout: _uiDiscoveryTimeoutMs);
      _cancelDiscovery = cancel;
      _discoverySub = stream.listen((devices) {
        if (!mounted) return;
        setState(() {
          _nearbyDevices = List<Device>.from(devices);
        });
      }, onDone: () {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_nearbyDevices.isEmpty
                ? '未发现附近设备'
                : '发现 ${_nearbyDevices.length} 台设备'),
            duration: const Duration(seconds: 2),
          ),
        );
        setState(() {
          _isScanning = false;
          _cancelDiscovery = null;
          _discoveryCountdownTimer?.cancel();
        });
      });

      // 启动倒计时
      _discoveryCountdownTimer?.cancel();
      _discoveryCountdownTimer =
          Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() {
          _discoveryRemainingMs -= 1000;
          if (_discoveryRemainingMs <= 0) {
            _discoveryRemainingMs = 0;
            t.cancel();
          }
        });
      });
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
      // 结束由 onDone 处理；这里不抢先复位
    }
  }

  void _cancelDeviceDiscovery() {
    if (_cancelDiscovery != null) {
      _cancelDiscovery!();
      _cancelDiscovery = null;
    }
    _discoverySub?.cancel();
    _discoverySub = null;
    _discoveryCountdownTimer?.cancel();
    _discoveryCountdownTimer = null;
    if (mounted) {
      setState(() {
        _isScanning = false;
        _discoveryRemainingMs = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('设备发现已取消'),
        duration: Duration(seconds: 2),
      ));
    }
  }

  Future<void> _sendNotesToDevice(Device device) async {
    if (!mounted) return;

    // 先弹出确认对话框（是否包含媒体文件）
  bool includeMedia = _sendIncludeMedia;
  final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            bool localInclude = includeMedia;
            return StatefulBuilder(builder: (ctx, setLocal) {
              return AlertDialog(
                title: const Text('发送确认'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('将向设备 “${device.alias}” 发送全部笔记数据。'),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('包含媒体文件'),
                      subtitle: const Text('图片/音频/视频等，可能增加体积和耗时'),
                      value: localInclude,
                      onChanged: (v) => setLocal(() => localInclude = v ?? true),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () {
                      // 关键修复：把对话框中的最新勾选结果写回外层变量
                      includeMedia = localInclude;
                      Navigator.of(ctx).pop(true);
                    },
                    child: const Text('开始发送'),
                  ),
                ],
              );
            });
          },
        ) ??
        false;
    if (!confirmed) return;

    // 保存用户选择
    _sendIncludeMedia = includeMedia;

    setState(() {
      _isSending = true;
      _sendingFingerprint = device.fingerprint;
    });

    try {
      final syncService = context.read<NoteSyncService>();
      if (!includeMedia) {
        // 反馈提示：明确说明此次不包含媒体
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('将仅发送笔记文本（不含媒体文件）'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
      final sessionId = await syncService.createSyncPackage(
        device,
        includeMediaFiles: includeMedia,
      );
      if (mounted) {
        final displayId = sessionId.length <= 8
            ? sessionId
            : '${sessionId.substring(0, 8)}...';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('笔记发送启动，会话ID: $displayId')),
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
          _sendingFingerprint = null;
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
          content: SizedBox(
              height: 80, child: Center(child: CircularProgressIndicator())),
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
                  final allSuccess = result.steps.isNotEmpty &&
                      result.steps.every((s) => s.success);
                  return ExpansionTile(
                    title: Text(result.name),
                    subtitle: Text(allSuccess ? '✅ 通过' : '❌ 存在问题'),
                    children: result.steps
                        .map((step) => ListTile(
                              leading: Icon(
                                step.success ? Icons.check_circle : Icons.error,
                                color: step.success ? Colors.green : Colors.red,
                              ),
                              title: Text(step.name),
                              subtitle: Text(step.details),
                              dense: true,
                            ))
                        .toList(),
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
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) async {
        if (!didPop) {
          final allow = await _onWillPop();
          if (allow && mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
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
                        Expanded(
                            child: Text('启动失败: $_initializationError',
                                style: const TextStyle(color: Colors.red))),
                      ] else if (_isScanning) ...[
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '正在搜索... 已发现 ${_nearbyDevices.length} 台${_discoveryRemainingMs > 0 ? ' (剩余 ${(_discoveryRemainingMs / 1000).ceil()}s)' : ''}',
                        ),
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
                  // 本机短指纹标识行
                  Padding(
                    padding: const EdgeInsets.only(top: 6.0),
                    child: Row(
                      children: [
                        Tooltip(
                          message: '# 后 6 位是设备指纹，用于区分同名设备，可在两端核对是否一致。',
                          child: Icon(Icons.fingerprint,
                              size: 16,
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _localShortFingerprint == null
                              ? '本机标识获取中...'
                              : '本机标识 #$_localShortFingerprint',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.color
                                ?.withValues(alpha: 0.8),
                          ),
                        ),
                        if (_localShortFingerprint != null)
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 0),
                              minimumSize: const Size(0, 28),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              final full = _localFingerprint ?? '';
                              Clipboard.setData(ClipboardData(text: full));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('已复制指纹: $full'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            child: const Text(
                              '复制',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // 同步状态显示
                  Consumer<NoteSyncService>(
                    builder: (context, syncService, child) {
                      _maybeShowOrHideSyncDialog(syncService);
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
                              if (syncService.syncStatus ==
                                      SyncStatus.packaging ||
                                  syncService.syncStatus ==
                                      SyncStatus.sending ||
                                  syncService.syncStatus ==
                                      SyncStatus.receiving ||
                                  syncService.syncStatus ==
                                      SyncStatus.merging) ...[
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
                                      _getSyncStatusText(
                                          syncService.syncStatus),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (syncService
                                        .syncStatusMessage.isNotEmpty)
                                      Text(
                                        syncService.syncStatusMessage,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              if (syncService.syncProgress > 0 &&
                                  syncService.syncProgress < 1)
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
                          Icon(Icons.devices_other,
                              size: 64, color: Colors.grey),
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
                        final displayIp = _resolveDeviceIp(device);
                        final ipLine = displayIp != null
                            ? '$displayIp:${device.port}'
                            : 'IP未知${device.port > 0 ? ' : :${device.port}' : ''}';
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                              child: Icon(
                                _getDeviceIcon(device.deviceType),
                                color: Colors.white,
                              ),
                            ),
                            title: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    device.alias,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                _buildShortFingerprint(device.fingerprint),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 第一行保持原有纯文本格式，兼容现有测试 (find.text('192.168.x.x:port'))
                                Text(
                                  ipLine,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                if ((device.deviceModel ?? '').isNotEmpty)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(top: 2.0, bottom: 2.0),
                                    child: Text(
                                      '${_platformLabel(device.deviceType)} • ${device.deviceModel}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.color
                                            ?.withValues(alpha: 0.65),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                _buildDiscoveryBadges(device),
                              ],
                            ),
                            isThreeLine: true,
                            trailing: (_sendingFingerprint ==
                                    device.fingerprint)
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.send),
                                    tooltip:
                                        _isSending ? '正在发送其它设备...' : '发送到此设备',
                                    onPressed: _isSending
                                        ? null
                                        : () => _sendNotesToDevice(device),
                                  ),
                            onLongPress: () => _copyIpPort(ipLine),
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
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _isInitializing
              ? null
              : (_isScanning ? _cancelDeviceDiscovery : _startDeviceDiscovery),
          icon: _isInitializing
              ? const Icon(Icons.hourglass_empty)
              : _isScanning
                  ? const Icon(Icons.close)
                  : const Icon(Icons.search),
          label:
              Text(_isInitializing ? '初始化中' : (_isScanning ? '取消发现' : '发现设备')),
          tooltip: _isScanning ? '取消本次设备发现' : '开始发现附近设备',
        ),
      ),
    );
  }

  void _maybeShowOrHideSyncDialog(NoteSyncService service) {
    // 统一：审批 + 进度 合并为一个弹窗
    final active = service.awaitingUserApproval ||
        service.syncStatus == SyncStatus.packaging ||
        service.syncStatus == SyncStatus.sending ||
        service.syncStatus == SyncStatus.receiving ||
        service.syncStatus == SyncStatus.merging;

    final terminal = service.syncStatus == SyncStatus.completed ||
        service.syncStatus == SyncStatus.failed ||
        service.syncStatus == SyncStatus.idle;

    if (active && !_syncDialogVisible) {
      _syncDialogVisible = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            return StatefulBuilder(builder: (ctx, setLocal) {
              return Consumer<NoteSyncService>(
                builder: (context, s, _) {
                  final progress = s.syncProgress.clamp(0.0, 1.0);
                  final inProgress = s.syncStatus == SyncStatus.packaging ||
                      s.syncStatus == SyncStatus.sending ||
                      s.syncStatus == SyncStatus.receiving ||
                      s.syncStatus == SyncStatus.merging;
                  final awaiting = s.awaitingUserApproval;
                  final sizeMB = s.pendingReceiveTotalBytes == null
                      ? '?'
                      : (s.pendingReceiveTotalBytes! / 1024 / 1024)
                          .toStringAsFixed(1);
                  // 平滑动画：状态 / 文本变化使用 AnimatedSwitcher
                  return AlertDialog(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                    titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    title: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      child: Row(
                        key: ValueKey('title-${awaiting ? 'approval' : s.syncStatus.name}'),
                        children: [
                          Icon(
                            awaiting
                                ? Icons.handshake
                                : s.syncStatus == SyncStatus.failed
                                    ? Icons.error_outline
                                    : s.syncStatus == SyncStatus.completed
                                        ? Icons.check_circle_outline
                                        : Icons.sync,
                            color: awaiting
                                ? Theme.of(context).colorScheme.primary
                                : s.syncStatus == SyncStatus.failed
                                    ? Colors.red
                                    : s.syncStatus == SyncStatus.completed
                                        ? Colors.green
                                        : Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              awaiting
                                  ? '接收同步请求'
                                  : _getSyncStatusText(s.syncStatus),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                    content: SizedBox(
                      width: 340,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 进度条 + 百分比
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                    minHeight: 6,
                                    value: awaiting
                                        ? null
                                        : (inProgress
                                            ? (progress == 0 || progress == 1
                                                ? null
                                                : progress)
                                            : 1),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                child: Text(
                                  awaiting
                                      ? '等待'
                                      : '${(s.syncProgress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                                  key: ValueKey('pct-${s.syncStatus.name}-${(s.syncProgress*100).toInt()}'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 240),
                            child: awaiting
                                ? Column(
                                    key: const ValueKey('approval-body'),
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '设备 “${s.receiveSenderAlias ?? '对方'}” 想向你同步笔记数据（约 $sizeMB MB）。是否接受？',
                                        style: const TextStyle(fontSize: 13, height: 1.3),
                                      ),
                                      const SizedBox(height: 12),
                                      CheckboxListTile(
                                        value: s.skipSyncConfirmation,
                                        onChanged: (v) async {
                                          await s.setSkipSyncConfirmation(
                                              v ?? false);
                                          setLocal(() {});
                                        },
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        title: const Text('以后不再提示', style: TextStyle(fontSize: 12)),
                                      ),
                                    ],
                                  )
                                : SizedBox(
                                    key: const ValueKey('progress-body'),
                                    width: double.infinity,
                                    child: AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 200),
                                      child: Text(
                                        s.syncStatusMessage,
                                        key: ValueKey('msg-${s.syncStatusMessage.hashCode}'),
                                        style: const TextStyle(fontSize: 13, height: 1.25),
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      if (awaiting) ...[
                        TextButton(
                          onPressed: () {
                            s.rejectIncoming();
                            Navigator.of(ctx).pop();
                          },
                          child: const Text('拒绝'),
                        ),
                        FilledButton(
                          onPressed: () {
                            s.approveIncoming();
                          },
                          child: const Text('接受'),
                        ),
                      ] else if (inProgress &&
                          (s.syncStatus == SyncStatus.sending ||
                              s.syncStatus == SyncStatus.receiving)) ...[
                        TextButton(
                          onPressed: () {
                            if (s.syncStatus == SyncStatus.sending) {
                              s.cancelOngoingSend();
                            } else if (s.syncStatus == SyncStatus.receiving) {
                              s.cancelReceiving();
                            }
                          },
                          child: Text(
                              s.syncStatus == SyncStatus.receiving ? '取消接收' : '取消发送'),
                        ),
                      ] else if (!inProgress && !awaiting) ...[
                        TextButton(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _syncDialogVisible = false;
                          },
                          child: const Text('关闭'),
                        ),
                      ],
                    ],
                  );
                },
              );
            });
          },
        ).then((_) {
          _syncDialogVisible = false;
        });
      });
    } else if (terminal && _syncDialogVisible) {
      // 终态：更新对话框为可关闭状态（不立即强制关闭，给用户查看结果）
      if (service.syncStatus == SyncStatus.completed) {
        // 成功提示
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('同步完成')),
        );
      } else if (service.syncStatus == SyncStatus.failed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(service.syncStatusMessage),
              backgroundColor: Colors.red),
        );
      }
      // 不再自动关闭，由用户点击“关闭”按钮手动关闭，保留结果供查看
  // 终态，无额外操作
    }
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

  /// 优先返回 device.ip；如果为空尝试从发现方式中提取 HttpDiscovery 的 ip
  String? _resolveDeviceIp(Device device) {
    if (device.ip != null && device.ip!.isNotEmpty) return device.ip;
    for (final m in device.discoveryMethods) {
      if (m is HttpDiscovery && m.ip.isNotEmpty) return m.ip;
    }
    return null;
  }

  /// 构建发现方式徽章
  Widget _buildDiscoveryBadges(Device device) {
    if (device.discoveryMethods.isEmpty) {
      return Text(
        '未提供发现方式',
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
        ),
      );
    }
    final chips = device.discoveryMethods.map((m) {
      String label;
      IconData icon;
      if (m is MulticastDiscovery) {
        label = 'Multicast';
        icon = Icons.wifi_tethering;
      } else if (m is HttpDiscovery) {
        label = 'HTTP';
        icon = Icons.http;
      } else if (m is SignalingDiscovery) {
        label = 'Signal';
        icon = Icons.cloud;
      } else {
        label = 'Other';
        icon = Icons.device_unknown;
      }
      return Padding(
        padding: const EdgeInsets.only(right: 4, bottom: 2),
        child: Chip(
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
      backgroundColor:
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
          side: BorderSide(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
            width: 0.5,
          ),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          avatar: Icon(icon,
              size: 14, color: Theme.of(context).colorScheme.primary),
          label: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }).toList();
    return Wrap(spacing: 0, runSpacing: 0, children: chips);
  }

  Future<void> _copyIpPort(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已复制: $text'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {}
  }

  /// 构建简短指纹徽章（显示后 6 位），便于区分同名设备
  Widget _buildShortFingerprint(String fingerprint) {
    if (fingerprint.isEmpty) return const SizedBox.shrink();
    final short = _shortFingerprint(fingerprint);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '#$short',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSecondaryContainer,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  String _shortFingerprint(String full) {
    if (full.length <= 6) return full.toUpperCase();
    return full.substring(full.length - 6).toUpperCase();
  }

  String _platformLabel(DeviceType type) {
    switch (type) {
      case DeviceType.mobile:
        return 'Mobile';
      case DeviceType.desktop:
        return 'Desktop';
      case DeviceType.web:
        return 'Web';
      case DeviceType.server:
        return 'Server';
      case DeviceType.headless:
        return 'Headless';
    }
  }
}
