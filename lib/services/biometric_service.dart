import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../utils/app_logger.dart';

/// 生物识别验证服务
/// 封装 local_auth 包提供统一的生物识别验证接口
class BiometricService {
  static final BiometricService _instance = BiometricService._internal();
  factory BiometricService() => _instance;
  BiometricService._internal();

  final LocalAuthentication _localAuth = LocalAuthentication();

  /// 检查设备是否支持生物识别
  Future<bool> isDeviceSupported() async {
    if (kIsWeb) return false;

    try {
      return await _localAuth.isDeviceSupported();
    } on PlatformException catch (e) {
      AppLogger.e('检查设备支持时出错', error: e, source: 'BiometricService');
      return false;
    }
  }

  /// 检查是否可以使用生物识别（设备支持且已设置）
  Future<bool> canCheckBiometrics() async {
    if (kIsWeb) return false;

    try {
      return await _localAuth.canCheckBiometrics;
    } on PlatformException catch (e) {
      AppLogger.e('检查生物识别可用性时出错', error: e, source: 'BiometricService');
      return false;
    }
  }

  /// 获取可用的生物识别类型
  Future<List<BiometricType>> getAvailableBiometrics() async {
    if (kIsWeb) return [];

    try {
      return await _localAuth.getAvailableBiometrics();
    } on PlatformException catch (e) {
      AppLogger.e('获取可用生物识别类型时出错', error: e, source: 'BiometricService');
      return [];
    }
  }

  /// 执行生物识别验证
  /// [localizedReason] 显示给用户的验证原因
  /// [biometricOnly] 是否仅使用生物识别（不允许使用PIN/密码）
  Future<bool> authenticate({
    required String localizedReason,
    bool biometricOnly = false,
  }) async {
    if (kIsWeb) return false;

    try {
      // 首先检查设备是否支持
      final isSupported = await isDeviceSupported();
      if (!isSupported) {
        AppLogger.d('设备不支持生物识别', source: 'BiometricService');
        return false;
      }

      // 检查是否有可用的生物识别
      final canCheck = await canCheckBiometrics();
      if (!canCheck) {
        AppLogger.d('设备未设置生物识别', source: 'BiometricService');
        return false;
      }

      // 执行验证
      final authenticated = await _localAuth.authenticate(
        localizedReason: localizedReason,
        options: AuthenticationOptions(
          stickyAuth: true, // 防止应用切换后需要重新验证
          biometricOnly: biometricOnly,
          useErrorDialogs: true, // 使用系统错误对话框
        ),
      );

      AppLogger.d('生物识别验证结果: $authenticated', source: 'BiometricService');
      return authenticated;
    } on PlatformException catch (e) {
      AppLogger.e(
        '生物识别验证出错: ${e.code} - ${e.message}',
        error: e,
        source: 'BiometricService',
      );
      return false;
    }
  }

  /// 检查生物识别是否完全可用（设备支持且已设置）
  Future<bool> isBiometricAvailable() async {
    if (kIsWeb) return false;

    try {
      final isSupported = await isDeviceSupported();
      final canCheck = await canCheckBiometrics();
      return isSupported && canCheck;
    } catch (e) {
      AppLogger.e('检查生物识别可用性时出错', error: e, source: 'BiometricService');
      return false;
    }
  }

  /// 获取生物识别类型的友好名称
  String getBiometricTypeName(BiometricType type) {
    switch (type) {
      case BiometricType.face:
        return '面容识别';
      case BiometricType.fingerprint:
        return '指纹识别';
      case BiometricType.iris:
        return '虹膜识别';
      case BiometricType.strong:
        return '强生物识别';
      case BiometricType.weak:
        return '弱生物识别';
    }
  }
}
