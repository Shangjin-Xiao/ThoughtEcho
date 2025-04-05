import 'package:flutter/material.dart';

class IconUtils {
  static IconData getIconData(String? iconName) {
    switch (iconName) {
      case 'book':
        return Icons.book;
      case 'bookmark':
        return Icons.bookmark;
      case 'favorite':
        return Icons.favorite;
      case 'star':
        return Icons.star;
      case 'label':
        return Icons.label;
      case 'local_offer':
        return Icons.local_offer;
      case 'category':
        return Icons.category;
      case 'folder':
        return Icons.folder;
      case 'note':
        return Icons.note;
      case 'description':
        return Icons.description;
      case 'article':
        return Icons.article;
      case 'format_quote':
        return Icons.format_quote;
      case 'lightbulb':
        return Icons.lightbulb;
      case 'psychology':
        return Icons.psychology;
      case 'emoji_objects':
        return Icons.emoji_objects;
      case 'sentiment_satisfied':
        return Icons.sentiment_satisfied;
      case 'mood':
        return Icons.mood;
      case 'notifications':
        return Icons.notifications;
      case 'alarm':
        return Icons.alarm;
      case 'event':
        return Icons.event;
      case 'calendar_today':
        return Icons.calendar_today;
      case 'person':
        return Icons.person;
      case 'group':
        return Icons.group;
      case 'work':
        return Icons.work;
      case 'school':
        return Icons.school;
      case 'home':
        return Icons.home;
      case 'place':
        return Icons.place;
      case 'music_note':
        return Icons.music_note;
      case 'movie':
        return Icons.movie;
      case 'photo':
        return Icons.photo;
      case 'brush':
        return Icons.brush;
      case 'palette':
        return Icons.palette;
      case 'sports_esports':
        return Icons.sports_esports;
      case 'sports':
        return Icons.sports;
      case 'fitness_center':
        return Icons.fitness_center;
      case 'restaurant':
        return Icons.restaurant;
      case 'local_cafe':
        return Icons.local_cafe;
      case 'shopping_cart':
        return Icons.shopping_cart;
      case 'monetization_on':
        return Icons.monetization_on;
      case 'beach_access':
        return Icons.beach_access;
      case 'nature':
        return Icons.nature;
      case 'pets':
        return Icons.pets;
      default:
        return Icons.label_outline; // 默认图标
    }
  }

  // 获取所有可用的图标名称
  static List<String> getAllIconNames() {
    return [
      'book',
      'bookmark',
      'favorite',
      'star',
      'label',
      'local_offer',
      'category',
      'folder',
      'note',
      'description',
      'article',
      'format_quote',
      'lightbulb',
      'psychology',
      'emoji_objects',
      'sentiment_satisfied',
      'mood',
      'notifications',
      'alarm',
      'event',
      'calendar_today',
      'person',
      'group',
      'work',
      'school',
      'home',
      'place',
      'music_note',
      'movie',
      'photo',
      'brush',
      'palette',
      'sports_esports',
      'sports',
      'fitness_center',
      'restaurant',
      'local_cafe',
      'shopping_cart',
      'monetization_on',
      'beach_access',
      'nature',
      'pets',
    ];
  }

  // 获取所有图标及其对应的IconData
  static Map<String, IconData> getAllIcons() {
    Map<String, IconData> icons = {};
    for (String name in getAllIconNames()) {
      icons[name] = getIconData(name);
    }
    return icons;
  }
}
