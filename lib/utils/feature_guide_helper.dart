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
  /// 返回值表示这个气泡**有没有真的显示出来**。调用方靠它做限流：
  /// 目标没渲染、条件不满足、已经显示过时都会返回 false，这时候不该算进配额。
  static Future<bool> show({
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
        return false;
      }

      final config = FeatureGuide.configs[guideId];
      if (config == null) {
        debugPrint('未找到引导配置: $guideId');
        return false;
      }

      final overlayState = Overlay.maybeOf(context);
      if (overlayState == null) {
        debugPrint('未找到 Overlay，无法显示功能引导: $guideId');
        return false;
      }

      await WidgetsBinding.instance.endOfFrame;

      if (!context.mounted) {
        return false;
      }

      if (shouldShow != null && !shouldShow()) {
        debugPrint('功能引导 $guideId 已取消，条件不满足');
        return false;
      }

      if (targetKey != null) {
        final renderBox = await _waitForTargetRender(
          targetKey,
          cancellation: () => shouldShow != null && !shouldShow(),
        );
        if (renderBox == null) {
          debugPrint('目标元素尚未渲染或已离开视图: $guideId');
          return false;
        }
      }

      if (shouldShow != null && !shouldShow()) {
        debugPrint('功能引导 $guideId 在显示前被取消');
        return false;
      }

      if (route != null && !route.isCurrent) {
        debugPrint('功能引导 $guideId 所属页面已切换，取消显示');
        return false;
      }

      if (!overlayState.mounted) {
        debugPrint('Overlay 已卸载，无法显示功能引导: $guideId');
        return false;
      }

      if (!context.mounted) {
        return false;
      }

      final guide = FeatureGuide(
        id: guideId,
        title: FeatureGuide.getLocalizedTitle(context, guideId),
        description: FeatureGuide.getLocalizedDescription(context, guideId),
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
      return true;
    } catch (e) {
      debugPrint('显示功能引导失败: $e');
      return false;
    }
  }

  /// 按优先级显示**其中一个**引导，成功显示后立刻停止。
  ///
  /// 这里原本是 `showSequence`：把候选气泡一个接一个全弹完。记录页最多能排到 4 个，
  /// 用户刚进页面就要连点四次「知道了」，等于劝退。现在一次只放一个，剩下的留到
  /// 下次进这个页面——引导本身有价值，密度没有。
  ///
  /// 返回是否真的显示了一个。前面的候选如果目标没渲染出来，会顺延到下一个。
  static Future<bool> showFirstAvailable({
    required BuildContext context,
    required List<(String, GlobalKey?)> guides,
    bool Function()? shouldShow,
    Duration autoDismissDuration = const Duration(milliseconds: 2200),
  }) async {
    for (final (guideId, targetKey) in guides) {
      if (!context.mounted) return false;
      if (shouldShow != null && !shouldShow()) return false;

      final shown = await show(
        context: context,
        guideId: guideId,
        targetKey: targetKey,
        autoDismissDuration: autoDismissDuration,
        shouldShow: shouldShow,
      );
      if (shown) return true;
    }
    return false;
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
