import 'package:flutter/material.dart';
import '../../gen_l10n/app_localizations.dart';

/// AI 搜索切换按钮组件
/// 
/// 在搜索框旁显示，点击切换普通搜索和 AI 语义搜索模式
class AISearchToggle extends StatelessWidget {
  final bool isAIMode;
  final VoidCallback onToggle;

  const AISearchToggle({
    super.key,
    required this.isAIMode,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return IconButton(
      icon: Icon(
        isAIMode ? Icons.auto_awesome : Icons.search,
        color: isAIMode ? theme.colorScheme.primary : null,
      ),
      tooltip: isAIMode ? l10n.aiSearchMode : l10n.normalSearchMode,
      onPressed: onToggle,
    );
  }
}
