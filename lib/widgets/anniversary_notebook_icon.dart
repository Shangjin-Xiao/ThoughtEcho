import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:thoughtecho/utils/anniversary_notebook_svg.dart';

/// 庆典横幅左侧的笔记本插画。封面上的年份按 [years] 运行时生成，
/// 不再是画死在静态资源里的「1」。
class AnniversaryNotebookIcon extends StatelessWidget {
  /// 第几周年，决定封面上的数字。
  final int years;

  const AnniversaryNotebookIcon({super.key, required this.years});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: SvgPicture.string(
        buildAnniversaryNotebookSvg(years),
        fit: BoxFit.contain,
      ),
    );
  }
}
