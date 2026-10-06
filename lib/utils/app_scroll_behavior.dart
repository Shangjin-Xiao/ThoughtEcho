import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 全局自定义 [ScrollBehavior] 扩展。
///
/// 在默认 [MaterialScrollBehavior] 基础之上，将 [PointerDeviceKind.mouse]
/// 加入 [dragDevices]，允许桌面端（macOS/Windows/Linux）使用鼠标指针直接拖拽滚动列表或滚动条。
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      };
}
