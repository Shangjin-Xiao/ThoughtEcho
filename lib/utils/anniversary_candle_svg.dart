/// 庆典蛋糕上数字蜡烛的 SVG 生成。
///
/// 蛋糕主体是静态资源，数字蜡烛随周年届数在运行时生成。
/// 放在 utils 而不是 widget 里，是为了让其不依赖 Flutter（纯 Dart 环境与脚本可直接调用出图）。
library;

import 'dart:math' as math;

/// 开发者模式能模拟到的最大届数。数字蜡烛本身无上限，此常量供设置页下拉框收口。
const int maxSimulatedAnniversaryYear = 10;

/// 单个数字的字形与排版规格。
class _DigitSpec {
  final String path;
  final double wickX; // 烛芯与火苗在字形顶部的连接 x
  final double wickY; // 烛芯底端所在的 y（与数字蜡身顶面精确接合）
  final double stickX; // 插入蛋糕的烛脚 x
  final double stickY; // 烛脚顶端所在的 y

  const _DigitSpec({
    required this.path,
    required this.wickX,
    required this.wickY,
    required this.stickX,
    required this.stickY,
  });
}

/// 标准字形盒：宽 56、高 74。
const double _digitWidth = 56;
const double _digitHeight = 74;
const double _digitGap = 14;

/// 蛋糕顶面奶油上蜡烛底部所在的 y 坐标（与蛋糕主体资源对齐）。
const double _bottomY = 168;

/// 数字蜡烛整体最宽限制（超过则等比缩放，避免超出蛋糕奶油顶面）。
const double _maxNumberWidth = 160;

/// 0-9 数字蜡烛字形定义：
/// 笔画饱满圆润、内部孔洞清晰开阔，顶部各带精准的烛芯接合点，底部各带烛脚。
const Map<String, _DigitSpec> _digitSpecs = {
  '0': _DigitSpec(
    path: 'M28 10 C39 10 46 22 46 37 C46 52 39 64 28 64 '
        'C17 64 10 52 10 37 C10 22 17 10 28 10 Z',
    wickX: 28,
    wickY: 2,
    stickX: 28,
    stickY: 72,
  ),
  '1': _DigitSpec(
    path: 'M17 25 L30 10 L30 64',
    wickX: 30,
    wickY: 2,
    stickX: 30,
    stickY: 72,
  ),
  '2': _DigitSpec(
    path: 'M14 26 C15 13 24 9 32 9 C41 9 46 15 46 24 '
        'C46 38 29 48 13 64 L46 64',
    wickX: 32,
    wickY: 1,
    stickX: 29,
    stickY: 72,
  ),
  '3': _DigitSpec(
    path: 'M14 22 C18 13 25 9 33 9 C43 9 47 16 47 24 '
        'C47 33 39 37 29 37 C41 37 48 44 48 53 '
        'C48 62 40 65 31 65 C21 65 14 59 12 52',
    wickX: 33,
    wickY: 1,
    stickX: 30,
    stickY: 72,
  ),
  '4': _DigitSpec(
    path: 'M33 64 L33 10 L11 44 L45 44',
    wickX: 33,
    wickY: 2,
    stickX: 33,
    stickY: 72,
  ),
  '5': _DigitSpec(
    path: 'M43 10 L18 10 L15 34 C21 29 27 28 33 28 '
        'C42 28 47 35 47 48 C47 59 40 65 30 65 '
        'C20 65 14 60 11 53',
    wickX: 30,
    wickY: 2,
    stickX: 29,
    stickY: 72,
  ),
  '6': _DigitSpec(
    path: 'M40 14 C36 10 32 9 27 9 C17 9 10 20 10 40 '
        'C10 56 18 65 29 65 C40 65 47 56 47 46 '
        'C47 36 40 28 29 28 C19 28 12 36 10 44',
    wickX: 27,
    wickY: 1,
    stickX: 28,
    stickY: 72,
  ),
  '7': _DigitSpec(
    path: 'M14 10 L44 10 L26 64',
    wickX: 29,
    wickY: 2,
    stickX: 26,
    stickY: 72,
  ),
  '8': _DigitSpec(
    path: 'M28 37 C20 37 12 43 12 52 C12 60 19 65 28 65 '
        'C37 65 44 60 44 52 C44 43 36 37 28 37 '
        'C19 37 14 31 14 23 C14 15 20 9 28 9 '
        'C36 9 42 15 42 23 C42 31 37 37 28 37 Z',
    wickX: 28,
    wickY: 1,
    stickX: 28,
    stickY: 72,
  ),
  '9': _DigitSpec(
    path: 'M16 60 C20 64 24 65 29 65 C39 65 46 54 46 34 '
        'C46 18 38 9 27 9 C16 9 9 18 9 28 '
        'C9 38 16 46 27 46 C37 46 44 38 46 30',
    wickX: 27,
    wickY: 1,
    stickX: 28,
    stickY: 72,
  ),
};

/// 生成第 [years] 周年的数字蜡烛 SVG（与蛋糕主体使用同一个 400×400 viewBox）。
String buildAnniversaryCandleSvg(int years) {
  final digits = math.max(1, years).toString().split('');
  final rawWidth =
      digits.length * _digitWidth + (digits.length - 1) * _digitGap;
  final scale = math.min(1.0, _maxNumberWidth / rawWidth);
  final totalWidth = rawWidth * scale;
  final height = _digitHeight * scale;
  final startX = 200 - totalWidth / 2;
  final topY = _bottomY - height;
  final scaledGap = _digitGap * scale;
  final scaledDigitW = _digitWidth * scale;

  final buffer = StringBuffer()
    ..write('<svg xmlns="http://www.w3.org/2000/svg" '
        'viewBox="0 0 400 400" width="100%" height="100%">')
    ..write('<defs>')
    // 庆典金色渐变（明快温暖的香槟金到琥珀金）
    ..write(
        '<linearGradient id="candleBodyGrad" x1="0%" y1="0%" x2="100%" y2="100%">'
        '<stop offset="0%" stop-color="#FFE57F"/>'
        '<stop offset="40%" stop-color="#FFB300"/>'
        '<stop offset="100%" stop-color="#E65100"/>'
        '</linearGradient>')
    ..write('</defs>');

  // 1. 落在蛋糕白色奶油上的接触阴影
  for (int i = 0; i < digits.length; i++) {
    final spec = _digitSpecs[digits[i]] ?? _digitSpecs['0']!;
    final footX = startX + i * (scaledDigitW + scaledGap) + spec.stickX * scale;
    buffer.write('<ellipse cx="${_n(footX)}" cy="${_n(_bottomY + 4)}" '
        'rx="${_n(18 * scale)}" ry="${_n(5.5 * scale)}" fill="#CBD5E1" opacity="0.8"/>');
  }

  // 2. 插入蛋糕奶油的白色透明烛脚插签
  for (int i = 0; i < digits.length; i++) {
    final spec = _digitSpecs[digits[i]] ?? _digitSpecs['0']!;
    final footX = startX + i * (scaledDigitW + scaledGap) + spec.stickX * scale;
    final stickW = 5.0 * scale;
    final stickH = 12.0 * scale;
    buffer.write(
        '<rect x="${_n(footX - stickW / 2)}" y="${_n(_bottomY - 4 * scale)}" '
        'width="${_n(stickW)}" height="${_n(stickH)}" rx="${_n(2 * scale)}" fill="#E2E8F0"/>');
    buffer.write(
        '<rect x="${_n(footX - stickW / 2)}" y="${_n(_bottomY - 4 * scale)}" '
        'width="${_n(stickW * 0.4)}" height="${_n(stickH)}" rx="${_n(1 * scale)}" fill="#FFFFFF"/>');
  }

  // 3. 数字蜡烛身（3D立体厚度、外轮廓、主体渐变、内嵌浅金色线与高光反射）
  for (int i = 0; i < digits.length; i++) {
    final spec = _digitSpecs[digits[i]] ?? _digitSpecs['0']!;
    final dx = startX + i * (scaledDigitW + scaledGap);
    final path = spec.path;

    buffer.write(
        '<g transform="translate(${_n(dx)} ${_n(topY)}) scale(${_n(scale)})">');

    // (a) 3D 立体下沉厚度
    buffer.write('<path d="$path" fill="none" stroke="#BF360C" '
        'stroke-width="17" stroke-linecap="round" stroke-linejoin="round" '
        'transform="translate(1.5, 3.5)"/>');

    // (b) 蜡质外沿基底
    buffer.write('<path d="$path" fill="none" stroke="#E65100" '
        'stroke-width="17" stroke-linecap="round" stroke-linejoin="round"/>');

    // (c) 蜡烛主体渐变
    buffer.write('<path d="$path" fill="none" stroke="url(#candleBodyGrad)" '
        'stroke-width="13.5" stroke-linecap="round" stroke-linejoin="round"/>');

    // (d) 内部浅金色嵌线
    buffer.write('<path d="$path" fill="none" stroke="#FFF9C4" '
        'stroke-width="5" stroke-linecap="round" stroke-linejoin="round" stroke-opacity="0.85"/>');

    // (e) 左上方高光条
    buffer.write('<path d="$path" fill="none" stroke="#FFFFFF" '
        'stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" '
        'stroke-opacity="0.85" transform="translate(-1.8, -1.8)"/>');

    buffer.write('</g>');
  }

  // 4. 棉质烛芯与多层温暖火苗（每个数字独立生火，自然逼真）
  for (int i = 0; i < digits.length; i++) {
    final spec = _digitSpecs[digits[i]] ?? _digitSpecs['0']!;
    final dx = startX + i * (scaledDigitW + scaledGap);
    final wickX = dx + spec.wickX * scale;
    final wickY = topY + spec.wickY * scale;
    final wickTipY = wickY - 10.0 * scale;

    // 烛芯
    buffer.write('<path d="M ${_n(wickX)} ${_n(wickY + 1 * scale)} '
        'Q ${_n(wickX - 1.2 * scale)} ${_n(wickY - 5 * scale)} ${_n(wickX)} ${_n(wickTipY)}" '
        'stroke="#374151" stroke-width="${_n(2.2 * scale)}" stroke-linecap="round" fill="none"/>');

    // 火苗
    buffer.write(
        '<g transform="translate(${_n(wickX)} ${_n(wickTipY)}) scale(${_n(scale)})">');

    // 环境暖光晕
    buffer.write(
        '<circle cx="0" cy="-15" r="28" fill="#FFA000" fill-opacity="0.15"/>');
    buffer.write(
        '<circle cx="0" cy="-15" r="18" fill="#FFA000" fill-opacity="0.25"/>');

    // 外层橘红火苗
    buffer.write(
        '<path d="M 0 0 C 13 -4, 10 -19, 0 -30 C -10 -19, -13 -4, 0 0 Z" fill="#FF7A00"/>');

    // 中层金黄火芯
    buffer.write(
        '<path d="M 0 -1.5 C 7 -4.5, 5.5 -15, 0 -21 C -5.5 -15, -7 -4.5, 0 -1.5 Z" fill="#FFD000"/>');

    // 内层亮白核心
    buffer.write(
        '<path d="M 0 -3.5 C 3.2 -5.5, 2.2 -11, 0 -14 C -2.2 -11, -3.2 -5.5, 0 -3.5 Z" fill="#FFFFFF"/>');

    // 底部微蓝焰根
    buffer.write(
        '<ellipse cx="0" cy="-1.5" rx="3" ry="1.6" fill="#38BDF8" opacity="0.85"/>');

    buffer.write('</g>');
  }

  buffer.write('</svg>');
  return buffer.toString();
}

/// SVG 数值格式化：去除冗余小数位。
String _n(double value) {
  final rounded = (value * 100).round() / 100;
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toString();
}
