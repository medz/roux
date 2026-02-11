import 'package:benchmark_harness/perf_benchmark_harness.dart';
import 'package:relic/relic.dart' as relic;
import 'package:roux/roux.dart' as roux;
import 'package:routingkit/routingkit.dart' as routingkit;

const _sampleCount = 1024;
const _defaultStaticValue = 1;
const _defaultDynamicValue = 2;

final _staticPatterns = List<String>.generate(
  _sampleCount,
  (i) => '/users/all_$i',
  growable: false,
);
final _dynamicPatterns = List<String>.generate(
  _sampleCount,
  (i) => '/users/:id/orders/:orderId/item$i',
  growable: false,
);
final _dynamicLookups = List<String>.generate(
  _sampleCount,
  (i) => '/users/user_$i/orders/order_$i/item$i',
  growable: false,
);

var _sink = 0;
var _cursor = 0;

int _nextIndex() {
  final index = _cursor;
  _cursor = (_cursor + 1) & (_sampleCount - 1);
  return index;
}

class _CollectingEmitter extends ScoreEmitterV2 {
  final Map<String, double> runtimeByName = <String, double>{};

  @override
  void emit(
    String testName,
    double value, {
    String metric = 'RunTime',
    String unit = 'us',
  }) {
    if (metric == 'RunTime') {
      runtimeByName[testName] = value;
    }
    print([testName, metric, value.toStringAsFixed(1), unit].join(';'));
  }
}

abstract class _SingleAddBenchmark extends PerfBenchmarkBase {
  _SingleAddBenchmark(Iterable<String> grouping, _CollectingEmitter emitter)
    : super(grouping.join(';'), emitter: emitter);

  @override
  void exercise() => run();
}

class _StaticSingleAddRouxBenchmark extends _SingleAddBenchmark {
  _StaticSingleAddRouxBenchmark(_CollectingEmitter emitter)
    : super(['AddSingle', 'Static', 'Roux'], emitter);

  @override
  void run() {
    final index = _nextIndex();
    final route = _staticPatterns[index];
    final router = roux.Router<int>();
    router.add(route, _defaultStaticValue);
    _sink ^= router.match(route)?.data ?? 0;
  }
}

class _DynamicSingleAddRouxBenchmark extends _SingleAddBenchmark {
  _DynamicSingleAddRouxBenchmark(_CollectingEmitter emitter)
    : super(['AddSingle', 'Dynamic', 'Roux'], emitter);

  @override
  void run() {
    final index = _nextIndex();
    final route = _dynamicPatterns[index];
    final lookup = _dynamicLookups[index];
    final router = roux.Router<int>();
    router.add(route, _defaultDynamicValue);
    _sink ^= router.match(lookup)?.data ?? 0;
  }
}

class _StaticSingleAddRoutingkitBenchmark extends _SingleAddBenchmark {
  _StaticSingleAddRoutingkitBenchmark(_CollectingEmitter emitter)
    : super(['AddSingle', 'Static', 'Routingkit'], emitter);

  @override
  void run() {
    final index = _nextIndex();
    final route = _staticPatterns[index];
    final router = routingkit.createRouter<int>();
    router.add('GET', route, _defaultStaticValue);
    _sink ^= router.find('GET', route)?.data ?? 0;
  }
}

class _DynamicSingleAddRoutingkitBenchmark extends _SingleAddBenchmark {
  _DynamicSingleAddRoutingkitBenchmark(_CollectingEmitter emitter)
    : super(['AddSingle', 'Dynamic', 'Routingkit'], emitter);

  @override
  void run() {
    final index = _nextIndex();
    final route = _dynamicPatterns[index];
    final lookup = _dynamicLookups[index];
    final router = routingkit.createRouter<int>();
    router.add('GET', route, _defaultDynamicValue);
    _sink ^= router.find('GET', lookup)?.data ?? 0;
  }
}

class _StaticSingleAddRelicBenchmark extends _SingleAddBenchmark {
  _StaticSingleAddRelicBenchmark(_CollectingEmitter emitter)
    : super(['AddSingle', 'Static', 'Relic'], emitter);

  @override
  void run() {
    final index = _nextIndex();
    final route = _staticPatterns[index];
    final router = relic.Router<int>();
    router.get(route, _defaultStaticValue);
    _sink ^= router.lookup(relic.Method.get, route).asMatch.value;
  }
}

class _DynamicSingleAddRelicBenchmark extends _SingleAddBenchmark {
  _DynamicSingleAddRelicBenchmark(_CollectingEmitter emitter)
    : super(['AddSingle', 'Dynamic', 'Relic'], emitter);

  @override
  void run() {
    final index = _nextIndex();
    final route = _dynamicPatterns[index];
    final lookup = _dynamicLookups[index];
    final router = relic.Router<int>();
    router.get(route, _defaultDynamicValue);
    _sink ^= router.lookup(relic.Method.get, lookup).asMatch.value;
  }
}

void main() {
  print('single add benchmark (benchmark_harness/perf_benchmark_harness)');
  print('scenario: create empty router, add one route, verify by one lookup');
  print(
    'samples=$_sampleCount (pre-generated patterns to avoid constant folding)',
  );
  print('format=test;metric;value;unit');
  print('lower is better (us)');

  final emitter = _CollectingEmitter();
  for (final benchmark in <_SingleAddBenchmark>[
    _StaticSingleAddRoutingkitBenchmark(emitter),
    _StaticSingleAddRelicBenchmark(emitter),
    _StaticSingleAddRouxBenchmark(emitter),
    _DynamicSingleAddRoutingkitBenchmark(emitter),
    _DynamicSingleAddRelicBenchmark(emitter),
    _DynamicSingleAddRouxBenchmark(emitter),
  ]) {
    benchmark.report();
  }

  _printRelative(
    emitter.runtimeByName,
    baseline: 'Routingkit',
    title: 'routingkit / roux',
  );
  _printRelative(
    emitter.runtimeByName,
    baseline: 'Relic',
    title: 'relic / roux',
  );
  print('sink=$_sink');
}

void _printRelative(
  Map<String, double> results, {
  required String baseline,
  required String title,
}) {
  final keyStaticBase = 'AddSingle;Static;$baseline';
  final keyStaticRoux = 'AddSingle;Static;Roux';
  final keyDynamicBase = 'AddSingle;Dynamic;$baseline';
  final keyDynamicRoux = 'AddSingle;Dynamic;Roux';

  final staticRatio = results[keyStaticBase]! / results[keyStaticRoux]!;
  final dynamicRatio = results[keyDynamicBase]! / results[keyDynamicRoux]!;

  print('\nrelative ($title, >1 means roux is faster)');
  print('single add static  ${staticRatio.toStringAsFixed(2)}x');
  print('single add dynamic ${dynamicRatio.toStringAsFixed(2)}x');
}
