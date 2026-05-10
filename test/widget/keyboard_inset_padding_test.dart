import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/widgets/add_note_dialog_parts.dart';

void main() {
  testWidgets('moves content by keyboard inset without relayout padding',
      (tester) async {
    const childKey = ValueKey('keyboard-inset-child');

    Widget buildWithInset(double bottomInset) {
      return MediaQuery(
        data: MediaQueryData(
          viewInsets: EdgeInsets.only(bottom: bottomInset),
        ),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: KeyboardInsetPadding(
            child: SizedBox(
              key: childKey,
              width: 100,
              height: 100,
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildWithInset(0));
    final topWithoutKeyboard = tester.getTopLeft(find.byKey(childKey)).dy;

    await tester.pumpWidget(buildWithInset(120));
    final topWithKeyboard = tester.getTopLeft(find.byKey(childKey)).dy;

    expect(topWithoutKeyboard, 16);
    expect(topWithKeyboard, topWithoutKeyboard - 120);
  });
}
