import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../theme/app_semantic_colors.dart';

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
    Color? foregroundColor,
    SnackBarAction? action,
    SnackBarBehavior behavior = SnackBarBehavior.floating,
  }) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: foregroundColor == null
                ? null
                : TextStyle(color: foregroundColor),
          ),
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

  /// Informational message — inherits the theme's SnackBar colors.
  static void info(BuildContext context, String message,
      {SnackBarAction? action}) {
    show(context, message, action: action);
  }

  /// Success message — semantic success container, important duration.
  static void success(BuildContext context, String message) {
    final semantic = AppSemanticColors.of(context);
    show(
      context,
      message,
      backgroundColor: semantic.successContainer,
      foregroundColor: semantic.onSuccessContainer,
      duration: AppConstants.snackBarDurationImportant,
    );
  }

  /// Error message — `colorScheme.errorContainer`, longer duration.
  static void error(BuildContext context, String message,
      {SnackBarAction? action}) {
    final colorScheme = Theme.of(context).colorScheme;
    show(
      context,
      message,
      backgroundColor: colorScheme.errorContainer,
      foregroundColor: colorScheme.onErrorContainer,
      duration: AppConstants.snackBarDurationError,
      action: action,
    );
  }

  /// Warning message — semantic warning container, important duration.
  static void warning(BuildContext context, String message) {
    final semantic = AppSemanticColors.of(context);
    show(
      context,
      message,
      backgroundColor: semantic.warningContainer,
      foregroundColor: semantic.onWarningContainer,
      duration: AppConstants.snackBarDurationImportant,
    );
  }
}
