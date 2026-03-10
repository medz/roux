import 'package:relic/relic.dart' as relic;
import 'package:roux/roux.dart' as roux;

import '_shared.dart';

const _defaultRouteCount = 500;
const _defaultQueryCount = 50000;
const _defaultDynamicCardinality = 4096;
const _benchmarkNote =
    'primary comparison benchmark; roux uses normalizePath=true, '
    'relic uses its built-in always-normalized lookup; '
    'dynamic paths are reused to avoid cache-thrash dominating the result';

class AlignedFeatureBenchmark extends SingleScenarioBenchmark {
  AlignedFeatureBenchmark(
    Target target, {
    required this.routeCount,
    required this.queryCount,
    required this.dynamicCardinality,
  }) : super(target, 'aligned-feature');

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
    for (var i = 0; i < queryCount; i++) {
      final routeIndex = i % routeCount;
      if ((i & 1) == 0) {
        requests.add(Request('/./static/../static/$routeIndex/home/', false));
      } else {
        final dynamicIndex = (i >> 1) % dynamicCardinality;
        final dynamicRouteIndex = dynamicIndex % routeCount;
        requests.add(
          Request(
            '/users//tmp/../user_$dynamicIndex/orders/./order_$dynamicIndex/item$dynamicRouteIndex/',
            true,
          ),
        );
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
  final dynamicCardinality = parseIntArg(args, 3, _defaultDynamicCardinality);
  printHeader(
    'aligned-feature',
    target,
    routeCount: routeCount,
    queryCount: queryCount,
    note: '$_benchmarkNote dynamicCardinality=$dynamicCardinality',
  );
  final bench = AlignedFeatureBenchmark(
    target,
    routeCount: routeCount,
    queryCount: queryCount,
    dynamicCardinality: dynamicCardinality,
  );
  final score = bench.measure();
  print('score(us)=${score.toStringAsFixed(1)}');
}
