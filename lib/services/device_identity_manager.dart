import 'dart:async';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 管理应用在本设备上的稳定指纹（跨进程/重启保持）
/// 仅在首次调用时生成 UUIDv4 并持久化。
class DeviceIdentityManager {
  static const _keyFingerprint = 'device_fingerprint_v1';
  static final DeviceIdentityManager _instance = DeviceIdentityManager._();
  final _uuid = const Uuid();
  String? _cached;
  bool _loading = false;
  final List<Completer<String>> _waiters = [];

  DeviceIdentityManager._();
  static DeviceIdentityManager get I => _instance;

  /// 已缓存的指纹（如果尚未加载则为 null）
  String? get currentFingerprint => _cached;

  /// 获取稳定指纹（异步确保首轮加载）
  Future<String> getFingerprint() async {
    if (_cached != null) return _cached!;
    if (_loading) {
      final c = Completer<String>();
      _waiters.add(c);
      return c.future;
    }
    _loading = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      var fp = prefs.getString(_keyFingerprint);
      if (fp == null || fp.isEmpty) {
        fp = _uuid.v4();
        await prefs.setString(_keyFingerprint, fp);
      }
      _cached = fp;
      for (final w in _waiters) {
        if (!w.isCompleted) w.complete(fp);
      }
      _waiters.clear();
      return fp;
    } catch (e) {
      // 失败时退化为随机 fallback（不持久化），最大程度避免阻塞
      final fallback = _fallbackRandom();
      _cached = fallback;
      for (final w in _waiters) {
        if (!w.isCompleted) w.complete(fallback);
      }
      _waiters.clear();
      return fallback;
    } finally {
      _loading = false;
    }
  }

  String _fallbackRandom() {
    final r = Random();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}
