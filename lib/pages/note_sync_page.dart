import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/localsend_service.dart';
import '../models/quote.dart';
import '../models/localsend_device.dart';
import '../models/localsend_session_status.dart';
import '../services/database_service.dart';
import '../utils/app_logger.dart';

class NoteSyncPage extends StatefulWidget {
  const NoteSyncPage({super.key});

  @override
  State<NoteSyncPage> createState() => _NoteSyncPageState();
}

class _NoteSyncPageState extends State<NoteSyncPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Quote> _selectedNotes = [];
  bool _isLoading = false;
  String _serverStatus = '未启动';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeLocalSendService();
  }

  Future<void> _initializeLocalSendService() async {
    try {
      setState(() => _isLoading = true);
      
      final databaseService = context.read<DatabaseService>();
      // LocalSendService should be initialized in main.dart and available via Provider
      
      logInfo('NoteSyncPage 初始化完成', source: 'NoteSyncPage');
    } catch (e) {
      logError('NoteSyncPage 初始化失败: $e', error: e, source: 'NoteSyncPage');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同步服务初始化失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LocalSendService>(
      builder: (context, localSendService, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('局域网同步'),
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.send), text: '发送'),
                Tab(icon: Icon(Icons.download), text: '接收'),
              ],
            ),
            actions: [
              IconButton(
                icon: Icon(
                  localSendService.isServerRunning ? Icons.stop : Icons.play_arrow,
                  color: localSendService.isServerRunning ? Colors.red : Colors.green,
                ),
                onPressed: () => _toggleServer(localSendService),
                tooltip: localSendService.isServerRunning ? '停止服务器' : '启动服务器',
              ),
            ],
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _buildServerStatusBar(localSendService),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildSendTab(localSendService),
                          _buildReceiveTab(localSendService),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildServerStatusBar(LocalSendService localSendService) {
    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (localSendService.isServerRunning) {
      statusColor = Colors.green;
      statusText = '服务器运行中';
      statusIcon = Icons.check_circle;
    } else {
      statusColor = Colors.orange;
      statusText = '服务器已停止';
      statusIcon = Icons.warning;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: statusColor.withOpacity(0.1),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 20),
          const SizedBox(width: 8),
          Text(
            statusText,
            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          if (localSendService.isScanning)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (localSendService.currentOperationMessage.isNotEmpty)
            Flexible(
              child: Text(
                localSendService.currentOperationMessage,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSendTab(LocalSendService localSendService) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '选择要发送的笔记',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _selectAllNotes,
                icon: const Icon(Icons.select_all),
                label: const Text('全选'),
              ),
              TextButton.icon(
                onPressed: _clearSelection,
                icon: const Icon(Icons.clear),
                label: const Text('清空'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _buildNotesList(),
          ),
          const SizedBox(height: 16),
          _buildSendProgressIndicator(localSendService),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_selectedNotes.isEmpty || 
                             localSendService.sessionStatus == LocalSendSessionStatus.sending)
                      ? null
                      : () => _selectTargetDevice(localSendService),
                  icon: const Icon(Icons.send),
                  label: Text('发送选中的 ${_selectedNotes.length} 条笔记'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReceiveTab(LocalSendService localSendService) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '设备发现',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: localSendService.isScanning
                      ? null
                      : () => _scanForDevices(localSendService),
                  icon: const Icon(Icons.search),
                  label: const Text('扫描设备'),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: localSendService.isServerRunning
                    ? null
                    : () => _toggleServer(localSendService),
                icon: const Icon(Icons.wifi),
                label: const Text('启动接收'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _buildDevicesList(localSendService),
          ),
          const SizedBox(height: 16),
          _buildReceiveHelpCard(),
        ],
      ),
    );
  }

  Widget _buildNotesList() {
    return Consumer<DatabaseService>(
      builder: (context, databaseService, child) {
        return StreamBuilder<List<Quote>>(
          stream: databaseService.quotesStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text('加载笔记失败: ${snapshot.error}'),
              );
            }

            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final quotes = snapshot.data!;
            if (quotes.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.note_alt_outlined, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('暂无笔记', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              );
            }

            return ListView.builder(
              itemCount: quotes.length,
              itemBuilder: (context, index) {
                final quote = quotes[index];
                final isSelected = _selectedNotes.any((q) => q.id == quote.id);

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: CheckboxListTile(
                    title: Text(
                      quote.content.length > 50
                          ? '${quote.content.substring(0, 50)}...'
                          : quote.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${quote.date} • ${quote.tagIds.length} 个标签'),
                        if (quote.deltaContent != null)
                          const Text(
                            '包含富文本内容',
                            style: TextStyle(color: Colors.blue, fontSize: 12),
                          ),
                      ],
                    ),
                    value: isSelected,
                    onChanged: (selected) {
                      setState(() {
                        if (selected == true) {
                          _selectedNotes.add(quote);
                        } else {
                          _selectedNotes.removeWhere((q) => q.id == quote.id);
                        }
                      });
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildDevicesList(LocalSendService localSendService) {
    final devices = localSendService.discoveredDevices;
    
    if (devices.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.devices_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('未发现设备', style: TextStyle(color: Colors.grey)),
            SizedBox(height: 8),
            Text(
              '点击"扫描设备"按钮搜索局域网中的设备',
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: devices.length,
      itemBuilder: (context, index) {
        final device = devices[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue,
              child: Text(
                device.alias.isNotEmpty ? device.alias[0].toUpperCase() : 'D',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            title: Text(device.alias.isNotEmpty ? device.alias : '未知设备'),
            subtitle: Text('${device.ip}:${device.port}'),
            trailing: IconButton(
              icon: const Icon(Icons.send),
              onPressed: _selectedNotes.isEmpty
                  ? null
                  : () => _sendNotesToDevice(localSendService, device),
              tooltip: '发送笔记到此设备',
            ),
          ),
        );
      },
    );
  }

  Widget _buildSendProgressIndicator(LocalSendService localSendService) {
    if (localSendService.sessionStatus != LocalSendSessionStatus.sending) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          LinearProgressIndicator(value: localSendService.currentProgress),
          const SizedBox(height: 4),
          Text(
            '发送进度: ${(localSendService.currentProgress * 100).toInt()}%',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiveHelpCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.help_outline, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  '接收说明',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '1. 确保所有设备连接到同一WiFi网络\n'
              '2. 点击"启动接收"开启接收模式\n'
              '3. 其他设备通过LocalSend发送.json格式的笔记文件\n'
              '4. 接收到的文件将自动导入到应用中',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  void _selectAllNotes() {
    final databaseService = context.read<DatabaseService>();
    final quotesStream = databaseService.quotesStream;
    
    quotesStream.first.then((quotes) {
      setState(() {
        _selectedNotes = List.from(quotes);
      });
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedNotes.clear();
    });
  }

  Future<void> _toggleServer(LocalSendService localSendService) async {
    try {
      if (localSendService.isServerRunning) {
        await localSendService.stopServer();
        setState(() => _serverStatus = '已停止');
      } else {
        await localSendService.startServer();
        setState(() => _serverStatus = '运行中');
      }
    } catch (e) {
      logError('切换服务器状态失败: $e', error: e, source: 'NoteSyncPage');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }

  Future<void> _scanForDevices(LocalSendService localSendService) async {
    try {
      await localSendService.scanForDevices();
    } catch (e) {
      logError('扫描设备失败: $e', error: e, source: 'NoteSyncPage');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('扫描设备失败: $e')),
        );
      }
    }
  }

  Future<void> _selectTargetDevice(LocalSendService localSendService) async {
    // 首先扫描设备
    await _scanForDevices(localSendService);
    
    if (!mounted) return;

    final devices = localSendService.discoveredDevices;
    if (devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未发现可用设备，请确保目标设备已开启LocalSend')),
      );
      return;
    }

    // 显示设备选择对话框
    final selectedDevice = await showDialog<LocalSendDevice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择目标设备'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: devices.length,
            itemBuilder: (context, index) {
              final device = devices[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: Text(
                    device.alias.isNotEmpty ? device.alias[0].toUpperCase() : 'D',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(device.alias.isNotEmpty ? device.alias : '未知设备'),
                subtitle: Text('${device.ip}:${device.port}'),
                onTap: () => Navigator.of(context).pop(device),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (selectedDevice != null) {
      await _sendNotesToDevice(localSendService, selectedDevice);
    }
  }

  Future<void> _sendNotesToDevice(LocalSendService localSendService, LocalSendDevice device) async {
    try {
      await localSendService.sendNotesToDevice(
        device: device,
        notes: _selectedNotes,
        onProgress: (progress) {
          // Progress is handled by the service and UI updates automatically
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功发送 ${_selectedNotes.length} 条笔记到 ${device.alias}')),
        );
        // 清空选择
        setState(() {
          _selectedNotes.clear();
        });
      }
    } catch (e) {
      logError('发送笔记失败: $e', error: e, source: 'NoteSyncPage');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败: $e')),
        );
      }
    }
  }
}