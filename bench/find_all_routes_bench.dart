import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:roux/roux.dart';

import '_router_setup.dart';

class FindAllRoutesBench extends BenchmarkBase with RouterSetup {
  FindAllRoutesBench() : super('findAllRoutes');

  @override
  void run() {
    for (final path in paths) {
      findAllRoutes(router, 'GET', path);
    }
  }
}
