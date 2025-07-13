import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// 卡片类型枚举
enum CardType {
  knowledge,      // 知识卡片
  quote,          // 引用卡片
  philosophical,  // 哲学卡片
}

/// AI生成的卡片模型
class GeneratedCard {
  final String id;
  final String noteId;
  final String originalContent;
  final String svgContent;        // SVG代码
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
  Future<Uint8List> toImageBytes() async {
    try {
      // TODO: 实现SVG到图片的转换
      // 目前返回一个简单的占位符图片
      // 在实际使用中，这个方法需要使用flutter_svg的正确API

      // 创建一个简单的画布来生成占位符图片
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..color = const Color(0xFFE0E0E0);

      // 绘制背景
      canvas.drawRect(const Rect.fromLTWH(0, 0, 400, 600), paint);

      // 绘制文本（简化版）
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'AI生成的卡片\n(图片转换功能开发中)',
          style: TextStyle(
            color: Color(0xFF666666),
            fontSize: 16,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, const Offset(50, 280));

      final picture = recorder.endRecording();
      final image = await picture.toImage(400, 600);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      picture.dispose();

      return byteData!.buffer.asUint8List();
    } catch (e) {
      throw Exception('转换图片失败: $e');
    }
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
