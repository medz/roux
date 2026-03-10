import 'dart:math';

import 'package:relic/relic.dart' as relic;
import 'package:roux/roux.dart' as roux;

import '_shared.dart';

const _defaultRouteCount = 500;

enum RelicOfficialScenario {
  addStatic,
  lookupStatic,
  addDynamic,
  lookupDynamic,
}

RelicOfficialScenario parseRelicOfficialScenario(List<String> args) {
  if (args.length < 2) {
    throw ArgumentError(
      'Expected scenario: add-static, lookup-static, add-dynamic, or lookup-dynamic',
    );
  }
  return switch (args[1].toLowerCase()) {
    'add-static' => RelicOfficialScenario.addStatic,
    'lookup-static' => RelicOfficialScenario.lookupStatic,
    'add-dynamic' => RelicOfficialScenario.addDynamic,
    'lookup-dynamic' => RelicOfficialScenario.lookupDynamic,
    _ => throw ArgumentError('Unknown scenario: ${args[1]}'),
  };
}

String relicOfficialScenarioName(RelicOfficialScenario scenario) =>
    switch (scenario) {
      RelicOfficialScenario.addStatic => 'add-static',
      RelicOfficialScenario.lookupStatic => 'lookup-static',
      RelicOfficialScenario.addDynamic => 'add-dynamic',
      RelicOfficialScenario.lookupDynamic => 'lookup-dynamic',
    };

final class _RelicBenchmarkData {
  _RelicBenchmarkData(this.indexes, this.staticRoutes, this.dynamicRoutes);

  final List<int> indexes;
  final List<String> staticRoutes;
  final List<String> dynamicRoutes;
}

_RelicBenchmarkData _buildRelicBenchmarkData(int routeCount) {
  final indexes = List<int>.generate(routeCount, (i) => i);
  final permutedIndexes = indexes.toList()..shuffle(Random(123));
  final staticRoutes = [for (final i in permutedIndexes) '/path$i'];
  final dynamicRoutes = [
    for (final i in permutedIndexes)
      '/users/user_${Random(i).nextInt(1000)}'
          '/items/item_${Random(i + 1).nextInt(5000)}'
          '/profile$i',
  ];
  return _RelicBenchmarkData(indexes, staticRoutes, dynamicRoutes);
}

class RelicOfficialBenchmark extends SingleScenarioBenchmark {
  RelicOfficialBenchmark(
    Target target, {
    required this.scenario,
    required this.routeCount,
  }) : super(target, 'relic-official-feature');

  final RelicOfficialScenario scenario;
  final int routeCount;
  late final _RelicBenchmarkData _data;
  var sink = 0;
  roux.Router<int>? _rouxRouter;
  relic.Router<int>? _relicRouter;

  @override
  void setup() {
    _data = _buildRelicBenchmarkData(routeCount);
    switch (scenario) {
      case RelicOfficialScenario.lookupStatic:
        switch (target) {
          case Target.roux:
            final router = roux.Router<int>();
            for (final i in _data.indexes) {
              router.add('/path$i', i, method: 'GET');
            }
            _rouxRouter = router;
          case Target.relic:
            final router = relic.Router<int>();
            for (final i in _data.indexes) {
              router.get('/path$i', i);
            }
            _relicRouter = router;
        }
      case RelicOfficialScenario.lookupDynamic:
        switch (target) {
          case Target.roux:
            final router = roux.Router<int>();
            for (final i in _data.indexes) {
              router.add(
                '/users/:id/items/:itemId/profile$i',
                i,
                method: 'GET',
              );
            }
            _rouxRouter = router;
          case Target.relic:
            final router = relic.Router<int>();
            for (final i in _data.indexes) {
              router.get('/users/:id/items/:itemId/profile$i', i);
            }
            _relicRouter = router;
        }
      case RelicOfficialScenario.addStatic:
      case RelicOfficialScenario.addDynamic:
        break;
    }
  }

  @override
  void run() {
    switch (scenario) {
      case RelicOfficialScenario.addStatic:
        _runAddStatic();
      case RelicOfficialScenario.lookupStatic:
        _runLookupStatic();
      case RelicOfficialScenario.addDynamic:
        _runAddDynamic();
      case RelicOfficialScenario.lookupDynamic:
        _runLookupDynamic();
    }
  }

  void _runAddStatic() {
    switch (target) {
      case Target.roux:
        final router = roux.Router<int>();
        for (final i in _data.indexes) {
          router.add('/path$i', i, method: 'GET');
        }
        sink ^= router.hashCode;
      case Target.relic:
        final router = relic.Router<int>();
        for (final i in _data.indexes) {
          router.get('/path$i', i);
        }
        sink ^= router.hashCode;
    }
  }

  void _runLookupStatic() {
    switch (target) {
      case Target.roux:
        final router = _rouxRouter!;
        for (final route in _data.staticRoutes) {
          sink ^= requireRouxMatch<int>(
            router.match(route, method: 'GET'),
            route,
            'GET',
          ).data;
        }
      case Target.relic:
        final router = _relicRouter!;
        const method = relic.Method.get;
        for (final route in _data.staticRoutes) {
          sink ^= requireRelicMatch<int>(
            router.lookup(method, route),
            route,
          ).value;
        }
    }
  }

  void _runAddDynamic() {
    switch (target) {
      case Target.roux:
        final router = roux.Router<int>();
        for (final i in _data.indexes) {
          router.add('/users/:id/items/:itemId/profile$i', i, method: 'GET');
        }
        sink ^= router.hashCode;
      case Target.relic:
        final router = relic.Router<int>();
        for (final i in _data.indexes) {
          router.get('/users/:id/items/:itemId/profile$i', i);
        }
        sink ^= router.hashCode;
    }
  }

  void _runLookupDynamic() {
    switch (target) {
      case Target.roux:
        final router = _rouxRouter!;
        for (final route in _data.dynamicRoutes) {
          sink ^= requireRouxMatch<int>(
            router.match(route, method: 'GET'),
            route,
            'GET',
          ).data;
        }
      case Target.relic:
        final router = _relicRouter!;
        const method = relic.Method.get;
        for (final route in _data.dynamicRoutes) {
          sink ^= requireRelicMatch<int>(
            router.lookup(method, route),
            route,
          ).value;
        }
    }
  }

  @override
  void teardown() {
    if (sink == -1) throw StateError('unreachable');
  }
}

void main(List<String> args) {
  final target = parseTarget(args);
  final scenario = parseRelicOfficialScenario(args);
  final routeCount = parseIntArg(args, 2, _defaultRouteCount);
  printHeader(
    'relic-official-feature',
    target,
    routeCount: routeCount,
    queryCount: routeCount,
    note:
        'scenario=${relicOfficialScenarioName(scenario)} contract copied from '
        'relic/packages/benchmark/bin/benchmark.dart with fixed GET',
  );
  final bench = RelicOfficialBenchmark(
    target,
    scenario: scenario,
    routeCount: routeCount,
  );
  final score = bench.measure();
  print('score(us)=${score.toStringAsFixed(1)}');
}
