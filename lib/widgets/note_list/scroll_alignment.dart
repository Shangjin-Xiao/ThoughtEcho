bool shouldSkipVisibleTargetAlignment({
  required double targetOffset,
  required double currentOffset,
  required double viewportExtent,
  required bool forceAlignToTop,
}) {
  if (forceAlignToTop || viewportExtent <= 0) {
    return false;
  }

  return targetOffset >= currentOffset &&
      targetOffset < currentOffset + viewportExtent;
}

/// 在数据事件之间保存「被内容变短夹掉的滚动偏移」。
///
/// 单独抽出来是因为它有两条容易悄悄回归的规则：
/// - **有效期**：过老的目标不能再去拽用户，他早就滑到别处了；
/// - **作废版本**：用户重新拖拽、或筛选切换要回到顶部时，目标必须整体作废。
///   光清字段挡不住**已经排进帧回调队列**的那次还原，所以还要递增版本号，
///   让在途回调自己退出。
class ScrollAnchorTracker {
  ScrollAnchorTracker({required this.retention});

  /// 待还原目标的有效期。超过就丢弃。
  final Duration retention;

  double? _offset;
  DateTime? _since;
  int _generation = 0;

  /// 当前版本号。排帧回调前取一次，回调执行时用 [isCurrent] 比对。
  int get generation => _generation;

  /// 排队时取的版本是否仍然有效。
  bool isCurrent(int capturedGeneration) => capturedGeneration == _generation;

  bool get hasPending => _offset != null;

  /// 读取仍在有效期内的目标；过期会就地丢弃并返回 null。
  ///
  /// **不清空**：调用方拿到决策结果后再显式 [remember] 或 [clear]，
  /// 这样同一个目标跨多次数据事件顺延时能保住它最初挂起的时刻。
  double? peek(DateTime now) {
    final offset = _offset;
    final since = _since;
    if (offset == null || since == null) return null;
    if (now.difference(since) > retention) {
      _offset = null;
      _since = null;
      return null;
    }
    return offset;
  }

  /// 挂起（或顺延）一个还原目标。
  ///
  /// 同一个目标反复顺延时**保留最初的时刻**：数据事件可能一个接一个地来，
  /// 每次都重新计时的话有效期会被无限续期，用户可能在很久之后忽然被拽回去。
  /// 目标本身变了才算新的夹紧事件，这时才重新计时。
  void remember(double offset, DateTime now) {
    if (_offset != offset) {
      _since = now;
    }
    _since ??= now;
    _offset = offset;
  }

  /// 清空目标（已还原到位、或已无需还原）。不影响版本号。
  void clear() {
    _offset = null;
    _since = null;
  }

  /// 作废：清空目标并递增版本，让已排队的回调直接退出。
  void cancel() {
    clear();
    _generation++;
  }
}

/// 数据事件（整表替换 `_quotes`）之后对滚动锚点的处置方式。
enum ScrollAnchorAction {
  /// 什么都不用做。
  none,

  /// 目标暂时够不着（内容还没回填够）或此刻不宜移动位置，先记着。
  remember,

  /// 立即无动画跳回目标偏移。
  restore,
}

/// [resolveScrollAnchorAction] 的结果。[targetOffset] 在 remember/restore 时有值。
class ScrollAnchorDecision {
  const ScrollAnchorDecision(this.action, [this.targetOffset]);

  final ScrollAnchorAction action;
  final double? targetOffset;

  @override
  String toString() => 'ScrollAnchorDecision($action, $targetOffset)';
}

/// 决定数据事件后要不要把滚动位置拉回原处。
///
/// 列表在用户滑动途中被换成更短的数据时，maxScrollExtent 会骤减并把当前偏移
/// 夹紧，视觉上就是「列表突然飞走 / 弹回顶部」。这里把「记住目标」和「择机还原」
/// 的判断抽成纯函数，方便覆盖各种边界。
///
/// - [previousOffset]：本次数据应用之前的偏移量。**只在内容已经装不下它时**
///   才会成为锚点候选，见下方说明。
/// - [pendingOffset]：之前被夹掉、仍在有效期内的待还原偏移。
/// - [currentPixels] / [maxScrollExtent]：数据应用后的实际滚动状态。
/// - [isDragging]：用户此刻是否正按住列表。拖拽期间跳位置会打断手势，
///   所以只记不跳，等松手后的事件或滚动停止再还原。
///
/// **[previousOffset] 绝不能直接当作还原目标。** 数据事件（分页追加等）绝大多数
/// 发生在惯性滑动中，`currentPixels` 每帧都在合法变化；若把"事件发生前的偏移"
/// 当目标去比 `currentPixels`，普通的一次分页就会把正在上滑的用户拽回事件发生前
/// 的位置，惯性也被打断。真正需要兜底的只有一种情况：内容变短到
/// `maxScrollExtent` 已经装不下原偏移——那才是被夹掉，而不是用户自己滑走的。
ScrollAnchorDecision resolveScrollAnchorAction({
  required double? previousOffset,
  required double? pendingOffset,
  required double currentPixels,
  required double maxScrollExtent,
  required bool isDragging,
  required double tolerance,
}) {
  // 原偏移是否被内容变短夹掉了。没被夹掉就完全不参与决策。
  final wasClampedAway = previousOffset != null &&
      previousOffset > 0 &&
      previousOffset > maxScrollExtent + tolerance;

  // 目标取两者中更深的那个：连续多次变短时不能把目标越记越浅。
  double? target = pendingOffset;
  if (wasClampedAway && (target == null || previousOffset > target)) {
    target = previousOffset;
  }

  if (target == null || target <= 0) {
    return const ScrollAnchorDecision(ScrollAnchorAction.none);
  }

  // 内容还装不下目标：继续挂着，等后续事件把列表补长。
  // 只补长了一半（maxScrollExtent 仍小于目标）也走这里，不能把目标丢掉。
  if (target > maxScrollExtent + tolerance) {
    return ScrollAnchorDecision(ScrollAnchorAction.remember, target);
  }

  // 已经在目标位置或更深处，没什么要还原的。
  if (currentPixels >= target - tolerance) {
    return const ScrollAnchorDecision(ScrollAnchorAction.none);
  }

  // 正在拖拽：不跟手势抢，保留目标，等滚动停下来再还原。
  if (isDragging) {
    return ScrollAnchorDecision(ScrollAnchorAction.remember, target);
  }

  return ScrollAnchorDecision(ScrollAnchorAction.restore, target);
}
