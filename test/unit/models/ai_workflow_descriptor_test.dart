library;

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/ai_workflow_descriptor.dart';

import '../../test_harness.dart';

void main() {
  setUpAll(() async {
    await TestHarness.initialize();
  });

  group('AIWorkflowId enum', () {
    test('contains expected values', () {
      expect(AIWorkflowId.values, containsAll([
        AIWorkflowId.polish,
        AIWorkflowId.continueWriting,
        AIWorkflowId.deepAnalysis,
        AIWorkflowId.sourceAnalysis,
        AIWorkflowId.insights,
        AIWorkflowId.webFetch,
      ]));
      expect(AIWorkflowId.values.length, 6);
    });
  });

  group('AIWorkflowDescriptor model', () {
    test('creates instance with all fields provided', () {
      const descriptor = AIWorkflowDescriptor(
        id: AIWorkflowId.polish,
        command: '/polish',
        displayName: '润色文本',
        requiresBoundNote: true,
        allowedInStandardMode: true,
        allowAgentNaturalLanguageTrigger: true,
        producesEditableResult: true,
        description: '对笔记内容进行润色与修饰',
        icon: 'edit',
      );

      expect(descriptor.id, AIWorkflowId.polish);
      expect(descriptor.command, '/polish');
      expect(descriptor.displayName, '润色文本');
      expect(descriptor.requiresBoundNote, isTrue);
      expect(descriptor.allowedInStandardMode, isTrue);
      expect(descriptor.allowAgentNaturalLanguageTrigger, isTrue);
      expect(descriptor.producesEditableResult, isTrue);
      expect(descriptor.description, '对笔记内容进行润色与修饰');
      expect(descriptor.icon, 'edit');
    });

    test('creates instance with optional fields as null', () {
      const descriptor = AIWorkflowDescriptor(
        id: AIWorkflowId.deepAnalysis,
        command: '/deep_analysis',
        displayName: '深度分析',
        requiresBoundNote: false,
        allowedInStandardMode: false,
        allowAgentNaturalLanguageTrigger: false,
        producesEditableResult: false,
      );

      expect(descriptor.id, AIWorkflowId.deepAnalysis);
      expect(descriptor.command, '/deep_analysis');
      expect(descriptor.displayName, '深度分析');
      expect(descriptor.requiresBoundNote, isFalse);
      expect(descriptor.allowedInStandardMode, isFalse);
      expect(descriptor.allowAgentNaturalLanguageTrigger, isFalse);
      expect(descriptor.producesEditableResult, isFalse);
      expect(descriptor.description, isNull);
      expect(descriptor.icon, isNull);
    });
  });
}
