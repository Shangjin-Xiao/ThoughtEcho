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
/// 所以 mock 初值只在 `setUpAll` 给一次。
///
/// **但用到存储的用例必须各自把前置状态写全，不能接着上一个用例留下的状态往下写。**
/// CI 是分片跑的（`flutter test --shard-index/--total-shards`），同一个文件里的用例
/// 会落到不同进程，「上一个用例已经 initialize 过存储」这个假设在那边不成立——
/// 之前就是这么挂的：单跑第三个用例时 `SafeMMKV` 还没初始化，直接抛
/// `Bad state: SafeMMKV 尚未初始化`。所以下面每个碰存储的用例都自己
/// `SafeMMKV().initialize()`（幂等）并把要用到的键逐个写定。
///
/// 其余用例一律走「没有存储」的内存路径。
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

  test('旧键没删掉的残留不会被再迁一次，否则又是跨风格串色', () async {
    // 迁移写盘成功、删旧键失败，是会发生的：_removeLegacyThemeAccent 只记警告。
    // 这时存储里同时留着「按风格的墨色」和「旧的全局键」——下面把这个状态**写全**，
    // 不依赖上一个用例（分片时它可能根本不在这个进程里跑，见文件头注释）。
    final storage = SafeMMKV();
    await storage.initialize();
    // 素笺上一轮迁移成功了。
    await storage.setString(
      'theme_accent_${ThemeStyle.plain.name}',
      ThemeAccent.indigo.name,
    );
    // 旧的全局键没删掉，留了下来。
    await storage.setString('theme_accent', ThemeAccent.indigo.name);
    // 用户之后切到了纸墨，而纸墨（以及 material）没有单独选过墨。
    await storage.setString('theme_style', ThemeStyle.paper.name);
    await storage.remove('theme_accent_${ThemeStyle.paper.name}');
    await storage.remove('theme_accent_${ThemeStyle.material.name}');

    final appTheme = AppTheme();
    await appTheme.initialize();

    // 按「当前风格有没有」判就会把靛蓝再迁到纸墨上，两套风格又是同一支墨——
    // 这个改动要修的串色原样回来。判据必须是「一条按风格的取值都没有」。
    expect(appTheme.themeStyle, ThemeStyle.paper);
    expect(appTheme.accentFor(ThemeStyle.paper), ThemeAccent.umber);
    // 素笺自己那支不受影响，残留的旧键清掉。
    expect(appTheme.accentFor(ThemeStyle.plain), ThemeAccent.indigo);
    expect(storage.getString('theme_accent'), isNull);
  });

  test('全新安装时，默认加载心迹/信笺主题（ThemeStyle.paper）', () async {
    final storage = SafeMMKV();
    await storage.initialize();
    await storage.remove('theme_style');
    await storage.remove('app_installed_v2');
    await storage.remove('app_settings');

    final appTheme = AppTheme();
    await appTheme.initialize();

    expect(appTheme.themeStyle, ThemeStyle.paper);
    expect(storage.getString('theme_style'), ThemeStyle.paper.name);
  });

  test('旧用户（已安装/已有设置）未配置风格时保留在 material', () async {
    final storage = SafeMMKV();
    await storage.initialize();
    await storage.remove('theme_style');
    await storage.setBool('app_installed_v2', true);

    final appTheme = AppTheme();
    await appTheme.initialize();

    expect(appTheme.themeStyle, ThemeStyle.material);
  });

  test('app_settings 单独存在时的非全新安装分支，未配置风格时保留在 material', () async {
    final storage = SafeMMKV();
    await storage.initialize();
    await storage.remove('theme_style');
    await storage.remove('app_installed_v2');
    await storage.setString('app_settings', '{}');

    final appTheme = AppTheme();
    await appTheme.initialize();

    expect(appTheme.themeStyle, ThemeStyle.material);
  });
}
