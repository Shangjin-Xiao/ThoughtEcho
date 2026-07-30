import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 记录页列表项的统一动效层（入场 + 删除折叠）。
///
/// 这一层的约束就是历次「动画修好了又坏」的根因，改动前请先读完：
///
/// 1. **常驻挂载**。无论有没有动画在播，每个列表项外层都有这一层，动画开始和
///    结束都不改变 widget 树的形状。旧实现按需插入/移除包装层（`TweenAnimationBuilder`
///    + `_NoteDeleteCollapse`），插入的那一帧和移除的那一帧都会让整张卡片子树重新
///    挂载：Quill 重建、图片重解码、KeepAlive 状态丢失。叠加「冷 Quill 首布局每帧
///    一次」的预算后，卡片可能几帧后才画出内容——体感就是动画突然加速或丢掉。
///    因此：**不要再按状态条件包装这一层**。
///
/// 2. **高度折叠不用 `Align`/`SizeTransition`**。它们内部的 `Align` 会把宽度约束
///    放松成 loose，卡片在动画期间横向缩到内容宽度、动画结束再弹回整宽（短笔记
///    尤其明显）。这里用自定义 [RenderBox] 只裁高度，宽度约束原样传给子树。
///
/// 3. **不引入常驻图层**。透明度没有用 `Opacity`/`FadeTransition`：它们只要
///    alpha > 0 就是 repaint boundary 并压一层 `OpacityLayer`，常驻等于给每个列表
///    项多一次 saveLayer。这里自己实现，alpha 为 255 时走纯透传。
///
/// 4. **时序由动画自身驱动**。入场播完、删除折叠播完都通过回调通知外层，外层不再
///    用挂钟定时器猜动画什么时候结束——挂钟和真实动画起点脱节（数据流回推、掉帧、
///    路由退场都会推迟动画起点），一旦对不上就把动画掐断。外层的定时器只作为
///    「item 始终没 build 出来」的兜底。
class NoteItemMotion extends StatefulWidget {
  const NoteItemMotion({
    super.key,
    required this.insertVersion,
    required this.insertAnimationType,
    required this.animateInsertLayout,
    required this.isDeleting,
    required this.onInsertCompleted,
    required this.onDeleteCompleted,
    required this.child,
  });

  static const Duration insertDuration = Duration(milliseconds: 250);
  static const Duration deleteDuration = Duration(milliseconds: 280);

  /// slide 类型的入场位移量。
  static const double insertSlideOffset = 16.0;

  /// 入场动画版本号，null 表示当前没有入场动画。版本号变化即重播（保存/撤销恢复）。
  final int? insertVersion;

  /// 入场动画类型：`slide`、`scale` 或 `none`。
  final String insertAnimationType;

  /// 结构性插入（列表真的多出一行）时才同时撑开高度；
  /// 原地更新已有笔记只做淡入和位移，避免下方卡片被挤动。
  final bool animateInsertLayout;

  final bool isDeleting;

  /// 入场动画完整播完时回调，参数是播完的版本号。
  final ValueChanged<int> onInsertCompleted;

  /// 删除折叠动画播完时回调，外层在此执行真正的删除。
  final VoidCallback onDeleteCompleted;

  final Widget child;

  @override
  State<NoteItemMotion> createState() => NoteItemMotionState();
}

@visibleForTesting
class NoteItemMotionState extends State<NoteItemMotion>
    with TickerProviderStateMixin {
  /// 两个控制器都惰性创建：静止的列表项不持有 Ticker。
  AnimationController? _insertController;
  Animation<double>? _insertProgress;
  AnimationController? _deleteController;
  Animation<double>? _deleteFade;
  Animation<double>? _deleteCollapse;

  /// 当前正在播（或已播完但外层还没清理挂起状态）的入场动画版本号。
  int? _playingInsertVersion;

  bool get _insertEnabled =>
      widget.insertAnimationType != 'none' && widget.insertVersion != null;

  /// 供测试断言当前动效状态。
  @visibleForTesting
  double get debugHeightFactor => _heightFactor;

  @visibleForTesting
  double get debugOpacity => _opacity;

  @override
  void initState() {
    super.initState();
    if (_insertEnabled) {
      _startInsert(widget.insertVersion!);
    }
    if (widget.isDeleting) {
      _startDelete();
    }
  }

  @override
  void didUpdateWidget(NoteItemMotion oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!_insertEnabled) {
      _stopInsert();
    } else if (widget.insertVersion != _playingInsertVersion) {
      _startInsert(widget.insertVersion!);
    }

    if (widget.isDeleting && !oldWidget.isDeleting) {
      _startDelete();
    } else if (!widget.isDeleting && oldWidget.isDeleting) {
      _stopDelete();
    }
  }

  void _startInsert(int version) {
    _playingInsertVersion = version;
    final controller = _insertController ??= AnimationController(
      vsync: this,
      duration: NoteItemMotion.insertDuration,
    )
      ..addListener(_handleTick)
      ..addStatusListener(_handleInsertStatus);
    _insertProgress ??= CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
    );
    controller.forward(from: 0.0);
  }

  /// 外层清理了挂起状态（动画播完，或搜索/筛选切换时统一取消）：
  /// 直接回到静止态，不留半透明或半高的残留。
  /// 仅在 [didUpdateWidget] 中调用，紧随其后就是 build，不需要 setState。
  void _stopInsert() {
    if (_playingInsertVersion == null) return;
    _playingInsertVersion = null;
    _insertController?.stop();
  }

  void _startDelete() {
    final controller = _deleteController ??= AnimationController(
      vsync: this,
      duration: NoteItemMotion.deleteDuration,
    )
      ..addListener(_handleTick)
      ..addStatusListener(_handleDeleteStatus);
    // 透明度先行（easeOut：一开始就快速变淡，给出即时删除反馈）；
    // 高度折叠用 easeInOutCubic，让下方卡片平滑上移。
    _deleteFade ??= CurvedAnimation(parent: controller, curve: Curves.easeOut);
    _deleteCollapse ??= CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOutCubic,
    );
    controller.forward(from: 0.0);
  }

  /// 删除被撤销（笔记又回到列表）时复位，避免卡片停在半折叠状态。
  /// 同样只在 [didUpdateWidget] 中调用，紧随其后就是 build。
  void _stopDelete() {
    final controller = _deleteController;
    if (controller == null) return;
    controller.stop();
    controller.value = 0.0;
  }

  void _handleTick() {
    if (!mounted) return;
    setState(() {});
  }

  void _handleInsertStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final version = _playingInsertVersion;
    if (version == null) return;
    widget.onInsertCompleted(version);
  }

  void _handleDeleteStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (!widget.isDeleting) return;
    widget.onDeleteCompleted();
  }

  @override
  void dispose() {
    _insertController?.dispose();
    _deleteController?.dispose();
    super.dispose();
  }

  bool get _insertPlaying => _playingInsertVersion != null;

  double get _insertProgressValue => _insertPlaying
      ? (_insertProgress?.value ?? 1.0).clamp(0.0, 1.0)
      : 1.0;

  double get _deleteFadeValue =>
      widget.isDeleting ? (_deleteFade?.value ?? 0.0).clamp(0.0, 1.0) : 0.0;

  double get _deleteCollapseValue =>
      widget.isDeleting ? (_deleteCollapse?.value ?? 0.0).clamp(0.0, 1.0) : 0.0;

  double get _opacity =>
      (_insertProgressValue * (1.0 - _deleteFadeValue)).clamp(0.0, 1.0);

  double get _heightFactor {
    final double deleteFactor = 1.0 - _deleteCollapseValue;
    final double insertFactor =
        _insertPlaying && widget.animateInsertLayout ? _insertProgressValue : 1.0;
    return insertFactor < deleteFactor ? insertFactor : deleteFactor;
  }

  @override
  Widget build(BuildContext context) {
    final bool isScale = widget.insertAnimationType == 'scale';
    final double progress = _insertProgressValue;

    return _NoteItemMotionBox(
      opacity: _opacity,
      heightFactor: _heightFactor,
      translateY: _insertPlaying && !isScale
          ? -NoteItemMotion.insertSlideOffset * (1.0 - progress)
          : 0.0,
      scale: _insertPlaying && isScale ? 0.98 + 0.02 * progress : 1.0,
      child: widget.child,
    );
  }
}

/// 列表项动效渲染层：四个参数都在静止值时是纯代理盒，不多一次布局分支、
/// 不多一个图层，也不改变子树拿到的约束。
class _NoteItemMotionBox extends SingleChildRenderObjectWidget {
  const _NoteItemMotionBox({
    required this.opacity,
    required this.heightFactor,
    required this.translateY,
    required this.scale,
    required Widget super.child,
  });

  /// 1.0 = 完全不透明。
  final double opacity;

  /// 1.0 = 不折叠，按子组件原高度占位。
  final double heightFactor;

  /// 绘制期纵向偏移，0 = 不偏移。
  final double translateY;

  /// 以顶部中心为锚点的缩放，1.0 = 不缩放。
  final double scale;

  @override
  _RenderNoteItemMotion createRenderObject(BuildContext context) {
    return _RenderNoteItemMotion(
      opacity: opacity,
      heightFactor: heightFactor,
      translateY: translateY,
      scale: scale,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderNoteItemMotion renderObject,
  ) {
    renderObject
      ..opacity = opacity
      ..heightFactor = heightFactor
      ..translateY = translateY
      ..scale = scale;
  }
}

class _RenderNoteItemMotion extends RenderProxyBox {
  _RenderNoteItemMotion({
    required double opacity,
    required double heightFactor,
    required double translateY,
    required double scale,
  })  : _opacity = opacity.clamp(0.0, 1.0),
        _alpha = ui.Color.getAlphaFromOpacity(opacity),
        _heightFactor = heightFactor.clamp(0.0, 1.0),
        _translateY = translateY,
        _scale = scale;

  double _opacity;
  int _alpha;
  double _heightFactor;
  double _translateY;
  double _scale;

  final LayerHandle<ClipRectLayer> _clipLayer = LayerHandle<ClipRectLayer>();
  final LayerHandle<OpacityLayer> _opacityLayer = LayerHandle<OpacityLayer>();
  final LayerHandle<TransformLayer> _transformLayer =
      LayerHandle<TransformLayer>();

  set opacity(double value) {
    final double clamped = value.clamp(0.0, 1.0);
    if (_opacity == clamped) return;
    final bool didNeedCompositing = alwaysNeedsCompositing;
    final int oldAlpha = _alpha;
    _opacity = clamped;
    _alpha = ui.Color.getAlphaFromOpacity(clamped);
    if (didNeedCompositing != alwaysNeedsCompositing) {
      markNeedsCompositingBitsUpdate();
    }
    markNeedsPaint();
    // 只在"可见/不可见"翻转时更新语义，动画每帧都刷语义纯属浪费。
    if ((oldAlpha == 0) != (_alpha == 0)) {
      markNeedsSemanticsUpdate();
    }
  }

  set heightFactor(double value) {
    final double clamped = value.clamp(0.0, 1.0);
    if (_heightFactor == clamped) return;
    _heightFactor = clamped;
    markNeedsLayout();
  }

  set translateY(double value) {
    if (_translateY == value) return;
    _translateY = value;
    markNeedsPaint();
  }

  set scale(double value) {
    if (_scale == value) return;
    _scale = value;
    markNeedsPaint();
  }

  bool get _hasTransform => _translateY != 0.0 || _scale != 1.0;

  @override
  bool get alwaysNeedsCompositing => child != null && _alpha > 0 && _alpha < 255;

  @override
  void performLayout() {
    final RenderBox? child = this.child;
    if (child == null) {
      size = computeSizeForNoChild(constraints);
      return;
    }
    // 关键：约束原样透传，只有输出尺寸按折叠比例缩短。
    child.layout(constraints, parentUsesSize: true);
    size = _heightFactor >= 1.0
        ? child.size
        : constraints.constrain(
            Size(child.size.width, child.size.height * _heightFactor),
          );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final RenderBox? child = this.child;
    if (child == null) return computeSizeForNoChild(constraints);
    final Size childSize = child.getDryLayout(constraints);
    if (_heightFactor >= 1.0) return childSize;
    return constraints.constrain(
      Size(childSize.width, childSize.height * _heightFactor),
    );
  }

  Matrix4 _paintTransform() {
    final Matrix4 transform = Matrix4.identity();
    if (_translateY != 0.0) {
      transform.setEntry(1, 3, _translateY);
    }
    if (_scale != 1.0) {
      // 以顶部中心为锚点缩放：x' = scale * x + anchorX * (1 - scale)
      final double anchorX = size.width / 2.0;
      final Matrix4 scaleAboutTopCenter = Matrix4.identity()
        ..setEntry(0, 0, _scale)
        ..setEntry(1, 1, _scale)
        ..setEntry(0, 3, anchorX * (1.0 - _scale));
      transform.multiply(scaleAboutTopCenter);
    }
    return transform;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final RenderBox? child = this.child;
    if (child == null || _alpha == 0) {
      _clipLayer.layer = null;
      _opacityLayer.layer = null;
      _transformLayer.layer = null;
      return;
    }

    void paintChildContent(PaintingContext context, Offset offset) {
      if (!_hasTransform) {
        _transformLayer.layer = null;
        context.paintChild(child, offset);
        return;
      }
      _transformLayer.layer = context.pushTransform(
        needsCompositing,
        offset,
        _paintTransform(),
        (PaintingContext context, Offset offset) {
          context.paintChild(child, offset);
        },
        oldLayer: _transformLayer.layer,
      );
    }

    void paintFaded(PaintingContext context, Offset offset) {
      if (_alpha == 255) {
        _opacityLayer.layer = null;
        paintChildContent(context, offset);
        return;
      }
      _opacityLayer.layer = context.pushOpacity(
        offset,
        _alpha,
        paintChildContent,
        oldLayer: _opacityLayer.layer,
      );
    }

    if (_heightFactor >= 1.0) {
      _clipLayer.layer = null;
      paintFaded(context, offset);
      return;
    }

    if (size.isEmpty) {
      _clipLayer.layer = null;
      _opacityLayer.layer = null;
      _transformLayer.layer = null;
      return;
    }

    _clipLayer.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      paintFaded,
      oldLayer: _clipLayer.layer,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final RenderBox? child = this.child;
    if (child == null) return false;
    if (!_hasTransform) {
      return child.hitTest(result, position: position);
    }
    return result.addWithPaintTransform(
      transform: _paintTransform(),
      position: position,
      hitTest: (BoxHitTestResult result, Offset position) {
        return child.hitTest(result, position: position);
      },
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (_hasTransform) {
      transform.multiply(_paintTransform());
    }
  }

  @override
  bool paintsChild(RenderBox child) {
    assert(child.parent == this);
    return _alpha > 0;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    final RenderBox? child = this.child;
    if (child != null && _alpha > 0) {
      visitor(child);
    }
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    _opacityLayer.layer = null;
    _transformLayer.layer = null;
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('opacity', _opacity));
    properties.add(DoubleProperty('heightFactor', _heightFactor));
    properties.add(DoubleProperty('translateY', _translateY));
    properties.add(DoubleProperty('scale', _scale));
  }
}
