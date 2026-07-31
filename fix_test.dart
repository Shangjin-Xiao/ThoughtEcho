import 'dart:io';

void main() {
  final file = File('integration_test/note_list_performance_test.dart');
  var content = file.readAsStringSync();
  content = content.replaceFirst('scrollCacheExtent: const ScrollCacheExtent.pixels(800,', 'scrollCacheExtent: const ScrollCacheExtent.pixels(800),');
  file.writeAsStringSync(content);
}
