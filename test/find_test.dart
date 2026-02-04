import 'package:test/test.dart';
import 'package:roux/roux.dart';

import '_utils.dart';

void main() {
  group('route matching', () {
    RouterContext<String> buildRouter() {
      return createTestRouter([
        '/test',
        '/test/:id',
        '/test/:idYZ/y/z',
        '/test/:idY/y',
        '/test/foo',
        '/test/foo/*',
        '/test/foo/**',
        '/test/foo/bar/qux',
        '/test/foo/baz',
        '/test/fooo',
        '/another/path',
        '/wildcard/**',
        r'/static\:path/\*/\*\*',
        '/**',
      ]);
    }

    test('static matches', () {
      final router = buildRouter();
      expect(findRoute(router, 'GET', '/test')?.data, '/test');
      expect(findRoute(router, 'GET', '/test/foo')?.data, '/test/foo');
      expect(findRoute(router, 'GET', '/test/fooo')?.data, '/test/fooo');
      expect(findRoute(router, 'GET', '/another/path')?.data, '/another/path');
    });

    test('param matches', () {
      final router = buildRouter();
      expect(findRoute(router, 'GET', '/test/123')?.data, '/test/:id');
      expect(findRoute(router, 'GET', '/test/123')?.params, {'id': '123'});

      expect(findRoute(router, 'GET', '/test/123/y')?.data, '/test/:idY/y');
      expect(findRoute(router, 'GET', '/test/123/y')?.params, {'idY': '123'});

      expect(
        findRoute(router, 'GET', '/test/123/y/z')?.data,
        '/test/:idYZ/y/z',
      );
      expect(findRoute(router, 'GET', '/test/123/y/z')?.params, {
        'idYZ': '123',
      });

      expect(findRoute(router, 'GET', '/test/foo/123')?.data, '/test/foo/*');
      expect(findRoute(router, 'GET', '/test/foo/123')?.params, {'_0': '123'});
    });

    test('wildcard matches', () {
      final router = buildRouter();
      expect(
        findRoute(router, 'GET', '/test/foo/123/456')?.data,
        '/test/foo/**',
      );
      expect(findRoute(router, 'GET', '/test/foo/123/456')?.params, {
        '_': '123/456',
      });

      expect(findRoute(router, 'GET', '/wildcard/foo')?.data, '/wildcard/**');
      expect(findRoute(router, 'GET', '/wildcard/foo')?.params, {'_': 'foo'});

      expect(
        findRoute(router, 'GET', '/wildcard/foo/bar')?.data,
        '/wildcard/**',
      );
      expect(findRoute(router, 'GET', '/wildcard/foo/bar')?.params, {
        '_': 'foo/bar',
      });

      expect(findRoute(router, 'GET', '/wildcard')?.data, '/wildcard/**');
      expect(findRoute(router, 'GET', '/wildcard')?.params, {'_': ''});
    });

    test('root wildcard', () {
      final router = buildRouter();
      expect(findRoute(router, 'GET', '/anything')?.data, '/**');
      expect(findRoute(router, 'GET', '/anything')?.params, {'_': 'anything'});

      expect(findRoute(router, 'GET', '/any/deep/path')?.data, '/**');
      expect(findRoute(router, 'GET', '/any/deep/path')?.params, {
        '_': 'any/deep/path',
      });
    });

    test('escaped characters', () {
      final router = buildRouter();
      expect(
        findRoute(router, 'GET', '/static%3Apath/*/**')?.data,
        r'/static\:path/\*/\*\*',
      );
      expect(
        findRoute(router, 'GET', '/static:path/some/deep/path')?.data,
        '/**',
      );
    });

    test('remove works', () {
      final router = buildRouter();
      removeRoute(router, 'GET', '/test');
      removeRoute(router, 'GET', '/test/*');
      removeRoute(router, 'GET', '/test/foo/*');
      removeRoute(router, 'GET', '/test/foo/**');
      removeRoute(router, 'GET', '/**');

      expect(findRoute(router, 'GET', '/test'), isNull);
      expect(findRoute(router, 'GET', '/anything'), isNull);
    });
  });
}
