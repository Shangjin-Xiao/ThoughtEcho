import 'dart:developer' as developer;
import 'package:sentry_flutter/sentry_flutter.dart';

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
  static AppTracer start(
    String name, {
    String? operation,
    String? description,
    Map<String, Object?>? arguments,
  }) {
    // 1. 启动本地 Timeline (供 Firebase 和 DevTools 抓取)
    final timeline = developer.TimelineTask(filterKey: 'ThoughtEcho')
      ..start(name, arguments: arguments);

    // 2. 启动线上 Sentry Span
    final sentryOp = operation ?? 'ui.action';
    final currentSpan = Sentry.getSpan();

    ISentrySpan? span;
    if (currentSpan != null) {
      // 如果当前上下文中已经有 Transaction，作为其子 Span 挂载
      span = currentSpan.startChild(sentryOp, description: name);
    } else {
      // 否则新起一个 Transaction 作为根节点
      span = Sentry.startTransaction(
        name,
        sentryOp,
        description: description,
        bindToScope: true, // 绑定到作用域，方便后续发生的 Error 自动关联到该事务
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
