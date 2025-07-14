import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/svg_to_image_service.dart';

/// 卡片类型枚举
enum CardType {
  knowledge, // 知识卡片
  quote, // 引用卡片
  philosophical, // 哲学卡片
}

/// AI生成的卡片模型
class GeneratedCard {
  final String id;
  final String noteId;
  final String originalContent;
  final String svgContent; // SVG代码
  final CardType type;
  final DateTime createdAt;

  const GeneratedCard({
    required this.id,
    required this.noteId,
    required this.originalContent,
    required this.svgContent,
    required this.type,
    required this.createdAt,
  });

  /// 转换为可分享的图片字节数组
  Future<Uint8List> toImageBytes({
    int width = 400,
    int height = 600,
    ui.ImageByteFormat format = ui.ImageByteFormat.png,
    Color backgroundColor = Colors.white,
    bool maintainAspectRatio = true,
  }) async {
    return await SvgToImageService.convertSvgToImage(
      svgContent,
      width: width,
      height: height,
      format: format,
      backgroundColor: backgroundColor,
      maintainAspectRatio: maintainAspectRatio,
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
  }) {
    return GeneratedCard(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      originalContent: originalContent ?? this.originalContent,
      svgContent: svgContent ?? this.svgContent,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
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
        other.createdAt == createdAt;
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
    );
  }

  @override
  String toString() {
    return 'GeneratedCard(id: $id, noteId: $noteId, type: $type, createdAt: $createdAt)';
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
