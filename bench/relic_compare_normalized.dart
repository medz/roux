import 'dart:math';

import 'package:benchmark_harness/perf_benchmark_harness.dart';
import 'package:relic/relic.dart' as relic;
import 'package:roux/roux.dart' as roux;

const _defaultRouteCount = 1000;

late final List<int> _indexes;
late final List<String> _staticRoutesToLookup;
late final List<String> _dynamicRoutesToLookup;
var _sink = 0;

void _consumeStringParams(Map<String, String>? params) {
  if (params == null) return;
  _sink ^= params.length;
  for (final entry in params.entries) {
    _sink ^= entry.key.length;
    _sink ^= entry.value.length;
  }
}

void _consumeSymbolParams(Map<Symbol, String> params) {
  _sink ^= params.length;
  for (final entry in params.entries) {
    _sink ^= entry.key.hashCode;
    _sink ^= entry.value.length;
  }
}

void _setupBenchmarkData(int routeCount) {
  _indexes = List<int>.generate(routeCount, (i) => i, growable: false);
  final permutedIndexes = _indexes.toList()..shuffle(Random(123));

  _staticRoutesToLookup = permutedIndexes.map((i) => '/path$i').toList();
  _dynamicRoutesToLookup = permutedIndexes
      .map(
        (i) =>
            '/users/user_${Random(i).nextInt(1000)}'
            '/items/item_${Random(i + 1).nextInt(5000)}'
            '/profile$i',
      )
      .toList();
}

int get _routeCount => _indexes.length;

class _CollectingEmitter extends ScoreEmitterV2 {
  final Map<String, double> runtimeByName = {};

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

abstract class _RouterBenchmark extends PerfBenchmarkBase {
  _RouterBenchmark(Iterable<String> grouping, _CollectingEmitter emitter)
    : super(grouping.join(';'), emitter: emitter);

  @override
  void exercise() => run();
}

class _StaticAddRouxNormalizedBenchmark extends _RouterBenchmark {
  _StaticAddRouxNormalizedBenchmark(_CollectingEmitter emitter)
    : super(['Add', 'Static', 'x$_routeCount', 'RouxNormalized'], emitter);

  @override
  void run() {
    final router = roux.Router<int>(normalizePath: true);
    for (final i in _indexes) {
      router.add('/path$i', i, method: 'GET');
    }
  }
}

class _StaticLookupRouxNormalizedBenchmark extends _RouterBenchmark {
  _StaticLookupRouxNormalizedBenchmark(_CollectingEmitter emitter)
    : super(['Lookup', 'Static', 'x$_routeCount', 'RouxNormalized'], emitter);

  late final roux.Router<int> _router;

  @override
  void setup() {
    _router = roux.Router<int>(normalizePath: true);
    for (final i in _indexes) {
      _router.add('/path$i', i, method: 'GET');
    }
  }

  @override
  void run() {
    for (final route in _staticRoutesToLookup) {
      _sink ^= _router.match(route, method: 'GET')?.data ?? 0;
    }
  }
}

class _DynamicAddRouxNormalizedBenchmark extends _RouterBenchmark {
  _DynamicAddRouxNormalizedBenchmark(_CollectingEmitter emitter)
    : super(['Add', 'Dynamic', 'x$_routeCount', 'RouxNormalized'], emitter);

  @override
  void run() {
    final router = roux.Router<int>(normalizePath: true);
    for (final i in _indexes) {
      router.add('/users/:id/items/:itemId/profile$i', i, method: 'GET');
    }
  }
}

class _DynamicLookupRouxNormalizedBenchmark extends _RouterBenchmark {
  _DynamicLookupRouxNormalizedBenchmark(_CollectingEmitter emitter)
    : super(['Lookup', 'Dynamic', 'x$_routeCount', 'RouxNormalized'], emitter);

  late final roux.Router<int> _router;

  @override
  void setup() {
    _router = roux.Router<int>(normalizePath: true);
    for (final i in _indexes) {
      _router.add('/users/:id/items/:itemId/profile$i', i, method: 'GET');
    }
  }

  @override
  void run() {
    for (final route in _dynamicRoutesToLookup) {
      _sink ^= _router.match(route, method: 'GET')?.data ?? 0;
    }
  }
}

class _DynamicLookupParamsRouxNormalizedBenchmark extends _RouterBenchmark {
  _DynamicLookupParamsRouxNormalizedBenchmark(_CollectingEmitter emitter)
    : super([
        'Lookup+Params',
        'Dynamic',
        'x$_routeCount',
        'RouxNormalized',
      ], emitter);

  late final roux.Router<int> _router;

  @override
  void setup() {
    _router = roux.Router<int>(normalizePath: true);
    for (final i in _indexes) {
      _router.add('/users/:id/items/:itemId/profile$i', i, method: 'GET');
    }
  }

  @override
  void run() {
    for (final route in _dynamicRoutesToLookup) {
      final match = _router.match(route, method: 'GET');
      _sink ^= match?.data ?? 0;
      _consumeStringParams(match?.params);
    }
  }
}

class _StaticAddRelicBenchmark extends _RouterBenchmark {
  _StaticAddRelicBenchmark(_CollectingEmitter emitter)
    : super(['Add', 'Static', 'x$_routeCount', 'Relic'], emitter);

  @override
  void run() {
    final router = relic.Router<int>();
    for (final i in _indexes) {
      router.get('/path$i', i);
    }
  }
}

class _StaticLookupRelicBenchmark extends _RouterBenchmark {
  _StaticLookupRelicBenchmark(_CollectingEmitter emitter)
    : super(['Lookup', 'Static', 'x$_routeCount', 'Relic'], emitter);

  late final relic.Router<int> _router;

  @override
  void setup() {
    _router = relic.Router<int>();
    for (final i in _indexes) {
      _router.get('/path$i', i);
    }
  }

  @override
  void run() {
    for (final route in _staticRoutesToLookup) {
      _sink ^= _router.lookup(relic.Method.get, route).asMatch.value;
    }
  }
}

class _DynamicAddRelicBenchmark extends _RouterBenchmark {
  _DynamicAddRelicBenchmark(_CollectingEmitter emitter)
    : super(['Add', 'Dynamic', 'x$_routeCount', 'Relic'], emitter);

  @override
  void run() {
    final router = relic.Router<int>();
    for (final i in _indexes) {
      router.get('/users/:id/items/:itemId/profile$i', i);
    }
  }
}

class _DynamicLookupRelicBenchmark extends _RouterBenchmark {
  _DynamicLookupRelicBenchmark(_CollectingEmitter emitter)
    : super(['Lookup', 'Dynamic', 'x$_routeCount', 'Relic'], emitter);

  late final relic.Router<int> _router;

  @override
  void setup() {
    _router = relic.Router<int>();
    for (final i in _indexes) {
      _router.get('/users/:id/items/:itemId/profile$i', i);
    }
  }

  @override
  void run() {
    for (final route in _dynamicRoutesToLookup) {
      _sink ^= _router.lookup(relic.Method.get, route).asMatch.value;
    }
  }
}

class _DynamicLookupParamsRelicBenchmark extends _RouterBenchmark {
  _DynamicLookupParamsRelicBenchmark(_CollectingEmitter emitter)
    : super(['Lookup+Params', 'Dynamic', 'x$_routeCount', 'Relic'], emitter);

  late final relic.Router<int> _router;

  @override
  void setup() {
    _router = relic.Router<int>();
    for (final i in _indexes) {
      _router.get('/users/:id/items/:itemId/profile$i', i);
    }
  }

  @override
  void run() {
    for (final route in _dynamicRoutesToLookup) {
      final match = _router.lookup(relic.Method.get, route).asMatch;
      _sink ^= match.value;
      _consumeSymbolParams(match.parameters);
    }
  }
}

void main(List<String> args) {
  final routeCount = _parseArg(args, 0, _defaultRouteCount);
  _setupBenchmarkData(routeCount);

  print(
    'normalized relic-style benchmark (benchmark_harness/perf_benchmark_harness)',
  );
  print('routeCount=$routeCount seed=123');
  print('note: roux uses normalizePath=true, relic uses default normalization');
  print('format=test;metric;value;unit');
  print('lower is better (us)');

  final emitter = _CollectingEmitter();
  for (final benchmark in <_RouterBenchmark>[
    _StaticAddRelicBenchmark(emitter),
    _StaticAddRouxNormalizedBenchmark(emitter),
    _StaticLookupRelicBenchmark(emitter),
    _StaticLookupRouxNormalizedBenchmark(emitter),
    _DynamicAddRelicBenchmark(emitter),
    _DynamicAddRouxNormalizedBenchmark(emitter),
    _DynamicLookupRelicBenchmark(emitter),
    _DynamicLookupRouxNormalizedBenchmark(emitter),
    _DynamicLookupParamsRelicBenchmark(emitter),
    _DynamicLookupParamsRouxNormalizedBenchmark(emitter),
  ]) {
    benchmark.report();
  }

  _printRelative(
    emitter.runtimeByName,
    baseline: 'Relic',
    target: 'RouxNormalized',
    title: 'relic / roux(normalizePath=true)',
  );
  print('sink=$_sink');
}

void _printRelative(
  Map<String, double> results, {
  required String baseline,
  required String target,
  required String title,
}) {
  final keyStaticBase = 'Add;Static;x$_routeCount;$baseline';
  final keyStaticTarget = 'Add;Static;x$_routeCount;$target';
  final keyLookupStaticBase = 'Lookup;Static;x$_routeCount;$baseline';
  final keyLookupStaticTarget = 'Lookup;Static;x$_routeCount;$target';
  final keyDynamicBase = 'Add;Dynamic;x$_routeCount;$baseline';
  final keyDynamicTarget = 'Add;Dynamic;x$_routeCount;$target';
  final keyLookupDynamicBase = 'Lookup;Dynamic;x$_routeCount;$baseline';
  final keyLookupDynamicTarget = 'Lookup;Dynamic;x$_routeCount;$target';
  final keyLookupParamsBase = 'Lookup+Params;Dynamic;x$_routeCount;$baseline';
  final keyLookupParamsTarget = 'Lookup+Params;Dynamic;x$_routeCount;$target';

  print('\nrelative ($title, >1 means roux is faster)');
  print(
    'add static     ${(results[keyStaticBase]! / results[keyStaticTarget]!).toStringAsFixed(2)}x',
  );
  print(
    'lookup static  ${(results[keyLookupStaticBase]! / results[keyLookupStaticTarget]!).toStringAsFixed(2)}x',
  );
  print(
    'add dynamic    ${(results[keyDynamicBase]! / results[keyDynamicTarget]!).toStringAsFixed(2)}x',
  );
  print(
    'lookup dynamic ${(results[keyLookupDynamicBase]! / results[keyLookupDynamicTarget]!).toStringAsFixed(2)}x',
  );
  print(
    'lookup dyn+params ${(results[keyLookupParamsBase]! / results[keyLookupParamsTarget]!).toStringAsFixed(2)}x',
  );
}

int _parseArg(List<String> args, int index, int fallback) {
  if (index >= args.length) {
    return fallback;
  }
  return int.tryParse(args[index]) ?? fallback;
}
