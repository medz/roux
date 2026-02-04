import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:roux/roux.dart';

class RemoveRouteBench extends BenchmarkBase {
  RemoveRouteBench() : super('removeRoute');

  @override
  void run() {
    final router = createRouter<String>();
    addRoute(router, 'GET', '/users', 'users');
    addRoute(router, 'GET', '/users/:id', 'user');
    addRoute(router, 'GET', '/assets/**', 'assets');
    addRoute(router, 'GET', '/**', 'root-wild');

    removeRoute(router, 'GET', '/users');
    removeRoute(router, 'GET', '/users/:id');
    removeRoute(router, 'GET', '/assets/**');
    removeRoute(router, 'GET', '/**');
  }
}
