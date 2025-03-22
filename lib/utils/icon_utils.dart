import 'package:flutter/material.dart';

class IconUtils {
  static final Map<String, IconData> categoryIcons = {
    'home': Icons.home,
    'work': Icons.work,
    'school': Icons.school,
    'book': Icons.book,
    'movie': Icons.movie,
    'music': Icons.music_note,
    'travel': Icons.flight,
    'food': Icons.restaurant,
    'shopping': Icons.shopping_cart,
    'sport': Icons.sports_basketball,
    'health': Icons.health_and_safety,
    'finance': Icons.attach_money,
    'family': Icons.family_restroom,
    'friend': Icons.people,
    'pet': Icons.pets,
    'nature': Icons.nature,
    'art': Icons.palette,
    'technology': Icons.computer,
    'game': Icons.sports_esports,
    'other': Icons.more_horiz,
  };

  static IconData getIconData(String? iconName) {
    if (iconName == null || !categoryIcons.containsKey(iconName)) {
      return Icons.label; // 默认图标
    }
    return categoryIcons[iconName]!;
  }

  static List<MapEntry<String, IconData>> getAllIcons() {
    return categoryIcons.entries.toList();
  }
}