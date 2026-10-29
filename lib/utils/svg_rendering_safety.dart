import 'package:xml/xml_events.dart';

/// Rejects dash arrays before the SVG compiler can expand them into an
/// unbounded number of path commands. Applies to inherited attributes too.
void validateSvgDashSafety(String svgContent) {
  // Use the same XML event parser as vector_graphics_compiler so character
  // references in inline styles and namespaced attributes cannot bypass this.
  for (final event in parseEvents(svgContent)) {
    if (event is! XmlStartElementEvent) continue;
    for (final attribute in event.attributes) {
      final name = attribute.localName;
      if (name == 'stroke-dasharray' ||
          (name == 'style' &&
              attribute.value.split(';').any((declaration) =>
                  declaration.split(':').first.trim() == 'stroke-dasharray'))) {
        throw const FormatException('SVG dash arrays are not supported');
      }
    }
  }
}
