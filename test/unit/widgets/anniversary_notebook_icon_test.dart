import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:thoughtecho/widgets/anniversary_notebook_icon.dart';

void main() {
  group('AnniversaryNotebookIcon', () {
    testWidgets('renders SvgPicture', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AnniversaryNotebookIcon())),
      );

      expect(find.byType(SvgPicture), findsOneWidget);
    });
  });
}
