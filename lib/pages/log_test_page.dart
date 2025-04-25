import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/log_service.dart';

class LogTestPage extends StatefulWidget {
  const LogTestPage({super.key});

  @override
  State<LogTestPage> createState() => _LogTestPageState();
}

class _LogTestPageState extends State<LogTestPage> {
  final TextEditingController _messageController = TextEditingController();
  
  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logService = Provider.of<LogService>(context, listen: false);
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志测试'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '当前日志级别: ${logService.currentLevel.name.toUpperCase()}',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                labelText: '日志消息内容',
                hintText: '输入要记录的日志消息',
                border: OutlineInputBorder(),
              ),
              minLines: 3,
              maxLines: 5,
            ),
            const SizedBox(height: 24),
            const Text('选择日志级别:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            // 日志级别按钮
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: [
                _buildLogButton(
                  context, 
                  'Verbose', 
                  Theme.of(context).colorScheme.outline,
                  () => _logMessage(logService, LogLevel.verbose)
                ),
                _buildLogButton(
                  context, 
                  'Debug', 
                  Theme.of(context).colorScheme.secondary,
                  () => _logMessage(logService, LogLevel.debug)
                ),
                _buildLogButton(
                  context, 
                  'Info', 
                  Theme.of(context).colorScheme.primary,
                  () => _logMessage(logService, LogLevel.info)
                ),
                _buildLogButton(
                  context, 
                  'Warning', 
                  Theme.of(context).colorScheme.tertiary,
                  () => _logMessage(logService, LogLevel.warning)
                ),
                _buildLogButton(
                  context, 
                  'Error', 
                  Theme.of(context).colorScheme.error,
                  () => _logMessage(logService, LogLevel.error)
                ),
              ],
            ),
            const SizedBox(height: 24),
            // 特殊测试按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.bug_report),
                  label: const Text('生成错误日志'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.errorContainer,
                    foregroundColor: theme.colorScheme.onErrorContainer,
                  ),
                  onPressed: () {
                    try {
                      // 故意引发一个异常
                      final List<String> emptyList = [];
                      // ignore: unused_local_variable
                      final item = emptyList[10]; // 这会抛出RangeError
                    } catch (e, stackTrace) {
                      logService.error(
                        '发生未处理的异常', 
                        error: e, 
                        stackTrace: stackTrace
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('生成了一条错误日志'))
                      );
                    }
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.memory),
                  label: const Text('生成大量日志'),
                  onPressed: () {
                    // 生成100条不同级别的测试日志
                    _generateBulkLogs(logService);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('生成了100条测试日志'))
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  // 构建日志级别按钮
  Widget _buildLogButton(BuildContext context, String label, Color color, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize: const Size(100, 44),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
  
  // 记录用户输入的消息
  void _logMessage(LogService logService, LogLevel level) {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入日志消息内容'))
      );
      return;
    }
    
    switch (level) {
      case LogLevel.verbose:
        logService.verbose(message);
        break;
      case LogLevel.debug:
        logService.debug(message);
        break;
      case LogLevel.info:
        logService.info(message);
        break;
      case LogLevel.warning:
        logService.warning(message);
        break;
      case LogLevel.error:
        logService.error(message);
        break;
      case LogLevel.none:
        // 不应该发生
        break;
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已记录 ${level.name} 级别日志'))
    );
  }
  
  // 生成大量测试日志
  void _generateBulkLogs(LogService logService) {
    final levels = [
      LogLevel.verbose,
      LogLevel.debug,
      LogLevel.info,
      LogLevel.warning,
      LogLevel.error
    ];
    
    for (int i = 1; i <= 100; i++) {
      final level = levels[i % levels.length];
      final message = '测试日志 #$i - ${DateTime.now().millisecondsSinceEpoch}';
      
      switch (level) {
        case LogLevel.verbose:
          logService.verbose(message);
          break;
        case LogLevel.debug:
          logService.debug(message);
          break;
        case LogLevel.info:
          logService.info(message);
          break;
        case LogLevel.warning:
          logService.warning(message);
          break;
        case LogLevel.error:
          logService.error(message);
          break;
        case LogLevel.none:
          break;
      }
    }
  }
}