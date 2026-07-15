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
  }

  void _handleScrollStateChanged() {
    if (_materialized || !mounted) {
      return;
    }
    if (isListScrolling.value) {
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
    if (!mounted || _materialized || isListScrolling.value) {
      return;
    }
    setState(() => _materialized = true);
  }

  @override
  void dispose() {
    _DeferredRichTextMaterializationQueue.remove(this);
    isListScrolling.removeListener(_handleScrollStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_materialized) {
      return widget.richTextBuilder(context);
    }
    if (!isListScrolling.value) {
      _DeferredRichTextMaterializationQueue.enqueue(this);
    }
    return widget.placeholder;
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
    if (_frameScheduled || _pending.isEmpty || isListScrolling.value) {
      return;
    }
    _frameScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frameScheduled = false;
      _pending.removeWhere((state) => !state.mounted || state._materialized);
      if (_pending.isEmpty || isListScrolling.value) {
        return;
      }

      // getOffsetToReveal returns the scroll offsets that align each edge;
      // the current offset lies between them exactly when the target is shown.
      final state = _pending.firstWhere(
        (candidate) => candidate._isVisible,
        orElse: () => _pending.first,
      );
      _pending.remove(state);
      state._materializeFromQueue();
      // One cold Quill per vsync prevents idle recovery from recreating the
      // same multi-item build spike that was removed from the scroll frame.
      _scheduleNextFrame(rescheduling: true);
    }, rescheduling: rescheduling);
  }
}
