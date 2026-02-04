import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:roux/roux.dart';

class AddRouteBench extends BenchmarkBase {
  AddRouteBench() : super('addRoute');

  @override
  void run() {
    final router = createRouter<String>();
    addRoute(router, 'GET', '/users', 'users');
    addRoute(router, 'GET', '/users/:id', 'user');
    addRoute(router, 'GET', '/files/:filename/*', 'file-format');
    addRoute(router, 'GET', '/files/:filename', 'file');
    addRoute(router, 'GET', '/assets/**', 'assets');
    addRoute(router, 'GET', '/docs/**:path', 'docs');
    addRoute(router, 'GET', '/**', 'root-wild');
  }
}
