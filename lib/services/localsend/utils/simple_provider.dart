import 'dart:async';

/// Simplified provider system for ThoughtEcho LocalSend integration
/// Based on concepts from Refena but much simpler

abstract class Notifier<T> {
  late T _state;
  final StreamController<T> _controller = StreamController<T>.broadcast();
  
  T get state => _state;
  
  set state(T newState) {
    _state = newState;
    _controller.add(newState);
  }
  
  Stream<T> get stream => _controller.stream;
  
  T init();
  
  void dispose() {
    _controller.close();
  }
}

class NotifierProvider<N extends Notifier<T>, T> {
  final N Function() _create;
  N? _instance;
  
  NotifierProvider(this._create);
  
  N call() {
    _instance ??= _create()..state = _instance!.init();
    return _instance!;
  }
  
  void dispose() {
    _instance?.dispose();
    _instance = null;
  }
}

/// Simplified Ref for accessing providers
class SimpleRef {
  final Map<NotifierProvider, dynamic> _instances = {};
  
  T read<T>(NotifierProvider<Notifier<T>, T> provider) {
    return (_instances[provider] ??= provider()).state;
  }
  
  Notifier<T> notifier<T>(NotifierProvider<Notifier<T>, T> provider) {
    return _instances[provider] ??= provider();
  }
  
  void dispose() {
    for (final instance in _instances.values) {
      if (instance is Notifier) {
        instance.dispose();
      }
    }
    _instances.clear();
  }
}
