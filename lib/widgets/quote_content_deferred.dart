part of 'quote_content_widget.dart';

class _DeferredRichTextContent extends StatefulWidget {
  const _DeferredRichTextContent({
    required this.placeholder,
    required this.richTextBuilder,
  });

  final Widget placeholder;
  final WidgetBuilder richTextBuilder;

  @override
  State<_DeferredRichTextContent> createState() =>
      _DeferredRichTextContentState();
}

class _DeferredRichTextContentState extends State<_DeferredRichTextContent> {
  bool _materialized = false;

  @override
  void initState() {
    super.initState();
    isListScrolling.addListener(_handleScrollStateChanged);
    isListDragActive.addListener(_handleScrollStateChanged);
  }

  static bool get _listGestureActive =>
      isListScrolling.value || isListDragActive.value;

  void _handleScrollStateChanged() {
    if (_materialized || !mounted) {
      return;
    }
    if (_listGestureActive) {
      _DeferredRichTextMaterializationQueue.remove(this);
    } else {
      _DeferredRichTextMaterializationQueue.enqueue(this);
    }
  }

  bool get _isVisible {
    final renderObject = context.findRenderObject();
    if (renderObject == null || !renderObject.attached) {
      return false;
    }
    final viewport = RenderAbstractViewport.maybeOf(renderObject);
    final scrollable = Scrollable.maybeOf(context);
    if (viewport == null || scrollable == null) {
      return true;
    }
    final position = scrollable.position;
    if (!position.hasContentDimensions) {
      return true;
    }
    final leadingRevealOffset =
        viewport.getOffsetToReveal(renderObject, 0).offset;
    final trailingRevealOffset =
        viewport.getOffsetToReveal(renderObject, 1).offset;
    final lowerVisibleOffset = leadingRevealOffset < trailingRevealOffset
        ? leadingRevealOffset
        : trailingRevealOffset;
    final upperVisibleOffset = leadingRevealOffset > trailingRevealOffset
        ? leadingRevealOffset
        : trailingRevealOffset;
    return position.pixels >= lowerVisibleOffset - 0.5 &&
        position.pixels <= upperVisibleOffset + 0.5;
  }

  void _materializeFromQueue() {
    if (!mounted || _materialized || _listGestureActive) {
      return;
    }
    setState(() => _materialized = true);
  }

  @override
  void dispose() {
    _DeferredRichTextMaterializationQueue.remove(this);
    isListScrolling.removeListener(_handleScrollStateChanged);
    isListDragActive.removeListener(_handleScrollStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_materialized) {
      return widget.richTextBuilder(context);
    }
    if (!_listGestureActive) {
      _DeferredRichTextMaterializationQueue.enqueue(this);
    }
    return widget.placeholder;
  }
}

/// 冷 Quill 首布局的每帧额度。
///
/// 滚动信号只能覆盖“正在滚动”这段时间。首屏渲染、惯性停止后的补建，以及
/// `scrollCacheExtent` 在屏幕外预构建的卡片都发生在信号为 false 时，一帧里可能
/// 同时挂载多张冷卡片，把若干次 20~48ms 的 Quill 首布局叠进同一帧。额度把它压回
/// 每帧一次，其余卡片走同尺寸轻量占位并交给恢复队列逐帧补齐。
class _ColdCollapsedQuillFrameBudget {
  static const int _maxPerFrame = 1;

  static Duration? _frameTimeStamp;
  static int _used = 0;

  /// 申请本帧的冷 Quill 创建额度；返回 false 表示调用方应改用轻量占位。
  static bool tryConsume() {
    final binding = SchedulerBinding.instance;
    final phase = binding.schedulerPhase;
    // 帧外构建（如直接调用 build 的测试）没有可归属的帧，不施加额度。
    if (phase != SchedulerPhase.transientCallbacks &&
        phase != SchedulerPhase.persistentCallbacks) {
      return true;
    }

    final stamp = binding.currentFrameTimeStamp;
    if (_frameTimeStamp != stamp) {
      _frameTimeStamp = stamp;
      _used = 0;
    }
    if (_used >= _maxPerFrame) {
      return false;
    }
    _used++;
    return true;
  }

  static void reset() {
    _frameTimeStamp = null;
    _used = 0;
  }
}

class _DeferredRichTextMaterializationQueue {
  static final LinkedHashSet<_DeferredRichTextContentState> _pending =
      LinkedHashSet<_DeferredRichTextContentState>();
  static bool _frameScheduled = false;

  static void enqueue(_DeferredRichTextContentState state) {
    if (!state.mounted || state._materialized) {
      return;
    }
    _pending.add(state);
    _scheduleNextFrame();
  }

  static void remove(_DeferredRichTextContentState state) {
    _pending.remove(state);
  }

  static void _scheduleNextFrame({bool rescheduling = false}) {
    if (_frameScheduled ||
        _pending.isEmpty ||
        _DeferredRichTextContentState._listGestureActive) {
      return;
    }
    _frameScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frameScheduled = false;
      _pending.removeWhere((state) => !state.mounted || state._materialized);
      if (_pending.isEmpty ||
          _DeferredRichTextContentState._listGestureActive) {
        return;
      }

      // getOffsetToReveal returns the scroll offsets that align each edge;
      // the current offset lies between them exactly when the target is shown.
      final state = _pending.firstWhere(
        (candidate) => candidate._isVisible,
        orElse: () => _pending.first,
      );
      _pending.remove(state);
      // 与新挂载卡片共享同一份每帧额度：本帧额度归恢复队列，同帧新出现的冷卡片
      // 会退回占位，避免“队列补一张 + 列表新建一张”又凑成两次首布局。
      _ColdCollapsedQuillFrameBudget.tryConsume();
      state._materializeFromQueue();
      // One cold Quill per vsync prevents idle recovery from recreating the
      // same multi-item build spike that was removed from the scroll frame.
      _scheduleNextFrame(rescheduling: true);
    }, rescheduling: rescheduling);
  }
}
