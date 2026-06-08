import 'dart:developer' as developer;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class DiagnosticLayoutProbe extends SingleChildRenderObjectWidget {
  const DiagnosticLayoutProbe({
    super.key,
    required this.index,
    required this.kind,
    required super.child,
  });

  final int index;
  final String kind;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return DiagnosticLayoutProbeRenderObject(index: index, kind: kind);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant DiagnosticLayoutProbeRenderObject renderObject,
  ) {
    renderObject
      ..index = index
      ..kind = kind;
  }
}

class DiagnosticLayoutProbeRenderObject extends RenderProxyBox {
  DiagnosticLayoutProbeRenderObject({
    required int index,
    required String kind,
  })  : _index = index,
        _kind = kind;

  int _index;
  String _kind;
  Size? _previousSize;

  set index(int value) => _index = value;
  set kind(String value) => _kind = value;

  @override
  void performLayout() {
    final Size? previousSize = _previousSize;
    developer.Timeline.startSync(
      'NoteListItemLayout',
      arguments: <String, Object>{
        'index': _index,
        'kind': _kind,
        'oldHeight': previousSize?.height.toStringAsFixed(1) ?? 'none',
      },
    );
    try {
      super.performLayout();
    } finally {
      developer.Timeline.finishSync();
    }

    if (previousSize == null ||
        (size.height - previousSize.height).abs() >= 1) {
      developer.Timeline.instantSync(
        'NoteListItemSizeChanged',
        arguments: <String, Object>{
          'index': _index,
          'kind': _kind,
          'oldHeight': previousSize?.height.toStringAsFixed(1) ?? 'none',
          'newHeight': size.height.toStringAsFixed(1),
          'deltaHeight':
              (size.height - (previousSize?.height ?? 0)).toStringAsFixed(1),
        },
      );
    }
    _previousSize = size;
  }
}
