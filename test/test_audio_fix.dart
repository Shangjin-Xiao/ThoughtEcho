// 测试音频嵌入修复的简单脚本
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'lib/utils/quill_editor_extensions.dart';

void main() {
  // 测试获取嵌入构建器
  final builders = QuillEditorExtensions.getEmbedBuilders();

  print('可用的嵌入构建器:');
  for (final builder in builders) {
    print('- ${builder.key}');
  }

  // 检查是否包含音频构建器
  final hasAudioBuilder = builders.any((builder) => builder.key == 'audio');
  final hasVideoBuilder = builders.any((builder) => builder.key == 'video');
  final hasImageBuilder = builders.any((builder) => builder.key == 'image');

  print('\n检查结果:');
  print('音频构建器: ${hasAudioBuilder ? "✓ 存在" : "✗ 缺失"}');
  print('视频构建器: ${hasVideoBuilder ? "✓ 存在" : "✗ 缺失"}');
  print('图片构建器: ${hasImageBuilder ? "✓ 存在" : "✗ 缺失"}');

  if (hasAudioBuilder && hasVideoBuilder && hasImageBuilder) {
    print('\n🎉 所有媒体类型的构建器都已正确配置！');
  } else {
    print('\n❌ 存在缺失的构建器，需要进一步检查');
  }
}
