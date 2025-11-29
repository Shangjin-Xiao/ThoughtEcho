import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:thoughtecho/services/note_sync_service.dart';
import 'package:thoughtecho/services/localsend/models/device.dart';
// 网络测速入口已根据用户需求隐藏，相关 import 注释保留以便未来恢复
// import 'package:thoughtecho/utils/sync_network_tester.dart';
import 'package:thoughtecho/services/device_identity_manager.dart';
import '../gen_l10n/app_localizations.dart';

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
  bool _sendIncludeMedia = true; // 发送时是否包含媒体文件（用户可选）
  bool _dialogWasTerminal = false; // 标记当前对话框是否停留在终态
  bool _dialogRestartPending = false; // 避免终态->活跃切换时重复重建
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
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.initializingSyncService),
            duration: const Duration(seconds: 2),
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
        final l10n = AppLocalizations.of(context);
        setState(() {
          _isInitializing = false;
          _initializationError = e.toString();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.syncServiceStartFailed(e.toString())),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: l10n.retry,
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

    final l10n = AppLocalizations.of(context);

    // 弹出确认对话框
    final shouldLeave = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: Text(l10n.confirmLeave),
              content: Text(busySync
                  ? l10n.leaveWhileSyncing(
                      _getSyncStatusText(syncService.syncStatus, l10n))
                  : _isScanning
                      ? l10n.leaveWhileScanning
                      : l10n.leaveWhileSending),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(l10n.cancel),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(l10n.confirm),
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

    final l10n = AppLocalizations.of(context);

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
            SnackBar(
              content: Text(l10n.syncServiceNotReady),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
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
            SnackBar(
              content: Text(l10n.syncServiceInitializing),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
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
          SnackBar(
            content: Text(l10n.searchingNearbyDevices),
            duration: const Duration(seconds: 2),
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
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_nearbyDevices.isEmpty
                ? l10n.noNearbyDevices
                : l10n.foundDevicesCount(_nearbyDevices.length)),
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
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.deviceDiscoveryFailed(e.toString())),
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
      final l10n = AppLocalizations.of(context);
      setState(() {
        _isScanning = false;
        _discoveryRemainingMs = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.deviceDiscoveryCancelled),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _sendNotesToDevice(Device device) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);

    // 先弹出确认对话框（是否包含媒体文件）
    bool includeMedia = _sendIncludeMedia;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            bool localInclude = includeMedia;
            return StatefulBuilder(builder: (ctx, setLocal) {
              return AlertDialog(
                title: Text(l10n.sendConfirmTitle),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.sendConfirmContent(device.alias)),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.includeMediaFilesOption),
                      subtitle: Text(l10n.includeMediaFilesHintSync),
                      value: localInclude,
                      onChanged: (v) =>
                          setLocal(() => localInclude = v ?? true),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text(l10n.cancel),
                  ),
                  FilledButton(
                    onPressed: () {
                      // 关键修复：把对话框中的最新勾选结果写回外层变量
                      includeMedia = localInclude;
                      Navigator.of(ctx).pop(true);
                    },
                    child: Text(l10n.startSend),
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
          SnackBar(
            content: Text(l10n.sendTextOnlyHint),
            duration: const Duration(seconds: 2),
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
            content: Text(l10n.sendStarted(displayId)),
            duration: const Duration(seconds: 3)),
      );
    } catch (e) {
      debugPrint('发送笔记失败: $e');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.sendFailedWithError(e.toString())),
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
    final l10n = AppLocalizations.of(context);
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
          title: Text(l10n.noteSync),
          actions: [
            // 用户需求：隐藏网络测速/诊断入口
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isScanning ? null : _startDeviceDiscovery,
              tooltip: l10n.refreshDeviceList,
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
                        Text(l10n.initializingService),
                      ] else if (_initializationError.isNotEmpty) ...[
                        const Icon(Icons.error, color: Colors.red, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(l10n.startFailed(_initializationError),
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
                                ? l10n.scanningDevicesWithTime(
                                    _nearbyDevices.length,
                                    (_discoveryRemainingMs / 1000).ceil())
                                : l10n.scanningDevices(_nearbyDevices.length),
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
                        Text(l10n.foundDevicesCount(_nearbyDevices.length)),
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
                              content: Text(
                                  l10n.copiedFingerprint(_localFingerprint!)),
                              duration: const Duration(seconds: 2)),
                        );
                      }
                    },
                    child: Text(
                      _localShortFingerprint == null
                          ? l10n.localDeviceLoading
                          : l10n.localDeviceId(_localShortFingerprint!),
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
                    ? Center(
                        key: const ValueKey('sync-empty'),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.devices_other,
                                size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text(
                              l10n.noNearbyDevices,
                              style: const TextStyle(
                                fontSize: 18,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.ensureDeviceOnSameNetwork,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.grey),
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
                              : '${l10n.networkInfoUnknown}${device.port > 0 ? ' · ${l10n.portNumber(device.port)}' : ''}';
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
                                      label: Text(l10n.send),
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
                          Text(
                            l10n.usageInstructionsTitle,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '• ${l10n.syncUsageInstruction1}\n'
                        '• ${l10n.syncUsageInstruction2}\n'
                        '• ${l10n.syncUsageInstruction3}\n'
                        '• ${l10n.syncUsageInstruction4}',
                        style: const TextStyle(fontSize: 12),
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
          label: Text(_isInitializing
              ? l10n.initializing
              : (_isScanning ? l10n.cancelDiscovery : l10n.discoverDevices)),
          tooltip: _isScanning
              ? l10n.cancelDiscoveryTooltip
              : l10n.startDiscoveryTooltip,
        ),
      ),
    );
  }

  void _showSyncDialog() {
    if (!mounted || _syncDialogVisible) return;

    _syncDialogVisible = true;
    _dialogWasTerminal = false;
    final dialogContext = context;
    final l10n = AppLocalizations.of(context);

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
                  titleText = l10n.receiveSyncRequest;
                  titleIcon = Icons.handshake;
                  titleColor = Theme.of(context).colorScheme.primary;
                } else if (waitingPeer) {
                  titleText = l10n.waitingPeerApproval;
                  titleIcon = Icons.handshake_outlined;
                  titleColor = Theme.of(context).colorScheme.primary;
                } else if (isFailure) {
                  titleText = _getSyncStatusText(s.syncStatus, l10n);
                  titleIcon = Icons.error_outline;
                  titleColor = Colors.red;
                } else if (isSuccess) {
                  titleText = _getSyncStatusText(s.syncStatus, l10n);
                  titleIcon = Icons.check_circle_outline;
                  titleColor = Colors.green;
                } else {
                  titleText = _getSyncStatusText(s.syncStatus, l10n);
                  titleIcon = Icons.sync;
                  titleColor = Theme.of(context).colorScheme.primary;
                }

                final String percentLabel = waitingPeer || waitingUser
                    ? l10n.waitingLabel
                    : '${(s.syncProgress * 100).clamp(0, 100).toStringAsFixed(0)}%';
                final double? progressValue =
                    waitingPeer || waitingUser ? null : progress;
                final String progressMessage =
                    waitingPeer ? l10n.syncRequestSent : s.syncStatusMessage;

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
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        l10n.deviceWantsToSync(
                                            s.receiveSenderAlias ??
                                                l10n.unknown),
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
                                contentPadding: const EdgeInsets.only(left: 0),
                                title: Text(l10n.doNotAskAgain,
                                    style: const TextStyle(fontSize: 13)),
                                subtitle: Text(
                                  l10n.autoAcceptSyncRequests,
                                  style: const TextStyle(fontSize: 11),
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
                              style: const TextStyle(fontSize: 14, height: 1.3),
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
                          _dismissSyncDialog();
                        },
                        child: Text(l10n.reject),
                      ),
                      FilledButton(
                        onPressed: () {
                          s.approveIncoming();
                        },
                        child: Text(l10n.accept),
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
                              ? l10n.cancelReceive
                              : l10n.cancelSend,
                        ),
                      ),
                    ] else if (!inProgress && !waitingPeer) ...[
                      TextButton(
                        onPressed: _dismissSyncDialog,
                        child: Text(l10n.close),
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
        _dialogWasTerminal = false;
        _dialogRestartPending = false;
      });
    });
  }

  void _dismissSyncDialog() {
    if (!_syncDialogVisible) return;
    _syncDialogVisible = false;
    _dialogWasTerminal = false;
    if (!mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
    }
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

    if (active) {
      if (_syncDialogVisible) {
        if (_dialogWasTerminal && !_dialogRestartPending) {
          _dialogRestartPending = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _dismissSyncDialog();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                _dialogRestartPending = false;
                return;
              }
              final latestService = context.read<NoteSyncService>();
              final stillActive = latestService.awaitingUserApproval ||
                  latestService.awaitingPeerApproval ||
                  latestService.syncStatus == SyncStatus.packaging ||
                  latestService.syncStatus == SyncStatus.sending ||
                  latestService.syncStatus == SyncStatus.receiving ||
                  latestService.syncStatus == SyncStatus.merging;
              _dialogRestartPending = false;
              if (stillActive) {
                _showSyncDialog();
              }
            });
          });
        } else {
          _dialogWasTerminal = false;
        }
      } else if (!_dialogRestartPending) {
        _showSyncDialog();
      }
    } else if (terminal && _syncDialogVisible) {
      _dialogWasTerminal = true;
      final l10n = AppLocalizations.of(context);
      if (service.syncStatus == SyncStatus.completed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(l10n.syncCompleted),
              duration: const Duration(seconds: 2)),
        );
      } else if (service.syncStatus == SyncStatus.failed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(service.syncStatusMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3)),
        );
      }
    }
  }

  /// 获取同步状态颜色
  // 已移除顶部状态条颜色逻辑，保留方法则会未使用，故删除

  /// 获取同步状态文本
  String _getSyncStatusText(SyncStatus status, AppLocalizations l10n) {
    switch (status) {
      case SyncStatus.idle:
        return l10n.syncStatusIdle;
      case SyncStatus.packaging:
        return l10n.syncStatusPackaging;
      case SyncStatus.sending:
        return l10n.syncStatusSending;
      case SyncStatus.receiving:
        return l10n.syncStatusReceiving;
      case SyncStatus.merging:
        return l10n.syncStatusMerging;
      case SyncStatus.completed:
        return l10n.syncStatusCompleted;
      case SyncStatus.failed:
        return l10n.syncStatusFailed;
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
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.copiedText(text)),
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
    final l10n = AppLocalizations.of(context);
    final alias = device.alias.trim();
    final model = device.deviceModel?.trim() ?? '';
    final displayName = model.isNotEmpty ? model : alias;
    final showAlias = model.isNotEmpty &&
        alias.isNotEmpty &&
        alias.toLowerCase() != displayName.toLowerCase();

    final tooltipMessage =
        showAlias ? l10n.deviceAliasAndModel(displayName, alias) : displayName;

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
