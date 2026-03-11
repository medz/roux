import 'package:relic/relic.dart' as relic;
import 'package:roux/roux.dart' as roux;

import '_shared.dart';

const _defaultRouteCount = 500;
const _defaultQueryCount = 50000;
const _defaultDynamicCardinality = 4096;

enum LookupScenario { staticHot, staticCold, dynamicHot, dynamicCold }

LookupScenario parseLookupScenario(List<String> args) {
  if (args.length < 2) {
    throw ArgumentError(
      'Expected scenario: static-hot, static-cold, dynamic-hot, or dynamic-cold',
    );
  }
  return switch (args[1].toLowerCase()) {
    'static-hot' => LookupScenario.staticHot,
    'static-cold' => LookupScenario.staticCold,
    'dynamic-hot' => LookupScenario.dynamicHot,
    'dynamic-cold' => LookupScenario.dynamicCold,
    _ => throw ArgumentError('Unknown scenario: ${args[1]}'),
  };
}

String lookupScenarioName(LookupScenario scenario) => switch (scenario) {
  LookupScenario.staticHot => 'static-hot',
  LookupScenario.staticCold => 'static-cold',
  LookupScenario.dynamicHot => 'dynamic-hot',
  LookupScenario.dynamicCold => 'dynamic-cold',
};

class LookupFeatureBenchmark extends SingleScenarioBenchmark {
  LookupFeatureBenchmark(
    Target target, {
    required this.scenario,
    required this.routeCount,
    required this.queryCount,
    required this.dynamicCardinality,
  }) : super(target, 'lookup-feature');

  final LookupScenario scenario;
  final int routeCount;
  final int queryCount;
  final int dynamicCardinality;
  final requests = <Request>[];
  var sink = 0;
  roux.Router<int>? _rouxRouter;
  relic.Router<int>? _relicRouter;

  @override
  void setup() {
    requests.clear();
    final hotStaticIndex = routeCount ~/ 2;
    final hotDynamicIndex = hotStaticIndex % routeCount;
    final hotDynamicPath =
        '/users//tmp/../user_hot/orders/./order_hot/item$hotDynamicIndex/';
    for (var i = 0; i < queryCount; i++) {
      switch (scenario) {
        case LookupScenario.staticHot:
          requests.add(
            Request('/./static/../static/$hotStaticIndex/home/', false),
          );
          break;
        case LookupScenario.staticCold:
          final routeIndex = i % routeCount;
          requests.add(Request('/./static/../static/$routeIndex/home/', false));
          break;
        case LookupScenario.dynamicHot:
          requests.add(Request(hotDynamicPath, true));
          break;
        case LookupScenario.dynamicCold:
          final dynamicIndex = i % dynamicCardinality;
          final routeIndex = dynamicIndex % routeCount;
          requests.add(
            Request(
              '/users//tmp/../user_$dynamicIndex/orders/./order_$dynamicIndex/item$routeIndex/',
              true,
            ),
          );
          break;
      }
    }

    switch (target) {
      case Target.roux:
        final router = roux.Router<int>(normalizePath: true);
        for (var i = 0; i < routeCount; i++) {
          router.add('/static/$i/home', i, method: 'GET');
          router.add('/users/:id/orders/:orderId/item$i', i, method: 'GET');
        }
        _rouxRouter = router;
        break;
      case Target.relic:
        final router = relic.Router<int>();
        for (var i = 0; i < routeCount; i++) {
          router.get('/static/$i/home', i);
          router.get('/users/:id/orders/:orderId/item$i', i);
        }
        _relicRouter = router;
        break;
    }
  }

  @override
  void run() {
    switch (target) {
      case Target.roux:
        final router = _rouxRouter!;
        for (final request in requests) {
          final match = requireRouxMatch<int>(
            router.match(request.path, method: 'GET'),
            request.path,
            'GET',
          );
          sink ^= match.data;
          if (request.needsParams) {
            consumeStringParams(match.params, _mix);
          }
        }
        return;
      case Target.relic:
        final router = _relicRouter!;
        const method = relic.Method.get;
        for (final request in requests) {
          final match = requireRelicMatch<int>(
            router.lookup(method, request.path),
            request.path,
          );
          sink ^= match.value;
          if (request.needsParams) {
            consumeSymbolParams(match.parameters, _mix);
          }
        }
        return;
    }
  }

  void _mix(int value) => sink ^= value;

  @override
  void teardown() {
    verifyRan();
  }
}

void main(List<String> args) {
  final target = parseTarget(args);
  final scenario = parseLookupScenario(args);
  final routeCount = parseIntArg(args, 2, _defaultRouteCount);
  final queryCount = parseIntArg(args, 3, _defaultQueryCount);
  final dynamicCardinality = parseIntArg(args, 4, _defaultDynamicCardinality);
  printHeader(
    'lookup-feature',
    target,
    routeCount: routeCount,
    queryCount: queryCount,
    note:
        'scenario=${lookupScenarioName(scenario)} fixed GET, params consumed for '
        'dynamic, roux normalizePath=true, dirty input reused where applicable, '
        'dynamicCardinality=$dynamicCardinality',
  );
  final bench = LookupFeatureBenchmark(
    target,
    scenario: scenario,
    routeCount: routeCount,
    queryCount: queryCount,
    dynamicCardinality: dynamicCardinality,
  );
  final score = bench.measure();
  print('score(us)=${score.toStringAsFixed(1)}');
}
