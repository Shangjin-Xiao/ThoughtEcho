import 'package:flutter/material.dart';
import '../gen_l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../utils/color_utils.dart'; // applyOpacity 扩展方法

/// AI 功能选项的数据模型
class AiOptionItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconColor;

  const AiOptionItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
  });
}

/// 统一的 AI 功能选项菜单组件
///
/// 使用 Material 3 Card + 圆角图标样式，支持以下功能：
/// - 智能分析来源
/// - 润色文本
/// - 续写文本
/// - 深度分析
/// - 问笔记
class AiOptionsMenu extends StatelessWidget {
  /// 是否显示问笔记选项
  final bool showAskNote;

  /// 回调函数
  final VoidCallback onAnalyzeSource;
  final VoidCallback onPolishText;
  final VoidCallback onContinueText;
  final VoidCallback onAnalyzeContent;
  final VoidCallback? onAskNote;

  const AiOptionsMenu({
    super.key,
    this.showAskNote = true,
    required this.onAnalyzeSource,
    required this.onPolishText,
    required this.onContinueText,
    required this.onAnalyzeContent,
    this.onAskNote,
  });

  /// 显示 AI 选项菜单的 BottomSheet
  static Future<void> show({
    required BuildContext context,
    bool showAskNote = true,
    required VoidCallback onAnalyzeSource,
    required VoidCallback onPolishText,
    required VoidCallback onContinueText,
    required VoidCallback onAnalyzeContent,
    VoidCallback? onAskNote,
  }) {
    final theme = Theme.of(context);

    return showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.dialogRadius),
        ),
      ),
      builder: (BuildContext context) {
        return AiOptionsMenu(
          showAskNote: showAskNote,
          onAnalyzeSource: () {
            Navigator.pop(context);
            onAnalyzeSource();
          },
          onPolishText: () {
            Navigator.pop(context);
            onPolishText();
          },
          onContinueText: () {
            Navigator.pop(context);
            onContinueText();
          },
          onAnalyzeContent: () {
            Navigator.pop(context);
            onAnalyzeContent();
          },
          onAskNote: onAskNote != null
              ? () {
                  Navigator.pop(context);
                  onAskNote();
                }
              : null,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    final options = [
      AiOptionItem(
        icon: Icons.text_fields,
        title: l10n.smartAnalyzeSource,
        subtitle: l10n.smartAnalyzeSourceDesc,
        onTap: onAnalyzeSource,
        iconColor: theme.colorScheme.tertiary,
      ),
      AiOptionItem(
        icon: Icons.brush,
        title: l10n.polishText,
        subtitle: l10n.polishTextDesc,
        onTap: onPolishText,
        iconColor: theme.colorScheme.secondary,
      ),
      AiOptionItem(
        icon: Icons.add_circle_outline,
        title: l10n.continueWriting,
        subtitle: l10n.continueWritingDesc,
        onTap: onContinueText,
        iconColor: theme.colorScheme.primary,
      ),
      AiOptionItem(
        icon: Icons.analytics,
        title: l10n.deepAnalysis,
        subtitle: l10n.deepAnalysisDesc,
        onTap: onAnalyzeContent,
        iconColor: theme.colorScheme.error,
      ),
      if (showAskNote && onAskNote != null)
        AiOptionItem(
          icon: Icons.chat,
          title: l10n.askNote,
          subtitle: l10n.askNoteDesc,
          onTap: onAskNote!,
          iconColor: theme.colorScheme.primary,
        ),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 拖拽指示条
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.applyOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // 标题
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.auto_awesome,
                        size: 20,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      l10n.aiAssistant,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              // 功能选项卡片网格
              ...options.map((option) => _buildOptionCard(context, option)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionCard(BuildContext context, AiOptionItem option) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.applyOpacity(0.5),
            width: 1,
          ),
        ),
        child: InkWell(
          onTap: option.onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // 圆角图标容器
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: (option.iconColor ?? theme.colorScheme.primary)
                        .applyOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    option.icon,
                    size: 24,
                    color: option.iconColor ?? theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                // 文本内容
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        option.subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // 箭头指示
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
