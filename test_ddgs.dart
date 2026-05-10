import 'package:ddgs/ddgs.dart';

void main() async {
  final ddgs = DDGS();
  try {
    final results =
        await ddgs.text('flutter', backend: 'duckduckgo', maxResults: 2);
    print(results);
  } catch (e) {
    print('Error: $e');
  }
}
