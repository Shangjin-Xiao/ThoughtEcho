import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/log_service.dart'; // 导入日志服务
import 'logs_page.dart'; // 导入日志查看页面

class LogsSettingsPage extends StatelessWidget {
  const LogsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final logService = Provider.of<LogService>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('日志设置'),
        actions: [
          // 添加一个打开日志查看页面的按钮
          TextButton.icon(
            icon: const Icon(Icons.article_outlined),
            label: const Text('查看日志'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LogsPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              '选择应用记录的日志详细程度。更详细的日志有助于调试，但可能会影响性能并占用更多存储空间（如果未来实现日志文件存储）。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ),
          const Divider(),
          // 遍历所有日志级别，创建 RadioListTile
          ...LogLevel.values.map((level) {
            // 为 none 添加特殊说明
            String subtitle = '';
            switch(level) {
              case LogLevel.verbose:
                subtitle = '记录所有详细信息，用于深入调试。';
                break;
              case LogLevel.debug:
                subtitle = '记录调试相关信息。';
                break;
              case LogLevel.info:
                subtitle = '记录常规操作信息。 (推荐)';
                break;
              case LogLevel.warning:
                subtitle = '记录潜在问题或警告。';
                break;
              case LogLevel.error:
                subtitle = '仅记录错误信息。';
                break;
              case LogLevel.none:
                subtitle = '不记录任何日志。';
                break;
            }

            return RadioListTile<LogLevel>(
              title: Text(level.name[0].toUpperCase() + level.name.substring(1)), // 首字母大写
              subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
              value: level,
              groupValue: logService.currentLevel,
              onChanged: (LogLevel? value) {
                if (value != null) {
                  logService.setLogLevel(value);
                }
              },
              activeColor: theme.colorScheme.primary,
            );
          }),
        ],
      ),
    );
  }
}
