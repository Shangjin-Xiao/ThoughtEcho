import 'package:flutter/material.dart';
import '../gen_l10n/app_localizations.dart';

/// 引导提示的预设位置偏好
enum FeatureGuidePlacement { auto, above, below, left, right }

/// 功能引导模型
/// 用于定义应用中各个功能的引导信息
class FeatureGuide {
  /// 唯一标识符，用于记录是否已显示
  final String id;

  /// 引导标题
  final String title;

  /// 引导描述内容
  final String description;

  /// 目标元素的 GlobalKey（用于定位高亮区域）
  final dynamic targetKey;

  /// 提示框相对于目标的位置偏移
  final Offset? offset;

  /// 是否在右侧显示（默认false为下方显示）
  final bool showOnRight;

  /// 是否在上方显示（默认false为下方显示）
  final bool showOnTop;

  /// 首选的显示位置
  final FeatureGuidePlacement preferredPlacement;

  const FeatureGuide({
    required this.id,
    required this.title,
    required this.description,
    this.targetKey,
    this.offset,
    this.showOnRight = false,
    this.showOnTop = false,
    this.preferredPlacement = FeatureGuidePlacement.auto,
  });

  /// 预定义的引导配置
  static const Map<String, FeatureGuideConfig> configs = {
    // 首页
    'homepage_daily_quote': FeatureGuideConfig(
      placement: FeatureGuidePlacement.above,
    ),

    // 记录页
    'note_page_filter': FeatureGuideConfig(),
    'note_page_favorite': FeatureGuideConfig(),
    'note_page_expand': FeatureGuideConfig(),

    // 全屏编辑器
    'editor_metadata': FeatureGuideConfig(),
    // 新增：全屏编辑器工具栏操作气泡
    'editor_toolbar_usage': FeatureGuideConfig(
      placement: FeatureGuidePlacement.below,
      offset: Offset(0, 8),
    ),
    'add_note_fullscreen_button': FeatureGuideConfig(
      placement: FeatureGuidePlacement.left,
    ),
    'add_note_tag_hidden': FeatureGuideConfig(
      placement: FeatureGuidePlacement.below,
    ),
    'note_item_more_share': FeatureGuideConfig(
      placement: FeatureGuidePlacement.left,
    ),

    // 设置页
    'settings_preferences': FeatureGuideConfig(
      placement: FeatureGuidePlacement.right,
      offset: Offset(-30, -10), // 右侧偏上一点，避免挡住文字
    ),
    'settings_startup': FeatureGuideConfig(
      placement: FeatureGuidePlacement.right,
      offset: Offset(-30, 5), // 右侧居中
    ),
    'settings_theme': FeatureGuideConfig(
      placement: FeatureGuidePlacement.right,
      offset: Offset(-30, 10), // 右侧偏下一点
    ),
  };

  /// 获取指定 guideId 的本地化标题
  static String getLocalizedTitle(BuildContext context, String guideId) {
    final l10n = AppLocalizations.of(context);
    switch (guideId) {
      case 'homepage_daily_quote':
        return l10n.guideHomepageDailyQuoteTitle;
      case 'note_page_filter':
        return l10n.guideNotePageFilterTitle;
      case 'note_page_favorite':
        return l10n.guideNotePageFavoriteTitle;
      case 'note_page_expand':
        return l10n.guideNotePageExpandTitle;
      case 'editor_metadata':
        return l10n.guideEditorMetadataTitle;
      case 'editor_toolbar_usage':
        return l10n.guideEditorToolbarUsageTitle;
      case 'add_note_fullscreen_button':
        return l10n.guideAddNoteFullscreenButtonTitle;
      case 'add_note_tag_hidden':
        return l10n.guideAddNoteTagHiddenTitle;
      case 'note_item_more_share':
        return l10n.guideNoteItemMoreShareTitle;
      case 'settings_preferences':
        return l10n.guideSettingsPreferencesTitle;
      case 'settings_startup':
        return l10n.guideSettingsStartupTitle;
      case 'settings_theme':
        return l10n.guideSettingsThemeTitle;
      default:
        return '';
    }
  }

  /// 获取指定 guideId 的本地化描述
  static String getLocalizedDescription(BuildContext context, String guideId) {
    final l10n = AppLocalizations.of(context);
    switch (guideId) {
      case 'homepage_daily_quote':
        return l10n.guideHomepageDailyQuoteDesc;
      case 'note_page_filter':
        return l10n.guideNotePageFilterDesc;
      case 'note_page_favorite':
        return l10n.guideNotePageFavoriteDesc;
      case 'note_page_expand':
        return l10n.guideNotePageExpandDesc;
      case 'editor_metadata':
        return l10n.guideEditorMetadataDesc;
      case 'editor_toolbar_usage':
        return l10n.guideEditorToolbarUsageDesc;
      case 'add_note_fullscreen_button':
        return l10n.guideAddNoteFullscreenButtonDesc;
      case 'add_note_tag_hidden':
        return l10n.guideAddNoteTagHiddenDesc;
      case 'note_item_more_share':
        return l10n.guideNoteItemMoreShareDesc;
      case 'settings_preferences':
        return l10n.guideSettingsPreferencesDesc;
      case 'settings_startup':
        return l10n.guideSettingsStartupDesc;
      case 'settings_theme':
        return l10n.guideSettingsThemeDesc;
      default:
        return '';
    }
  }
}

/// 功能引导配置（简化版，不包含运行时的 Key）
class FeatureGuideConfig {
  final FeatureGuidePlacement placement;
  final Offset? offset; // 位置微调偏移

  const FeatureGuideConfig({
    this.placement = FeatureGuidePlacement.auto,
    this.offset,
  });
}
