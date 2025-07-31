import 'dart:math';

/// Generate random device alias
String generateRandomAlias() {
  final adjectives = ['Swift', 'Bright', 'Quick', 'Smart', 'Cool', 'Fast'];
  final nouns = ['Device', 'Phone', 'Tablet', 'Computer', 'Gadget'];
  
  final random = Random();
  final adjective = adjectives[random.nextInt(adjectives.length)];
  final noun = nouns[random.nextInt(nouns.length)];
  
  return '$adjective $noun';
}