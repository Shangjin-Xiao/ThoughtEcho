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

/// 单枚勋章：金色圆牌 + 届数。
class _AnniversaryBadge extends StatelessWidget {
  final int year;

  const _AnniversaryBadge({required this.year});

  static const double _size = 28;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = l10n.anniversaryBadgeTooltip(year);

    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: Container(
          width: _size,
          height: _size,
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
      ),
    );
  }
}
