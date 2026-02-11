import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:roux/roux.dart';

const _routeCount = 500;
const _lookupCount = 100000;

class _LookupBenchmark extends BenchmarkBase {
  _LookupBenchmark() : super('roux.lookup.dynamic');

  late final Router<int> _router;
  late final List<String> _queries;
  var _sink = 0;

  @override
  void setup() {
    _router = Router<int>(
      routes: {
        for (var i = 0; i < _routeCount; i++) '/users/:id/items/item$i': i,
      },
    );
    _queries = List<String>.generate(
      _lookupCount,
      (i) => '/users/user_$i/items/item${i % _routeCount}',
      growable: false,
    );
  }

  @override
  void run() {
    for (final query in _queries) {
      _sink ^= _router.match(query)?.data ?? 0;
    }
  }

  @override
  void teardown() {
    if (_sink == -1) {
      throw StateError('unreachable');
    }
  }
}

void main() {
  final bench = _LookupBenchmark();
  final score = bench.measure();
  print('router=$_routeCount lookups=$_lookupCount');
  print('time(us)=${score.toStringAsFixed(1)}');
}
