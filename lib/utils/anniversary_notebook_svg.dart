/// 庆典横幅上笔记本插画的 SVG 生成。
///
/// 封面上的年份数字过去是画死在静态资源里的「1」，两周年就会对不上。现在整张图在
/// 运行时生成：本体是固定的几何形状，数字部分复用 [anniversaryDigitPaths]，届数
/// 变几位数都能自己排版缩放。
///
/// 放在 utils 而不是 widget 里，是为了让其不依赖 Flutter（纯 Dart 环境与脚本可直接调用出图）。
library;

import 'dart:math' as math;

import 'package:thoughtecho/utils/anniversary_digit_glyphs.dart';

/// 封面上留给年份的区域（100×100 viewBox 坐标系）：避开左侧书脊，四周留白。
const double _numberCenterX = 51;
const double _numberCenterY = 49;
const double _numberMaxWidth = 44;
const double _numberMaxHeight = 44;

/// 数字在字形盒坐标系下的描边粗细。
const double _numberStrokeWidth = 10;

/// 封面上相邻数字的间距。比蛋糕蜡烛那边收窄一些：封面地方小，用共用间距的话
/// 两位数会被挤得又小又散。
const double _numberGap = 6;

/// 生成第 [years] 周年的笔记本插画 SVG。[years] 小于 1 时按 1 处理。
String buildAnniversaryNotebookSvg(int years) {
  final digits = math.max(1, years).toString().split('');
  final rawWidth =
      digits.length * anniversaryDigitWidth + (digits.length - 1) * _numberGap;
  final scale = math.min(
    _numberMaxWidth / rawWidth,
    _numberMaxHeight / anniversaryDigitHeight,
  );
  final totalWidth = rawWidth * scale;
  final startX = _numberCenterX - totalWidth / 2;
  // 字形盒里的实际笔画大致落在 y 9~65，用这段的中点对齐视觉中心，
  // 而不是拿字形盒的几何中心去对，否则数字会整体偏下。
  final topY = _numberCenterY - (9 + 65) / 2 * scale;
  final stepX = (anniversaryDigitWidth + _numberGap) * scale;

  final buffer = StringBuffer()
    ..write('<svg xmlns="http://www.w3.org/2000/svg" '
        'viewBox="0 0 100 100" width="100%" height="100%" fill="none">')
    ..write('<defs>')
    ..write(
        '<linearGradient id="coverGradient" x1="16" y1="12" x2="76" y2="86" '
        'gradientUnits="userSpaceOnUse">'
        '<stop stop-color="#4B8DFF"/>'
        '<stop offset="1" stop-color="#1954E6"/>'
        '</linearGradient>')
    ..write(
        '<linearGradient id="ribbonGradient" x1="32" y1="80" x2="32" y2="98" '
        'gradientUnits="userSpaceOnUse">'
        '<stop stop-color="#FF4D4D"/>'
        '<stop offset="1" stop-color="#DE0000"/>'
        '</linearGradient>')
    ..write('<filter id="ambientShadow" x="0" y="0" width="100" height="100" '
        'filterUnits="userSpaceOnUse">'
        '<feDropShadow dx="2" dy="6" stdDeviation="6" flood-color="#0F2B73" '
        'flood-opacity="0.15"/>'
        '</filter>')
    // 数字投影的作用域要能容下两位数，别沿用一周年时那个 60×60 的小方框。
    ..write('<filter id="numShadow" x="10" y="10" width="80" height="80" '
        'filterUnits="userSpaceOnUse">'
        '<feDropShadow dx="0" dy="2" stdDeviation="2.5" flood-color="#000000" '
        'flood-opacity="0.2"/>'
        '</filter>')
    ..write('</defs>')
    ..write('<g filter="url(#ambientShadow)">')
    // 内页
    ..write(
        '<rect x="20" y="16" width="58" height="74" rx="4" fill="#E2E8F0"/>')
    ..write(
        '<rect x="18" y="14" width="58" height="74" rx="4" fill="#F8FAFC"/>')
    ..write('<line x1="74" y1="18" x2="74" y2="84" stroke="#E2E8F0" '
        'stroke-width="0.5"/>')
    ..write('<line x1="72" y1="16" x2="72" y2="86" stroke="#E2E8F0" '
        'stroke-width="0.5"/>')
    // 书签带
    ..write('<path d="M 28 80 L 36 80 L 36 96 L 32 92 L 28 96 Z" '
        'fill="url(#ribbonGradient)"/>')
    ..write('<rect x="28" y="80" width="8" height="3" fill="#000000" '
        'fill-opacity="0.15"/>')
    // 封面与书脊
    ..write('<rect x="16" y="12" width="60" height="74" rx="4" '
        'fill="url(#coverGradient)"/>')
    ..write('<rect x="16.5" y="12.5" width="59" height="73" rx="3.5" '
        'stroke="#FFFFFF" stroke-opacity="0.35" stroke-width="1"/>')
    ..write('<path d="M 16 16 A 4 4 0 0 1 20 12 L 26 12 L 26 86 L 20 86 '
        'A 4 4 0 0 1 16 82 Z" fill="#001144" fill-opacity="0.2"/>')
    ..write('<line x1="26" y1="12" x2="26" y2="86" stroke="#000000" '
        'stroke-opacity="0.15" stroke-width="0.5"/>')
    ..write('<line x1="26.5" y1="12" x2="26.5" y2="86" stroke="#FFFFFF" '
        'stroke-opacity="0.15" stroke-width="0.5"/>')
    // 封面上的年份
    ..write('<g filter="url(#numShadow)">');

  for (var i = 0; i < digits.length; i++) {
    final dx = startX + i * stepX;
    buffer.write('<g transform="translate(${formatSvgNumber(dx)} '
        '${formatSvgNumber(topY)}) scale(${formatSvgNumber(scale)})">');
    buffer.write('<path d="${anniversaryDigitPath(digits[i])}" fill="none" '
        'stroke="#FFFFFF" stroke-width="${formatSvgNumber(_numberStrokeWidth)}" '
        'stroke-linecap="round" stroke-linejoin="round"/>');
    buffer.write('</g>');
  }

  buffer
    ..write('</g>')
    ..write('</g>')
    ..write('</svg>');
  return buffer.toString();
}
