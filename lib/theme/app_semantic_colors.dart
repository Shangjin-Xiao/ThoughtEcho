import 'package:flutter/material.dart';

/// 状态语义色（成功 / 警告 / 危险 / 信息）。
///
/// Material 3 的 `ColorScheme` 只提供 `error` 一种状态色，没有 success 和 warning。
/// 过去项目里靠 `Colors.green` / `Colors.orange` 顶替，问题是这些 Material 命名色
/// 饱和度远高于 M3 生成的色调，和动态取色主题并排时很突兀，暗色模式下也不改变明度。
///
/// 这里的取值按 M3 tonal palette 的标准色调层级手工对齐：亮色模式取 tone 40（前景）、
/// tone 90（容器）、tone 10（容器上的文字）；暗色模式取 tone 80 / 30 / 90。这样它们和
/// `ColorScheme` 派生出来的颜色处在同一套明度曲线上。
///
/// 这是 AGENTS.md 允许的「语义色集中定义」，页面里不要再写 `Color(0x...)` 字面量。
///
/// 用法：
/// ```dart
/// final semantic = Theme.of(context).extension<AppSemanticColors>()!;
/// Icon(Icons.check_circle, color: semantic.success);
/// ```
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
  });

  /// 成功状态的前景色，用于图标和文字直接绘制在 surface 上。
  final Color success;

  /// 成功状态的容器背景色，用于 SnackBar、Banner、徽章底色。
  final Color successContainer;

  /// 绘制在 [successContainer] 之上的文字和图标颜色。
  final Color onSuccessContainer;

  /// 警告状态的前景色。
  final Color warning;

  /// 警告状态的容器背景色。
  final Color warningContainer;

  /// 绘制在 [warningContainer] 之上的文字和图标颜色。
  final Color onWarningContainer;

  /// 危险 / 错误状态直接复用 `ColorScheme.error`，不在此重复定义。
  /// 信息状态复用 `ColorScheme.primary`。

  static const light = AppSemanticColors(
    success: Color(0xFF256B43),
    successContainer: Color(0xFFBEEFCD),
    onSuccessContainer: Color(0xFF00210E),
    warning: Color(0xFF7A5900),
    warningContainer: Color(0xFFFFDF9E),
    onWarningContainer: Color(0xFF261A00),
  );

  static const dark = AppSemanticColors(
    success: Color(0xFF8CD6A5),
    successContainer: Color(0xFF0B5230),
    onSuccessContainer: Color(0xFFA8F0C0),
    warning: Color(0xFFF2C260),
    warningContainer: Color(0xFF5C4200),
    onWarningContainer: Color(0xFFFFDF9E),
  );

  /// 从 context 取语义色。主题未注册扩展时回退到亮/暗默认值，避免空断言崩溃。
  static AppSemanticColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppSemanticColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? warningContainer,
    Color? onWarningContainer,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer:
          Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer:
          Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer:
          Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
    );
  }
}
