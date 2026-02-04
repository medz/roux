import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:roux/roux.dart';

import '_router_setup.dart';

class FindRouteBench extends BenchmarkBase with RouterSetup {
  FindRouteBench() : super('findRoute');

  @override
  void run() {
    for (final path in paths) {
      findRoute(router, 'GET', path);
    }
  }
}
