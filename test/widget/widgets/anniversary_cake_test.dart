import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/widgets/anniversary_cake.dart';

void main() {
  group('AnniversaryCake', () {
    testWidgets('渲染包含蛋糕底图和数字蜡烛的层叠结构', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 200,
                child: AnniversaryCake(years: 2),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(AnniversaryCake), findsOneWidget);
      expect(find.byType(Stack), findsWidgets);
      expect(find.byType(SvgPicture), findsNWidgets(2));
    });
  });
}
