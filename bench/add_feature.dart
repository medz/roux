import 'package:relic/relic.dart' as relic;
import 'package:roux/roux.dart' as roux;

import '_shared.dart';

const _defaultRouteCount = 500;

enum AddScenario { staticRoutes, dynamicRoutes }

AddScenario parseAddScenario(List<String> args) {
  if (args.length < 2) {
    throw ArgumentError('Expected scenario: static or dynamic');
  }
  return switch (args[1].toLowerCase()) {
    'static' => AddScenario.staticRoutes,
    'dynamic' => AddScenario.dynamicRoutes,
    _ => throw ArgumentError('Unknown scenario: ${args[1]}'),
  };
}

String addScenarioName(AddScenario scenario) => switch (scenario) {
  AddScenario.staticRoutes => 'static',
  AddScenario.dynamicRoutes => 'dynamic',
};

class AddFeatureBenchmark extends SingleScenarioBenchmark {
  AddFeatureBenchmark(
    Target target, {
    required this.scenario,
    required this.routeCount,
  }) : super(target, 'add-feature');

  final AddScenario scenario;
  final int routeCount;
  var sink = 0;

  @override
  void run() {
    switch (target) {
      case Target.roux:
        final router = roux.Router<int>();
        for (var i = 0; i < routeCount; i++) {
          switch (scenario) {
            case AddScenario.staticRoutes:
              router.add('/static/$i/home', i, method: 'GET');
            case AddScenario.dynamicRoutes:
              router.add('/users/:id/orders/:orderId/item$i', i, method: 'GET');
          }
        }
        sink ^= router.hashCode;
      case Target.relic:
        final router = relic.Router<int>();
        for (var i = 0; i < routeCount; i++) {
          switch (scenario) {
            case AddScenario.staticRoutes:
              router.get('/static/$i/home', i);
            case AddScenario.dynamicRoutes:
              router.get('/users/:id/orders/:orderId/item$i', i);
          }
        }
        sink ^= router.hashCode;
    }
  }

  @override
  void teardown() {
    if (sink == -1) throw StateError('unreachable');
  }
}

void main(List<String> args) {
  final target = parseTarget(args);
  final scenario = parseAddScenario(args);
  final routeCount = parseIntArg(args, 2, _defaultRouteCount);
  printHeader(
    'add-feature',
    target,
    routeCount: routeCount,
    queryCount: routeCount,
    note: 'scenario=${addScenarioName(scenario)} fixed GET registration',
  );
  final bench = AddFeatureBenchmark(
    target,
    scenario: scenario,
    routeCount: routeCount,
  );
  final score = bench.measure();
  print('score(us)=${score.toStringAsFixed(1)}');
}
