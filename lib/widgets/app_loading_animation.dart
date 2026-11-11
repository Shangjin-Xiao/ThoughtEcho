import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../gen_l10n/app_localizations.dart';

/// 心迹自绘的加载动画样式。
///
/// 全部由 [CustomPainter] 实时绘制，颜色只取自 [ColorScheme]，因此亮暗色、
/// 动态取色与纸墨/素笺主题下都不需要另备素材——这是替换 Lottie 的主要理由：
/// Lottie JSON 的颜色写死在文件里，换了主题就成了一块外来贴图。
///
/// 每个样式在 [viewport] 中描述自己的内容框（单位坐标），组件按内容框的
/// 宽高比给出默认高度，所以宽的书写动画不会被塞进正方形里留出大片空白。
enum AppLoadingStyle {
  /// 翻书：一本摊开的书连续翻过三页。适合整页/整块区域等待。
  bookFlip(
    period: Duration(milliseconds: 2800),
    viewport: Rect.fromLTRB(0.14, 0.21, 0.86, 0.79),
    restingFrame: 0.0,
  ),

  /// 墨迹书写：手写连笔一笔写出后淡去。适合 AI 生成、分析等「正在落笔」的等待。
  inkWriting(
    period: Duration(milliseconds: 2600),
    viewport: Rect.fromLTRB(0.10, 0.35, 0.90, 0.67),
    restingFrame: 0.66,
  ),

  /// 墨滴晕染：一滴墨落入水面荡开涟漪。适合同步、导入等安静的后台等待。
  inkDrop(
    period: Duration(milliseconds: 2200),
    viewport: Rect.fromLTRB(0.10, 0.12, 0.90, 0.78),
    restingFrame: 0.5,
  ),

  /// 逐行落笔：几行字逐行写出。适合列表或详情的内容占位。
  writingLines(
    period: Duration(milliseconds: 2400),
    viewport: Rect.fromLTRB(0.10, 0.30, 0.90, 0.70),
    restingFrame: 0.75,
  );

  const AppLoadingStyle({
    required this.period,
    required this.viewport,
    required this.restingFrame,
  });

  /// 一个完整循环的时长。
  final Duration period;

  /// 内容框，单位坐标系下的可见区域。
  final Rect viewport;

  /// 系统开启「减少动态效果」时停留的那一帧（0–1）。取的是最能说明
  /// 「正在加载」含义的静态画面，而不是第一帧的空白。
  final double restingFrame;

  /// 内容框宽高比。
  double get aspectRatio => viewport.width / viewport.height;
}

/// 自绘加载动画。
///
/// 只负责动画本身；需要居中占位、附带说明文字时用 `AppLoadingView`。
class AppLoadingAnimation extends StatefulWidget {
  const AppLoadingAnimation({
    super.key,
    this.style = AppLoadingStyle.bookFlip,
    this.width = 96,
    this.color,
    this.semanticLabel,
  });

  final AppLoadingStyle style;

  /// 动画宽度；高度按 [AppLoadingStyle.aspectRatio] 推导。
  final double width;

  /// 主色覆盖。默认 `colorScheme.primary`。
  final Color? color;

  /// 读屏文案，默认「加载中」。
  final String? semanticLabel;

  @override
  State<AppLoadingAnimation> createState() => _AppLoadingAnimationState();
}

class _AppLoadingAnimationState extends State<AppLoadingAnimation>
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
  void didUpdateWidget(AppLoadingAnimation oldWidget) {
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
    final palette = _LoaderPalette.of(context, widget.color);
    final height = widget.width / widget.style.aspectRatio;
    return Semantics(
      label: widget.semanticLabel ?? AppLocalizations.of(context).loading,
      child: RepaintBoundary(
        child: SizedBox(
          width: widget.width,
          height: height,
          child: CustomPaint(painter: _painterFor(palette)),
        ),
      ),
    );
  }

  CustomPainter _painterFor(_LoaderPalette palette) {
    switch (widget.style) {
      case AppLoadingStyle.bookFlip:
        return _BookFlipPainter(_controller, palette);
      case AppLoadingStyle.inkWriting:
        return _InkWritingPainter(_controller, palette);
      case AppLoadingStyle.inkDrop:
        return _InkDropPainter(_controller, palette);
      case AppLoadingStyle.writingLines:
        return _WritingLinesPainter(_controller, palette);
    }
  }
}

/// 从主题推导出的绘制用色。
@immutable
class _LoaderPalette {
  const _LoaderPalette({
    required this.accent,
    required this.ink,
    required this.outline,
    required this.page,
    required this.cover,
    required this.shadow,
    required this.isDark,
  });

  factory _LoaderPalette.of(BuildContext context, Color? accentOverride) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = accentOverride ?? scheme.primary;
    return _LoaderPalette(
      accent: accent,
      ink: scheme.onSurface,
      outline: scheme.outlineVariant,
      // 亮色下纸页要比背景更亮一点才像纸；暗色下最亮的容器色才能从背景里浮出来。
      page: isDark
          ? scheme.surfaceContainerHigh
          : Color.alphaBlend(
              accent.withValues(alpha: 0.03),
              scheme.surfaceContainerLowest,
            ),
      cover: Color.lerp(accent, scheme.surface, isDark ? 0.45 : 0.12)!,
      shadow: scheme.shadow,
      isDark: isDark,
    );
  }

  final Color accent;
  final Color ink;
  final Color outline;
  final Color page;
  final Color cover;
  final Color shadow;
  final bool isDark;

  @override
  bool operator ==(Object other) =>
      other is _LoaderPalette &&
      other.accent == accent &&
      other.ink == ink &&
      other.outline == outline &&
      other.page == page &&
      other.cover == cover &&
      other.shadow == shadow &&
      other.isDark == isDark;

  @override
  int get hashCode =>
      Object.hash(accent, ink, outline, page, cover, shadow, isDark);
}

double _smoothstep(double t) {
  final x = t.clamp(0.0, 1.0);
  return x * x * (3 - 2 * x);
}

double _easeInOutCubic(double t) {
  final x = t.clamp(0.0, 1.0);
  return x < 0.5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3) / 2;
}

/// 所有样式共用的坐标换算：在单位坐标里作画，按 viewport 缩放进画布。
abstract class _LoaderPainter extends CustomPainter {
  _LoaderPainter(this.progress, this.palette, this.viewport)
      : super(repaint: progress);

  final Animation<double> progress;
  final _LoaderPalette palette;
  final Rect viewport;

  /// 一个逻辑像素对应的单位长度，用来给细线兜底，避免小尺寸下线条消失。
  double _pixel = 0;

  double stroke(double width, {double minPixels = 1.2}) =>
      math.max(width, _pixel * minPixels);

  Paint line(Color color, double width, {double minPixels = 1.2}) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = stroke(width, minPixels: minPixels);

  Paint fill(Color color) => Paint()..color = color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final scale = math.min(
      size.width / viewport.width,
      size.height / viewport.height,
    );
    _pixel = 1 / scale;
    canvas.save();
    canvas.translate(
      (size.width - viewport.width * scale) / 2,
      (size.height - viewport.height * scale) / 2,
    );
    canvas.scale(scale);
    canvas.translate(-viewport.left, -viewport.top);
    paintFrame(canvas, progress.value);
    canvas.restore();
  }

  void paintFrame(Canvas canvas, double t);

  @override
  bool shouldRepaint(covariant _LoaderPainter oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.progress != progress;
}

// ---------------------------------------------------------------------------
// 翻书
// ---------------------------------------------------------------------------

/// 一页纸的几何：从书脊出发，上下两条二次曲线到自由边。
class _PageGeometry {
  _PageGeometry(double angle, {double flex = 0}) {
    const cx = _BookFlipPainter.cx;
    const w = _BookFlipPainter.pageWidth;
    const h = _BookFlipPainter.pageHeight;
    const y0 = _BookFlipPainter.top;
    const sag = _BookFlipPainter.spineSag;
    final s = math.sin(angle);
    // 立起来的纸页在略俯视的视角下会显得更高。
    final lift = 0.075 * s;
    final edgeX = cx + w * math.cos(angle);
    // 翻页时捏着页角，页角领先、页中间滞后，于是纸面鼓起一道弧。
    final ctrlAngle = angle - flex * s;
    final ctrlX = cx + w * 0.5 * math.cos(ctrlAngle);
    topStart = const Offset(cx, y0 + sag);
    topCtrl = Offset(ctrlX, y0 - 0.004 - lift * 0.9);
    topEnd = Offset(edgeX, y0 - lift);
    bottomStart = const Offset(cx, y0 + h + sag);
    bottomCtrl = Offset(ctrlX, y0 + h - 0.004 - lift * 0.25);
    bottomEnd = Offset(edgeX, y0 + h - lift * 0.3);
  }

  late final Offset topStart, topCtrl, topEnd;
  late final Offset bottomStart, bottomCtrl, bottomEnd;

  Path get path => Path()
    ..moveTo(topStart.dx, topStart.dy)
    ..quadraticBezierTo(topCtrl.dx, topCtrl.dy, topEnd.dx, topEnd.dy)
    ..lineTo(bottomEnd.dx, bottomEnd.dy)
    ..quadraticBezierTo(
      bottomCtrl.dx,
      bottomCtrl.dy,
      bottomStart.dx,
      bottomStart.dy,
    )
    ..close();

  static Offset _quad(Offset a, Offset c, Offset b, double u) {
    final v = 1 - u;
    return a * (v * v) + c * (2 * v * u) + b * (u * u);
  }

  /// 纸面上的点：u 沿书脊→自由边，v 沿上沿→下沿。
  Offset at(double u, double v) {
    final t = _quad(topStart, topCtrl, topEnd, u);
    final b = _quad(bottomStart, bottomCtrl, bottomEnd, u);
    return Offset.lerp(t, b, v)!;
  }
}

class _BookFlipPainter extends _LoaderPainter {
  _BookFlipPainter(Animation<double> progress, _LoaderPalette palette)
      : super(progress, palette, AppLoadingStyle.bookFlip.viewport);

  static const double cx = 0.5;
  static const double pageWidth = 0.32;
  static const double pageHeight = 0.38;
  static const double top = 0.31;
  static const double spineSag = 0.035;

  static const _rows = [0.2, 0.34, 0.48, 0.62, 0.76];
  static const _rowLengths = [0.8, 0.66, 0.84, 0.72, 0.4];

  Color get _edge => Color.lerp(palette.outline, palette.accent, 0.35)!;

  void _paintText(Canvas canvas, _PageGeometry page, double opacity) {
    if (opacity <= 0) return;
    final paint = line(palette.accent.withValues(alpha: 0.38 * opacity), 0.011);
    for (var i = 0; i < _rows.length; i++) {
      final v = _rows[i];
      const start = 0.2;
      final end = 0.2 + 0.68 * _rowLengths[i];
      final path = Path();
      const samples = 6;
      for (var k = 0; k <= samples; k++) {
        final p = page.at(start + (end - start) * k / samples, v);
        if (k == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  void _paintCover(Canvas canvas) {
    const m = 0.022;
    const w = pageWidth;
    const h = pageHeight;
    final path = Path()
      ..moveTo(cx - w - m, top + m * 0.6)
      ..quadraticBezierTo(cx - w * 0.5, top + m * 0.4, cx, top + spineSag)
      ..quadraticBezierTo(
          cx + w * 0.5, top + m * 0.4, cx + w + m, top + m * 0.6)
      ..lineTo(cx + w + m, top + h + m * 1.6)
      ..quadraticBezierTo(
        cx + w * 0.5,
        top + h + m * 1.2,
        cx,
        top + h + spineSag + m * 1.6,
      )
      ..quadraticBezierTo(
        cx - w * 0.5,
        top + h + m * 1.2,
        cx - w - m,
        top + h + m * 1.6,
      )
      ..close();
    canvas.drawPath(path, fill(palette.cover));
  }

  /// 被掀起的纸页在下方纸面投下的软影，落在自由边外侧。
  void _paintCastShadow(Canvas canvas, double angle) {
    final s = math.sin(angle);
    if (s < 0.02) return;
    final onRight = angle <= math.pi / 2;
    final edgeX = cx + pageWidth * math.cos(angle);
    final width = 0.10 * s;
    final strength = (palette.isDark ? 0.26 : 0.16) * s;
    final rect = Rect.fromLTRB(
      onRight ? edgeX : edgeX - width,
      top - 0.1,
      onRight ? edgeX + width : edgeX,
      top + pageHeight + 0.1,
    );
    final shader = LinearGradient(
      begin: onRight ? Alignment.centerLeft : Alignment.centerRight,
      end: onRight ? Alignment.centerRight : Alignment.centerLeft,
      colors: [
        palette.shadow.withValues(alpha: strength),
        palette.shadow.withValues(alpha: 0),
      ],
    ).createShader(rect);
    canvas.save();
    canvas.clipPath(_PageGeometry(onRight ? 0 : math.pi).path);
    canvas.drawRect(rect, Paint()..shader = shader);
    canvas.restore();
  }

  @override
  void paintFrame(Canvas canvas, double t) {
    _paintCover(canvas);

    // 书芯厚度：两层略微错开的纸边。
    for (final k in const [2, 1]) {
      final off = 0.006 * k;
      final color = Color.lerp(palette.page, _edge, 0.25 * k)!;
      canvas.drawPath(
        _PageGeometry(0).path.shift(Offset(off, off * 0.6)),
        fill(color),
      );
      canvas.drawPath(
        _PageGeometry(math.pi).path.shift(Offset(-off, off * 0.6)),
        fill(color),
      );
    }

    for (final angle in const [0.0, math.pi]) {
      final page = _PageGeometry(angle);
      canvas.drawPath(page.path, fill(palette.page));
      _paintText(canvas, page, 1);
    }

    // 三页错峰翻过；循环结束时左右两叠与开头完全一致，接缝不可见。
    final flips = <double>[];
    for (var i = 0; i < 3; i++) {
      final local = (t - i * 0.19) / 0.46;
      if (local > 0 && local < 1) flips.add(math.pi * _easeInOutCubic(local));
    }
    final right = flips.where((a) => a <= math.pi / 2).toList()..sort();
    final left = flips.where((a) => a > math.pi / 2).toList()
      ..sort((a, b) => b.compareTo(a));

    final shadeScale = palette.isDark ? 0.31 : 0.5;
    for (final angle in [...left, ...right]) {
      _paintCastShadow(canvas, angle);
      final page = _PageGeometry(angle, flex: 0.45);
      final s = math.sin(angle);
      final front = angle <= math.pi / 2;
      final shade = (front ? 0.35 * s : 0.15 + 0.2 * s) * shadeScale;
      final color = Color.lerp(palette.page, palette.ink, shade)!;
      canvas.drawPath(page.path, fill(color));
      canvas.drawLine(
        page.topEnd,
        page.bottomEnd,
        line(Color.lerp(color, _edge, 0.6)!, 0.006, minPixels: 0.8),
      );
      final c = math.cos(angle).abs();
      if (c > 0.35) _paintText(canvas, page, (c - 0.35) / 0.65);
    }

    // 书沟。
    const gutterTop = Offset(cx, top + spineSag);
    const gutterBottom = Offset(cx, top + pageHeight + spineSag);
    canvas.drawLine(
      gutterTop,
      gutterBottom,
      line(Color.lerp(palette.page, _edge, 0.5)!, 0.012, minPixels: 1),
    );
    canvas.drawLine(
      gutterTop,
      gutterBottom,
      line(Color.lerp(palette.page, _edge, 0.75)!, 0.007, minPixels: 0.6),
    );
  }
}

// ---------------------------------------------------------------------------
// 墨迹书写
// ---------------------------------------------------------------------------

class _InkWritingPainter extends _LoaderPainter {
  _InkWritingPainter(Animation<double> progress, _LoaderPalette palette)
      : super(progress, palette, AppLoadingStyle.inkWriting.viewport);

  static const _turns = 3;
  static const _r = 1.0;
  static const _d = 1.7;
  static const _writeEnd = 0.68;
  static final double _sMax = _turns * 2 * math.pi;

  /// 长摆线：d > r 时每一圈都会打出一个环，形如连笔的 ℓℓℓ。
  static Offset _point(double s) {
    final x = _r * s - _d * math.sin(s);
    final y = _r - _d * math.cos(s);
    final nx = 0.18 + 0.64 * (x + _d) / (_r * _sMax + 2 * _d);
    final ny = 0.43 + 0.17 * (y - (_r - _d)) / (2 * _d);
    return Offset(nx, ny);
  }

  @override
  void paintFrame(Canvas canvas, double t) {
    final rule = line(palette.outline, 0.006, minPixels: 0.8);
    for (final y in const [0.40, 0.62]) {
      canvas.drawLine(Offset(0.12, y), Offset(0.88, y), rule);
    }

    final double written;
    final double opacity;
    if (t < _writeEnd) {
      final k = t / _writeEnd;
      written = _smoothstep(k) * 0.98 + 0.02 * k;
      opacity = 1;
    } else {
      written = 1;
      opacity = 1 - _smoothstep((t - _writeEnd - 0.08) / 0.24);
    }
    if (opacity <= 0) return;

    final fade = opacity < 1;
    if (fade) {
      canvas.saveLayer(
        null,
        Paint()..color = palette.accent.withValues(alpha: opacity),
      );
    }

    // 逐段描画，笔画宽度随走笔方向轻微起伏，模拟笔压。
    final segments = math.max(1, (160 * written).round());
    final sEnd = _sMax * written;
    var prev = _point(0);
    for (var i = 1; i <= segments; i++) {
      final s = sEnd * i / segments;
      final p = _point(s);
      final w = 0.010 + 0.006 * (0.5 + 0.5 * math.sin(s - 1.2));
      canvas.drawLine(prev, p, line(palette.accent, w));
      prev = p;
    }

    if (fade) canvas.restore();

    if (t < _writeEnd + 0.04) {
      canvas.drawCircle(
          prev, stroke(0.016, minPixels: 2), fill(palette.accent));
    }
  }
}

// ---------------------------------------------------------------------------
// 墨滴晕染
// ---------------------------------------------------------------------------

class _InkDropPainter extends _LoaderPainter {
  _InkDropPainter(Animation<double> progress, _LoaderPalette palette)
      : super(progress, palette, AppLoadingStyle.inkDrop.viewport);

  static const _surfaceY = 0.62;
  static const _fall = 0.28;

  Path _drop(double x, double y, double r, double stretch) {
    final centerY = y + r * (1 - stretch) / 2;
    final ry = r * (1 + stretch) / 2;
    final tipY = y - r * stretch * 2.1;
    return Path()
      ..moveTo(x, tipY)
      ..cubicTo(
        x + r * 0.35,
        tipY + (centerY - tipY) * 0.45,
        x + r,
        centerY - ry * 0.5,
        x + r,
        centerY,
      )
      ..arcTo(
        Rect.fromCenter(
          center: Offset(x, centerY),
          width: 2 * r,
          height: 2 * ry,
        ),
        0,
        math.pi,
        false,
      )
      ..cubicTo(
        x - r,
        centerY - ry * 0.5,
        x - r * 0.35,
        tipY + (centerY - tipY) * 0.45,
        x,
        tipY,
      )
      ..close();
  }

  @override
  void paintFrame(Canvas canvas, double t) {
    canvas.drawLine(
      const Offset(0.12, _surfaceY),
      const Offset(0.88, _surfaceY),
      line(palette.outline.withValues(alpha: 0.5), 0.004, minPixels: 0.6),
    );

    if (t < _fall) {
      final k = math.pow(t / _fall, 2).toDouble();
      final y = 0.18 + (_surfaceY - 0.18) * k;
      canvas.drawPath(_drop(0.5, y, 0.028, 1 + 0.5 * k), fill(palette.accent));
      return;
    }

    final local = (t - _fall) / (1 - _fall);
    for (var i = 0; i < 3; i++) {
      final q = (local - i * 0.16) / 0.72;
      if (q <= 0 || q >= 1) continue;
      final e = 1 - math.pow(1 - q, 3).toDouble();
      final rx = 0.05 + 0.33 * e;
      canvas.drawOval(
        Rect.fromCenter(
          center: const Offset(0.5, _surfaceY),
          width: rx * 2,
          height: rx * 0.64,
        ),
        line(
          palette.accent.withValues(alpha: (1 - q) * 0.9),
          0.014 * (1 - q) + 0.003,
          minPixels: 0.8,
        ),
      );
    }

    // 落点的墨团慢慢渗进去。
    final blot = 1 - _smoothstep(local / 0.6);
    if (blot > 0) {
      final rx = 0.04 * (0.6 + 0.4 * blot);
      canvas.drawOval(
        Rect.fromCenter(
          center: const Offset(0.5, _surfaceY),
          width: rx * 2,
          height: rx * 0.7,
        ),
        fill(palette.accent.withValues(alpha: blot)),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// 逐行落笔
// ---------------------------------------------------------------------------

class _WritingLinesPainter extends _LoaderPainter {
  _WritingLinesPainter(Animation<double> progress, _LoaderPalette palette)
      : super(progress, palette, AppLoadingStyle.writingLines.viewport);

  static const _rows = [0.36, 0.50, 0.64];
  static const _lengths = [0.66, 0.54, 0.34];
  static const _x0 = 0.17;
  static const _holdFrom = 0.78;

  @override
  void paintFrame(Canvas canvas, double t) {
    final rule = line(palette.outline, 0.005, minPixels: 0.8);
    for (final y in _rows) {
      canvas.drawLine(Offset(0.12, y + 0.03), Offset(0.88, y + 0.03), rule);
    }

    final opacity =
        t < _holdFrom ? 1.0 : 1 - _smoothstep((t - _holdFrom) / 0.18);
    if (opacity <= 0) return;

    for (var i = 0; i < _rows.length; i++) {
      final q = _smoothstep((t - i * 0.22) / 0.26);
      if (q <= 0) continue;
      final y = _rows[i];
      final x1 = _x0 + _lengths[i] * q;
      canvas.drawLine(
        Offset(_x0, y),
        Offset(x1, y),
        line(palette.accent.withValues(alpha: 0.55 * opacity), 0.026),
      );
      if (q < 1) {
        canvas.drawCircle(
          Offset(x1 + 0.03, y - 0.005),
          stroke(0.012, minPixels: 1.6),
          fill(palette.accent.withValues(alpha: opacity)),
        );
      }
    }
  }
}
