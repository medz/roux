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

  _staticRoutesToLookup = permutedIndexes.map((i) {
    switch (i % 3) {
      case 0:
        return '/./path$i/';
      case 1:
        return '/static/../path$i';
      default:
        return '/prefix//./../path$i/';
    }
  }).toList();
  _dynamicRoutesToLookup = permutedIndexes.map((i) {
    final userId = 'user_${Random(i).nextInt(1000)}';
    final itemId = 'item_${Random(i + 1).nextInt(5000)}';
    switch (i % 3) {
      case 0:
        return '/users//./$userId/items/./$itemId/profile$i/';
      case 1:
        return '/users/tmp/../$userId/items/tmp/../$itemId/profile$i';
      default:
        return '/users//tmp/.././$userId/items//./tmp/../$itemId/profile$i/';
    }
  }).toList();
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

class _StaticLookupRouxNormalizedDirtyBenchmark extends _RouterBenchmark {
  _StaticLookupRouxNormalizedDirtyBenchmark(_CollectingEmitter emitter)
    : super([
        'Lookup',
        'StaticDirty',
        'x$_routeCount',
        'RouxNormalized',
      ], emitter);

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

class _DynamicLookupRouxNormalizedDirtyBenchmark extends _RouterBenchmark {
  _DynamicLookupRouxNormalizedDirtyBenchmark(_CollectingEmitter emitter)
    : super([
        'Lookup',
        'DynamicDirty',
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
      _sink ^= _router.match(route, method: 'GET')?.data ?? 0;
    }
  }
}

class _DynamicLookupParamsRouxNormalizedDirtyBenchmark
    extends _RouterBenchmark {
  _DynamicLookupParamsRouxNormalizedDirtyBenchmark(_CollectingEmitter emitter)
    : super([
        'Lookup+Params',
        'DynamicDirty',
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

class _StaticLookupRelicDirtyBenchmark extends _RouterBenchmark {
  _StaticLookupRelicDirtyBenchmark(_CollectingEmitter emitter)
    : super(['Lookup', 'StaticDirty', 'x$_routeCount', 'Relic'], emitter);

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

class _DynamicLookupRelicDirtyBenchmark extends _RouterBenchmark {
  _DynamicLookupRelicDirtyBenchmark(_CollectingEmitter emitter)
    : super(['Lookup', 'DynamicDirty', 'x$_routeCount', 'Relic'], emitter);

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

class _DynamicLookupParamsRelicDirtyBenchmark extends _RouterBenchmark {
  _DynamicLookupParamsRelicDirtyBenchmark(_CollectingEmitter emitter)
    : super([
        'Lookup+Params',
        'DynamicDirty',
        'x$_routeCount',
        'Relic',
      ], emitter);

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
    'dirty normalized benchmark (benchmark_harness/perf_benchmark_harness)',
  );
  print('routeCount=$routeCount seed=123');
  print("note: lookup inputs include //, ./, ../, and trailing slash");
  print('format=test;metric;value;unit');
  print('lower is better (us)');

  final emitter = _CollectingEmitter();
  for (final benchmark in <_RouterBenchmark>[
    _StaticLookupRelicDirtyBenchmark(emitter),
    _StaticLookupRouxNormalizedDirtyBenchmark(emitter),
    _DynamicLookupRelicDirtyBenchmark(emitter),
    _DynamicLookupRouxNormalizedDirtyBenchmark(emitter),
    _DynamicLookupParamsRelicDirtyBenchmark(emitter),
    _DynamicLookupParamsRouxNormalizedDirtyBenchmark(emitter),
  ]) {
    benchmark.report();
  }

  _printRelative(
    emitter.runtimeByName,
    baseline: 'Relic',
    target: 'RouxNormalized',
    title: 'relic / roux(normalizePath=true, dirty inputs)',
  );
  print('sink=$_sink');
}

void _printRelative(
  Map<String, double> results, {
  required String baseline,
  required String target,
  required String title,
}) {
  final staticBase = 'Lookup;StaticDirty;x$_routeCount;$baseline';
  final staticTarget = 'Lookup;StaticDirty;x$_routeCount;$target';
  final dynamicBase = 'Lookup;DynamicDirty;x$_routeCount;$baseline';
  final dynamicTarget = 'Lookup;DynamicDirty;x$_routeCount;$target';
  final paramsBase = 'Lookup+Params;DynamicDirty;x$_routeCount;$baseline';
  final paramsTarget = 'Lookup+Params;DynamicDirty;x$_routeCount;$target';

  print('\nrelative ($title, >1 means roux is faster)');
  print(
    'lookup static dirty      ${(results[staticBase]! / results[staticTarget]!).toStringAsFixed(2)}x',
  );
  print(
    'lookup dynamic dirty     ${(results[dynamicBase]! / results[dynamicTarget]!).toStringAsFixed(2)}x',
  );
  print(
    'lookup dyn+params dirty  ${(results[paramsBase]! / results[paramsTarget]!).toStringAsFixed(2)}x',
  );
}

int _parseArg(List<String> args, int index, int fallback) {
  if (index >= args.length) {
    return fallback;
  }
  return int.tryParse(args[index]) ?? fallback;
}
