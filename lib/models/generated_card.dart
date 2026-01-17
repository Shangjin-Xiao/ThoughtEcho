import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/svg_to_image_service.dart';

/// 卡片类型枚举
enum CardType {
  knowledge, // 知识卡片
  quote, // 引用卡片
  philosophical, // 哲学卡片
  minimalist, // 简约卡片（新增）
  gradient, // 渐变卡片（新增）
  nature, // 自然卡片（新增）
  retro, // 复古卡片（新增）
  ink, // 水墨卡片（新增）
  cyberpunk, // 赛博朋克（新增）
  geometric, // 几何抽象（新增）
  academic, // 学术/笔记（新增）
  emotional, // 情感/日记（新增）
  dev, // 开发者/代码（新增）
}

/// AI生成的卡片模型
class GeneratedCard {
  final String id;
  final String noteId;
  final String originalContent;
  final String svgContent; // SVG代码
  final CardType type;
  final DateTime createdAt;
  // 新增元数据（可选，用于再渲染与展示）
  final String? author;
  final String? source;
  final String? location;
  final String? weather;
  final String? temperature;
  final String? date; // 原始日期字符串（格式化后 SVG 内展示的可能不同）
  final String? dayPeriod;

  const GeneratedCard({
    required this.id,
    required this.noteId,
    required this.originalContent,
    required this.svgContent,
    required this.type,
    required this.createdAt,
    this.author,
    this.source,
    this.location,
    this.weather,
    this.temperature,
    this.date,
    this.dayPeriod,
  });

  /// 转换为可分享的图片字节数组
  Future<Uint8List> toImageBytes({
    int width = 400,
    int height = 600,
    ui.ImageByteFormat format = ui.ImageByteFormat.png,
    Color backgroundColor = Colors.white,
    bool maintainAspectRatio = true,
    BuildContext? context,
    double scaleFactor = 1.0,
    ExportRenderMode renderMode = ExportRenderMode.contain,
  }) async {
    return await SvgToImageService.convertSvgToImage(
      svgContent,
      width: width,
      height: height,
      format: format,
      backgroundColor: backgroundColor,
      maintainAspectRatio: maintainAspectRatio,
      context: context,
      scaleFactor: scaleFactor,
      renderMode: renderMode,
    );
  }

  /// 从JSON创建对象
  factory GeneratedCard.fromJson(Map<String, dynamic> json) {
    return GeneratedCard(
      id: json['id'] as String,
      noteId: json['noteId'] as String,
      originalContent: json['originalContent'] as String,
      svgContent: json['svgContent'] as String,
      type: CardType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => CardType.knowledge,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      author: json['author'] as String?,
      source: json['source'] as String?,
      location: json['location'] as String?,
      weather: json['weather'] as String?,
      temperature: json['temperature'] as String?,
      date: json['date'] as String?,
      dayPeriod: json['dayPeriod'] as String?,
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'noteId': noteId,
      'originalContent': originalContent,
      'svgContent': svgContent,
      'type': type.toString(),
      'createdAt': createdAt.toIso8601String(),
      'author': author,
      'source': source,
      'location': location,
      'weather': weather,
      'temperature': temperature,
      'date': date,
      'dayPeriod': dayPeriod,
    };
  }

  /// 复制并修改部分属性
  GeneratedCard copyWith({
    String? id,
    String? noteId,
    String? originalContent,
    String? svgContent,
    CardType? type,
    DateTime? createdAt,
    String? author,
    String? source,
    String? location,
    String? weather,
    String? temperature,
    String? date,
    String? dayPeriod,
  }) {
    return GeneratedCard(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      originalContent: originalContent ?? this.originalContent,
      svgContent: svgContent ?? this.svgContent,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      author: author ?? this.author,
      source: source ?? this.source,
      location: location ?? this.location,
      weather: weather ?? this.weather,
      temperature: temperature ?? this.temperature,
      date: date ?? this.date,
      dayPeriod: dayPeriod ?? this.dayPeriod,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GeneratedCard &&
        other.id == id &&
        other.noteId == noteId &&
        other.originalContent == originalContent &&
        other.svgContent == svgContent &&
        other.type == type &&
        other.createdAt == createdAt &&
        other.author == author &&
        other.source == source &&
        other.location == location &&
        other.weather == weather &&
        other.temperature == temperature &&
        other.date == date &&
        other.dayPeriod == dayPeriod;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      noteId,
      originalContent,
      svgContent,
      type,
      createdAt,
      author,
      source,
      location,
      weather,
      temperature,
      date,
      dayPeriod,
    );
  }

  @override
  String toString() {
    return 'GeneratedCard(id: $id, noteId: $noteId, type: $type, createdAt: $createdAt, author: $author, location: $location, weather: $weather, dayPeriod: $dayPeriod)';
  }
}

/// AI卡片生成异常
class AICardGenerationException implements Exception {
  final String message;
  final dynamic originalError;

  const AICardGenerationException(this.message, [this.originalError]);

  @override
  String toString() {
    if (originalError != null) {
      return 'AICardGenerationException: $message (原因: $originalError)';
    }
    return 'AICardGenerationException: $message';
  }
}
