import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/feature_guide.dart';
import '../services/feature_guide_service.dart';
import '../widgets/feature_guide_popover.dart';

/// 功能引导助手类
/// 提供简单的 API 来显示功能引导提示
class FeatureGuideHelper {
  /// 显示功能引导气泡
  /// 
  /// 参数:
  /// - context: BuildContext
  /// - guideId: 引导唯一标识符（如 'homepage_daily_quote'）
  /// - targetKey: 目标元素的 GlobalKey（可选，如果不提供则居中显示）
  /// - autoDismissDuration: 自动消失时间（默认5秒）
  /// 
  /// 使用示例:
  /// ```dart
  /// final _quoteKey = GlobalKey();
  /// 
  /// @override
  /// void initState() {
  ///   super.initState();
  ///   WidgetsBinding.instance.addPostFrameCallback((_) {
  ///     FeatureGuideHelper.show(
  ///       context: context,
  ///       guideId: 'homepage_daily_quote',
  ///       targetKey: _quoteKey,
  ///     );
  ///   });
  /// }
  /// ```
  static Future<void> show({
    required BuildContext context,
    required String guideId,
    GlobalKey? targetKey,
    Duration autoDismissDuration = const Duration(seconds: 5),
  }) async {
    try {
      // 获取引导服务
      final guideService = context.read<FeatureGuideService>();

      // 检查是否已显示过
      if (guideService.hasShown(guideId)) {
        debugPrint('功能引导 $guideId 已显示过，跳过');
        return;
      }

      // 获取引导配置
      final config = FeatureGuide.configs[guideId];
      if (config == null) {
        debugPrint('未找到引导配置: $guideId');
        return;
      }

      // 延迟更长时间，确保页面完全渲染完成
      await Future.delayed(const Duration(milliseconds: 600));

      // 检查 context 是否还有效
      if (!context.mounted) return;
      
      // 如果有 targetKey，等待其渲染
      if (targetKey != null) {
        final renderBox = targetKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox == null) {
          debugPrint('目标元素尚未渲染: $guideId');
          return;
        }
      }

      // 创建引导对象
      final guide = FeatureGuide(
        id: guideId,
        title: config.title,
        description: config.description,
        targetKey: targetKey,
      );

      // 显示 Popover 气泡
      final overlay = Overlay.of(context);
      late OverlayEntry overlayEntry;

      overlayEntry = OverlayEntry(
        builder: (context) => FeatureGuidePopover(
          guide: guide,
          autoDismissDuration: autoDismissDuration,
          onDismiss: () {
            overlayEntry.remove();
            // 标记为已显示
            guideService.markAsShown(guideId);
          },
        ),
      );

      overlay.insert(overlayEntry);
    } catch (e) {
      debugPrint('显示功能引导失败: $e');
    }
  }

  /// 批量显示多个引导（按顺序）
  /// 
  /// 参数:
  /// - context: BuildContext
  /// - guides: 引导列表 [(guideId, targetKey), ...]
  /// - delayBetween: 每个引导之间的延迟时间
  /// 
  /// 使用示例:
  /// ```dart
  /// FeatureGuideHelper.showSequence(
  ///   context: context,
  ///   guides: [
  ///     ('note_page_filter', _filterKey),
  ///     ('note_page_favorite', _favoriteKey),
  ///   ],
  /// );
  /// ```
  static Future<void> showSequence({
    required BuildContext context,
    required List<(String, GlobalKey?)> guides,
    Duration delayBetween = const Duration(milliseconds: 800),
    Duration autoDismissDuration = const Duration(seconds: 4),
  }) async {
    for (final (guideId, targetKey) in guides) {
      await show(
        context: context,
        guideId: guideId,
        targetKey: targetKey,
        autoDismissDuration: autoDismissDuration,
      );
      await Future.delayed(delayBetween);
    }
  }

  /// 重置某个引导（用于测试或重新显示）
  static Future<void> reset(BuildContext context, String guideId) async {
    if (!context.mounted) return;
    final guideService = context.read<FeatureGuideService>();
    await guideService.resetGuide(guideId);
  }

  /// 重置所有引导（用于测试）
  static Future<void> resetAll(BuildContext context) async {
    if (!context.mounted) return;
    final guideService = context.read<FeatureGuideService>();
    await guideService.resetAllGuides();
  }

  /// 检查某个引导是否已显示
  static bool hasShown(BuildContext context, String guideId) {
    final guideService = context.read<FeatureGuideService>();
    return guideService.hasShown(guideId);
  }

  /// 获取所有已显示的引导列表
  static List<String> getShownGuides(BuildContext context) {
    final guideService = context.read<FeatureGuideService>();
    return guideService.getShownGuides();
  }
}
