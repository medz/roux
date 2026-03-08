import 'package:benchmark_harness/perf_benchmark_harness.dart';
import 'package:roux/roux.dart';

const _defaultQueryCount = 1000;
var _sink = 0;

enum _Scenario {
  staticAny('MatchAll', 'StaticAny'),
  dynamicAny('MatchAll', 'DynamicAny'),
  staticMethod('MatchAll', 'StaticMethod'),
  dynamicAppend('MatchAll', 'DynamicAppend');

  const _Scenario(this.group, this.name);
  final String group;
  final String name;
}

class _CollectingEmitter extends ScoreEmitterV2 {
  final Map<String, double> runtimeByName = <String, double>{};

  @override
  void emit(
    String testName,
    double value, {
    String metric = 'RunTime',
    String unit = 'us',
  }) {
    if (metric == 'RunTime') {
      runtimeByName[testName] = value;
    }
    print([testName, metric, value.toStringAsFixed(1), unit].join(';'));
  }
}

abstract class _MatchAllBenchmark extends PerfBenchmarkBase {
  _MatchAllBenchmark(this.scenario, this.queryCount, _CollectingEmitter emitter)
    : super(
        [scenario.group, scenario.name, 'x$queryCount', 'Roux'].join(';'),
        emitter: emitter,
      );

  final _Scenario scenario;
  final int queryCount;
  late final Router<int> _router = buildRouter();
  late final List<String> _queries = buildQueries(queryCount);

  Router<int> buildRouter();

  List<String> buildQueries(int queryCount);

  String? get method => null;

  @override
  void exercise() => run();

  @override
  void run() {
    final method = this.method;
    for (final path in _queries) {
      final matches = _router.matchAll(path, method: method);
      for (final match in matches) {
        _sink ^= match.data;
        _sink ^= match.params?.length ?? 0;
      }
    }
  }
}

class _StaticAnyBenchmark extends _MatchAllBenchmark {
  _StaticAnyBenchmark(int queryCount, _CollectingEmitter emitter)
    : super(_Scenario.staticAny, queryCount, emitter);

  @override
  Router<int> buildRouter() => Router<int>(
    routes: {'/*': 1, '/api/*': 2, '/api/users/*': 3, '/api/users/all': 4},
  );

  @override
  List<String> buildQueries(int queryCount) =>
      List<String>.filled(queryCount, '/api/users/all', growable: false);
}

class _DynamicAnyBenchmark extends _MatchAllBenchmark {
  _DynamicAnyBenchmark(int queryCount, _CollectingEmitter emitter)
    : super(_Scenario.dynamicAny, queryCount, emitter);

  @override
  Router<int> buildRouter() => Router<int>(
    routes: {
      '/*': 1,
      '/api/*': 2,
      '/api/:resource/*': 3,
      '/api/:resource/:id/*': 4,
      '/api/:resource/:id/details': 5,
    },
  );

  @override
  List<String> buildQueries(int queryCount) => List<String>.generate(
    queryCount,
    (i) => '/api/users/user_$i/details',
    growable: false,
  );
}

class _StaticMethodBenchmark extends _MatchAllBenchmark {
  _StaticMethodBenchmark(int queryCount, _CollectingEmitter emitter)
    : super(_Scenario.staticMethod, queryCount, emitter);

  @override
  Router<int> buildRouter() {
    final router = Router<int>();
    router.add('/*', 1);
    router.add('/api/*', 2);
    router.add('/api/users/*', 3);
    router.add('/api/users/all', 4);
    router.add('/api/*', 5, method: 'GET');
    router.add('/api/users/*', 6, method: 'GET');
    router.add('/api/users/all', 7, method: 'GET');
    return router;
  }

  @override
  List<String> buildQueries(int queryCount) =>
      List<String>.filled(queryCount, '/api/users/all', growable: false);

  @override
  String get method => 'GET';
}

class _DynamicAppendBenchmark extends _MatchAllBenchmark {
  _DynamicAppendBenchmark(int queryCount, _CollectingEmitter emitter)
    : super(_Scenario.dynamicAppend, queryCount, emitter);

  @override
  Router<int> buildRouter() {
    final router = Router<int>(duplicatePolicy: DuplicatePolicy.append);
    router.add('/*', 1);
    router.add('/*', 2);
    router.add('/api/*', 3);
    router.add('/api/*', 4);
    router.add('/api/:resource/*', 5);
    router.add('/api/:resource/*', 6);
    router.add('/api/:resource/:id/*', 7);
    router.add('/api/:resource/:id/*', 8);
    router.add('/api/:resource/:id/details', 9);
    router.add('/api/:resource/:id/details', 10);
    return router;
  }

  @override
  List<String> buildQueries(int queryCount) => List<String>.generate(
    queryCount,
    (i) => '/api/users/user_$i/details',
    growable: false,
  );
}

void main(List<String> args) {
  final queryCount = _parseArg(args, 0, _defaultQueryCount);

  print('matchAll benchmark (benchmark_harness/perf_benchmark_harness)');
  print('queryCount=$queryCount');
  print('format=test;metric;value;unit');
  print('lower is better (us)');

  final emitter = _CollectingEmitter();
  for (final benchmark in <_MatchAllBenchmark>[
    _StaticAnyBenchmark(queryCount, emitter),
    _DynamicAnyBenchmark(queryCount, emitter),
    _StaticMethodBenchmark(queryCount, emitter),
    _DynamicAppendBenchmark(queryCount, emitter),
  ]) {
    benchmark.report();
  }
  print('sink=$_sink');
}

int _parseArg(List<String> args, int index, int fallback) {
  if (index >= args.length) {
    return fallback;
  }
  return int.tryParse(args[index]) ?? fallback;
}
