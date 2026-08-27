import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/app_widgets_binding.dart';

/// 造一张已知字节数的图并塞进缓存：`createTestImage` 出来的是 4 字节/像素。
Future<void> _put(ImageCache cache, Object key, ui.Image image) async {
  final completer = Completer<ImageInfo>();
  cache.putIfAbsent(
    key,
    () => OneFrameImageStreamCompleter(completer.future),
  );
  completer.complete(ImageInfo(image: image));
  // 完成回调走一圈微任务，缓存才会把这条从 pending 挪进已计字节的那份。
  await Future<void>.delayed(Duration.zero);
}

void main() {
  // `createTestImage` 需要一个已初始化的 binding；这里不用 testWidgets，是因为
  // 它的 fake async 会把 `OneFrameImageStreamCompleter` 的完成回调挂住。
  TestWidgetsFlutterBinding.ensureInitialized();

  group('内存压力分流', () {
    test('前台收到的压力当成真的缺内存', () {
      expect(
        memoryPressureKindFor(AppLifecycleState.resumed),
        MemoryPressureKind.scarcity,
      );
    });

    test('拿不到生命周期状态时按缺内存处理', () {
      expect(memoryPressureKindFor(null), MemoryPressureKind.scarcity);
    });

    test('界面完全不可见之后收到的压力才是例行 trim', () {
      // TRIM_MEMORY_UI_HIDDEN 在 onStop 之后才发，对应这三档，都不该清空缓存。
      for (final state in <AppLifecycleState>[
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.detached,
      ]) {
        expect(
          memoryPressureKindFor(state),
          MemoryPressureKind.backgroundTrim,
          reason: '$state 应当被当成例行 trim',
        );
      }
    });

    test('inactive 仍然算真缺内存', () {
      // 权限弹窗、系统浮层、下拉通知栏时进程完全在前台，例行 trim 还没发生，
      // 这时收到的压力必须整清 —— 少释放一次并不能免于被杀。
      expect(
        memoryPressureKindFor(AppLifecycleState.inactive),
        MemoryPressureKind.scarcity,
      );
    });
  });

  group('后台 trim 只淘汰不清空', () {
    test('留下最近用过的那几张，额度还回原值', () async {
      final cache = ImageCache()..maximumSizeBytes = 4 * 1024 * 1024;
      // 每张 64×64×4 = 16KB。
      final images = <ui.Image>[];
      for (var i = 0; i < 8; i++) {
        images.add(await createTestImage(width: 64, height: 64));
      }
      for (var i = 0; i < images.length; i++) {
        await _put(cache, 'image-$i', images[i]);
      }
      expect(cache.currentSize, 8);
      final fullBytes = cache.currentSizeBytes;
      expect(fullBytes, greaterThan(0));

      // 只留两张的额度。
      shrinkImageCacheForBackgroundTrim(cache, keepBytes: 32 * 1024);

      expect(cache.currentSizeBytes, lessThanOrEqualTo(32 * 1024));
      expect(cache.currentSizeBytes, greaterThan(0),
          reason: '是淘汰不是清空，最近用过的要留下');
      expect(cache.maximumSizeBytes, 4 * 1024 * 1024,
          reason: '额度必须还回去，否则前台回来只剩一点点缓存');
      // LRU：最早放进去的先走，最后放进去的还在。
      expect(cache.containsKey('image-7'), isTrue);
      expect(cache.containsKey('image-0'), isFalse);
    });

    test('额度本来就比保留值还小时什么都不做', () async {
      final cache = ImageCache()..maximumSizeBytes = 16 * 1024;
      final image = await createTestImage(width: 32, height: 32);
      await _put(cache, 'only', image);
      final before = cache.currentSizeBytes;

      shrinkImageCacheForBackgroundTrim(cache, keepBytes: 8 * 1024 * 1024);

      expect(cache.currentSizeBytes, before);
      expect(cache.maximumSizeBytes, 16 * 1024);
    });
  });
}
