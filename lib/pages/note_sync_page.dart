import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:thoughtecho/services/note_sync_service.dart';
import 'package:thoughtecho/services/localsend/models/device.dart';
// 网络测速入口已根据用户需求隐藏，相关 import 注释保留以便未来恢复
// import 'package:thoughtecho/utils/sync_network_tester.dart';
import 'package:thoughtecho/services/device_identity_manager.dart';

class _AutoScrollText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  const _AutoScrollText(this.text, {this.style});

  @override
  State<_AutoScrollText> createState() => _AutoScrollTextState();
}

class _AutoScrollTextState extends State<_AutoScrollText> {
  final ScrollController _scrollController = ScrollController();
  bool _isAnimating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startAutoScroll());
  }

  @override
  void didUpdateWidget(covariant _AutoScrollText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      _isAnimating = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _startAutoScroll());
    }
  }

  Future<void> _startAutoScroll() async {
    if (!mounted) return;
    if (_isAnimating) return;
    _isAnimating = true;

    try {
      while (mounted) {
        if (!_scrollController.hasClients) {
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }

        final maxScroll = _scrollController.position.maxScrollExtent;
        if (maxScroll <= 0) {
          _isAnimating = false;
          return;
        }

        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) break;

        // 速度：每秒 30 像素
        final duration = Duration(milliseconds: (maxScroll * 30).toInt());
        if (_scrollController.hasClients) {
          await _scrollController.animateTo(
            maxScroll,
            duration: duration,
            curve: Curves.linear,
          );
        }
        if (!mounted) break;

        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) break;

        if (_scrollController.hasClients) {
          await _scrollController.animateTo(
            0,
            duration: duration,
            curve: Curves.linear,
          );
        }
      }
    } catch (e) {
      // 忽略动画中断等异常
    } finally {
      if (mounted) _isAnimating = false;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Text(
        widget.text,
        style: widget.style,
        softWrap: false,
        maxLines: 1,
      ),
    );
  }
}

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
  String? _currentDialogSessionId; // 当前显示对话框的会话ID，避免重复弹窗
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
                      onChanged: (v) =>
                          setLocal(() => localInclude = v ?? true),
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

    // ignore: use_build_context_synchronously (已在 await 之前捕获所需引用)
    final messenger = ScaffoldMessenger.of(context);
    // ignore: use_build_context_synchronously
    final syncService = context.read<NoteSyncService>();
    try {
      if (!includeMedia && mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('将仅发送笔记文本（不含媒体文件）'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      final sessionId = await syncService.createSyncPackage(
        device,
        includeMediaFiles: includeMedia,
      );
      if (!mounted) return;
      final displayId =
          sessionId.length <= 8 ? sessionId : '${sessionId.substring(0, 8)}...';
      messenger.showSnackBar(
        SnackBar(
            content: Text('笔记发送启动，会话ID: $displayId'),
            duration: const Duration(seconds: 3)),
      );
    } catch (e) {
      debugPrint('发送笔记失败: $e');
      if (mounted) {
        messenger.showSnackBar(
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
  // 网络诊断功能已隐藏，如需恢复可将上面实现解注释
  // 已隐藏，留空实现（保持接口，避免潜在外部调用报错）
  // ignore: unused_element
  Future<void> _runNetworkDiagnostics() async {}

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          final allow = await _onWillPop();
          // ignore: use_build_context_synchronously (allow结果与Widget生命周期无关，已检查mounted)
          if (allow && mounted) Navigator.of(context).pop(result);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('笔记同步'),
          actions: [
            // 用户需求：隐藏网络测速/诊断入口
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isScanning ? null : _startDeviceDiscovery,
              tooltip: '刷新设备列表',
            ),
          ],
        ),
        body: Column(
          children: [
            // 顶部状态指示器精简：仅保留当前发现/数量，本机指纹；同步状态由弹窗处理
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (_isInitializing) ...[
                        const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 8),
                        const Text('正在启动...'),
                      ] else if (_initializationError.isNotEmpty) ...[
                        const Icon(Icons.error, color: Colors.red, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text('启动失败: $_initializationError',
                                style: const TextStyle(
                                    color: Colors.red, fontSize: 12))),
                      ] else if (_isScanning) ...[
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _discoveryRemainingMs > 0
                                ? '搜索中... ${_nearbyDevices.length} 台 (${(_discoveryRemainingMs / 1000).ceil()}s)'
                                : '搜索中... ${_nearbyDevices.length} 台',
                          ),
                        ),
                      ] else ...[
                        Icon(
                          _nearbyDevices.isNotEmpty
                              ? Icons.devices
                              : Icons.search,
                          size: 18,
                          color:
                              _nearbyDevices.isNotEmpty ? Colors.green : null,
                        ),
                        const SizedBox(width: 6),
                        Text('发现 ${_nearbyDevices.length} 台设备'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onLongPress: () {
                      if (_localFingerprint != null) {
                        Clipboard.setData(
                            ClipboardData(text: _localFingerprint!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text('已复制本机指纹: $_localFingerprint'),
                              duration: const Duration(seconds: 2)),
                        );
                      }
                    },
                    child: Text(
                      _localShortFingerprint == null
                          ? '本机标识获取中...'
                          : '本机 #$_localShortFingerprint',
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.color
                              ?.withValues(alpha: 0.75)),
                    ),
                  ),
                  // 触发同步对话框逻辑（隐藏状态条但保留监听）
                  Consumer<NoteSyncService>(builder: (context, s, _) {
                    _maybeShowOrHideSyncDialog(s);
                    return const SizedBox.shrink();
                  }),
                ],
              ),
            ),

            // 设备列表
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _nearbyDevices.isEmpty
                    ? const Center(
                        key: ValueKey('sync-empty'),
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
                    : ListView.separated(
                        key: ValueKey(
                            'sync-device-list-${_nearbyDevices.length}-${_sendingFingerprint ?? 'idle'}'),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: _nearbyDevices.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final theme = Theme.of(context);
                          final device = _nearbyDevices[index];
                          final displayIp = _resolveDeviceIp(device);
                          final ipLine = displayIp != null
                              ? '${device.https ? 'https' : 'http'}://$displayIp:${device.port}'
                              : '网络信息未知${device.port > 0 ? ' · 端口 ${device.port}' : ''}';
                          final isSendingToThis =
                              _sendingFingerprint == device.fingerprint;

                          return AnimatedContainer(
                            key: ValueKey(device.fingerprint),
                            duration: const Duration(milliseconds: 240),
                            curve: Curves.easeOutCubic,
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              color: isSendingToThis
                                  ? theme.colorScheme.primaryContainer
                                      .withValues(alpha: 0.35)
                                  : theme.colorScheme.surface,
                              border: Border.all(
                                color: isSendingToThis
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outlineVariant,
                                width: isSendingToThis ? 1.6 : 1,
                              ),
                              boxShadow: isSendingToThis
                                  ? [
                                      BoxShadow(
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.25),
                                        blurRadius: 16,
                                        offset: const Offset(0, 6),
                                      ),
                                    ]
                                  : const [],
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              leading: CircleAvatar(
                                radius: 24,
                                backgroundColor: theme
                                    .colorScheme.primaryContainer
                                    .withValues(alpha: 0.65),
                                child: Icon(
                                  _getDeviceIcon(device.deviceType),
                                  color: theme.colorScheme.onPrimaryContainer,
                                  size: 24,
                                ),
                              ),
                              title: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _buildDeviceName(device),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildShortFingerprint(device.fingerprint),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  ipLine,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                              trailing: isSendingToThis
                                  ? const SizedBox(
                                      width: 32,
                                      height: 32,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : FilledButton.tonalIcon(
                                      icon: const Icon(Icons.send, size: 18),
                                      label: const Text('发送'),
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                      ),
                                      onPressed: _isSending
                                          ? null
                                          : () => _sendNotesToDevice(device),
                                    ),
                              onTap: _isSending
                                  ? null
                                  : () => _sendNotesToDevice(device),
                              onLongPress: () => _copyIpPort(ipLine),
                            ),
                          );
                        },
                      ),
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
        service.awaitingPeerApproval ||
        service.syncStatus == SyncStatus.packaging ||
        service.syncStatus == SyncStatus.sending ||
        service.syncStatus == SyncStatus.receiving ||
        service.syncStatus == SyncStatus.merging;

    final terminal = service.syncStatus == SyncStatus.completed ||
        service.syncStatus == SyncStatus.failed ||
        service.syncStatus == SyncStatus.idle;

    // 生成会话ID：根据当前状态和会话信息
    String? currentSessionId;
    if (active) {
      // 使用实际的会话ID或状态组合作为唯一标识
      currentSessionId = '${service.syncStatus.name}_${service.awaitingUserApproval}_${service.awaitingPeerApproval}';
    }

    // 避免重复弹窗：如果已经显示了对话框，且会话ID相同，则不重复弹出
    if (active && !_syncDialogVisible) {
      _syncDialogVisible = true;
      _currentDialogSessionId = currentSessionId;
      final dialogContext = context;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: dialogContext,
          barrierDismissible: false,
          builder: (ctx) {
            return StatefulBuilder(builder: (ctx, setLocal) {
              return Consumer<NoteSyncService>(
                builder: (context, s, _) {
                  final progress = s.syncProgress.clamp(0.0, 1.0);
                  final waitingPeer = s.awaitingPeerApproval;
                  final waitingUser = s.awaitingUserApproval;
                  final inProgress = s.syncStatus == SyncStatus.packaging ||
                      s.syncStatus == SyncStatus.sending ||
                      s.syncStatus == SyncStatus.receiving ||
                      s.syncStatus == SyncStatus.merging;

                  final bool isFailure = s.syncStatus == SyncStatus.failed;
                  final bool isSuccess = s.syncStatus == SyncStatus.completed;

                  String titleText;
                  IconData titleIcon;
                  Color? titleColor;

                  if (waitingUser) {
                    titleText = '接收同步请求';
                    titleIcon = Icons.handshake;
                    titleColor = Theme.of(context).colorScheme.primary;
                  } else if (waitingPeer) {
                    titleText = '等待对方确认';
                    titleIcon = Icons.handshake_outlined;
                    titleColor = Theme.of(context).colorScheme.primary;
                  } else if (isFailure) {
                    titleText = _getSyncStatusText(s.syncStatus);
                    titleIcon = Icons.error_outline;
                    titleColor = Colors.red;
                  } else if (isSuccess) {
                    titleText = _getSyncStatusText(s.syncStatus);
                    titleIcon = Icons.check_circle_outline;
                    titleColor = Colors.green;
                  } else {
                    titleText = _getSyncStatusText(s.syncStatus);
                    titleIcon = Icons.sync;
                    titleColor = Theme.of(context).colorScheme.primary;
                  }

                  final String percentLabel = waitingPeer || waitingUser
                      ? '等待'
                      : '${(s.syncProgress * 100).clamp(0, 100).toStringAsFixed(0)}%';
                  final double? progressValue =
                      waitingPeer || waitingUser ? null : progress;
                  final String progressMessage = waitingPeer
                      ? '已向目标设备发送同步请求，请在对方确认后继续。'
                      : s.syncStatusMessage;

                  return AlertDialog(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                    actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    title: Row(
                      children: [
                        Icon(titleIcon, color: titleColor, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            titleText,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 18),
                          ),
                        ),
                      ],
                    ),
                    content: SizedBox(
                      width: 360,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    minHeight: 8,
                                    value: progressValue,
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                percentLabel,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (waitingUser)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                        .withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        size: 20,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          '设备 "${s.receiveSenderAlias ?? '对方'}" 想同步笔记',
                                          style: TextStyle(
                                            fontSize: 14,
                                            height: 1.4,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                CheckboxListTile(
                                  value: s.skipSyncConfirmation,
                                  onChanged: (v) async {
                                    await s.setSkipSyncConfirmation(v ?? false);
                                    setLocal(() {});
                                  },
                                  dense: true,
                                  contentPadding:
                                      const EdgeInsets.only(left: 0),
                                  title: const Text('以后不再提示',
                                      style: TextStyle(fontSize: 13)),
                                  subtitle: const Text(
                                    '将自动接受来自其他设备的同步请求',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                              ],
                            )
                          else
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                progressMessage,
                                style:
                                    const TextStyle(fontSize: 14, height: 1.3),
                              ),
                            ),
                        ],
                      ),
                    ),
                    actions: [
                      if (waitingUser) ...[
                        TextButton(
                          onPressed: () {
                            s.rejectIncoming();
                            Navigator.of(ctx).pop();
                            _syncDialogVisible = false;
                            _currentDialogSessionId = null;
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
                            s.syncStatus == SyncStatus.receiving
                                ? '取消接收'
                                : '取消发送',
                          ),
                        ),
                      ] else if (!inProgress && !waitingPeer) ...[
                        TextButton(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _syncDialogVisible = false;
                            _currentDialogSessionId = null;
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
          _currentDialogSessionId = null;
        });
      });
    } else if (terminal && _syncDialogVisible) {
      // 终态：更新对话框为可关闭状态（不立即强制关闭，给用户查看结果）
      if (service.syncStatus == SyncStatus.completed) {
        // 成功提示
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('同步完成'), duration: Duration(seconds: 2)),
        );
      } else if (service.syncStatus == SyncStatus.failed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(service.syncStatusMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3)),
        );
      }
      // 不再自动关闭，由用户点击“关闭”按钮手动关闭，保留结果供查看
      // 终态，无额外操作
    }
  }

  /// 获取同步状态颜色
  // 已移除顶部状态条颜色逻辑，保留方法则会未使用，故删除

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
        return '正在合并';
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
  // 发现方式徽章 UI 已按需求移除

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

  /// 构建设备名称组件，优先展示设备型号，过长时横向滚动显示
  Widget _buildDeviceName(Device device) {
    final theme = Theme.of(context);
    final alias = device.alias.trim();
    final model = device.deviceModel?.trim() ?? '';
    final displayName = model.isNotEmpty ? model : alias;
    final showAlias = model.isNotEmpty &&
        alias.isNotEmpty &&
        alias.toLowerCase() != displayName.toLowerCase();

    final tooltipMessage = showAlias ? '$displayName\n别名：$alias' : displayName;

    final titleStyle = theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          height: 1.15,
        ) ??
        const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 16,
          height: 1.15,
        );

    final aliasStyle = theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.2,
        ) ??
        TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.2,
        );

    return Tooltip(
      message: tooltipMessage,
      waitDuration: const Duration(milliseconds: 350),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _AutoScrollText(
            displayName,
            style: titleStyle,
          ),
          if (showAlias)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _AutoScrollText(
                alias,
                style: aliasStyle,
              ),
            ),
        ],
      ),
    );
  }

  // 平台标签显示已移除
}

