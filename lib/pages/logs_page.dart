import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/log_service.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  LogLevel? _filterLevel;
  String? _searchQuery;
  final TextEditingController _searchController = TextEditingController();
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  // 过滤日志方法
  bool _filterLog(String log, LogLevel? level, String? query) {
    if (level == null && (query == null || query.isEmpty)) {
      return true; // 没有过滤条件
    }
    
    bool levelMatch = true;
    if (level != null) {
      // 通过日志字符串中的级别标识过滤 (如 [INFO], [WARNING] 等)
      levelMatch = log.contains('[${level.name.toUpperCase()}]');
    }
    
    bool queryMatch = true;
    if (query != null && query.isNotEmpty) {
      queryMatch = log.toLowerCase().contains(query.toLowerCase());
    }
    
    return levelMatch && queryMatch;
  }

  @override
  Widget build(BuildContext context) {
    final logService = Provider.of<LogService>(context);
    final theme = Theme.of(context);
    
    // 获取过滤后的日志
    final filteredLogs = logService.logs
        .where((log) => _filterLog(log, _filterLevel, _searchQuery))
        .toList();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志查看'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: '清除所有日志',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('清除日志'),
                  content: const Text('确定要清除所有日志记录吗？此操作无法撤销。'),
                  actions: [
                    TextButton(
                      child: const Text('取消'),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    TextButton(
                      child: const Text('清除'),
                      onPressed: () {
                        logService.clearLogs();
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('日志已清除')),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
          PopupMenuButton<LogLevel?>(
            tooltip: '按日志级别过滤',
            icon: const Icon(Icons.filter_list),
            initialValue: _filterLevel,
            onSelected: (level) {
              setState(() {
                // 如果当前已选中该级别，则取消选择（显示所有级别）
                _filterLevel = level == _filterLevel ? null : level;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: null,
                child: Text('显示所有'),
              ),
              ...LogLevel.values
                  .where((level) => level != LogLevel.none) // 排除 none 级别
                  .map((level) => PopupMenuItem(
                        value: level,
                        child: Text(level.name[0].toUpperCase() + level.name.substring(1)),
                      ))
                  .toList()
            ],
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
                suffixIcon: _searchQuery != null && _searchQuery!.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = null;
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.isEmpty ? null : value;
                });
              },
            ),
          ),
          
          // 过滤信息显示
          if (_filterLevel != null || (_searchQuery != null && _searchQuery!.isNotEmpty))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  Text(
                    '过滤条件: ' +
                    (_filterLevel != null 
                      ? _filterLevel!.name.toUpperCase() 
                      : '') +
                    (_filterLevel != null && (_searchQuery != null && _searchQuery!.isNotEmpty) 
                      ? ' + ' 
                      : '') +
                    (_searchQuery != null && _searchQuery!.isNotEmpty
                      ? '"$_searchQuery"'
                      : ''),
                    style: theme.textTheme.bodySmall,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _filterLevel = null;
                        _searchQuery = null;
                        _searchController.clear();
                      });
                    },
                    child: const Text('清除过滤'),
                  ),
                ],
              ),
            ),
          
          // 日志显示区域
          Expanded(
            child: filteredLogs.isEmpty
                ? Center(
                    child: Text(
                      logService.logs.isEmpty
                          ? '没有日志记录'
                          : '没有匹配的日志记录',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(8.0),
                    itemCount: filteredLogs.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final log = filteredLogs[index];
                      
                      // 确定日志级别颜色
                      Color logColor = theme.colorScheme.onSurface;
                      if (log.contains('[ERROR]')) {
                        logColor = Colors.red;
                      } else if (log.contains('[WARNING]')) {
                        logColor = Colors.orange;
                      } else if (log.contains('[INFO]')) {
                        logColor = Colors.blue;
                      } else if (log.contains('[DEBUG]')) {
                        logColor = Colors.teal;
                      } else if (log.contains('[VERBOSE]')) {
                        logColor = Colors.grey;
                      }
                      
                      return InkWell(
                        onLongPress: () {
                          // 复制日志到剪贴板
                          Clipboard.setData(ClipboardData(text: log));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('日志已复制到剪贴板')),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            log,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: logColor,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        color: theme.colorScheme.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Text(
          '日志条数: ${filteredLogs.length}/${logService.logs.length} • 长按日志可复制',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}