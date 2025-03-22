import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get light {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      useMaterial3: true,
      fontFamily: 'Noto Sans SC',
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontFamily: 'Noto Sans SC'),
        displayMedium: TextStyle(fontFamily: 'Noto Sans SC'),
        displaySmall: TextStyle(fontFamily: 'Noto Sans SC'),
        headlineLarge: TextStyle(fontFamily: 'Noto Sans SC'),
        headlineMedium: TextStyle(fontFamily: 'Noto Sans SC'),
        headlineSmall: TextStyle(fontFamily: 'Noto Sans SC'),
        titleLarge: TextStyle(fontFamily: 'Noto Sans SC'),
        titleMedium: TextStyle(fontFamily: 'Noto Sans SC'),
        titleSmall: TextStyle(fontFamily: 'Noto Sans SC'),
        bodyLarge: TextStyle(fontFamily: 'Noto Sans SC'),
        bodyMedium: TextStyle(fontFamily: 'Noto Sans SC'),
        bodySmall: TextStyle(fontFamily: 'Noto Sans SC'),
        labelLarge: TextStyle(fontFamily: 'Noto Sans SC'),
        labelMedium: TextStyle(fontFamily: 'Noto Sans SC'),
        labelSmall: TextStyle(fontFamily: 'Noto Sans SC'),
      ),
    );
  }

  static ThemeData get dark {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      fontFamily: 'Noto Sans SC',
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontFamily: 'Noto Sans SC'),
        displayMedium: TextStyle(fontFamily: 'Noto Sans SC'),
        displaySmall: TextStyle(fontFamily: 'Noto Sans SC'),
        headlineLarge: TextStyle(fontFamily: 'Noto Sans SC'),
        headlineMedium: TextStyle(fontFamily:
}
