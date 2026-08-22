// 随包衬线体的产物校验。
//
// 其他主题测试断言的都是「代码里写了什么」——族名对不对、字重抬没抬。这一条不同，
// 它断言的是**那个 5MB 的二进制本身还能用**：asset 声明有没有漏、文件有没有在某次
// 合并里被损坏、引擎认不认这个格式。
//
// 这类失败在界面上是静默的：字体加载不到只会悄悄退回系统默认字体，
// 不报错、不崩溃，只是主题的字体那一层又变回没做。
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/theme/theme_style.dart';

const _fontAsset = 'assets/fonts/NotoSerifSC-Subset.ttf';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('随包衬线体', () {
    late ByteData bytes;

    setUpAll(() async {
      bytes = await rootBundle.load(_fontAsset);
    });

    test('asset 已声明且非空', () {
      // rootBundle.load 在 asset 没被 pubspec 收进来时直接抛异常，
      // 走到这里说明声明是通的。
      expect(bytes.lengthInBytes, greaterThan(1024 * 1024),
          reason: '产物明显偏小，八成是 Git LFS 指针或者损坏的文件');
    });

    test('是引擎能解析的 TrueType，不是 TTC 或 CFF', () {
      // sfnt 版本号：0x00010000 = TrueType 轮廓。
      // 'ttcf'（字体集合）和 'OTTO'（CFF 轮廓）都在这里被挡掉——
      // PdfFontService 踩过后者的坑，见那边的 isValidFontData。
      expect(bytes.getUint32(0), 0x00010000);
    });

    testWidgets('FontLoader 能把它注册进引擎', (tester) async {
      final loader = FontLoader(ThemeStyleForm.bundledSerif)
        ..addFont(Future.value(bytes));
      // 文件格式不对时 loadFontFromList 会抛，这里就是在断言「不抛」。
      await loader.load();
    });
  });
}
