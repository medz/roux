import 'package:relic/relic.dart' as relic;
import 'package:roux/roux.dart' as roux;

import '_shared.dart';

const _defaultRouteCount = 500;
const _defaultQueryCount = 50000;
const _benchmarkNote =
    'stress benchmark: unique dirty dynamic paths exceed relic intern cache capacity';

class CacheThrashFeatureBenchmark extends SingleScenarioBenchmark {
  CacheThrashFeatureBenchmark(
    Target target, {
    required this.routeCount,
    required this.queryCount,
  }) : super(target, 'cache-thrash-feature');

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
      requests.add(
        Request(
          '/users//tmp/../user_$i/orders/./order_$i/item${i % routeCount}/',
          true,
        ),
      );
    }

    switch (target) {
      case Target.roux:
        final router = roux.Router<int>(normalizePath: true);
        for (var i = 0; i < routeCount; i++) {
          router.add('/users/:id/orders/:orderId/item$i', i, method: 'GET');
        }
        _rouxRouter = router;
      case Target.relic:
        final router = relic.Router<int>();
        for (var i = 0; i < routeCount; i++) {
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
          consumeStringParams(match?.params, _mix);
        }
      case Target.relic:
        final router = _relicRouter!;
        const method = relic.Method.get;
        for (final request in requests) {
          final match = router.lookup(method, request.path).asMatch;
          sink ^= match.value;
          consumeSymbolParams(match.parameters, _mix);
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
    'cache-thrash-feature',
    target,
    routeCount: routeCount,
    queryCount: queryCount,
    note: _benchmarkNote,
  );
  final bench = CacheThrashFeatureBenchmark(
    target,
    routeCount: routeCount,
    queryCount: queryCount,
  );
  final score = bench.measure();
  print('score(us)=${score.toStringAsFixed(1)}');
}
