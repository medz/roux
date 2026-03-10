import 'package:relic/relic.dart' as relic;
import 'package:roux/roux.dart' as roux;

import '_shared.dart';

const _defaultRouteCount = 500;
const _defaultQueryCount = 50000;

class AlignedFeatureBenchmark extends SingleScenarioBenchmark {
  AlignedFeatureBenchmark(
    Target target, {
    required this.routeCount,
    required this.queryCount,
  }) : super(target, 'aligned-feature');

  final int routeCount;
  final int queryCount;
  final requests = <Request>[];
  var sink = 0;
  roux.Router<int>? _rouxRouter;
  relic.Router<int>? _relicRouter;

  @override
  void setup() {
    requests.clear();
    for (var i = 0; i < queryCount; i++) {
      final routeIndex = i % routeCount;
      if ((i & 1) == 0) {
        requests.add(Request('/./static/../static/$routeIndex/home/', false));
      } else {
        requests.add(
          Request(
            '/users//tmp/../user_$i/orders/./order_$i/item$routeIndex/',
            true,
          ),
        );
      }
    }

    switch (target) {
      case Target.roux:
        final router = newRouxRouter(normalizePath: true);
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
    'aligned-feature',
    target,
    routeCount: routeCount,
    queryCount: queryCount,
    note: 'shared feature set with dirty normalized inputs and params consumed',
  );
  final bench = AlignedFeatureBenchmark(
    target,
    routeCount: routeCount,
    queryCount: queryCount,
  );
  final score = bench.measure();
  print('score(us)=${score.toStringAsFixed(1)}');
}
