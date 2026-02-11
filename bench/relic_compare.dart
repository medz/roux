import 'dart:math';

import 'package:benchmark_harness/perf_benchmark_harness.dart';
import 'package:relic/relic.dart' as relic;
import 'package:roux/roux.dart' as roux;
import 'package:routingkit/routingkit.dart' as routingkit;

const _defaultRouteCount = 1000;

late final List<int> _indexes;
late final List<String> _staticRoutesToLookup;
late final List<String> _dynamicRoutesToLookup;
var _sink = 0;

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

abstract class _RouterBenchmark extends PerfBenchmarkBase {
  _RouterBenchmark(Iterable<String> grouping, _CollectingEmitter emitter)
    : super(grouping.join(';'), emitter: emitter);

  @override
  void exercise() => run();
}

class _StaticAddRouxBenchmark extends _RouterBenchmark {
  _StaticAddRouxBenchmark(_CollectingEmitter emitter)
    : super(['Add', 'Static', 'x$_routeCount', 'Roux'], emitter);

  @override
  void run() {
    final routes = <String, int>{};
    for (final i in _indexes) {
      routes['/path$i'] = i;
    }
    roux.Router<int>(routes: routes);
  }
}

class _StaticLookupRouxBenchmark extends _RouterBenchmark {
  _StaticLookupRouxBenchmark(_CollectingEmitter emitter)
    : super(['Lookup', 'Static', 'x$_routeCount', 'Roux'], emitter);

  late final roux.Router<int> _router;

  @override
  void setup() {
    final routes = <String, int>{};
    for (final i in _indexes) {
      routes['/path$i'] = i;
    }
    _router = roux.Router<int>(routes: routes);
  }

  @override
  void run() {
    for (final route in _staticRoutesToLookup) {
      _sink ^= _router.match(route)?.data ?? 0;
    }
  }
}

class _DynamicAddRouxBenchmark extends _RouterBenchmark {
  _DynamicAddRouxBenchmark(_CollectingEmitter emitter)
    : super(['Add', 'Dynamic', 'x$_routeCount', 'Roux'], emitter);

  @override
  void run() {
    final routes = <String, int>{};
    for (final i in _indexes) {
      routes['/users/:id/items/:itemId/profile$i'] = i;
    }
    roux.Router<int>(routes: routes);
  }
}

class _DynamicLookupRouxBenchmark extends _RouterBenchmark {
  _DynamicLookupRouxBenchmark(_CollectingEmitter emitter)
    : super(['Lookup', 'Dynamic', 'x$_routeCount', 'Roux'], emitter);

  late final roux.Router<int> _router;

  @override
  void setup() {
    final routes = <String, int>{};
    for (final i in _indexes) {
      routes['/users/:id/items/:itemId/profile$i'] = i;
    }
    _router = roux.Router<int>(routes: routes);
  }

  @override
  void run() {
    for (final route in _dynamicRoutesToLookup) {
      _sink ^= _router.match(route)?.data ?? 0;
    }
  }
}

class _StaticAddRoutingkitBenchmark extends _RouterBenchmark {
  _StaticAddRoutingkitBenchmark(_CollectingEmitter emitter)
    : super(['Add', 'Static', 'x$_routeCount', 'Routingkit'], emitter);

  @override
  void run() {
    final router = routingkit.createRouter<int>();
    for (final i in _indexes) {
      router.add('GET', '/path$i', i);
    }
  }
}

class _StaticLookupRoutingkitBenchmark extends _RouterBenchmark {
  _StaticLookupRoutingkitBenchmark(_CollectingEmitter emitter)
    : super(['Lookup', 'Static', 'x$_routeCount', 'Routingkit'], emitter);

  late final routingkit.Router<int> _router;

  @override
  void setup() {
    _router = routingkit.createRouter<int>();
    for (final i in _indexes) {
      _router.add('GET', '/path$i', i);
    }
  }

  @override
  void run() {
    for (final route in _staticRoutesToLookup) {
      _sink ^= _router.find('GET', route)?.data ?? 0;
    }
  }
}

class _DynamicAddRoutingkitBenchmark extends _RouterBenchmark {
  _DynamicAddRoutingkitBenchmark(_CollectingEmitter emitter)
    : super(['Add', 'Dynamic', 'x$_routeCount', 'Routingkit'], emitter);

  @override
  void run() {
    final router = routingkit.createRouter<int>();
    for (final i in _indexes) {
      router.add('GET', '/users/:id/items/:itemId/profile$i', i);
    }
  }
}

class _DynamicLookupRoutingkitBenchmark extends _RouterBenchmark {
  _DynamicLookupRoutingkitBenchmark(_CollectingEmitter emitter)
    : super(['Lookup', 'Dynamic', 'x$_routeCount', 'Routingkit'], emitter);

  late final routingkit.Router<int> _router;

  @override
  void setup() {
    _router = routingkit.createRouter<int>();
    for (final i in _indexes) {
      _router.add('GET', '/users/:id/items/:itemId/profile$i', i);
    }
  }

  @override
  void run() {
    for (final route in _dynamicRoutesToLookup) {
      _sink ^= _router.find('GET', route)?.data ?? 0;
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

void main(List<String> args) {
  final routeCount = _parseArg(args, 0, _defaultRouteCount);
  _setupBenchmarkData(routeCount);

  print('relic-style benchmark (benchmark_harness/perf_benchmark_harness)');
  print('routeCount=$routeCount seed=123');
  print('format=test;metric;value;unit');
  print('lower is better (us)');

  final emitter = _CollectingEmitter();
  for (final benchmark in <_RouterBenchmark>[
    _StaticAddRoutingkitBenchmark(emitter),
    _StaticAddRelicBenchmark(emitter),
    _StaticAddRouxBenchmark(emitter),
    _StaticLookupRoutingkitBenchmark(emitter),
    _StaticLookupRelicBenchmark(emitter),
    _StaticLookupRouxBenchmark(emitter),
    _DynamicAddRoutingkitBenchmark(emitter),
    _DynamicAddRelicBenchmark(emitter),
    _DynamicAddRouxBenchmark(emitter),
    _DynamicLookupRoutingkitBenchmark(emitter),
    _DynamicLookupRelicBenchmark(emitter),
    _DynamicLookupRouxBenchmark(emitter),
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
  final keyStaticAddBase = 'Add;Static;x$_routeCount;$baseline';
  final keyStaticAddRoux = 'Add;Static;x$_routeCount;Roux';
  final keyStaticLookupBase = 'Lookup;Static;x$_routeCount;$baseline';
  final keyStaticLookupRoux = 'Lookup;Static;x$_routeCount;Roux';
  final keyDynamicAddBase = 'Add;Dynamic;x$_routeCount;$baseline';
  final keyDynamicAddRoux = 'Add;Dynamic;x$_routeCount;Roux';
  final keyDynamicLookupBase = 'Lookup;Dynamic;x$_routeCount;$baseline';
  final keyDynamicLookupRoux = 'Lookup;Dynamic;x$_routeCount;Roux';

  print('\nrelative ($title, >1 means roux is faster)');
  _printRatio(
    'add static',
    results[keyStaticAddBase]!,
    results[keyStaticAddRoux]!,
  );
  _printRatio(
    'lookup static',
    results[keyStaticLookupBase]!,
    results[keyStaticLookupRoux]!,
  );
  _printRatio(
    'add dynamic',
    results[keyDynamicAddBase]!,
    results[keyDynamicAddRoux]!,
  );
  _printRatio(
    'lookup dynamic',
    results[keyDynamicLookupBase]!,
    results[keyDynamicLookupRoux]!,
  );
}

void _printRatio(String label, double baseline, double rouxValue) {
  final ratio = baseline / rouxValue;
  print('${label.padRight(14)} ${ratio.toStringAsFixed(2)}x');
}

int _parseArg(List<String> args, int index, int fallback) {
  if (index >= args.length) {
    return fallback;
  }
  return int.tryParse(args[index]) ?? fallback;
}
