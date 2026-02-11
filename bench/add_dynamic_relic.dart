import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:relic/relic.dart' as relic;
import 'package:roux/roux.dart' as roux;

const _defaultRouteCount = 5000;

late final List<int> _indexes;

void _setupBenchmarkData(int routeCount) {
  _indexes = List<int>.generate(routeCount, (i) => i);
}

abstract class _RouterBenchmark extends BenchmarkBase {
  _RouterBenchmark(this.target) : super('Add;Dynamic;$target');

  final String target;

  @override
  void exercise() => run();
}

class _RouxAddDynamicBenchmark extends _RouterBenchmark {
  _RouxAddDynamicBenchmark() : super('Roux');

  @override
  void run() {
    final router = roux.createRouter<int>();
    for (final i in _indexes) {
      roux.addRoute(router, 'GET', '/users/:id/items/:itemId/profile$i', i);
    }
  }
}

class _RelicAddDynamicBenchmark extends _RouterBenchmark {
  _RelicAddDynamicBenchmark() : super('Relic');

  @override
  void run() {
    final router = relic.Router<int>();
    for (final i in _indexes) {
      router.get('/users/:id/items/:itemId/profile$i', i);
    }
  }
}

int _parseArg(List<String> args, int index, int fallback) {
  if (index >= args.length) {
    return fallback;
  }
  return int.tryParse(args[index]) ?? fallback;
}

void main(List<String> args) {
  final routeCount = _parseArg(args, 0, _defaultRouteCount);
  _setupBenchmarkData(routeCount);

  print('add dynamic benchmark (relic vs roux)');
  print('routeCount=$routeCount');
  print('lower is better (us)');

  final rouxValue = _RouxAddDynamicBenchmark().measure();
  final relicValue = _RelicAddDynamicBenchmark().measure();
  final ratio = relicValue / rouxValue;

  print('Add;Dynamic;Roux  ${rouxValue.toStringAsFixed(1)}');
  print('Add;Dynamic;Relic ${relicValue.toStringAsFixed(1)}');
  print('Relic/Roux        ${ratio.toStringAsFixed(2)}x');
}
