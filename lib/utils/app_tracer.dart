import 'dart:developer' as developer;
import 'package:sentry_flutter/sentry_flutter.dart';

/// 记录页一次滚动会话的事务名。
///
/// 在两处用到，所以放在这里而不是各写一遍字面量：`note_list_scroll.dart` 起事务，
/// `sentry_helper.dart` 的 [sanitizeSentryTransaction] 按它筛掉不卡的那些会话。
const String scrollSessionTraceName = 'ThoughtEcho.NoteListView.scrollSession';

/// 滚动会话收尾地标的名字，帧统计以 span data 的形式挂在它上面。
const String scrollSessionFinalizeTraceName =
    '$scrollSessionTraceName.finalize';

/// 统一的性能监控追踪器
///
/// 封装了底层的 [developer.TimelineTask] (用于本地 DevTools 和 Firebase Test Lab 测试)
/// 以及 [Sentry] 的 Transaction/Span (用于线上生产环境监控)。
class AppTracer {
  final developer.TimelineTask _timelineTask;
  final ISentrySpan? _sentrySpan;

  AppTracer._(this._timelineTask, this._sentrySpan);

  /// 启动一段性能追踪
  ///
  /// [name] Timeline 和 Sentry 的统一事件名，例如 'ThoughtEcho.NoteListView.loadMore'
  /// [operation] Sentry 专用的分类标记，默认为 'ui.action'。对于加载动作建议用 'ui.load'
  ///
  /// [forceRootTransaction] 强制起一个根事务，哪怕作用域上已经绑着别的 span。
  /// 需要它的场合是「这段要能被独立采样和筛选」：Sentry 的 CPU profile 和
  /// `beforeSendTransaction` 都只认根事务，挂成子 span 就两样都拿不到。滚动会话
  /// 正好会撞上这种情况 —— 冷启动进页面时 `SentryNavigatorObserver` 的路由事务
  /// 还开着并绑在作用域上，而「冷启动几秒后的第一次滑动」恰恰是最想看的那一段。
  static AppTracer start(
    String name, {
    String? operation,
    String? description,
    Map<String, Object?>? arguments,
    bool forceRootTransaction = false,
  }) {
    // 1. 启动本地 Timeline (供 Firebase 和 DevTools 抓取)
    final timeline = developer.TimelineTask(filterKey: 'ThoughtEcho')
      ..start(name, arguments: arguments);

    // 2. 启动线上 Sentry Span
    final sentryOp = operation ?? 'ui.action';
    final currentSpan = Sentry.getSpan();

    ISentrySpan? span;
    if (currentSpan != null && !forceRootTransaction) {
      // 如果当前上下文中已经有 Transaction，作为其子 Span 挂载
      span = currentSpan.startChild(sentryOp, description: name);
    } else {
      // 否则新起一个 Transaction 作为根节点
      span = Sentry.startTransaction(
        name,
        sentryOp,
        description: description,
        // 绑定到作用域，方便后续发生的 Error 自动关联到该事务。但**只在没人绑过
        // 的时候绑**：强开根事务时作用域上往往正绑着别的事务（路由事务），这里再
        // 绑会把它顶掉，而且我们结束时会把 `scope.span` 置空 —— 它剩下的子 span
        // 就全挂不上去了。
        bindToScope: currentSpan == null,
      );
    }

    if (arguments != null) {
      for (final entry in arguments.entries) {
        span.setData(entry.key, entry.value);
      }
    }

    return AppTracer._(timeline, span);
  }

  /// 记录瞬时事件/地标针
  void instant(String name, {Map<String, Object?>? arguments}) {
    // 1. Timeline 瞬时地标 (供测试脚本关联卡顿帧)
    _timelineTask.instant(name, arguments: arguments);

    // 2. Sentry 子节点地标 (为了在瀑布流里显示瞬间耗时，创建一个极短的子 Span)
    final markSpan = _sentrySpan?.startChild('mark', description: name);
    if (arguments != null) {
      for (final entry in arguments.entries) {
        markSpan?.setData(entry.key, entry.value);
      }
    }
    markSpan?.finish();
  }

  /// 结束追踪
  void finish({Map<String, Object?>? arguments}) {
    if (arguments != null) {
      _timelineTask.finish(arguments: arguments);
      for (final entry in arguments.entries) {
        _sentrySpan?.setData(entry.key, entry.value);
      }
    } else {
      _timelineTask.finish();
    }
    _sentrySpan?.finish();
  }
}
