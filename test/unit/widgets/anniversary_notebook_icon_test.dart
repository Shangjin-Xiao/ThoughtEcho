import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/widgets/anniversary_notebook_icon.dart';

void main() {
  group('AnniversaryNotebookIconLayout', () {
    test('视觉包围盒应当在画布中水平居中', () {
      const layout = AnniversaryNotebookIconLayout();
      final canvasWidth = AnniversaryNotebookIconLayout.canvasSize.width;

      expect(layout.visualBounds.center.dx, closeTo(canvasWidth / 2, 0.1));
    });
  });
}
