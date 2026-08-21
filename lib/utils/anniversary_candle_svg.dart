/// 庆典蛋糕上数字蜡烛的 SVG 生成。
///
/// 蛋糕主体是静态资源，数字蜡烛随周年届数在运行时生成。
/// 放在 utils 而不是 widget 里，是为了让其不依赖 Flutter（纯 Dart 环境与脚本可直接调用出图）。
library;

import 'dart:math' as math;

import 'package:thoughtecho/utils/anniversary_digit_glyphs.dart';

/// 数字蜡烛排版覆盖到的最大届数。蜡烛本身位数无上限，这个上界供测试遍历用。
const int maxSimulatedAnniversaryYear = 10;

/// 单个数字蜡烛的排版规格：字形本身来自 [anniversaryDigitPaths]，这里只记蜡烛
/// 独有的烛芯与烛脚接点。
class _DigitSpec {
  final double wickX; // 烛芯与火苗在字形顶部的连接 x
  final double wickY; // 烛芯底端所在的 y（与数字蜡身顶面精确接合）
  final double stickX; // 插入蛋糕的烛脚 x
  final double stickY; // 烛脚顶端所在的 y

  const _DigitSpec({
    required this.wickX,
    required this.wickY,
    required this.stickX,
    required this.stickY,
  });
}

/// 蛋糕顶面奶油上蜡烛底部所在的 y 坐标（与蛋糕主体资源对齐）。
const double _bottomY = 168;

/// 数字蜡烛整体最宽限制（超过则等比缩放，避免超出蛋糕奶油顶面）。
const double _maxNumberWidth = 160;

/// 0-9 各自的烛芯接合点与烛脚位置，与共用字形一一对应。
const Map<String, _DigitSpec> _digitSpecs = {
  '0': _DigitSpec(
    wickX: 28,
    wickY: 2,
    stickX: 28,
    stickY: 72,
  ),
  '1': _DigitSpec(
    wickX: 30,
    wickY: 2,
    stickX: 30,
    stickY: 72,
  ),
  '2': _DigitSpec(
    wickX: 32,
    wickY: 1,
    stickX: 29,
    stickY: 72,
  ),
  '3': _DigitSpec(
    wickX: 33,
    wickY: 1,
    stickX: 30,
    stickY: 72,
  ),
  '4': _DigitSpec(
    wickX: 33,
    wickY: 2,
    stickX: 33,
    stickY: 72,
  ),
  '5': _DigitSpec(
    wickX: 30,
    wickY: 2,
    stickX: 29,
    stickY: 72,
  ),
  '6': _DigitSpec(
    wickX: 27,
    wickY: 1,
    stickX: 28,
    stickY: 72,
  ),
  '7': _DigitSpec(
    wickX: 29,
    wickY: 2,
    stickX: 26,
    stickY: 72,
  ),
  '8': _DigitSpec(
    wickX: 28,
    wickY: 1,
    stickX: 28,
    stickY: 72,
  ),
  '9': _DigitSpec(
    wickX: 27,
    wickY: 1,
    stickX: 28,
    stickY: 72,
  ),
};

/// 生成第 [years] 周年的数字蜡烛 SVG（与蛋糕主体使用同一个 400×400 viewBox）。
String buildAnniversaryCandleSvg(int years) {
  final digits = math.max(1, years).toString().split('');
  final rawWidth = anniversaryDigitsWidth(digits.length);
  final scale = math.min(1.0, _maxNumberWidth / rawWidth);
  final totalWidth = rawWidth * scale;
  final height = anniversaryDigitHeight * scale;
  final startX = 200 - totalWidth / 2;
  final topY = _bottomY - height;
  final scaledGap = anniversaryDigitGap * scale;
  final scaledDigitW = anniversaryDigitWidth * scale;

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
    final dx = startX + i * (scaledDigitW + scaledGap);
    final path = anniversaryDigitPath(digits[i]);

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
String _n(double value) => formatSvgNumber(value);
