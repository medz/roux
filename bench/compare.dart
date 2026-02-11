import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:relic/relic.dart' as relic;
import 'package:roux/roux.dart' as roux;
import 'package:routingkit/routingkit.dart' as routingkit;

const _defaultRouteCount = 500;
const _queryScales = <int>[100, 1000, 10000, 50000, 100000];
const _hotStaticIndex = 17;
const _hotDynamicIndex = 23;

late final List<String> _staticPatterns;
late final List<String> _dynamicPatterns;
late final Map<int, _ScenarioQueries> _queriesByScale;
var _sink = 0;

enum _LookupScenario {
  staticRoundRobin('Lookup;Static;RoundRobin'),
  staticHot('Lookup;Static;Hot'),
  dynamicRoundRobin('Lookup;Dynamic;RoundRobin'),
  dynamicHot('Lookup;Dynamic;Hot');

  const _LookupScenario(this.label);
  final String label;
}

class _ScenarioQueries {
  final List<String> staticRoundRobin;
  final List<String> staticHot;
  final List<String> dynamicRoundRobin;
  final List<String> dynamicHot;

  const _ScenarioQueries({
    required this.staticRoundRobin,
    required this.staticHot,
    required this.dynamicRoundRobin,
    required this.dynamicHot,
  });

  List<String> forScenario(_LookupScenario scenario) {
    switch (scenario) {
      case _LookupScenario.staticRoundRobin:
        return staticRoundRobin;
      case _LookupScenario.staticHot:
        return staticHot;
      case _LookupScenario.dynamicRoundRobin:
        return dynamicRoundRobin;
      case _LookupScenario.dynamicHot:
        return dynamicHot;
    }
  }
}

abstract class _LookupBenchmark extends BenchmarkBase {
  _LookupBenchmark(this.scenario, this.queryScale, this.target)
    : super('${scenario.label};x$queryScale;$target');

  final _LookupScenario scenario;
  final int queryScale;
  final String target;

  List<String> get queries =>
      _queriesByScale[queryScale]!.forScenario(scenario);

  @override
  void exercise() => run();
}

class _RouxLookupBenchmark extends _LookupBenchmark {
  _RouxLookupBenchmark(_LookupScenario scenario, int queryScale)
    : super(scenario, queryScale, 'Roux');

  late final roux.Router<int> _router;

  @override
  void setup() {
    _router = roux.Router<int>(
      routes: {
        for (var i = 0; i < _staticPatterns.length; i++) _staticPatterns[i]: i,
        for (var i = 0; i < _dynamicPatterns.length; i++)
          _dynamicPatterns[i]: i,
      },
    );
  }

  @override
  void run() {
    for (final path in queries) {
      _sink ^= _router.match(path)?.data ?? 0;
    }
  }
}

class _RoutingkitLookupBenchmark extends _LookupBenchmark {
  _RoutingkitLookupBenchmark(_LookupScenario scenario, int queryScale)
    : super(scenario, queryScale, 'Routingkit');

  late final routingkit.Router<int> _router;

  @override
  void setup() {
    _router = routingkit.createRouter<int>();
    for (var i = 0; i < _staticPatterns.length; i++) {
      _router.add('GET', _staticPatterns[i], i);
      _router.add('GET', _dynamicPatterns[i], i);
    }
  }

  @override
  void run() {
    for (final path in queries) {
      _sink ^= _router.find('GET', path)?.data ?? 0;
    }
  }
}

class _RelicLookupBenchmark extends _LookupBenchmark {
  _RelicLookupBenchmark(_LookupScenario scenario, int queryScale)
    : super(scenario, queryScale, 'Relic');

  late final relic.Router<int> _router;

  @override
  void setup() {
    _router = relic.Router<int>();
    for (var i = 0; i < _staticPatterns.length; i++) {
      _router.get(_staticPatterns[i], i);
      _router.get(_dynamicPatterns[i], i);
    }
  }

  @override
  void run() {
    for (final path in queries) {
      _sink ^= _router.lookup(relic.Method.get, path).asMatch.value;
    }
  }
}

void _setupBenchmarkData(int routeCount) {
  _staticPatterns = List<String>.generate(
    routeCount,
    (i) => '/static/$i/home',
    growable: false,
  );
  _dynamicPatterns = List<String>.generate(
    routeCount,
    (i) => '/users/:userId/orders/:orderId/item$i',
    growable: false,
  );

  _queriesByScale = <int, _ScenarioQueries>{
    for (final scale in _queryScales) scale: _buildQueries(scale, routeCount),
  };
}

_ScenarioQueries _buildQueries(int queryScale, int routeCount) {
  final hotStaticPath = '/static/${_hotStaticIndex % routeCount}/home';
  final hotDynamicPath =
      '/users/user_42/orders/order_7/item${_hotDynamicIndex % routeCount}';

  final staticRoundRobin = List<String>.generate(
    queryScale,
    (q) => '/static/${q % routeCount}/home',
    growable: false,
  );

  final dynamicRoundRobin = List<String>.generate(queryScale, (q) {
    final routeIndex = q % routeCount;
    final userId = (q * 37 + 11) % 100000;
    final orderId = (q * 17 + 3) % 500000;
    return '/users/user_$userId/orders/order_$orderId/item$routeIndex';
  }, growable: false);

  return _ScenarioQueries(
    staticRoundRobin: staticRoundRobin,
    staticHot: List<String>.filled(queryScale, hotStaticPath, growable: false),
    dynamicRoundRobin: dynamicRoundRobin,
    dynamicHot: List<String>.filled(
      queryScale,
      hotDynamicPath,
      growable: false,
    ),
  );
}

void main(List<String> args) {
  final routeCount = _parseArg(args, 0, _defaultRouteCount);
  _setupBenchmarkData(routeCount);

  print('lookup benchmark (benchmark_harness)');
  print('routeCount=$routeCount totalRoutes=${routeCount * 2}');
  print('queryScales=${_queryScales.join(",")}');
  print(
    'note: routingkit/relic require method, benchmark uses fixed GET for them',
  );
  print('lower is better (us)');

  final results = <String, double>{};
  for (final scenario in _LookupScenario.values) {
    for (final scale in _queryScales) {
      for (final bench in <_LookupBenchmark>[
        _RouxLookupBenchmark(scenario, scale),
        _RoutingkitLookupBenchmark(scenario, scale),
        _RelicLookupBenchmark(scenario, scale),
      ]) {
        final score = bench.measure();
        results[bench.name] = score;
        print('${bench.name.padRight(46)} ${score.toStringAsFixed(1)}');
      }
    }
  }

  _printRatios(results, 'Routingkit', 'routingkit / roux');
  _printRatios(results, 'Relic', 'relic / roux');
  print('sink=$_sink');
}

void _printRatios(
  Map<String, double> results,
  String baselineTarget,
  String title,
) {
  print('\nrelative ($title, >1 means roux is faster)');
  for (final scenario in _LookupScenario.values) {
    for (final scale in _queryScales) {
      final baselineKey = '${scenario.label};x$scale;$baselineTarget';
      final rouxKey = '${scenario.label};x$scale;Roux';
      final ratio = results[baselineKey]! / results[rouxKey]!;
      final label = '${scenario.label.replaceFirst('Lookup;', '')} x$scale';
      print('${label.padRight(30)} ${ratio.toStringAsFixed(2)}x');
    }
  }
}

int _parseArg(List<String> args, int index, int fallback) {
  if (index >= args.length) {
    return fallback;
  }
  return int.tryParse(args[index]) ?? fallback;
}
