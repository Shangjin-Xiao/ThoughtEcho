/// Content Sanitizer Utility
///
/// This class provides methods to sanitize and secure HTML content, primarily
/// by injecting Content Security Policy (CSP) headers to prevent XSS attacks.
class ContentSanitizer {
  /// The default CSP policy for static reports.
  ///
  /// - default-src 'none': Block everything by default
  /// - script-src 'none': No scripts allowed (critical for XSS prevention)
  /// - object-src 'none': No plugins (Flash, etc.)
  /// - style-src 'unsafe-inline': Allow inline styles (needed for the report's design)
  /// - img-src data: https: : Allow images from data URIs and HTTPS sources
  /// - font-src data: https: : Allow fonts from data URIs and HTTPS sources
  static const String defaultCsp =
      "default-src 'none'; script-src 'none'; object-src 'none'; style-src 'unsafe-inline'; "
      "img-src data: https:; font-src data: https:; connect-src 'none'; "
      "media-src 'none'; frame-src 'none'; child-src 'none';";

  // Optimization: Extract RegExp to static final fields to avoid repeated parsing
  // and compilation overhead on every invocation of injectCsp.
  static final RegExp _cspMetaRegex = RegExp(
    r'<meta[^>]*http-equiv=["'
    "'"
    r']?Content-Security-Policy["'
    "'"
    r']?[^>]*>',
    caseSensitive: false,
  );

  static final RegExp _scriptRegex = RegExp(
    r'<script\b[^>]*>[\s\S]*?</script>',
    caseSensitive: false,
  );

  static final RegExp _headRegex =
      RegExp(r'(<head[^>]*>)', caseSensitive: false);

  static final RegExp _htmlRegex =
      RegExp(r'(<html[^>]*>)', caseSensitive: false);

  static final RegExp _doctypeRegex =
      RegExp(r'(<!doctype[^>]*>)', caseSensitive: false);

  /// Injects a Content Security Policy (CSP) meta tag into the HTML content.
  ///
  /// If the HTML already contains a CSP meta tag, it removes it first to prevent
  /// attacker bypass, then injects the safe CSP tag into the `<head>` section.
  static String injectCsp(String html) {
    if (html.isEmpty) return html;

    final cspTag =
        '<meta http-equiv="Content-Security-Policy" content="$defaultCsp">';

    String sanitized = html;

    // 1. Remove any existing CSP meta tags to prevent attacker bypass
    sanitized = sanitized.replaceAll(_cspMetaRegex, '');

    // 2. Strip <script> tags as an additional layer of defense
    sanitized = sanitized.replaceAll(_scriptRegex, '');

    // Try to find <head> tag (case-insensitive), preserving attributes
    if (_headRegex.hasMatch(sanitized)) {
      return sanitized.replaceFirstMapped(
          _headRegex, (match) => '${match.group(0)}\n    $cspTag');
    }

    // Try to find <html> tag, preserving attributes
    if (_htmlRegex.hasMatch(sanitized)) {
      return sanitized.replaceFirstMapped(_htmlRegex,
          (match) => '${match.group(0)}\n<head>\n    $cspTag\n</head>');
    }

    // Try to find doctype tag, preserving attributes
    if (_doctypeRegex.hasMatch(sanitized)) {
      return sanitized.replaceFirstMapped(
          _doctypeRegex, (match) => '${match.group(0)}\n$cspTag');
    }

    // If no structure, just prepend it
    return '$cspTag\n$sanitized';
  }
}
