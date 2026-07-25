import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/localsend/utils/simple_provider.dart';

class CounterNotifier extends Notifier<int> {
  @override
  int init() => 0;

  void increment() {
    state++;
  }
}

void main() {
  group('Notifier', () {
    test('init and state', () {
      final notifier = CounterNotifier();
      notifier.state = notifier.init();
      expect(notifier.state, 0);

      notifier.increment();
      expect(notifier.state, 1);
    });

    test('stream emits new states', () async {
      final notifier = CounterNotifier();
      notifier.state = notifier.init();

      final states = <int>[];
      final subscription = notifier.stream.listen(states.add);

      notifier.increment();
      notifier.increment();

      await Future.delayed(Duration.zero);
      expect(states, [1, 2]);

      subscription.cancel();
      notifier.dispose();
    });
  });

  group('NotifierProvider', () {
    test('creates and caches instance', () {
      final provider =
          NotifierProvider<CounterNotifier, int>(() => CounterNotifier());

      final instance1 = provider();
      expect(instance1.state, 0);

      instance1.increment();
      expect(instance1.state, 1);

      final instance2 = provider();
      expect(identical(instance1, instance2), true);
      expect(instance2.state, 1);
    });

    test('dispose clears instance', () {
      final provider =
          NotifierProvider<CounterNotifier, int>(() => CounterNotifier());

      final instance1 = provider();
      provider.dispose();

      final instance2 = provider();
      expect(identical(instance1, instance2), false);
    });
  });

  group('SimpleRef', () {
    test('read returns state and caches provider', () {
      final ref = SimpleRef();
      final provider =
          NotifierProvider<CounterNotifier, int>(() => CounterNotifier());

      final state1 = ref.read(provider);
      expect(state1, 0);

      final notifier = ref.notifier(provider) as CounterNotifier;
      notifier.increment();

      final state2 = ref.read(provider);
      expect(state2, 1);
    });

    test('notifier returns cached instance', () {
      final ref = SimpleRef();
      final provider =
          NotifierProvider<CounterNotifier, int>(() => CounterNotifier());

      final notifier1 = ref.notifier(provider);
      final notifier2 = ref.notifier(provider);

      expect(identical(notifier1, notifier2), true);
    });

    test('dispose clears all instances', () {
      final ref = SimpleRef();
      final provider =
          NotifierProvider<CounterNotifier, int>(() => CounterNotifier());

      final notifier1 = ref.notifier(provider) as CounterNotifier;

      ref.dispose();

      // After ref.dispose, the stream controller inside the notifier is closed.
      // Trying to update the state should throw a StateError.
      expect(() => notifier1.increment(), throwsStateError);
    });
  });
}
