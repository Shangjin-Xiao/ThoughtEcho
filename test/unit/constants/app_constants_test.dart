import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/constants/app_constants.dart';

/// 测试应用常量配置
void main() {
  group('AppConstants Tests', () {
    test('搜索相关常量应该有合理的默认值', () {
      // 验证搜索防抖延迟时间
      expect(AppConstants.searchDebounceDelay.inMilliseconds, 300);
      
      // 验证最小搜索长度
      expect(AppConstants.minSearchLength, 2);
      
      // 验证搜索超时时间
      expect(AppConstants.searchTimeout.inSeconds, 4);
    });

    test('分页加载常量应该有合理的默认值', () {
      // 验证默认分页大小
      expect(AppConstants.defaultPageSize, 20);
      
      // 验证滚动预加载阈值
      expect(AppConstants.scrollPreloadThreshold, 0.8);
    });

    test('响应式设计常量应该有合理的断点', () {
      // 验证平板设备最小宽度
      expect(AppConstants.tabletMinWidth, 600.0);
      
      // 验证桌面设备最小宽度
      expect(AppConstants.desktopMinWidth, 1024.0);
      
      // 验证平板模式下的最大内容宽度
      expect(AppConstants.tabletMaxContentWidth, 800.0);
    });

    test('动画时间常量应该有合理的持续时间', () {
      // 验证默认动画持续时间
      expect(AppConstants.defaultAnimationDuration.inMilliseconds, 300);
      
      // 验证快速动画持续时间
      expect(AppConstants.fastAnimationDuration.inMilliseconds, 150);
      
      // 验证慢速动画持续时间
      expect(AppConstants.slowAnimationDuration.inMilliseconds, 500);
    });

    test('SnackBar持续时间应该有适当的区分', () {
      // 验证普通信息显示时间
      expect(AppConstants.snackBarDurationNormal.inSeconds, 2);
      
      // 验证重要信息显示时间
      expect(AppConstants.snackBarDurationImportant.inSeconds, 3);
      
      // 验证错误信息显示时间
      expect(AppConstants.snackBarDurationError.inSeconds, 4);
      
      // 确保错误信息显示时间最长
      expect(
        AppConstants.snackBarDurationError.inSeconds >= 
        AppConstants.snackBarDurationImportant.inSeconds,
        true,
      );
      expect(
        AppConstants.snackBarDurationImportant.inSeconds >= 
        AppConstants.snackBarDurationNormal.inSeconds,
        true,
      );
    });

    test('内存管理常量应该有合理的大小', () {
      // 验证大文件处理阈值 (10MB)
      expect(AppConstants.largeFileThreshold, 10 * 1024 * 1024);
      
      // 验证分块处理大小 (1MB)
      expect(AppConstants.chunkSize, 1024 * 1024);
      
      // 确保分块大小小于大文件阈值
      expect(AppConstants.chunkSize < AppConstants.largeFileThreshold, true);
    });

    test('缓存相关常量应该有合理的过期时间', () {
      // 验证图片缓存过期时间
      expect(AppConstants.imageCacheExpiration.inDays, 7);
      
      // 验证数据缓存过期时间
      expect(AppConstants.dataCacheExpiration.inHours, 24);
      
      // 确保图片缓存时间比数据缓存时间长
      expect(
        AppConstants.imageCacheExpiration.inHours >= 
        AppConstants.dataCacheExpiration.inHours,
        true,
      );
    });

    test('网络和IO超时时间应该足够但不过长', () {
      // 验证网络请求超时时间
      expect(AppConstants.networkTimeout.inSeconds, 30);
      
      // 验证文件操作超时时间
      expect(AppConstants.fileOperationTimeout.inSeconds, 10);
      
      // 确保网络超时时间比文件操作超时时间长
      expect(
        AppConstants.networkTimeout.inSeconds >= 
        AppConstants.fileOperationTimeout.inSeconds,
        true,
      );
    });
  });
}
