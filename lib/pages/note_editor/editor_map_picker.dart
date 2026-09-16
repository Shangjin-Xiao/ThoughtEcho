part of '../note_full_editor_page.dart';

/// 长按位置按钮打开地图选点，把选中的地点写回元数据状态。
///
/// 复用现有的位置按钮而不是新加一个：单击仍然是「开关自动定位」，长按才进
/// 地图——一个按钮管一件事（这条笔记记在哪儿），粗细两档精度。
extension _NoteEditorMapPicker on _NoteFullEditorPageState {
  Future<void> _openMapLocationPicker(StateSetter setDialogState) async {
    final navigator = Navigator.of(context);

    final result = await navigator.push<MapPickerResult>(
      MaterialPageRoute<MapPickerResult>(
        builder: (_) => MapLocationPickerPage(
          initialLatitude: _metadataState.latitude,
          initialLongitude: _metadataState.longitude,
        ),
      ),
    );

    if (!mounted || result == null) return;

    _updateState(() {
      _metadataState.latitude = result.latitude;
      _metadataState.longitude = result.longitude;
      // 反查失败时 location 为 null，显示会退回坐标。不保留上一个点的地址：
      // 坐标已经换了城市，旧地址就是错的。
      _metadataState.location = result.location;
      _metadataState.poiName = result.poiName;
      // 选完点还不显示位置就白选了
      _metadataState.showLocation = true;
    });
    setDialogState(() {});
  }
}
