import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:thoughtecho/utils/anniversary_candle_svg.dart';

/// 庆典蛋糕：蛋糕主体是静态资源，数字蜡烛按周年届数在运行时生成。
///
/// 一周年那版把唯一一根蜡烛画进了 SVG 里，换届就得改图。现在两层叠在同一个
/// 400×400 viewBox 上（都用 `BoxFit.contain`，所以坐标天然对齐），届数变化只影响
/// 生成的蜡烛层。
class AnniversaryCake extends StatelessWidget {
  /// 第几周年，决定蜡烛上的数字。
  final int years;

  const AnniversaryCake({super.key, required this.years});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        SvgPicture.asset(
          'assets/svg/anniversary_cake.svg',
          fit: BoxFit.contain,
          placeholderBuilder: (context) => const Icon(
            Icons.cake_outlined,
            size: 88,
            color: Color(0xFFFFD36B),
          ),
        ),
        SvgPicture.string(
          buildAnniversaryCandleSvg(years),
          fit: BoxFit.contain,
        ),
      ],
    );
  }
}
