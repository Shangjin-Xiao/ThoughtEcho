import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 系统内存压力通知的两种来源。它们长得一模一样，要的处理却相反。
enum MemoryPressureKind {
  /// 前台真的缺内存。该放的都放掉，掉帧也好过被系统杀掉。
  scarcity,

  /// 只是切到后台被系统例行 trim。
  ///
  /// Android 在应用进入后台时会发 `TRIM_MEMORY_UI_HIDDEN`，Flutter 引擎把它和
  /// 真正的低内存警告一起转成同一个 `memoryPressure` 消息。于是「切出去看一眼
  /// 通知再切回来」和「系统快没内存了」在 Dart 侧完全无法分辨 —— 而框架默认对
  /// 两者都执行 `imageCache.clear()`。
  backgroundTrim,
}

/// 靠生命周期状态区分这次内存压力是哪一种。
///
/// 例行 trim 是在 `onStop` 之后送达的，那时候生命周期已经不是 `resumed`；前台真
/// 缺内存时应用还在 `resumed`。拿不到状态（`null`，binding 还没收到过生命周期
/// 通知）时按 [MemoryPressureKind.scarcity] 处理：宁可多释放一次，也不要在真缺
/// 内存时装作没看见。
MemoryPressureKind memoryPressureKindFor(AppLifecycleState? lifecycleState) {
  return lifecycleState == AppLifecycleState.resumed || lifecycleState == null
      ? MemoryPressureKind.scarcity
      : MemoryPressureKind.backgroundTrim;
}

/// 后台期给解码图留的额度。
///
/// 记录页的折叠缩略图单张约 80KB，8MB 足够装下用户刚翻过的那一屏和前后缓存区，
/// 又只占前台额度（64MB，见 `main.dart` 的 `_configureImageCache`）的八分之一。
const int backgroundTrimImageCacheBytes = 8 * 1024 * 1024;

/// 把图片缓存**淘汰**到 [keepBytes]，而不是清空。
///
/// [ImageCache.maximumSizeBytes] 的 setter 会立刻按 LRU 淘汰到新额度，所以先调低
/// 再调回去，等于「只留下最近用过的那几张」：额度还回去不会把已经淘汰的拉回来。
void shrinkImageCacheForBackgroundTrim(
  ImageCache cache, {
  int keepBytes = backgroundTrimImageCacheBytes,
}) {
  final restore = cache.maximumSizeBytes;
  if (restore <= keepBytes) return;
  cache.maximumSizeBytes = keepBytes;
  cache.maximumSizeBytes = restore;
}

/// 应用自己的 [WidgetsFlutterBinding]，只为改一件事：**切后台不等于缺内存**。
///
/// 框架默认把 `memoryPressure` 一律当成缺内存：`PaintingBinding` 清空整个
/// `imageCache`，`WidgetsBinding` 再把 `didHaveMemoryPressure()` 广播给所有观察者
/// （本应用里那个观察者会清掉富文本的测量缓存）。而 Android 每次切后台都会发这条
/// 消息，于是「切出去回来，之前看过的图变灰重新加载、往回滑还要重新排版」成了必然
/// —— 用户两轮反馈里说的就是这件事，性能日志里对应 `rewarm` 和 `Δimg+`。
///
/// 例行 trim 这条路上只做两件真正划算的事：卸掉 asset bundle，把图片缓存**淘汰**
/// 到 [backgroundTrimImageCacheBytes] 而不是清空。测量缓存留着 —— 它装的是折叠
/// 判定和折叠排版这类小对象，省不下多少内存，重算却要落在回到前台的第一次滑动里。
///
/// 只给 `main()` 用：进程里第一个 binding 必须是它，否则框架已经建好别的 binding，
/// 这里再构造一个会直接断言失败。后台 isolate（`background_push_handler.dart`）在
/// 自己的 isolate 里另起 binding，与这里无关。
class AppWidgetsBinding extends WidgetsFlutterBinding {
  static bool _constructed = false;

  static WidgetsBinding ensureInitialized() {
    if (!_constructed) {
      _constructed = true;
      AppWidgetsBinding();
    }
    return WidgetsBinding.instance;
  }

  /// 后台例行 trim 走过几次，供性能日志对账用。
  static int backgroundTrimCount = 0;

  @override
  void handleMemoryPressure() {
    if (memoryPressureKindFor(lifecycleState) ==
        MemoryPressureKind.backgroundTrim) {
      backgroundTrimCount++;
      rootBundle.clear();
      shrinkImageCacheForBackgroundTrim(imageCache);
      return;
    }
    super.handleMemoryPressure();
  }
}
