import 'package:flutter/foundation.dart';

import '../services/settings_service.dart';

/// 笔记卡片视觉与布局设置聚合类。
///
/// 将分散在 [QuoteItemWidget] 和 [QuoteContent] 中的 5 项卡片相关设置
/// （显示精确时间、显示修改时间、禁用阴影、媒体样式、折叠时加粗优先）
/// 聚合为单一不可变值对象，降低 Selector 监听评估开销。
@immutable
class QuoteCardSettings {
  final bool showExactTime;
  final bool showNoteEditTime;
  final bool disableCardShadows;
  final String mediaStyle;
  final bool prioritizeBoldContent;

  const QuoteCardSettings({
    required this.showExactTime,
    required this.showNoteEditTime,
    required this.disableCardShadows,
    required this.mediaStyle,
    required this.prioritizeBoldContent,
  });

  factory QuoteCardSettings.fromSettings(SettingsService s) {
    return QuoteCardSettings(
      showExactTime: s.showExactTime,
      showNoteEditTime: s.showNoteEditTime,
      disableCardShadows: s.noteListDisableCardShadows,
      mediaStyle: s.noteCardMediaStyle,
      prioritizeBoldContent: s.prioritizeBoldContentInCollapse,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuoteCardSettings &&
          runtimeType == other.runtimeType &&
          showExactTime == other.showExactTime &&
          showNoteEditTime == other.showNoteEditTime &&
          disableCardShadows == other.disableCardShadows &&
          mediaStyle == other.mediaStyle &&
          prioritizeBoldContent == other.prioritizeBoldContent;

  @override
  int get hashCode => Object.hash(
        showExactTime,
        showNoteEditTime,
        disableCardShadows,
        mediaStyle,
        prioritizeBoldContent,
      );
}
