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
