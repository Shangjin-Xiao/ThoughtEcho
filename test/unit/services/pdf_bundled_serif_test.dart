// PDF 导出的字体跟着主题走。
//
// 在此之前屏幕上是宋体、导出的 PDF 永远是黑体——两边用的是两套完全独立的排版引擎，
// `pdf` 包不看 textTheme，字体得单独递过去。这几条锁的就是那次递送。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:thoughtecho/theme/theme_style.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PDF 随包衬线体', () {
    late pw.Font font;
    late pw.Context context;

    setUpAll(() async {
      final data = await rootBundle.load('assets/fonts/NotoSerifSC-Subset.ttf');
      font = pw.Font.ttf(data);
      context = pw.Context(document: pw.Document().document);
    });

    test('pdf 包能解析这个可变字体', () {
      // 可变字体对 pdf 包不是理所当然的：它不做字重轴插值，只认默认实例。
      // 子集化时已经把默认实例收到了 w400，所以这里拿到的就是 Regular。
      // 真正会出事的是 TTC 和 CFF/OTTO，isValidFontData 在服务侧挡掉了。
      expect(() => font.getFont(context), returnsNormally);
    });

    test('覆盖应用会导出的字符', () {
      final ttf = font.getFont(context);
      // 中文正文、拉丁、假名、西里尔——界面语言里除韩文之外的几种。
      for (final rune in '记录当下的想法ABCxyz0123ひらがなПривет，。“”——…'.runes) {
        expect(
          ttf.isRuneSupported(rune),
          isTrue,
          reason: '缺字: ${String.fromCharCode(rune)}',
        );
      }
    });

    test('子集外的字确实缺，所以回退链不能省', () {
      final ttf = font.getFont(context);
      // 韩文：源字体压根不含谚文，一定要靠 fallbackFonts 接住。
      // 这条不是在断言缺陷，是在钉住「PdfFontSet 必须带回退」这个前提——
      // sanitizeTextForPdf 会把所有字体都不支持的字符直接从文档里删掉。
      expect(ttf.isRuneSupported('한'.runes.first), isFalse);
    });

    test('族名常量就是 pdf 侧用来判断的那个取值', () {
      // PdfFontService.loadFontSet 拿 readingFontFamily 和这个常量比对。
      // 常量改名而 pubspec 没跟着改，随包字体会静默失效——那条由
      // theme_style_contrast_test 的 pubspec 断言兜着，这里只钉取值本身。
      expect(ThemeStyleForm.paper.fontFamily, ThemeStyleForm.bundledSerif);
      expect(ThemeStyleForm.plain.fontFamily, ThemeStyleForm.bundledSerif);
      expect(ThemeStyleForm.material.fontFamily, isNull,
          reason: 'material 风格的 PDF 应该继续走黑体那条路');
    });
  });
}
