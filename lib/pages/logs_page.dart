import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/unified_log_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_empty_view.dart';
import '../widgets/app_loading_view.dart';
import '../widgets/app_error_view.dart';
import '../utils/color_utils.dart'; // Import color_utils.dart
import '../utils/time_utils.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  // 过滤设置
  UnifiedLogLevel? _filterLevel;
  String? _filterSource;
  String? _searchQuery;
  final TextEditingController _searchController = TextEditingController();

  // 正在加载更多日志
  bool _isLoadingMore = false;

  // 分页相关
  int _currentPage = 0;
  static const int _pageSize = 50;
  final List<LogEntry> _historyLogs = [];
  bool _hasMoreLogs = true;

  // 滚动控制器
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 监听滚动事件，用于实现滚动到底部加载更多
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    super.dispose();
  }

  // 滚动监听器，用于加载更多日志
  void _scrollListener() {
    if (!_scrollController.hasClients) return;

    // 当滚动到底部时加载更多历史日志
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreLogs();
    }
  }

  // 加载更多历史日志
  Future<void> _loadMoreLogs() async {
    final logService = Provider.of<UnifiedLogService>(context, listen: false);

    // 如果没有更多日志可加载，或已在加载中，则返回
    if (!_hasMoreLogs || _isLoadingMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      // 计算要跳过的日志数量
      final offset = _currentPage * _pageSize;

      // 查询下一页日志
      final moreLogs = await logService.queryLogs(
        level: _filterLevel,
        searchText: _searchQuery,
        source: _filterSource,
        limit: _pageSize,
        offset: offset,
      );

      if (moreLogs.isEmpty) {
        // 没有更多日志
        setState(() {
          _hasMoreLogs = false;
          _isLoadingMore = false;
        });
      } else {
        // 添加新加载的日志并更新页码
        setState(() {
          _historyLogs.addAll(moreLogs);
          _currentPage++;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加载更多日志失败: $e')));
      setState(() {
        _isLoadingMore = false;
      });
      showDialog(
        context: context,
        builder: (context) => const AppErrorView(text: '加载日志失败'),
      );
    }
  }

  // 刷新日志列表
  Future<void> _refreshLogs() async {
    setState(() {
      _currentPage = 0;
      _historyLogs.clear();
      _hasMoreLogs = true;
    });

    await _loadMoreLogs();
  }

  // 过滤日志
  bool _filterLog(LogEntry log) {
    // 级别过滤
    if (_filterLevel != null && log.level != _filterLevel) {
      return false;
    }

    // 源过滤
    if (_filterSource != null && _filterSource!.isNotEmpty) {
      final source = log.source ?? '';
      if (!source.toLowerCase().contains(_filterSource!.toLowerCase())) {
        return false;
      }
    }

    // 文本搜索
    if (_searchQuery != null && _searchQuery!.isNotEmpty) {
      return log.message.toLowerCase().contains(_searchQuery!.toLowerCase()) ||
          (log.error ?? '').toLowerCase().contains(_searchQuery!.toLowerCase());
    }

    return true;
  }

  // 显示日志详情对话框
  void _showLogDetails(LogEntry log) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildLogDetailsSheet(log),
    );
  }

  // 构建日志详情底部表
  Widget _buildLogDetailsSheet(LogEntry log) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _getLogLevelIcon(log.level),
                          color: _getLogLevelColor(log.level, theme),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${log.level.name.toUpperCase()} 日志 ${log.source != null ? "[${log.source}]" : ""}',
                          style: theme.textTheme.titleMedium,
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          tooltip: '复制全部信息',
                          onPressed: () => _copyLogToClipboard(log),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '时间: ${log.timestamp.toLocal().toString()}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),

              // 详细内容（可滚动）
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // 消息
                    Text('消息:', style: theme.textTheme.labelLarge),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .applyOpacity(0.5), // Use applyOpacity
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        log.message,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),

                    // 错误信息（如果存在）
                    if (log.error != null && log.error!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        '错误:',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer.applyOpacity(
                            // Use applyOpacity
                            0.3,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          log.error!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],

                    // 堆栈跟踪（如果存在）
                    if (log.stackTrace != null &&
                        log.stackTrace!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('堆栈跟踪:', style: theme.textTheme.labelLarge),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .applyOpacity(0.5), // Use applyOpacity
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          log.stackTrace!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 复制日志内容到剪贴板
  void _copyLogToClipboard(LogEntry log) {
    final buffer = StringBuffer();
    buffer.write('时间: ${log.timestamp.toLocal().toString()}\n');
    buffer.write('级别: ${log.level.name.toUpperCase()}\n');

    if (log.source != null && log.source!.isNotEmpty) {
      buffer.write('来源: ${log.source}\n');
    }

    buffer.write('消息: ${log.message}\n');

    if (log.error != null && log.error!.isNotEmpty) {
      buffer.write('错误: ${log.error}\n');
    }

    if (log.stackTrace != null && log.stackTrace!.isNotEmpty) {
      buffer.write('堆栈跟踪: ${log.stackTrace}\n');
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('日志详情已复制到剪贴板')));
  }

  // 获取日志级别对应的图标
  IconData _getLogLevelIcon(UnifiedLogLevel level) {
    switch (level) {
      case UnifiedLogLevel.verbose:
        return Icons.text_snippet_outlined;
      case UnifiedLogLevel.debug:
        return Icons.code;
      case UnifiedLogLevel.info:
        return Icons.info_outline;
      case UnifiedLogLevel.warning:
        return Icons.warning_amber;
      case UnifiedLogLevel.error:
        return Icons.error_outline;
      case UnifiedLogLevel.none:
        return Icons.block;
    }
  }

  // 获取日志级别对应的颜色
  Color _getLogLevelColor(UnifiedLogLevel level, ThemeData theme) {
    switch (level) {
      case UnifiedLogLevel.verbose:
        return Colors.grey;
      case UnifiedLogLevel.debug:
        return Colors.teal;
      case UnifiedLogLevel.info:
        return Colors.blue;
      case UnifiedLogLevel.warning:
        return Colors.orange;
      case UnifiedLogLevel.error:
        return Colors.red;
      case UnifiedLogLevel.none:
        return theme.colorScheme.onSurface;
    }
  }

  // 构建过滤器横幅
  Widget _buildFiltersBanner() {
    final hasFilters =
        _filterLevel != null ||
        (_filterSource != null && _filterSource!.isNotEmpty) ||
        (_searchQuery != null && _searchQuery!.isNotEmpty);

    if (!hasFilters) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final List<Widget> filterChips = [];

    // 级别过滤器
    if (_filterLevel != null) {
      filterChips.add(
        Chip(
          label: Text(_filterLevel!.name.toUpperCase()),
          avatar: Icon(
            _getLogLevelIcon(_filterLevel!),
            size: 18,
            color: _getLogLevelColor(_filterLevel!, theme),
          ),
          onDeleted: () {
            setState(() {
              _filterLevel = null;
            });
            _refreshLogs();
          },
          backgroundColor: theme.colorScheme.secondaryContainer,
        ),
      );
    }

    // 源过滤器
    if (_filterSource != null && _filterSource!.isNotEmpty) {
      filterChips.add(
        Chip(
          label: Text('来源: $_filterSource'),
          avatar: const Icon(Icons.source_outlined, size: 18),
          onDeleted: () {
            setState(() {
              _filterSource = null;
            });
            _refreshLogs();
          },
          backgroundColor: theme.colorScheme.tertiaryContainer,
        ),
      );
    }

    // 搜索过滤器
    if (_searchQuery != null && _searchQuery!.isNotEmpty) {
      filterChips.add(
        Chip(
          label: Text('搜索: $_searchQuery'),
          avatar: const Icon(Icons.search, size: 18),
          onDeleted: () {
            setState(() {
              _searchQuery = null;
              _searchController.clear();
            });
            _refreshLogs();
          },
          backgroundColor: theme.colorScheme.primaryContainer,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < filterChips.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: filterChips[i],
                    ),
                ],
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _filterLevel = null;
                _filterSource = null;
                _searchQuery = null;
                _searchController.clear();
              });
              _refreshLogs();
            },
            child: const Text('清除全部'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    try {
      final theme = Theme.of(context);

      return Scaffold(
        appBar: AppBar(
          title: const Text('日志查看'),
          actions: [
            // 自动滚动按钮
            IconButton(
              icon: const Icon(Icons.filter_list),
              tooltip: '日志过滤',
              onPressed: () {
                _showFilterDialog();
              },
            ),
            IconButton(
              icon: const Icon(Icons.cleaning_services_outlined),
              tooltip: '清除日志',
              onPressed: () {
                _showClearLogsDialog();
              },
            ),
          ],
        ),
        body: Column(
          children: [
            // 搜索框
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '搜索日志...',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8.0)),
                  ),
                  suffixIcon:
                      _searchQuery != null && _searchQuery!.isNotEmpty
                          ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = null;
                              });
                              _refreshLogs();
                            },
                          )
                          : null,
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.isEmpty ? null : value;
                  });
                  // 延迟搜索，减少频繁查询
                  Future.delayed(const Duration(milliseconds: 300), () {
                    if (_searchQuery == value) {
                      _refreshLogs();
                    }
                  });
                },
                textInputAction: TextInputAction.search,
                onSubmitted: (value) {
                  setState(() {
                    _searchQuery = value.isEmpty ? null : value;
                  });
                  _refreshLogs();
                },
              ),
            ),

            // 过滤器横幅
            _buildFiltersBanner(),

            // 日志列表
            Expanded(
              child: Consumer<UnifiedLogService>(
                builder: (context, logService, child) {
                  // 获取内存中的日志（实时）与历史日志
                  final memoryLogs = logService.logs.where(_filterLog).toList();
                  final allLogs = [...memoryLogs, ..._historyLogs.where(_filterLog)];

                  return RefreshIndicator(
                    onRefresh: _refreshLogs,
                    child:
                        allLogs.isEmpty
                            ? const AppEmptyView(
                              svgAsset: 'assets/empty/empty_logs.svg',
                              text: '暂无日志',
                            )
                            : ListView.separated(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(8.0),
                              itemCount:
                                  allLogs.length +
                                  (_isLoadingMore ? 1 : 0) +
                                  (_hasMoreLogs ? 1 : 0),
                              separatorBuilder: (context, index) {
                                // 确保分隔符仅用于列表项之间，不包括加载指示器
                                if (index >= allLogs.length - 1) {
                                  return const SizedBox.shrink();
                                }
                                return Divider(
                                  height: 1,
                                  color: Theme.of(
                                    context,
                                  ).dividerColor.applyOpacity(0.5),
                                ); // Use applyOpacity
                              },
                              itemBuilder: (context, index) {
                                // 加载更多指示器
                                if (_isLoadingMore && index == allLogs.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: AppLoadingView(),
                                  );
                                }

                                // 加载更多按钮
                                if (_hasMoreLogs &&
                                    !_isLoadingMore &&
                                    index == allLogs.length) {
                                  return TextButton(
                                    onPressed: _loadMoreLogs,
                                    child: const Text('加载更多日志'),
                                  );
                                }

                                // 确保index在有效范围内
                                if (index >= allLogs.length) {
                                  return const SizedBox.shrink();
                                }

                                // 正常日志项
                                final log = allLogs[index];
                                final logColor = _getLogLevelColor(
                                  log.level,
                                  theme,
                                );

                                return InkWell(
                                  onTap: () => _showLogDetails(log),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8.0,
                                      horizontal: 4.0,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                        AppTheme.cardRadius,
                                      ),
                                      border: Border.all(
                                        color: theme.colorScheme.outline,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // 日志头部（时间和级别）
                                        Row(
                                          children: [
                                            Icon(
                                              _getLogLevelIcon(log.level),
                                              size: 16,
                                              color: logColor,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              log.level.name.toUpperCase(),
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                    color: logColor,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                            ),
                                            const SizedBox(width: 8),
                                            if (log.source != null &&
                                                log.source!.isNotEmpty)
                                              Expanded(
                                                child: Text(
                                                  '[${log.source}]',
                                                  style: theme.textTheme.labelSmall
                                                      ?.copyWith(
                                                        color: theme
                                                            .colorScheme
                                                            .onSurface
                                                            .applyOpacity(
                                                              0.7,
                                                            ), // Use applyOpacity
                                                      ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            Text(
                                              TimeUtils.formatLogTimestamp(
                                                log.timestamp,
                                              ),
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .onSurface
                                                        .applyOpacity(
                                                          0.5,
                                                        ), // Use applyOpacity
                                                    fontSize: 10,
                                                  ),
                                            ),
                                          ],
                                        ),

                                        // 日志消息
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 4.0,
                                            left: 20.0,
                                          ),
                                          child: Text(
                                            log.message,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(height: 1.2),
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),

                                        // 错误指示器（如果有）
                                        if (log.error != null &&
                                            log.error!.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4.0,
                                              left: 20.0,
                                            ),
                                            child: Text(
                                              '包含错误信息',
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: theme.colorScheme.error,
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                  );
                },
              ),
            ),

            // 底部状态栏
            Consumer<UnifiedLogService>(
              builder: (context, logService, child) {
                final memoryLogs = logService.logs.where(_filterLog).toList();
                final allLogs = [...memoryLogs, ..._historyLogs.where(_filterLog)];
                return Container(
                  color: theme.colorScheme.surface,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Text(
                    '已显示 ${allLogs.length} 条日志 • 长按日志可复制 • 点击查看详情',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                );
              },
            ),
          ],
        ),
      );
    } catch (e, stack) {
      return Scaffold(
        appBar: AppBar(title: const Text('日志查看')),
        body: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text(
                  '日志页渲染异常:\n\n${e.toString()}',
                  style: const TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 8),
                Text(
                  stack.toString(),
                  maxLines: 10,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  // 显示过滤对话框
  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildFilterBottomSheet(),
    );
  }

  // 构建过滤底部表
  Widget _buildFilterBottomSheet() {
    final theme = Theme.of(context); // 过滤状态
    late UnifiedLogLevel? tempFilterLevel = _filterLevel;
    String? tempFilterSource = _filterSource;

    // 创建用于源过滤的文本控制器，并设置初始值
    final sourceController = TextEditingController(
      text: tempFilterSource ?? '',
    );

    return StatefulBuilder(
      builder: (context, setState) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Column(
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.filter_list),
                    const SizedBox(width: 8),
                    Text('日志过滤选项', style: theme.textTheme.titleMedium),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          tempFilterLevel = null;
                          tempFilterSource = null;
                          sourceController.text = '';
                        });
                      },
                      child: const Text('重置'),
                    ),
                  ],
                ),
              ),

              // 过滤选项
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // 日志级别过滤
                    Text('按日志级别过滤', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children:
                          UnifiedLogLevel.values
                              .where(
                                (level) => level != UnifiedLogLevel.none,
                              ) // 排除"不记录"选项
                              .map(
                                (level) => FilterChip(
                                  label: Text(level.name.toUpperCase()),
                                  selected: tempFilterLevel == level,
                                  onSelected: (selected) {
                                    setState(() {
                                      tempFilterLevel = selected ? level : null;
                                    });
                                  },
                                  avatar: Icon(
                                    _getLogLevelIcon(level),
                                    color: _getLogLevelColor(level, theme),
                                    size: 18,
                                  ),
                                  backgroundColor:
                                      theme.colorScheme.surfaceContainerHighest,
                                  selectedColor:
                                      theme.colorScheme.secondaryContainer,
                                ),
                              )
                              .toList(),
                    ),

                    const SizedBox(height: 24),

                    // 源过滤
                    Text('按来源过滤', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    TextField(
                      controller: sourceController,
                      decoration: const InputDecoration(
                        hintText: '输入日志来源名称...',
                        prefixIcon: Icon(Icons.source_outlined),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        setState(() {
                          tempFilterSource = value.isEmpty ? null : value;
                        });
                      },
                    ),
                  ],
                ),
              ),

              // 底部确认取消按钮
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: theme.colorScheme.outline.applyOpacity(0.2),
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        // 应用过滤
                        this.setState(() {
                          _filterLevel = tempFilterLevel;
                          _filterSource = tempFilterSource;
                        });

                        Navigator.of(context).pop();
                        _refreshLogs();
                      },
                      child: const Text('应用'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 显示清除日志对话框
  void _showClearLogsDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('清除日志'),
            content: const Text('您想清除哪些日志？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  final logService = Provider.of<UnifiedLogService>(
                    context,
                    listen: false,
                  );
                  logService.clearMemoryLogs();

                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('内存中的日志已清除')));
                },
                child: const Text('仅清除内存日志'),
              ),
              FilledButton(
                onPressed: () async {
                  // 在异步操作前获取所需的 context 相关服务和对象
                  final navigator = Navigator.of(context);
                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                  final logService = Provider.of<UnifiedLogService>(
                    context,
                    listen: false,
                  );

                  navigator.pop();

                  // 显示加载指示器
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder:
                        (dialogContext) =>
                            const Center(child: CircularProgressIndicator()),
                  );

                  try {
                    await logService.clearAllLogs();
                    if (!mounted) return;
                    navigator.pop(); // 关闭加载指示器
                    scaffoldMessenger.showSnackBar(
                      const SnackBar(content: Text('所有日志记录已清除')),
                    );
                    setState(() {
                      _historyLogs.clear();
                      _currentPage = 0;
                      _hasMoreLogs = true;
                    });
                  } catch (e) {
                    if (!mounted) return;
                    navigator.pop(); // 关闭加载指示器
                    scaffoldMessenger.showSnackBar(
                      SnackBar(content: Text('清除日志失败: $e')),
                    );
                  }
                },
                child: const Text('清除全部日志'),
              ),
            ],
          ),
    );
  }
}
