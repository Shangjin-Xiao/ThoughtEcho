/// Color mode enum for LocalSend theme configuration

enum ColorMode {
  system,
  dark,
  light,
}

extension ColorModeExtension on ColorMode {
  bool get isSystem => this == ColorMode.system;
  bool get isDark => this == ColorMode.dark;
  bool get isLight => this == ColorMode.light;
}
