import 'package:relic/relic.dart' as relic;
import 'package:roux/roux.dart' as roux;
import 'package:spanner/spanner.dart' as spanner;

import '_shared.dart';

const _defaultRouteCount = 500;
const _defaultQueryCount = 50000;

class MinimalFeatureBenchmark extends SingleScenarioBenchmark {
  MinimalFeatureBenchmark(
    Target target, {
    required this.routeCount,
    required this.queryCount,
  }) : super(target, 'minimal-feature');

  final int routeCount;
  final int queryCount;
  final requests = <Request>[];
  var sink = 0;
  roux.Router<int>? _rouxRouter;
  relic.Router<int>? _relicRouter;
  spanner.Spanner? _spannerRouter;

  @override
  void setup() {
    requests.clear();
    for (var i = 0; i < queryCount; i++) {
      if ((i & 1) == 0) {
        requests.add(Request('/static/${i % routeCount}/home', false));
      } else {
        final routeIndex = i % routeCount;
        requests.add(
          Request('/users/user_$i/orders/order_$i/item$routeIndex', true),
        );
      }
    }

    switch (target) {
      case Target.roux:
        final router = newRouxRouter();
        for (var i = 0; i < routeCount; i++) {
          router.add('/static/$i/home', i, method: 'GET');
          router.add('/users/:id/orders/:orderId/item$i', i, method: 'GET');
        }
        _rouxRouter = router;
      case Target.relic:
        final router = relic.Router<int>();
        for (var i = 0; i < routeCount; i++) {
          router.get('/static/$i/home', i);
          router.get('/users/:id/orders/:orderId/item$i', i);
        }
        _relicRouter = router;
      case Target.spanner:
        final router = spanner.Spanner();
        final method = constGetHttpMethod();
        for (var i = 0; i < routeCount; i++) {
          router.addRoute(method, '/static/$i/home', i);
          router.addRoute(method, '/users/<id>/orders/<orderId>/item$i', i);
        }
        _spannerRouter = router;
    }
  }

  @override
  void run() {
    switch (target) {
      case Target.roux:
        final router = _rouxRouter!;
        for (final request in requests) {
          final match = router.match(request.path, method: 'GET');
          sink ^= match?.data ?? 0;
          if (request.needsParams) {
            consumeStringParams(match?.params, _mix);
          }
        }
      case Target.relic:
        final router = _relicRouter!;
        final method = constGetMethod();
        for (final request in requests) {
          final match = router.lookup(method, request.path).asMatch;
          sink ^= match.value;
          if (request.needsParams) {
            consumeSymbolParams(match.parameters, _mix);
          }
        }
      case Target.spanner:
        final router = _spannerRouter!;
        final method = constGetHttpMethod();
        for (final request in requests) {
          final match = router.lookup(method, request.path)!;
          for (final value in match.values) {
            sink ^= value as int;
          }
          if (request.needsParams) {
            consumeDynamicParams(match.params, _mix);
          }
        }
    }
  }

  void _mix(int value) => sink ^= value;

  @override
  void teardown() {
    if (sink == -1) throw StateError('unreachable');
  }
}

void main(List<String> args) {
  final target = parseTarget(args);
  final routeCount = parseIntArg(args, 1, _defaultRouteCount);
  final queryCount = parseIntArg(args, 2, _defaultQueryCount);
  printHeader(
    'minimal-feature',
    target,
    routeCount: routeCount,
    queryCount: queryCount,
    note: 'clean paths, fixed GET, static + simple dynamic, params consumed',
  );
  final bench = MinimalFeatureBenchmark(
    target,
    routeCount: routeCount,
    queryCount: queryCount,
  );
  final score = bench.measure();
  print('score(us)=${score.toStringAsFixed(1)}');
}
