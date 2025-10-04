import 'package:flutter/material.dart';

/// 引导提示的预设位置偏好
enum FeatureGuidePlacement {
  auto,
  above,
  below,
  left,
  right,
}

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
      title: '每日一言小技巧',
      description: '单击可快速复制内容\n双击可快速添加到笔记',
      placement: FeatureGuidePlacement.above,
    ),

    // 记录页
    'note_page_filter': FeatureGuideConfig(
      title: '筛选与排序',
      description: '点击这里可以筛选和排序你的笔记\n支持按标签、天气、时间等多种方式',
    ),
    'note_page_favorite': FeatureGuideConfig(
      title: '喜爱标记',
      description: '点击心形图标可以标记喜爱\n在筛选中可以按喜爱度排序',
    ),
    'note_page_expand': FeatureGuideConfig(
      title: '展开/折叠笔记',
      description: '双击卡片可以展开查看完整内容\n再次双击即可折叠',
    ),

    // 全屏编辑器
    'editor_metadata': FeatureGuideConfig(
      title: '编辑笔记元数据',
      description: '点击这里可以编辑笔记的标签、分类等信息',
    ),

    // 设置页
    'settings_preferences': FeatureGuideConfig(
      title: '偏好设置',
      description: '这里可以开启"加粗内容优先显示"等个性化设置',
      placement: FeatureGuidePlacement.above,
    ),
    'settings_startup': FeatureGuideConfig(
      title: '默认启动页面',
      description: '可以设置应用启动时默认打开的页面',
    ),
    'settings_theme': FeatureGuideConfig(
      title: '主题设置',
      description: '这里可以自定义应用的主题颜色和外观',
    ),
  };
}

/// 功能引导配置（简化版，不包含运行时的 Key）
class FeatureGuideConfig {
  final String title;
  final String description;
  final FeatureGuidePlacement placement;

  const FeatureGuideConfig({
    required this.title,
    required this.description,
    this.placement = FeatureGuidePlacement.auto,
  });
}
