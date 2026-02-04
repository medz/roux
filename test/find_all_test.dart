import 'package:test/test.dart';
import 'package:roux/roux.dart';

import '_utils.dart';

List<String> _findAllPaths(
  RouterContext<String> ctx,
  String method,
  String path,
) {
  return findAllRoutes(ctx, method, path).map((m) => m.data).toList();
}

void main() {
  group('findAllRoutes: basic', () {
    final router = createTestRouter([
      '/foo',
      '/foo/**',
      '/foo/bar',
      '/foo/bar/baz',
      '/foo/*/baz',
      '/**',
    ]);

    test('matches /foo/bar/baz pattern', () {
      final matches = _findAllPaths(router, 'GET', '/foo/bar/baz');
      expect(matches, ['/**', '/foo/**', '/foo/*/baz', '/foo/bar/baz']);
    });
  });

  group('findAllRoutes: complex', () {
    final router = createTestRouter([
      '/',
      '/foo',
      '/foo/*',
      '/foo/**',
      '/foo/bar',
      '/foo/baz',
      '/foo/baz/**',
      '/foo/*/sub',
      '/without-trailing',
      '/with-trailing/',
      '/c/**',
      '/cart',
    ]);

    test('can match routes', () {
      expect(_findAllPaths(router, 'GET', '/'), ['/']);
      expect(_findAllPaths(router, 'GET', '/foo'), [
        '/foo/**',
        '/foo/*',
        '/foo',
      ]);
      expect(_findAllPaths(router, 'GET', '/foo/bar'), [
        '/foo/**',
        '/foo/*',
        '/foo/bar',
      ]);
      expect(_findAllPaths(router, 'GET', '/foo/baz'), [
        '/foo/**',
        '/foo/*',
        '/foo/baz/**',
        '/foo/baz',
      ]);
      expect(_findAllPaths(router, 'GET', '/foo/123/sub'), [
        '/foo/**',
        '/foo/*/sub',
      ]);
      expect(_findAllPaths(router, 'GET', '/foo/123'), ['/foo/**', '/foo/*']);
    });

    test('trailing slash', () {
      expect(_findAllPaths(router, 'GET', '/with-trailing'), [
        '/with-trailing/',
      ]);
      expect(
        _findAllPaths(router, 'GET', '/with-trailing'),
        _findAllPaths(router, 'GET', '/with-trailing/'),
      );

      expect(_findAllPaths(router, 'GET', '/without-trailing'), [
        '/without-trailing',
      ]);
      expect(
        _findAllPaths(router, 'GET', '/without-trailing'),
        _findAllPaths(router, 'GET', '/without-trailing/'),
      );
    });

    test('prefix overlap', () {
      expect(_findAllPaths(router, 'GET', '/c/123'), ['/c/**']);
      expect(
        _findAllPaths(router, 'GET', '/c/123'),
        _findAllPaths(router, 'GET', '/c/123/'),
      );
      expect(
        _findAllPaths(router, 'GET', '/c/123'),
        _findAllPaths(router, 'GET', '/c'),
      );

      expect(_findAllPaths(router, 'GET', '/cart'), ['/cart']);
    });
  });

  group('findAllRoutes: order', () {
    final router = createTestRouter([
      '/hello',
      '/hello/world',
      '/hello/*',
      '/hello/**',
    ]);

    test('/hello', () {
      expect(_findAllPaths(router, 'GET', '/hello'), [
        '/hello/**',
        '/hello/*',
        '/hello',
      ]);
    });

    test('/hello/world', () {
      expect(_findAllPaths(router, 'GET', '/hello/world'), [
        '/hello/**',
        '/hello/*',
        '/hello/world',
      ]);
    });

    test('/hello/world/foobar', () {
      expect(_findAllPaths(router, 'GET', '/hello/world/foobar'), [
        '/hello/**',
      ]);
    });
  });

  group('findAllRoutes: named', () {
    final router = createTestRouter(['/foo', '/foo/:bar', '/foo/:bar/:qaz']);

    test('matches /foo', () {
      expect(_findAllPaths(router, 'GET', '/foo'), ['/foo']);
    });

    test('matches /foo/123', () {
      expect(_findAllPaths(router, 'GET', '/foo/123'), ['/foo/:bar']);
    });

    test('matches /foo/123/456', () {
      expect(_findAllPaths(router, 'GET', '/foo/123/456'), ['/foo/:bar/:qaz']);
    });
  });
}
