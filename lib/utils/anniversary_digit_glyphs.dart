/// 周年数字的共用字形。
///
/// 蛋糕上的数字蜡烛和横幅笔记本封面上的年份用的是同一套字形：路径都是「描边中线」
/// （用 stroke 画，不是 fill），所以同一条 path 换个描边颜色和粗细就能既当蜡烛又当
/// 封面烫金数字，届数变化只影响运行时生成的那一层，不用再改静态图。
library;

/// 标准字形盒：宽 56、高 74。
const double anniversaryDigitWidth = 56;
const double anniversaryDigitHeight = 74;

/// 相邻数字之间的间距（与字形盒同一坐标系）。
const double anniversaryDigitGap = 14;

/// 0-9 的字形中线路径：笔画饱满圆润、内部孔洞清晰开阔。
const Map<String, String> anniversaryDigitPaths = {
  '0': 'M28 10 C39 10 46 22 46 37 C46 52 39 64 28 64 '
      'C17 64 10 52 10 37 C10 22 17 10 28 10 Z',
  '1': 'M17 25 L30 10 L30 64',
  '2': 'M14 26 C15 13 24 9 32 9 C41 9 46 15 46 24 '
      'C46 38 29 48 13 64 L46 64',
  '3': 'M14 22 C18 13 25 9 33 9 C43 9 47 16 47 24 '
      'C47 33 39 37 29 37 C41 37 48 44 48 53 '
      'C48 62 40 65 31 65 C21 65 14 59 12 52',
  '4': 'M33 64 L33 10 L11 44 L45 44',
  '5': 'M43 10 L18 10 L15 34 C21 29 27 28 33 28 '
      'C42 28 47 35 47 48 C47 59 40 65 30 65 '
      'C20 65 14 60 11 53',
  '6': 'M40 14 C36 10 32 9 27 9 C17 9 10 20 10 40 '
      'C10 56 18 65 29 65 C40 65 47 56 47 46 '
      'C47 36 40 28 29 28 C19 28 12 36 10 44',
  '7': 'M14 10 L44 10 L26 64',
  '8': 'M28 37 C20 37 12 43 12 52 C12 60 19 65 28 65 '
      'C37 65 44 60 44 52 C44 43 36 37 28 37 '
      'C19 37 14 31 14 23 C14 15 20 9 28 9 '
      'C36 9 42 15 42 23 C42 31 37 37 28 37 Z',
  '9': 'M16 60 C20 64 24 65 29 65 C39 65 46 54 46 34 '
      'C46 18 38 9 27 9 C16 9 9 18 9 28 '
      'C9 38 16 46 27 46 C37 46 44 38 46 30',
};

/// 取 [digit] 的字形路径，非 0-9 的字符退回 `0`，保证调用方拿得到东西画。
String anniversaryDigitPath(String digit) =>
    anniversaryDigitPaths[digit] ?? anniversaryDigitPaths['0']!;

/// [digits] 排成一行（含间距）后的总宽度。
double anniversaryDigitsWidth(int digitCount) =>
    digitCount * anniversaryDigitWidth + (digitCount - 1) * anniversaryDigitGap;

/// SVG 数值格式化：去掉冗余小数位，别让 `12.0` 这种写进属性里。
String formatSvgNumber(double value) {
  final rounded = (value * 100).round() / 100;
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toString();
}
