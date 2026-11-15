import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 心迹自绘的空状态动画样式。
///
/// 与 `AppLoadingStyle` 同一套做法：[CustomPainter] 实时绘制、颜色只取自
/// [ColorScheme]，在单位坐标里作画并按 [viewport] 缩放，因此亮暗色、动态取色
/// 与纸墨/素笺主题下都不需要另备素材。
enum AppEmptyStyle {
  /// 放大镜寻字：放大镜沿横线笺慢慢扫过，镜中只有放大的空行，最后停在中央
  /// 轻轻摇头。用于搜索、筛选无结果。
  searchNoResult(
    period: Duration(milliseconds: 4200),
    viewport: Rect.fromLTRB(0.10, 0.12, 0.90, 0.88),
    restingFrame: 0.86,
  );

  const AppEmptyStyle({
    required this.period,
    required this.viewport,
    required this.restingFrame,
  });

  /// 一个完整循环的时长。
  final Duration period;

  /// 内容框，单位坐标系下的可见区域。
  final Rect viewport;

  /// 系统开启「减少动态效果」时停留的那一帧（0–1）：放大镜停在纸中央的画面。
  final double restingFrame;

  /// 内容框宽高比。
  double get aspectRatio => viewport.width / viewport.height;
}

/// 自绘空状态动画。
///
/// 默认视为装饰（读屏跳过），因为空状态下方总有一行说明文字；单独使用、
/// 旁边没有文字时再传 [semanticLabel]。
class AppEmptyAnimation extends StatefulWidget {
  const AppEmptyAnimation({
    super.key,
    this.style = AppEmptyStyle.searchNoResult,
    this.width = 160,
    this.color,
    this.semanticLabel,
  });

  final AppEmptyStyle style;

  /// 动画宽度；高度按 [AppEmptyStyle.aspectRatio] 推导。
  final double width;

  /// 主色覆盖。默认 `colorScheme.primary`。
  final Color? color;

  /// 读屏文案。为空时整个动画从语义树中排除。
  final String? semanticLabel;

  @override
  State<AppEmptyAnimation> createState() => _AppEmptyAnimationState();
}

class _AppEmptyAnimationState extends State<AppEmptyAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.style.period,
  );
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _syncTicker();
  }

  @override
  void didUpdateWidget(AppEmptyAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style != widget.style) {
      _controller.duration = widget.style.period;
      _controller.stop();
      _syncTicker();
    }
  }

  void _syncTicker() {
    if (_reduceMotion) {
      _controller.stop();
      _controller.value = widget.style.restingFrame;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _EmptyPalette.of(context, widget.color);
    final height = widget.width / widget.style.aspectRatio;
    final painted = RepaintBoundary(
      child: SizedBox(
        width: widget.width,
        height: height,
        child: CustomPaint(painter: _painterFor(palette)),
      ),
    );
    final label = widget.semanticLabel;
    if (label == null) return ExcludeSemantics(child: painted);
    return Semantics(label: label, image: true, child: painted);
  }

  CustomPainter _painterFor(_EmptyPalette palette) {
    switch (widget.style) {
      case AppEmptyStyle.searchNoResult:
        return _SearchNoResultPainter(_controller, palette);
    }
  }
}

/// 从主题推导出的绘制用色。
@immutable
class _EmptyPalette {
  const _EmptyPalette({
    required this.accent,
    required this.outline,
    required this.page,
    required this.glare,
    required this.shadow,
    required this.isDark,
  });

  factory _EmptyPalette.of(BuildContext context, Color? accentOverride) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = accentOverride ?? scheme.primary;
    return _EmptyPalette(
      accent: accent,
      outline: scheme.outlineVariant,
      // 与加载动画的纸页同色：亮色下比背景略亮，暗色下取最亮的容器色。
      page: isDark
          ? scheme.surfaceContainerHigh
          : Color.alphaBlend(
              accent.withValues(alpha: 0.03),
              scheme.surfaceContainerLowest,
            ),
      // 镜片高光：亮色用最亮的表面色，暗色用前景色压低透明度，避免发白刺眼。
      glare: isDark
          ? scheme.onSurface.withValues(alpha: 0.18)
          : scheme.surfaceContainerLowest.withValues(alpha: 0.7),
      shadow: scheme.shadow,
      isDark: isDark,
    );
  }

  final Color accent;
  final Color outline;
  final Color page;
  final Color glare;
  final Color shadow;
  final bool isDark;

  @override
  bool operator ==(Object other) =>
      other is _EmptyPalette &&
      other.accent == accent &&
      other.outline == outline &&
      other.page == page &&
      other.glare == glare &&
      other.shadow == shadow &&
      other.isDark == isDark;

  @override
  int get hashCode => Object.hash(accent, outline, page, glare, shadow, isDark);
}

double _smoothstep(double t) {
  final x = t.clamp(0.0, 1.0);
  return x * x * (3 - 2 * x);
}

double _easeInOutCubic(double t) {
  final x = t.clamp(0.0, 1.0);
  return x < 0.5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3) / 2;
}

/// 放大镜寻字。
class _SearchNoResultPainter extends CustomPainter {
  _SearchNoResultPainter(this.progress, this.palette)
      : super(repaint: progress);

  final Animation<double> progress;
  final _EmptyPalette palette;

  static const _viewport = Rect.fromLTRB(0.10, 0.12, 0.90, 0.88);
  static const _sheet = Rect.fromLTRB(0.22, 0.22, 0.78, 0.78);
  static const _sheetRadius = 0.04;
  static const _rows = [0.36, 0.48, 0.60, 0.70];
  static const _lensRadius = 0.105;
  static const _magnify = 1.5;

  /// 镜心关键帧 (t, x, y)：沿第 1、2、3 行来回扫，最后回到纸中央。
  static const _keys = [
    (0.00, 0.34, 0.40),
    (0.20, 0.64, 0.42),
    (0.38, 0.36, 0.56),
    (0.56, 0.62, 0.62),
    (0.72, 0.50, 0.50),
    (1.00, 0.50, 0.50),
  ];

  /// 一个逻辑像素对应的单位长度，给细线兜底。
  double _pixel = 0;

  double _stroke(double width, {double minPixels = 1.2}) =>
      math.max(width, _pixel * minPixels);

  Paint _line(Color color, double width, {double minPixels = 1.2}) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = _stroke(width, minPixels: minPixels);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final scale = math.min(
      size.width / _viewport.width,
      size.height / _viewport.height,
    );
    _pixel = 1 / scale;
    canvas.save();
    canvas.translate(
      (size.width - _viewport.width * scale) / 2,
      (size.height - _viewport.height * scale) / 2,
    );
    canvas.scale(scale);
    canvas.translate(-_viewport.left, -_viewport.top);
    _paintFrame(canvas, progress.value);
    canvas.restore();
  }

  void _drawRules(Canvas canvas) {
    final rule = _line(palette.outline, 0.005, minPixels: 0.8);
    for (final y in _rows) {
      canvas.drawLine(
        Offset(_sheet.left + 0.06, y),
        Offset(_sheet.right - 0.06, y),
        rule,
      );
    }
  }

  Offset _lensCenter(double t) {
    for (var i = 0; i < _keys.length - 1; i++) {
      final (t0, x0, y0) = _keys[i];
      final (t1, x1, y1) = _keys[i + 1];
      if (t >= t0 && t <= t1) {
        final k = _easeInOutCubic((t - t0) / (t1 - t0));
        // 行间移动时微微上抬，像手在纸面上方移动。
        final arc = -0.03 * math.sin(k * math.pi);
        return Offset(x0 + (x1 - x0) * k, y0 + (y1 - y0) * k + arc);
      }
    }
    return const Offset(0.5, 0.5);
  }

  void _paintFrame(Canvas canvas, double t) {
    final sheet = RRect.fromRectAndRadius(
      _sheet,
      const Radius.circular(_sheetRadius),
    );

    // 纸笺与投影
    canvas.drawRRect(
      sheet.shift(const Offset(0, 0.012)),
      Paint()
        ..color = palette.shadow.withValues(alpha: palette.isDark ? 0.35 : 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.02),
    );
    canvas.drawRRect(sheet, Paint()..color = palette.page);
    canvas.drawRRect(sheet, _line(palette.outline, 0.006, minPixels: 0.8));
    _drawRules(canvas);

    // 右上角一个淡淡的折角
    final corner = Path()
      ..moveTo(_sheet.right - 0.09, _sheet.top)
      ..lineTo(_sheet.right, _sheet.top + 0.09)
      ..lineTo(_sheet.right, _sheet.top + _sheetRadius)
      ..arcToPoint(
        Offset(_sheet.right - _sheetRadius, _sheet.top),
        radius: const Radius.circular(_sheetRadius),
        clockwise: false,
      )
      ..close();
    canvas.drawPath(
      corner,
      Paint()..color = palette.accent.withValues(alpha: 0.06),
    );

    // 首尾淡入淡出，循环衔接时放大镜不会瞬移。
    final alpha = math.min(
      _smoothstep(t / 0.06),
      1 - _smoothstep((t - 0.95) / 0.05),
    );
    if (alpha <= 0) return;

    final c = _lensCenter(t);
    // 停在中央后轻轻摇头。
    var tilt = -0.35;
    if (t > 0.74 && t < 0.94) {
      final k = (t - 0.74) / 0.20;
      tilt += math.sin(k * math.pi * 3) * 0.22 * (1 - k);
    }

    final fade = alpha < 1;
    if (fade) {
      canvas.saveLayer(
        null,
        Paint()..color = palette.accent.withValues(alpha: alpha),
      );
    }

    const r = _lensRadius;
    final lensRect = Rect.fromCircle(center: c, radius: r);

    // 镜片：放大后的空行
    canvas.save();
    canvas.clipPath(Path()..addOval(lensRect));
    canvas.drawRect(lensRect, Paint()..color = palette.page);
    canvas.drawRect(
      lensRect,
      Paint()..color = palette.accent.withValues(alpha: 0.05),
    );
    canvas.translate(c.dx, c.dy);
    canvas.scale(_magnify);
    canvas.translate(-c.dx, -c.dy);
    _drawRules(canvas);
    canvas.restore();

    // 高光
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.72),
      math.pi * 1.08,
      math.pi * 0.34,
      false,
      _line(palette.glare, 0.010, minPixels: 1),
    );

    // 镜框与手柄
    canvas.drawCircle(c, r, _line(palette.accent, 0.020));
    final a = math.pi / 4 + tilt;
    final dir = Offset(math.cos(a), math.sin(a));
    canvas.drawLine(
      c + dir * (r * 1.04),
      c + dir * (r * 1.95),
      _line(palette.accent, 0.034),
    );

    if (fade) canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SearchNoResultPainter oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.progress != progress;
}
