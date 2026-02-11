import 'dart:math';

import 'package:benchmark_harness/benchmark_harness.dart';
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

void main(List<String> args) {
  final routeCount = _parseArg(args, 0, _defaultRouteCount);
  _setupBenchmarkData(routeCount);

  print('roux vs routingkit benchmark (benchmark_harness)');
  print('routeCount=$routeCount seed=123');
  print('lower is better (us)');

  final results = <String, double>{};
  for (final bench in <_RouterBenchmark>[
    _RouxAddStaticBenchmark(),
    _RoutingkitAddStaticBenchmark(),
    _RouxLookupStaticBenchmark(),
    _RoutingkitLookupStaticBenchmark(),
    _RouxAddDynamicBenchmark(),
    _RoutingkitAddDynamicBenchmark(),
    _RouxLookupDynamicBenchmark(),
    _RoutingkitLookupDynamicBenchmark(),
  ]) {
    final score = bench.measure();
    results[bench.name] = score;
    print('${bench.name.padRight(40)} ${score.toStringAsFixed(1)}');
  }

  print('\nrelative (routingkit / roux, >1 means roux is faster)');
  _printRatio(
    'add static',
    results['Add;Static;x$routeCount;Routingkit']!,
    results['Add;Static;x$routeCount;Roux']!,
  );
  _printRatio(
    'lookup static',
    results['Lookup;Static;x$routeCount;Routingkit']!,
    results['Lookup;Static;x$routeCount;Roux']!,
  );
  _printRatio(
    'add dynamic',
    results['Add;Dynamic;x$routeCount;Routingkit']!,
    results['Add;Dynamic;x$routeCount;Roux']!,
  );
  _printRatio(
    'lookup dynamic',
    results['Lookup;Dynamic;x$routeCount;Routingkit']!,
    results['Lookup;Dynamic;x$routeCount;Roux']!,
  );
  print('sink=$_sink');
}

void _printRatio(String label, double routingkit, double roux) {
  final ratio = routingkit / roux;
  print('${label.padRight(14)} ${ratio.toStringAsFixed(2)}x');
}

int _parseArg(List<String> args, int index, int fallback) {
  if (index >= args.length) {
    return fallback;
  }
  return int.tryParse(args[index]) ?? fallback;
}
