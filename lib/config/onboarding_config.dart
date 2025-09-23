import 'package:flutter/material.dart';
import '../models/onboarding_models.dart';
import '../services/api_service.dart';

/// 引导页面配置
class OnboardingConfig {
  // 引导页面列表
  static const List<OnboardingPageData> pages = [
    // 第1页：欢迎页面
    OnboardingPageData(
      title: '欢迎使用心迹',
      subtitle: '你的专属灵感摘录本',
      description: '让我们一起随心记录',
      type: OnboardingPageType.welcome,
    ),

    // 第2页：核心功能展示
    OnboardingPageData(
      title: '核心功能',
      subtitle: '发现心迹的强大能力',
      features: _coreFeatures,
      type: OnboardingPageType.features,
    ),

    // 第3页：个性化设置
    OnboardingPageData(
      title: '个性化设置',
      subtitle: '定制您的专属体验',
      description: '这些设置可以随时在应用中修改',
      type: OnboardingPageType.preferences,
    ),
  ];

  // 核心功能列表
  static const List<OnboardingFeature> _coreFeatures = [
    OnboardingFeature(
      title: '智能笔记',
      description: '支持富文本编辑，自动记录时间、位置和天气',
      icon: Icons.edit_note,
    ),
    OnboardingFeature(
      title: '每日一言',
      description: '精选名言警句，为您的一天带来灵感启发',
      icon: Icons.format_quote,
    ),
    OnboardingFeature(
      title: 'AI 洞察',
      description: '智能分析您的笔记内容，发现思维模式和情感变化',
      icon: Icons.auto_awesome,
    ),
    OnboardingFeature(
      title: '本地优先',
      description: '所有数据存储在您的设备上，确保隐私安全',
      icon: Icons.security,
    ),
  ];

  // 偏好设置列表
  static final List<OnboardingPreference<dynamic>> preferences = [
    // 一言类型选择 - 移至完成页面
    OnboardingPreference<String>(
      key: 'hitokotoTypes',
      title: '每日一言类型',
      description: '选择您感兴趣的内容类型',
      defaultValue: 'a,b,c,d,e,f,g,h,i,j,k',
      type: OnboardingPreferenceType.multiSelect,
      options: ApiService.hitokotoTypes.entries
          .map(
            (entry) => OnboardingPreferenceOption<String>(
              value: entry.key,
              label: entry.value,
            ),
          )
          .toList(),
    ),

    // 默认启动页面
    const OnboardingPreference<int>(
      key: 'defaultStartPage',
      title: '默认启动页面',
      description: '选择打开应用时首先看到的页面',
      defaultValue: 0,
      type: OnboardingPreferenceType.radio,
      options: [
        OnboardingPreferenceOption<int>(
          value: 0,
          label: '主页概览',
          description: '查看每日一言和最近笔记',
        ),
        OnboardingPreferenceOption<int>(
          value: 1,
          label: '笔记列表',
          description: '直接进入笔记管理界面',
        ),
      ],
    ),

    // 剪贴板监控
    const OnboardingPreference<bool>(
      key: 'clipboardMonitoring',
      title: '剪贴板监控',
      description: '检测剪贴板内容，方便快速添加到笔记',
      defaultValue: false,
      type: OnboardingPreferenceType.toggle,
    ),

    // 显示喜爱按钮（默认开启）
    const OnboardingPreference<bool>(
      key: 'showFavoriteButton',
      title: '显示喜爱按钮',
      description: '在笔记卡片上显示心形按钮',
      defaultValue: true,
      type: OnboardingPreferenceType.toggle,
    ),

    // 优先显示加粗内容（默认关闭）
    const OnboardingPreference<bool>(
      key: 'prioritizeBoldContent',
      title: '优先显示加粗内容',
      description: '折叠笔记时优先展示加粗文本',
      defaultValue: false,
      type: OnboardingPreferenceType.toggle,
    ),

    // 仅使用本地笔记（默认关闭）
    const OnboardingPreference<bool>(
      key: 'useLocalOnly',
      title: '仅使用本地笔记',
      description: '每日一言优先使用本地记录',
      defaultValue: false,
      type: OnboardingPreferenceType.toggle,
    ),

    // 位置服务
    const OnboardingPreference<bool>(
      key: 'locationService',
      title: '位置服务',
      description: '启用位置服务以自动记录笔记地点和获取天气信息',
      defaultValue: false,
      type: OnboardingPreferenceType.toggle,
    ),

    // 使用AI生成每日提示（默认关闭）
    const OnboardingPreference<bool>(
      key: 'todayThoughtsUseAI',
      title: '使用AI生成每日提示',
      description: '在主页显示AI生成的每日提示',
      defaultValue: false,
      type: OnboardingPreferenceType.toggle,
    ),

    // 周期报告洞察（默认关闭）
    const OnboardingPreference<bool>(
      key: 'reportInsightsUseAI',
      title: '周期报告洞察使用AI',
      description: '生成周/月度报告时使用AI洞察',
      defaultValue: false,
      type: OnboardingPreferenceType.toggle,
    ),

    // SVG 卡片生成（默认开启按现有默认设置）
    const OnboardingPreference<bool>(
      key: 'aiCardGenerationEnabled',
      title: '启用AI卡片生成 (SVG)',
      description: '为笔记生成可视化SVG卡片',
      defaultValue: true,
      type: OnboardingPreferenceType.toggle,
    ),
  ];

  // 快速操作提示
  static const List<String> quickTips = [
    '💡 单击「每日一言」可复制内容',
    '✨ 双击「每日一言」可快速添加到笔记',
    '🏷️ 使用标签来组织您的笔记',
    '🔍 支持全文搜索，快速找到目标内容',
  ];

  // 获取总页数
  static int get totalPages => pages.length;

  // 检查是否为最后一页
  static bool isLastPage(int pageIndex) => pageIndex == pages.length - 1;

  // 获取页面数据
  static OnboardingPageData getPageData(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= pages.length) {
      throw ArgumentError('Invalid page index: $pageIndex');
    }
    return pages[pageIndex];
  }
}
