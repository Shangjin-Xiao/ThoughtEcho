/// 从锚点向两边扩散的遍历游标。
///
/// 空闲预热原来是从索引 0 一路往下暖的。列表静止在中间、或者刚回到前台时，这个
/// 顺序把功夫全花在了用户看不见的地方：2026-08-23 的日志里，用户停在第 45~72 条
/// 往回滑，预热的游标却还在 `23/121` —— 暖的是第 0~22 条，滑到的每一张都还得现算。
///
/// 改成从视口所在的那条向两边交替扩散：先下后上，同距离时优先向下（下滑比上滑
/// 常见）。[next] 每次要传当前长度，列表在预热途中追加了新页也能接着走。
class SpreadFromAnchorCursor {
  int _anchor = 0;
  int _forward = 0;
  int _backward = 0;
  int _emitted = 0;

  /// 这一轮从哪一条开始扩散。
  int get anchor => _anchor;

  /// 这一轮已经吐出过几个下标。
  int get emitted => _emitted;

  /// 重开一轮。[anchor] 会被夹进 `[0, length)`，负数或越界都不会让 [next] 空转。
  void restart({required int anchor, required int length}) {
    _anchor = length <= 0 ? 0 : anchor.clamp(0, length - 1);
    _forward = 0;
    _backward = 0;
    _emitted = 0;
  }

  /// 下一个还没走过的下标；都走完了返回 null。
  int? next(int length) {
    if (length <= 0) return null;
    final forwardIndex = _anchor + _forward;
    final backwardIndex = _anchor - 1 - _backward;
    final forwardValid = forwardIndex < length;
    final backwardValid = backwardIndex >= 0;
    if (!forwardValid && !backwardValid) return null;

    // 同距离时优先向下：下一个向下候选离锚点 `_forward`，向上候选离锚点
    // `_backward + 1`，所以判据是 `_forward <= _backward + 1` 而不是
    // `_forward <= _backward` —— 后者会在距离相同时先给上面那条。
    if (forwardValid && (!backwardValid || _forward <= _backward + 1)) {
      _forward++;
      _emitted++;
      return forwardIndex;
    }
    _backward++;
    _emitted++;
    return backwardIndex;
  }
}
