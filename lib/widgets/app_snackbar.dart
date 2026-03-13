import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

/// Unified SnackBar wrapper for consistent messaging across the app.
///
/// Usage:
/// ```dart
/// AppSnackBar.info(context, l10n.savedSuccessfully);
/// AppSnackBar.error(context, l10n.operationFailed);
/// AppSnackBar.success(context, l10n.exportComplete);
/// AppSnackBar.show(context, message, action: SnackBarAction(...));
/// ```
class AppSnackBar {
  AppSnackBar._();

  /// Show a general SnackBar with optional customization.
  static void show(
    BuildContext context,
    String message, {
    Duration? duration,
    Color? backgroundColor,
    SnackBarAction? action,
    SnackBarBehavior behavior = SnackBarBehavior.floating,
  }) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: duration ?? AppConstants.snackBarDurationNormal,
          backgroundColor: backgroundColor,
          behavior: behavior,
          action: action,
        ),
      );
  }

  /// Show a SnackBar with custom [content] widget (e.g. Row with icon).
  static void showCustom(
    BuildContext context,
    Widget content, {
    Duration? duration,
    Color? backgroundColor,
    SnackBarAction? action,
    SnackBarBehavior behavior = SnackBarBehavior.floating,
  }) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: content,
          duration: duration ?? AppConstants.snackBarDurationNormal,
          backgroundColor: backgroundColor,
          behavior: behavior,
          action: action,
        ),
      );
  }

  /// Informational message — default theme color, normal duration.
  static void info(BuildContext context, String message,
      {SnackBarAction? action}) {
    show(context, message, action: action);
  }

  /// Success message — green background, important duration.
  static void success(BuildContext context, String message) {
    show(
      context,
      message,
      backgroundColor: Colors.green,
      duration: AppConstants.snackBarDurationImportant,
    );
  }

  /// Error message — red background, longer duration.
  static void error(BuildContext context, String message,
      {SnackBarAction? action}) {
    show(
      context,
      message,
      backgroundColor: Colors.red,
      duration: AppConstants.snackBarDurationError,
      action: action,
    );
  }

  /// Warning message — orange background, important duration.
  static void warning(BuildContext context, String message) {
    show(
      context,
      message,
      backgroundColor: Colors.orange,
      duration: AppConstants.snackBarDurationImportant,
    );
  }
}
