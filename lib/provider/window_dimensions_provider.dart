/// Window dimensions provider for ThoughtEcho
import 'package:flutter/material.dart';

class WindowDimensionsProvider extends ChangeNotifier {
  Size _currentSize = const Size(800, 600);
  
  Size get currentSize => _currentSize;
  
  void updateSize(Size newSize) {
    _currentSize = newSize;
    notifyListeners();
  }
}