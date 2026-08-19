part of '../note_list_view.dart';

/// 空闲预热：趁列表静止，把「卡片第一次滑进视口才会做」的测量提前算好。
///
/// 前几轮已经证明，记录页的卡顿 100% 落在**第一次**上：往回滑全是已建好的卡片
/// 时 `frameJank=0`、`avgFrame` 不到 3ms；一旦有新卡片进场，同样的滑动就掉帧。
/// 而新卡片的首次布局里有三件事跟「什么时候做」无关，只跟内容和布局宽度有关：
///
/// 1. 折叠判定（`TextPainter.layout` 或一次 `plan()`）—— 日志里的 `expandMiss+`；
/// 2. 折叠正文排版（`CollapsedRichTextMetrics.plan`）—— 日志里的 `planMiss+`；
/// 3. 缩略图/通栏图的解码 —— 日志里 `imageCache` 那一行的 `Δimg+`。
///
/// 它们的结果都进按内容指纹做键的缓存，所以完全可以在用户没在滑的时候先算好。
/// 预热**不建任何 widget、不碰 element 树**：卡片建出来时照旧走自己那条路，
/// 只是查表命中。
///
/// 让路规则很硬：只要列表在滚、手指按在屏幕上、或正在自动滚动，这一轮直接放弃
/// 并改期。每一轮还有 [NoteListViewState._idleWarmupBudgetMicros] 的时间预算，
/// 到点就停在当前游标，下一轮接着来 —— 一次暖满 120 条会在空闲帧里堆出一个
/// 一百多毫秒的长任务，用户正好这时开始滑就白优化了。
extension _NoteListWarmupExtension on NoteListViewState {
  void _scheduleIdleLayoutWarmup({
    Duration delay = const Duration(milliseconds: 400),
  }) {
    if (!mounted) return;
    _idleWarmupDeferrals = 0;
    _idleWarmupTimer?.cancel();
    _idleWarmupTimer = Timer(delay, _runIdleWarmupTick);
  }

  /// 列表内容整体换过（搜索、筛选、排序）时把游标拨回开头。
  ///
  /// 追加分页不需要调用它：游标停在旧长度上，下一轮自然接着暖新来的那几条。
  void _resetIdleLayoutWarmup() {
    _idleWarmupCursor = 0;
  }

  void _runIdleWarmupTick() {
    if (!mounted) return;

    final quotes = _quotes;
    if (quotes.isEmpty) return;

    // 布局宽度由真实卡片回填；一张都还没建出来时等下一轮。
    final width = QuoteItemWidget.lastCollapsedContentWidth;
    if (width == null || !width.isFinite || width <= 0) {
      _deferIdleLayoutWarmup();
      return;
    }
    // 「暖完了没有」要等下面确认宽度和版式都没变才能判断，所以先不早退。
    if (isListScrolling.value ||
        isListDragActive.value ||
        _isUserScrolling ||
        _isAutoScrolling) {
      // 滚动停下来时 _scheduleScrollEndSettledWork 会重新排一轮，
      // 所以这里的改期只是兜底，用完次数就放手。
      _deferIdleLayoutWarmup();
      return;
    }

    final settings = _readSettingsServiceOrNull();
    if (settings == null) return;
    final mediaStyle = settings.noteCardMediaStyle;
    final prioritizeBoldContent = settings.prioritizeBoldContentInCollapse;

    // 宽度或版式变了（旋屏、分屏、切换媒体版式）说明此前暖的键全作废，从头再来。
    // 图片的去重集合也要一起清：`imageProviderFor` 的解码尺寸就是按这两样算的，
    // 只按 source 记「暖过了」的话，换了尺寸的那张永远等不到预热。
    if (_idleWarmupWidth != width || _idleWarmupMediaStyle != mediaStyle) {
      _idleWarmupWidth = width;
      _idleWarmupMediaStyle = mediaStyle;
      _idleWarmupCursor = 0;
      _idleWarmupPrecachedSources.clear();
    }

    final stopwatch = Stopwatch()..start();
    while (_idleWarmupCursor < quotes.length &&
        stopwatch.elapsedMicroseconds <
            NoteListViewState._idleWarmupBudgetMicros) {
      final quote = quotes[_idleWarmupCursor++];
      QuoteItemWidget.warmCollapsedMeasurements(
        context: context,
        quote: quote,
        contentMaxWidth: width,
        mediaStyle: mediaStyle,
        prioritizeBoldContent: prioritizeBoldContent,
      );
      _warmCollapsedMediaImage(
        quote: quote,
        mediaStyle: mediaStyle,
        contentMaxWidth: width,
      );
      _idleWarmupWarmedItems++;
    }

    if (_idleWarmupCursor < quotes.length) {
      _scheduleIdleLayoutWarmup(
        delay: const Duration(milliseconds: 16),
      );
      return;
    }

    // 测量都暖完了，接着把缓存区往外撑一级。
    if (_growIdleCacheExtent()) {
      _scheduleIdleLayoutWarmup(
        delay: const Duration(milliseconds: 16),
      );
    }
  }

  /// 静止期把滚动缓存区往外撑一级，返回是否真的撑了。
  ///
  /// 预热能把「量」提前，但卡片的**挂载**（构造 widget、建 element 与
  /// RenderObject）只有 Viewport 在它进入缓存区时才会做 —— 而那一刻正好在滚动帧
  /// 里。把缓存区在静止期一级一级撑大，这批挂载就落进空闲帧；下一次滑过去时它们
  /// 已经是现成的，和日志里 `built=0` 的那两段回滑一个待遇。
  ///
  /// **一次只撑一级**：每撑一级都要跑一次布局并把新进缓存区的那几张卡片建出来，
  /// 一次撑到位就是一个上百毫秒的长任务，用户正好这时开始滑就白优化了。
  bool _growIdleCacheExtent() {
    if (_idleCacheExtentBoostPx >=
        NoteListViewState._maxIdleCacheExtentBoostPx) {
      return false;
    }

    // 贴着底部时不撑。还没建出来的尾部条目是靠已建条目的平均高度估出来的
    // （`SliverMultiBoxAdaptorElement._extrapolateMaxScrollOffset`），多建几条就
    // 会改变 maxScrollExtent；人正好停在底部时那点变化会把偏移夹一下，看着就是
    // 「列表自己抖了一下」—— 这块代码为这件事返过好几次工，不要再招惹它。
    final position = _safeScrollPosition;
    if (position != null &&
        position.hasContentDimensions &&
        position.maxScrollExtent - position.pixels <=
            position.viewportDimension) {
      return false;
    }

    _updateState(() {
      _idleCacheExtentBoostPx =
          (_idleCacheExtentBoostPx + NoteListViewState._idleCacheExtentStepPx)
              .clamp(0.0, NoteListViewState._maxIdleCacheExtentBoostPx);
    });
    return true;
  }

  /// 这一轮什么都没暖成，改期重试；连续多次都没进展就彻底放手，
  /// 等下一个外部触发（滚动停止、数据事件）重新起头。
  void _deferIdleLayoutWarmup() {
    if (_idleWarmupDeferrals >= NoteListViewState._maxIdleWarmupDeferrals) {
      return;
    }
    final deferrals = _idleWarmupDeferrals + 1;
    _scheduleIdleLayoutWarmup();
    _idleWarmupDeferrals = deferrals;
  }

  /// 提前解码折叠卡片上的那张图。
  ///
  /// 解码本身在后台线程，但「解完 → 回调 → 重绘 → 上传纹理」这一串的头尾都落在
  /// 滚动帧里；日志里每个下滑 session 都带着 `Δimg+7`、`Δimg+17`。提前解好之后
  /// 卡片建出来就是 `imageCache` 命中，`Image` 内部那条
  /// 「命中即同步解析、不延迟」的路径直接出图。
  ///
  /// 解码尺寸必须和渲染侧一致，所以 provider 由两种版式各自的
  /// `imageProviderFor` 给，见那两处的说明。
  void _warmCollapsedMediaImage({
    required Quote quote,
    required String mediaStyle,
    required double contentMaxWidth,
  }) {
    if (mediaStyle == NoteCardMediaStyle.inline) return;
    if (quote.deltaContent == null || quote.editSource != 'fullscreen') return;

    final media = DeltaMediaCache.of(quote.deltaContent);
    final source = media.firstImageSource;
    if (source == null || source.isEmpty) return;
    if (!_idleWarmupPrecachedSources.add(source)) return;
    // 上限只是防止长列表把这个集合撑大；imageCache 自己有 LRU 兜底。
    if (_idleWarmupPrecachedSources.length >
        NoteListViewState._idleWarmupPrecacheTrackLimit) {
      _idleWarmupPrecachedSources.remove(_idleWarmupPrecachedSources.first);
    }

    final provider = mediaStyle == NoteCardMediaStyle.banner
        ? CollapsedMediaBanner.imageProviderFor(
            context,
            media,
            width: contentMaxWidth,
          )
        : CollapsedMediaThumbnail.imageProviderFor(context, media);
    if (provider == null) return;

    // 失败静默：文件可能已被删除或路径失效，卡片自己的 errorBuilder 会处理。
    _idleWarmupPrecachedImages++;
    unawaited(
      precacheImage(provider, context, onError: (_, __) {}),
    );
  }

  SettingsService? _readSettingsServiceOrNull() {
    try {
      return context.read<SettingsService>();
    } catch (_) {
      return null;
    }
  }
}
