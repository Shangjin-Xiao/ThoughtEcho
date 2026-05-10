import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/widgets/add_note_dialog_parts.dart';

void main() {
  testWidgets('reports keyboard inset during build', (tester) async {
    final reportedInsets = <double>[];

    Widget buildWithInset(double bottomInset) {
      return MediaQuery(
        data: MediaQueryData(
          viewInsets: EdgeInsets.only(bottom: bottomInset),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: KeyboardInsetPadding(
            onInsetBuild: reportedInsets.add,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildWithInset(0));
    await tester.pumpWidget(buildWithInset(240));

    expect(reportedInsets, containsAllInOrder(<double>[0, 240]));
  });
}
