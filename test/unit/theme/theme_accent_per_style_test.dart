import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/theme/app_theme.dart';
import 'package:thoughtecho/theme/theme_style.dart';
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';

import '../../test_harness.dart';

/// 墨色**按风格分开记**。
///
/// 曾经是全局一支：在纸与墨下点过赭石，切到素笺也是赭石，素笺配的那支黛青绿
/// 从此再也见不到——[ThemeStyle.defaultAccent] 给每套风格配默认墨的意义
/// （「这套纸配这支墨最好看」）被一次全局选择永久盖掉。
///
/// 存储只在这一个文件里碰：`SafeMMKV` 是单例，`SharedPrefsAdapter` 还会把
/// `SharedPreferences` 实例缓存下来，同一个 isolate 里换一套 mock 值是不生效的。
/// 所以迁移只测一次，其余用例一律走「没有存储」的内存路径。
void main() {
  setUpAll(() async {
    await TestHarness.initialize();
    // 老版本留下的状态：风格是素笺，墨色是全局的那一支靛蓝。
    SharedPreferences.setMockInitialValues({
      'theme_style': ThemeStyle.plain.name,
      'theme_accent': ThemeAccent.indigo.name,
    });
  });

  test('在一套风格下选墨，不会盖掉另一套风格的默认支', () async {
    // 没调 initialize()，_storage 是 null，两个 setter 只改内存——正是这里要的。
    final appTheme = AppTheme();

    await appTheme.setThemeStyle(ThemeStyle.paper);
    await appTheme.setThemeAccent(ThemeAccent.cinnabar);
    expect(appTheme.themeAccent, ThemeAccent.cinnabar);
    // 素笺没被选过，仍然跟随它自己的黛青。
    expect(appTheme.accentFor(ThemeStyle.plain), ThemeAccent.celadon);

    await appTheme.setThemeStyle(ThemeStyle.plain);
    expect(appTheme.themeAccent, ThemeAccent.celadon);

    // 在素笺下选一支，纸墨那支不受影响，切回去原样恢复。
    await appTheme.setThemeAccent(ThemeAccent.indigo);
    expect(appTheme.themeAccent, ThemeAccent.indigo);
    await appTheme.setThemeStyle(ThemeStyle.paper);
    expect(appTheme.themeAccent, ThemeAccent.cinnabar);
  });

  test('旧的全局墨色迁到当前风格名下，别的风格回到自己的默认支', () async {
    final appTheme = AppTheme();
    await appTheme.initialize();

    // 迁给当前风格（素笺）是唯一不改变用户所见的落法：那支墨此刻正显示在它上面。
    expect(appTheme.themeStyle, ThemeStyle.plain);
    expect(appTheme.themeAccent, ThemeAccent.indigo);
    // 纸墨从没被单独选过，回到它自己的赭石，而不是继续吃素笺那支。
    expect(appTheme.accentFor(ThemeStyle.paper), ThemeAccent.umber);

    final storage = SafeMMKV();
    expect(
      storage.getString('theme_accent_${ThemeStyle.plain.name}'),
      ThemeAccent.indigo.name,
    );
    // 旧键迁完就删：留着它，下次启动会按那时的风格再迁一遍。
    expect(storage.getString('theme_accent'), isNull);

    // 迁移之后再选墨仍然只落在当前风格头上。
    await appTheme.setThemeStyle(ThemeStyle.paper);
    await appTheme.setThemeAccent(ThemeAccent.cinnabar);
    expect(
      storage.getString('theme_accent_${ThemeStyle.paper.name}'),
      ThemeAccent.cinnabar.name,
    );
    expect(appTheme.accentFor(ThemeStyle.plain), ThemeAccent.indigo);
  });
}
