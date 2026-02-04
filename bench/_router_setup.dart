import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:roux/roux.dart';

mixin RouterSetup on BenchmarkBase {
  bool _initialized = false;

  late final RouterContext<String> router;
  late final List<String> paths;

  @override
  void setup() {
    if (_initialized) return;
    _initialized = true;

    router = createRouter<String>();
    addRoute(router, 'GET', '/users', 'users');
    addRoute(router, 'GET', '/users/:id', 'user');
    addRoute(router, 'GET', '/users/:id/posts/:postId', 'post');
    addRoute(router, 'GET', '/files/:filename/*', 'file-format');
    addRoute(router, 'GET', '/files/:filename', 'file');
    addRoute(router, 'GET', '/assets/**', 'assets');
    addRoute(router, 'GET', '/docs/**:path', 'docs');
    addRoute(router, 'GET', '/test/foo', 'foo');
    addRoute(router, 'GET', '/test/foo/*', 'foo-param');
    addRoute(router, 'GET', '/test/foo/**', 'foo-wild');
    addRoute(router, 'GET', '/wildcard/**', 'wild');
    addRoute(router, 'GET', '/**', 'root-wild');

    paths = <String>[
      '/users',
      '/users/123',
      '/users/123/posts/456',
      '/files/report',
      '/files/report/pdf',
      '/assets/css/app.css',
      '/docs/guide/getting-started',
      '/test/foo',
      '/test/foo/123',
      '/test/foo/123/456',
      '/wildcard/foo/bar',
      '/anything/goes/here',
    ];
  }
}
