import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/unified_log_service.dart'; // 使用统一日志服务
import 'logs_page.dart'; // 导入日志查看页面
import '../utils/color_utils.dart'; // 导入颜色工具
import '../gen_l10n/app_localizations.dart';

class LogsSettingsPage extends StatelessWidget {
  const LogsSettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final logService = Provider.of<UnifiedLogService>(context);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.logSettingsTitle),
        actions: [
          // 添加一个打开日志查看页面的按钮
          TextButton.icon(
            icon: const Icon(Icons.article_outlined),
            label: Text(l10n.viewLogs),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LogsPage()),
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
              l10n.logLevelDescription,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.applyOpacity(0.7),
              ),
            ),
          ),
          const Divider(),
          RadioGroup<UnifiedLogLevel>(
            groupValue: logService.currentLevel,
            onChanged: (UnifiedLogLevel? value) {
              if (value != null) {
                logService.setLogLevel(value);
              }
            },
            child: Column(
              children: UnifiedLogLevel.values.map((level) {
                // 为 none 添加特殊说明
                String subtitle = '';
                switch (level) {
                  case UnifiedLogLevel.verbose:
                    subtitle = l10n.logLevelVerbose;
                    break;
                  case UnifiedLogLevel.debug:
                    subtitle = l10n.logLevelDebug;
                    break;
                  case UnifiedLogLevel.info:
                    subtitle = l10n.logLevelInfo;
                    break;
                  case UnifiedLogLevel.warning:
                    subtitle = l10n.logLevelWarning;
                    break;
                  case UnifiedLogLevel.error:
                    subtitle = l10n.logLevelError;
                    break;
                  case UnifiedLogLevel.none:
                    subtitle = l10n.logLevelNone;
                    break;
                }
                return RadioListTile<UnifiedLogLevel>(
                  title: Text(
                    level.name[0].toUpperCase() + level.name.substring(1),
                  ), // 首字母大写
                  subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
                  value: level,
                  activeColor: theme.colorScheme.primary,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
