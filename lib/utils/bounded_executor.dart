import 'dart:async';
import 'dart:math' as math;

/// 有界并发执行调度器
///
/// 限制同时执行的异步任务上限，避免移动端网络套接字耗尽与云端服务商限流。
class BoundedExecutor {
  /// 最大并发数
  final int maxConcurrency;

  BoundedExecutor({this.maxConcurrency = 4}) : assert(maxConcurrency > 0);

  /// 以受控的并发数映射执行 [items] 的异步操作 [action]。
  ///
  /// 返回所有操作的结果列表，顺序与 [items] 保持严格一致。
  Future<List<R>> map<T, R>(
    Iterable<T> items,
    Future<R> Function(T item) action,
  ) async {
    final list = items.toList(growable: false);
    if (list.isEmpty) return <R>[];

    final results = List<R?>.filled(list.length, null);
    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        final currentIndex = nextIndex++;
        if (currentIndex >= list.length) {
          break;
        }
        results[currentIndex] = await action(list[currentIndex]);
      }
    }

    final workerCount = math.min(maxConcurrency, list.length);
    final workers = List.generate(workerCount, (_) => worker());
    await Future.wait(workers);

    return results.cast<R>();
  }
}
