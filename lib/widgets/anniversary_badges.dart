import 'package:flutter/material.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';

/// 庆典横幅上的纪念勋章墙：参与过第几届就挂第几枚。
///
/// 取代了动画里那句「你从 N 周年起就在这里了」—— 一句话只能说出最早那一届，
/// 勋章能把每一届都摆出来，三周年时参与过一、二周年的人看到的就是两枚。
class AnniversaryBadgeRow extends StatelessWidget {
  /// 已获得的届数，升序。
  final List<int> years;

  /// 最多摆几枚，超出的收进「+N」。横幅地方有限，别撑成两行。
  final int maxVisible;

  /// 溢出计数的文字颜色，跟着横幅的前景色走。
  final Color overflowColor;

  const AnniversaryBadgeRow({
    super.key,
    required this.years,
    required this.overflowColor,
    this.maxVisible = 5,
  });

  @override
  Widget build(BuildContext context) {
    if (years.isEmpty) return const SizedBox.shrink();

    final visible = years.take(maxVisible).toList();
    final hidden = years.length - visible.length;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final year in visible) _AnniversaryBadge(year: year),
        if (hidden > 0)
          Text(
            '+$hidden',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: overflowColor.withValues(alpha: 0.75),
                  fontWeight: FontWeight.w600,
                ),
          ),
      ],
    );
  }
}

/// 单枚勋章：金色圆牌 + 底下垂着的红绶带。
class _AnniversaryBadge extends StatelessWidget {
  final int year;

  const _AnniversaryBadge({required this.year});

  /// 圆牌直径。
  static const double _discSize = 28;

  /// 绶带露在圆牌下方的高度。
  static const double _ribbonDrop = 9;

  /// 绶带整体高度：多出来的部分掖在圆牌背后，免得接缝处露出一道断口。
  static const double _ribbonHeight = _ribbonDrop + 8;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = l10n.anniversaryBadgeTooltip(year);

    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: SizedBox(
          width: _discSize,
          height: _discSize + _ribbonDrop,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              // 绶带先画，被圆牌压住上沿。
              Positioned(
                top: _discSize + _ribbonDrop - _ribbonHeight,
                child: CustomPaint(
                  size: const Size(_discSize, _ribbonHeight),
                  painter: const _RibbonPainter(),
                ),
              ),
              Container(
                width: _discSize,
                height: _discSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFE08A), Color(0xFFE39B2C)],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.7),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7A4B00).withValues(alpha: 0.25),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  '$year',
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF5A3300),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 勋章下方的两条红绶带，末端各开一个 V 形缺口。
///
/// 两条给不同深浅：左边压暗一点当背面，右边亮一点当正面，交叠处才有前后关系，
/// 不然一整块纯红看着像个方块。
class _RibbonPainter extends CustomPainter {
  const _RibbonPainter();

  static const Color _front = Color(0xFFE23B3B);
  static const Color _back = Color(0xFFB01C1C);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final bottom = size.height;
    final notch = bottom - 4;
    const halfWidth = 6.5;
    const lean = 2.5; // 两条带子向外岔开的量

    // 左带（在后）
    final left = Path()
      ..moveTo(cx - 1, 0)
      ..lineTo(cx + halfWidth - lean - 1, 0)
      ..lineTo(cx + 1 - lean, bottom)
      ..lineTo(cx - 2 - lean, notch)
      ..lineTo(cx - halfWidth - lean, bottom)
      ..close();
    canvas.drawPath(left, Paint()..color = _back);

    // 右带（在前）
    final right = Path()
      ..moveTo(cx - halfWidth + lean + 1, 0)
      ..lineTo(cx + 1, 0)
      ..lineTo(cx + halfWidth + lean, bottom)
      ..lineTo(cx + 2 + lean, notch)
      ..lineTo(cx - 1 + lean, bottom)
      ..close();
    canvas.drawPath(right, Paint()..color = _front);
  }

  @override
  bool shouldRepaint(covariant _RibbonPainter oldDelegate) => false;
}
