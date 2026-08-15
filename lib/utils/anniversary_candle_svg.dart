/// 庆典蛋糕上那根数字蜡烛的 SVG 生成。
///
/// 蛋糕主体是静态资源，蜡烛随届数变化，只能运行时拼。放在 utils 而不是 widget 里，
/// 是为了让它不依赖 Flutter —— 纯 Dart 脚本可以直接调它出图预览。
///
/// 用数字而不是插 N 根蜡烛：展示尺寸只有 100–200px，蜡烛一多就得变细，几个小火苗
/// 挤在奶油上根本数不清，而「第几周年」恰恰是要被读到的信息。数字蜡烛任何届数都
/// 一眼可读、尺寸恒定，也只有一套布局要维护。
library;

import 'dart:math' as math;

/// 开发者模式能模拟到的最大届数。数字蜡烛本身没有上限，这个数只是给下拉框收口。
const int maxSimulatedAnniversaryYear = 10;

/// 数字字形的设计坐标系：每个字宽 [_digitWidth]、高 [_digitHeight]，
/// 路径按「一根弯成数字形状的蜡」来画，靠圆头描边成型。
const double _digitWidth = 60;
const double _digitHeight = 100;
const double _digitGap = 14;

/// 烛身粗细（描边宽度）。
const double _waxStroke = 19;

/// 蛋糕顶面上蜡烛底部所在的 y，与蛋糕主体资源对齐。
const double _bottomY = 165;

/// 数字蜡烛整体最宽画到这里，再宽就压过奶油顶面了。
const double _maxNumberWidth = 168;

/// 螺旋条纹的颜色和疏密。红白是生日蜡烛最认得出来的配色，也接得上一周年那版
/// 蜡烛身上的红斜纹。
const String _stripeColor = '#E63946';
const double _stripeDash = 11;
const double _stripeGap = 19;

/// 每个数字一条连续路径，画法是「描边成型」而不是填充闭合图形 ——
/// 现实里的数字蜡烛就是一根蜡弯出来的，圆头收尾自带蜡烛的钝角。
const Map<String, String> _digitPaths = {
  '0': 'M30 6 C46 6 55 26 55 53 C55 80 46 96 30 96 '
      'C14 96 5 80 5 53 C5 26 14 6 30 6 Z',
  '1': 'M13 26 L31 8 L31 96',
  '2': 'M8 28 C10 13 21 6 33 6 C47 6 55 15 55 29 '
      'C55 47 33 59 8 96 L55 96',
  '3': 'M8 22 C14 11 24 6 34 6 C47 6 54 14 54 26 '
      'C54 38 45 47 32 47 C46 47 57 55 57 71 '
      'C57 86 45 96 32 96 C21 96 11 90 7 79',
  '4': 'M44 96 L44 8 L6 68 L56 68',
  '5': 'M50 8 L19 8 L13 45 C21 39 28 37 34 37 '
      'C48 37 57 47 57 66 C57 84 45 96 30 96 '
      'C19 96 11 92 6 84',
  '6': 'M47 12 C42 8 36 6 30 6 C17 6 7 22 7 53 '
      'C7 80 17 96 32 96 C45 96 55 86 55 71 '
      'C55 57 45 47 33 47 C21 47 11 55 9 65',
  '7': 'M7 8 L55 8 L27 96',
  '8': 'M30 47 C17 47 7 57 7 71 C7 86 17 96 30 96 '
      'C43 96 53 86 53 71 C53 57 43 47 30 47 '
      'C19 47 11 38 11 27 C11 14 20 6 30 6 '
      'C41 6 50 14 50 27 C50 38 42 47 30 47 Z',
  '9': 'M13 90 C19 94 25 96 31 96 C44 96 54 80 54 49 '
      'C54 22 44 6 29 6 C16 6 6 16 6 31 '
      'C6 46 16 56 28 56 C40 56 50 47 52 37',
};

/// 生成第 [years] 周年的数字蜡烛 SVG（与蛋糕主体同一个 400×400 viewBox）。
String buildAnniversaryCandleSvg(int years) {
  final digits = math.max(1, years).toString().split('');
  final rawWidth =
      digits.length * _digitWidth + (digits.length - 1) * _digitGap;
  // 位数多了整体缩小，别压过奶油顶面；单位数不放大，保持和一周年时一样的分量。
  final scale = math.min(1.0, _maxNumberWidth / rawWidth);
  final width = rawWidth * scale;
  final height = _digitHeight * scale;
  final left = 200 - width / 2;
  final top = _bottomY - height;
  final stroke = _waxStroke * scale;

  final buffer = StringBuffer()
    ..write('<svg xmlns="http://www.w3.org/2000/svg" '
        'viewBox="0 0 400 400" width="100%" height="100%">')
    ..write('<defs>')
    ..write('<linearGradient id="waxGrad" x1="0%" y1="0%" x2="100%" y2="0%">'
        '<stop offset="0%" stop-color="#E5E7EB"/>'
        '<stop offset="30%" stop-color="#FFFFFF"/>'
        '<stop offset="70%" stop-color="#FFFFFF"/>'
        '<stop offset="100%" stop-color="#D1D5DB"/>'
        '</linearGradient>')
    ..write('<radialGradient id="flameGlow">'
        '<stop offset="0%" stop-color="#FFAA00" stop-opacity="0.45"/>'
        '<stop offset="100%" stop-color="#FFAA00" stop-opacity="0"/>'
        '</radialGradient>')
    ..write('</defs>');

  // 落在奶油上的接触阴影
  buffer.write('<ellipse cx="200" cy="${_n(_bottomY + 3)}" '
      'rx="${_n(width * 0.42)}" ry="${_n(stroke * 0.3)}" fill="#CBD5E1"/>');

  buffer.write('<g transform="translate(${_n(left)} ${_n(top)}) '
      'scale(${_n(scale)})">');
  for (var i = 0; i < digits.length; i++) {
    final path = _digitPaths[digits[i]];
    if (path == null) continue;
    final dx = i * (_digitWidth + _digitGap);
    buffer.write('<g transform="translate(${_n(dx)} 0)">'
        // 底下压一圈深一点的边，让白蜡在白奶油上仍有轮廓
        '<path d="$path" fill="none" stroke="#D1D5DB" '
        'stroke-width="${_n(_waxStroke + 4)}" stroke-linecap="round" '
        'stroke-linejoin="round"/>'
        '<path d="$path" fill="none" stroke="url(#waxGrad)" '
        'stroke-width="${_n(_waxStroke)}" stroke-linecap="round" '
        'stroke-linejoin="round"/>'
        // 螺旋红条：同一条路径再描一遍，靠虚线间隔断成一段段，条纹自然跟着
        // 数字转弯。宽度比烛身窄一圈，万一渲染器不支持 dasharray，退化成一条
        // 沿数字走的红芯，仍是「有颜色的蜡烛」而不是一块红。
        '<path d="$path" fill="none" stroke="$_stripeColor" '
        'stroke-width="${_n(_waxStroke * 0.62)}" stroke-linecap="butt" '
        'stroke-linejoin="round" '
        'stroke-dasharray="${_n(_stripeDash)} ${_n(_stripeGap)}"/>'
        // 偏左上的细高光，蜡的圆柱感全靠它
        '<path d="$path" fill="none" stroke="#FFFFFF" stroke-opacity="0.75" '
        'stroke-width="${_n(_waxStroke * 0.26)}" stroke-linecap="round" '
        'stroke-linejoin="round" transform="translate(-2.5 -2.5)"/>'
        '</g>');
  }
  buffer.write('</g>');

  // 烛芯和火苗：整组数字只有一支，位置取数字顶端正中。
  final flameScale = scale;
  final wickTop = top - 15 * flameScale;
  buffer.write('<path d="M 200 ${_n(top)} '
      'Q ${_n(197.5)} ${_n(top - 8 * flameScale)} 200 ${_n(wickTop)}" '
      'stroke="#4B5563" stroke-width="${_n(2.5 * flameScale)}" '
      'stroke-linecap="round" fill="none"/>');
  buffer.write('<g transform="translate(200 ${_n(wickTop - 1)}) '
      'scale(${_n(flameScale)})">'
      '<circle cx="0" cy="-22" r="34" fill="url(#flameGlow)"/>'
      '<path d="M 0 0 C 20 -5, 15 -28, 0 -40 C -15 -28, -20 -5, 0 0 Z" '
      'fill="#FF8C00"/>'
      '<path d="M 0 -2 C 10 -8, 8 -22, 0 -28 C -8 -22, -10 -8, 0 -2 Z" '
      'fill="#FFD700"/>'
      '<path d="M 0 -5 C 4 -8, 3 -15, 0 -18 C -3 -15, -4 -8, 0 -5 Z" '
      'fill="#FFFFFF"/>'
      '<ellipse cx="0" cy="-2" rx="4" ry="2" fill="#4FC3F7" opacity="0.8"/>'
      '</g>');

  buffer.write('</svg>');
  return buffer.toString();
}

/// SVG 数值：去掉多余小数位，别让生成的字符串又长又抖。
String _n(double value) {
  final rounded = (value * 100).round() / 100;
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toString();
}
