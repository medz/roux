import 'dart:math';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:relic/relic.dart' as relic;
import 'package:roux/roux.dart' as roux;
import 'package:routingkit/routingkit.dart' as routingkit;

const _defaultRouteCount = 5000;

late final List<int> _indexes;
late final List<String> _staticRoutesToLookup;
late final List<String> _dynamicRoutesToLookup;
var _sink = 0;

void _setupBenchmarkData(int routeCount) {
  _indexes = List<int>.generate(routeCount, (i) => i);
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

abstract class _RouterBenchmark extends BenchmarkBase {
  _RouterBenchmark(this.group, this.target) : super('$group;$target');

  final String group;
  final String target;

  @override
  void warmup() {
    for (var i = 0; i < 5; i++) {
      run();
    }
  }

  @override
  void exercise() => run();
}

class _RouxAddStaticBenchmark extends _RouterBenchmark {
  _RouxAddStaticBenchmark() : super('Add;Static;x${_indexes.length}', 'Roux');

  @override
  void run() {
    final router = roux.createRouter<int>();
    for (final i in _indexes) {
      roux.addRoute(router, 'GET', '/path$i', i);
    }
  }
}

class _RouxLookupStaticBenchmark extends _RouterBenchmark {
  _RouxLookupStaticBenchmark()
    : super('Lookup;Static;x${_indexes.length}', 'Roux');

  late final roux.RouterContext<int> _router;

  @override
  void setup() {
    _router = roux.createRouter<int>();
    for (final i in _indexes) {
      roux.addRoute(_router, 'GET', '/path$i', i);
    }
  }

  @override
  void run() {
    for (final route in _staticRoutesToLookup) {
      _sink ^= roux.findRoute(_router, 'GET', route)?.data ?? 0;
    }
  }
}

class _RouxAddDynamicBenchmark extends _RouterBenchmark {
  _RouxAddDynamicBenchmark() : super('Add;Dynamic;x${_indexes.length}', 'Roux');

  @override
  void run() {
    final router = roux.createRouter<int>();
    for (final i in _indexes) {
      roux.addRoute(router, 'GET', '/users/:id/items/:itemId/profile$i', i);
    }
  }
}

class _RouxLookupDynamicBenchmark extends _RouterBenchmark {
  _RouxLookupDynamicBenchmark()
    : super('Lookup;Dynamic;x${_indexes.length}', 'Roux');

  late final roux.RouterContext<int> _router;

  @override
  void setup() {
    _router = roux.createRouter<int>();
    for (final i in _indexes) {
      roux.addRoute(_router, 'GET', '/users/:id/items/:itemId/profile$i', i);
    }
  }

  @override
  void run() {
    for (final route in _dynamicRoutesToLookup) {
      _sink ^= roux.findRoute(_router, 'GET', route)?.data ?? 0;
    }
  }
}

class _RoutingkitAddStaticBenchmark extends _RouterBenchmark {
  _RoutingkitAddStaticBenchmark()
    : super('Add;Static;x${_indexes.length}', 'Routingkit');

  @override
  void run() {
    final router = routingkit.createRouter<int>();
    for (final i in _indexes) {
      router.add('GET', '/path$i', i);
    }
  }
}

class _RoutingkitLookupStaticBenchmark extends _RouterBenchmark {
  _RoutingkitLookupStaticBenchmark()
    : super('Lookup;Static;x${_indexes.length}', 'Routingkit');

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

class _RoutingkitAddDynamicBenchmark extends _RouterBenchmark {
  _RoutingkitAddDynamicBenchmark()
    : super('Add;Dynamic;x${_indexes.length}', 'Routingkit');

  @override
  void run() {
    final router = routingkit.createRouter<int>();
    for (final i in _indexes) {
      router.add('GET', '/users/:id/items/:itemId/profile$i', i);
    }
  }
}

class _RoutingkitLookupDynamicBenchmark extends _RouterBenchmark {
  _RoutingkitLookupDynamicBenchmark()
    : super('Lookup;Dynamic;x${_indexes.length}', 'Routingkit');

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

class _RelicAddStaticBenchmark extends _RouterBenchmark {
  _RelicAddStaticBenchmark() : super('Add;Static;x${_indexes.length}', 'Relic');

  @override
  void run() {
    final router = relic.Router<int>();
    for (final i in _indexes) {
      router.get('/path$i', i);
    }
  }
}

class _RelicLookupStaticBenchmark extends _RouterBenchmark {
  _RelicLookupStaticBenchmark()
    : super('Lookup;Static;x${_indexes.length}', 'Relic');

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

class _RelicAddDynamicBenchmark extends _RouterBenchmark {
  _RelicAddDynamicBenchmark()
    : super('Add;Dynamic;x${_indexes.length}', 'Relic');

  @override
  void run() {
    final router = relic.Router<int>();
    for (final i in _indexes) {
      router.get('/users/:id/items/:itemId/profile$i', i);
    }
  }
}

class _RelicLookupDynamicBenchmark extends _RouterBenchmark {
  _RelicLookupDynamicBenchmark()
    : super('Lookup;Dynamic;x${_indexes.length}', 'Relic');

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

  print('roux vs routingkit vs relic benchmark (benchmark_harness)');
  print('routeCount=$routeCount seed=123');
  print('lower is better (us)');

  final results = <String, double>{};
  for (final bench in <_RouterBenchmark>[
    _RouxAddStaticBenchmark(),
    _RoutingkitAddStaticBenchmark(),
    _RelicAddStaticBenchmark(),
    _RouxLookupStaticBenchmark(),
    _RoutingkitLookupStaticBenchmark(),
    _RelicLookupStaticBenchmark(),
    _RouxAddDynamicBenchmark(),
    _RoutingkitAddDynamicBenchmark(),
    _RelicAddDynamicBenchmark(),
    _RouxLookupDynamicBenchmark(),
    _RoutingkitLookupDynamicBenchmark(),
    _RelicLookupDynamicBenchmark(),
  ]) {
    final score = bench.measure();
    results[bench.name] = score;
    print('${bench.name.padRight(40)} ${score.toStringAsFixed(1)}');
  }

  print('\nrelative (routingkit / roux, >1 means roux is faster)');
  _printRoutingkitRatio(
    'add static',
    results['Add;Static;x$routeCount;Routingkit']!,
    results['Add;Static;x$routeCount;Roux']!,
  );
  _printRoutingkitRatio(
    'lookup static',
    results['Lookup;Static;x$routeCount;Routingkit']!,
    results['Lookup;Static;x$routeCount;Roux']!,
  );
  _printRoutingkitRatio(
    'add dynamic',
    results['Add;Dynamic;x$routeCount;Routingkit']!,
    results['Add;Dynamic;x$routeCount;Roux']!,
  );
  _printRoutingkitRatio(
    'lookup dynamic',
    results['Lookup;Dynamic;x$routeCount;Routingkit']!,
    results['Lookup;Dynamic;x$routeCount;Roux']!,
  );

  print('\nrelative (relic / roux, >1 means roux is faster)');
  _printRelicRatio(
    'add static',
    results['Add;Static;x$routeCount;Relic']!,
    results['Add;Static;x$routeCount;Roux']!,
  );
  _printRelicRatio(
    'lookup static',
    results['Lookup;Static;x$routeCount;Relic']!,
    results['Lookup;Static;x$routeCount;Roux']!,
  );
  _printRelicRatio(
    'add dynamic',
    results['Add;Dynamic;x$routeCount;Relic']!,
    results['Add;Dynamic;x$routeCount;Roux']!,
  );
  _printRelicRatio(
    'lookup dynamic',
    results['Lookup;Dynamic;x$routeCount;Relic']!,
    results['Lookup;Dynamic;x$routeCount;Roux']!,
  );
  print('sink=$_sink');
}

void _printRoutingkitRatio(String label, double routingkit, double roux) {
  final ratio = routingkit / roux;
  print('${label.padRight(14)} ${ratio.toStringAsFixed(2)}x');
}

void _printRelicRatio(String label, double relicValue, double roux) {
  final ratio = relicValue / roux;
  print('${label.padRight(14)} ${ratio.toStringAsFixed(2)}x');
}

int _parseArg(List<String> args, int index, int fallback) {
  if (index >= args.length) {
    return fallback;
  }
  return int.tryParse(args[index]) ?? fallback;
}
