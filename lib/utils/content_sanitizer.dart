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
  static const String _defaultCsp =
      "default-src 'none'; script-src 'none'; object-src 'none'; style-src 'unsafe-inline'; "
      "img-src data: https:; font-src data: https:; connect-src 'none'; "
      "media-src 'none'; frame-src 'none'; child-src 'none';";

  /// Injects a Content Security Policy (CSP) meta tag into the HTML content.
  ///
  /// If the HTML already contains a CSP meta tag, it returns the content unchanged.
  /// Otherwise, it injects the tag into the `<head>` section.
  static String injectCsp(String html) {
    if (html.isEmpty) return html;

    // Check if CSP is already present
    if (html.contains('http-equiv="Content-Security-Policy"') ||
        html.contains("http-equiv='Content-Security-Policy'")) {
      return html;
    }

    final cspTag =
        '<meta http-equiv="Content-Security-Policy" content="$_defaultCsp">';

    // Try to find <head> tag (case-insensitive), preserving attributes
    final headRegex = RegExp(r'(<head[^>]*>)', caseSensitive: false);
    if (headRegex.hasMatch(html)) {
      return html.replaceFirstMapped(
          headRegex, (match) => '${match.group(0)}\n    $cspTag');
    }

    // Try to find <html> tag, preserving attributes
    final htmlRegex = RegExp(r'(<html[^>]*>)', caseSensitive: false);
    if (htmlRegex.hasMatch(html)) {
      return html.replaceFirstMapped(htmlRegex,
          (match) => '${match.group(0)}\n<head>\n    $cspTag\n</head>');
    }

    // If no structure, just prepend it
    return '$cspTag\n$html';
  }
}
