import 'package:flutter/widgets.dart';

/// 全局导航 key，用于服务在无 context 时获取 context。
/// 独立成文件以避免 services 层为拿 key 而反向 import main.dart。
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
