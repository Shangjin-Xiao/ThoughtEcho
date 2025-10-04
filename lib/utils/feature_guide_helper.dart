import 'dart:async';

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
  /// - autoDismissDuration: 自动消失时间（默认约2.2秒）
  /// - shouldShow: 可选条件判断（返回false则中止显示）
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
  Duration autoDismissDuration = const Duration(milliseconds: 2200),
    bool Function()? shouldShow,
  }) async {
    try {
      final route = ModalRoute.of(context);
      final guideService = context.read<FeatureGuideService>();

      if (guideService.hasShown(guideId)) {
        debugPrint('功能引导 $guideId 已显示过，跳过');
        return;
      }

      final config = FeatureGuide.configs[guideId];
      if (config == null) {
        debugPrint('未找到引导配置: $guideId');
        return;
      }

      final overlayState = Overlay.maybeOf(context);
      if (overlayState == null) {
        debugPrint('未找到 Overlay，无法显示功能引导: $guideId');
        return;
      }

      await WidgetsBinding.instance.endOfFrame;

      if (!context.mounted) {
        return;
      }

      if (shouldShow != null && !shouldShow()) {
        debugPrint('功能引导 $guideId 已取消，条件不满足');
        return;
      }

      if (targetKey != null) {
        final renderBox = await _waitForTargetRender(
          targetKey,
          cancellation: () => shouldShow != null && !shouldShow(),
        );
        if (renderBox == null) {
          debugPrint('目标元素尚未渲染或已离开视图: $guideId');
          return;
        }
      }

      if (shouldShow != null && !shouldShow()) {
        debugPrint('功能引导 $guideId 在显示前被取消');
        return;
      }

      if (route != null && !route.isCurrent) {
        debugPrint('功能引导 $guideId 所属页面已切换，取消显示');
        return;
      }

      if (!overlayState.mounted) {
        debugPrint('Overlay 已卸载，无法显示功能引导: $guideId');
        return;
      }

      final guide = FeatureGuide(
        id: guideId,
        title: config.title,
        description: config.description,
        targetKey: targetKey,
        preferredPlacement: config.placement,
        offset: config.offset,
      );

      final completer = Completer<void>();
      var removed = false;
      late OverlayEntry overlayEntry;

      overlayEntry = OverlayEntry(
        builder: (context) => FeatureGuidePopover(
          guide: guide,
          autoDismissDuration: autoDismissDuration,
          onDismiss: () {
            if (removed) {
              return;
            }
            removed = true;
            overlayEntry.remove();
            guideService.markAsShown(guideId);
            if (!completer.isCompleted) {
              completer.complete();
            }
          },
          visibilityPredicate: shouldShow,
        ),
      );

      overlayState.insert(overlayEntry);
      await completer.future;
    } catch (e) {
      debugPrint('显示功能引导失败: $e');
    }
  }

  /// 批量显示多个引导（按顺序）
  /// 
  /// 参数:
  /// - context: BuildContext
  /// - guides: 引导列表 [(guideId, targetKey), ...]
  /// - shouldShow: 可选条件判断（返回false则取消后续气泡）
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
    bool Function()? shouldShow,
    Duration delayBetween = const Duration(milliseconds: 180),
    Duration autoDismissDuration = const Duration(milliseconds: 2200),
  }) async {
    if (guides.isEmpty) {
      return;
    }

    for (var i = 0; i < guides.length; i++) {
      final (guideId, targetKey) = guides[i];
      
      // 每个气泡独立等待条件满足,无超时限制
      // 只要页面还在(context mounted),就一直等待用户切回来
      while (shouldShow != null && !shouldShow()) {
        // Context 已销毁,整个序列终止
        if (context is Element && !context.mounted) {
          debugPrint('功能引导序列终止: context 已销毁');
          return;
        }
        // 等待用户切回对应页面
        await Future.delayed(const Duration(milliseconds: 200));
      }
      
      // 条件满足,显示当前引导
      // ignore: use_build_context_synchronously
      await show(
        context: context, // ignore: use_build_context_synchronously
        guideId: guideId,
        targetKey: targetKey,
        autoDismissDuration: autoDismissDuration,
        shouldShow: shouldShow,
      );
      
      if (context is Element && !context.mounted) {
        break;
      }
      
      final isLast = i == guides.length - 1;
      if (!isLast) {
        await Future.delayed(delayBetween);
      }
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

  static Future<RenderBox?> _waitForTargetRender(
    GlobalKey key, {
    Duration timeout = const Duration(milliseconds: 500),
    Duration checkInterval = const Duration(milliseconds: 16),
    bool Function()? cancellation,
  }) async {
    final stopwatch = Stopwatch()..start();

    while (stopwatch.elapsed <= timeout) {
      if (cancellation?.call() ?? false) {
        return null;
      }

      final context = key.currentContext;
      final renderBox = context?.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize && renderBox.attached) {
        return renderBox;
      }

      await Future.delayed(checkInterval);
    }

    return null;
  }
}
