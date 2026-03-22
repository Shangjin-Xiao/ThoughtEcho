import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AnniversaryNotebookIcon extends StatelessWidget {
  const AnniversaryNotebookIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: SvgPicture.asset(
        'assets/svg/anniversary_notebook.svg',
        fit: BoxFit.contain,
      ),
    );
  }
}
