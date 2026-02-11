import 'package:roux/roux.dart';
import 'package:test/test.dart';

void main() {
  group('route registration', () {
    test('supports empty constructor and add', () {
      final router = Router<String>();
      expect(router.match('/users/42'), isNull);

      router.add('/users/:id', 'user');
      expect(router.match('/users/42')?.data, 'user');
      expect(router.match('/users/42')?.params, {'id': '42'});
    });

    test('supports addAll', () {
      final router = Router<String>();
      router.addAll({'/': 'root', '/users/all': 'all', '/users/:id': 'detail'});

      expect(router.match('/')?.data, 'root');
      expect(router.match('/users/all')?.data, 'all');
      expect(router.match('/users/7')?.data, 'detail');
      expect(router.match('/users/7')?.params, {'id': '7'});
    });

    test('supports add after initial routes', () {
      final router = Router<String>(routes: {'/': 'root'});
      router.add('/users/*', 'users');

      expect(router.match('/')?.data, 'root');
      expect(router.match('/users/a/b')?.data, 'users');
      expect(router.match('/users/a/b')?.params, {'wildcard': 'a/b'});
    });

    test('rejects duplicate route shape on add', () {
      final router = Router<String>();
      router.add('/users/:id', 'a');

      expect(() => router.add('/users/:name', 'b'), throwsFormatException);
    });
  });

  group('method matching', () {
    test('uses ANY when method is not provided', () {
      final router = Router<String>(routes: {'/users/:id': 'any'});
      router.add('/users/:id', 'get', method: 'GET');

      expect(router.match('/users/42')?.data, 'any');
      expect(router.match('/users/42', method: 'GET')?.data, 'get');
    });

    test('falls back to ANY when method bucket misses', () {
      final router = Router<String>();
      router.add('/users/:id', 'any');
      router.add('/posts/:id', 'get-post', method: 'GET');

      expect(router.match('/users/1', method: 'GET')?.data, 'any');
      expect(router.match('/users/1', method: 'POST')?.data, 'any');
    });

    test('supports addAll with method', () {
      final router = Router<String>();
      router.addAll({'/health': 'ok', '/users/:id': 'detail'}, method: 'GET');

      expect(router.match('/health'), isNull);
      expect(router.match('/health', method: 'GET')?.data, 'ok');
      expect(router.match('/users/5', method: 'GET')?.params, {'id': '5'});
    });

    test('treats method names as case-insensitive', () {
      final router = Router<String>();
      router.add('/users/:id', 'get', method: 'get');

      expect(router.match('/users/9', method: 'GET')?.data, 'get');
      expect(router.match('/users/9', method: 'GeT')?.data, 'get');
    });

    test('enforces duplicate conflicts per method bucket', () {
      final router = Router<String>();
      router.add('/users/:id', 'get', method: 'GET');
      router.add('/users/:id', 'post', method: 'POST');

      expect(
        () => router.add('/users/:name', 'get2', method: 'GET'),
        throwsFormatException,
      );
    });

    test('rejects empty method input', () {
      final router = Router<String>();

      expect(
        () => router.add('/users/:id', 'x', method: '  '),
        throwsArgumentError,
      );
      expect(
        () => router.addAll({'/users/:id': 'x'}, method: ''),
        throwsArgumentError,
      );
      expect(() => router.match('/users/1', method: ''), throwsArgumentError);
    });
  });

  group('match priority', () {
    final router = Router<String>(
      routes: {
        '/': 'root',
        '/users/all': 'users-all',
        '/users/:id': 'users-id',
        '/users/*': 'users-wildcard',
        '/*': 'global',
      },
    );

    test('matches static before param and wildcard', () {
      final match = router.match('/users/all');
      expect(match?.data, 'users-all');
      expect(match?.params, isNull);
    });

    test('matches param before wildcard', () {
      final match = router.match('/users/42');
      expect(match?.data, 'users-id');
      expect(match?.params, {'id': '42'});
    });

    test('matches wildcard before global fallback', () {
      final match = router.match('/users/42/profile');
      expect(match?.data, 'users-wildcard');
      expect(match?.params, {'wildcard': '42/profile'});
    });

    test('matches global fallback last', () {
      final match = router.match('/unknown/path');
      expect(match?.data, 'global');
      expect(match?.params, {'wildcard': 'unknown/path'});
    });

    test('matches root', () {
      final match = router.match('/');
      expect(match?.data, 'root');
      expect(match?.params, isNull);
    });
  });

  group('parameters and wildcard', () {
    final router = Router<String>(
      routes: {
        '/:id': 'single-param',
        '/:name/details': 'named-param',
        '/files/*': 'files',
        '/*': 'global',
      },
    );

    test('uses route-local parameter names', () {
      final first = router.match('/42');
      expect(first?.data, 'single-param');
      expect(first?.params, {'id': '42'});

      final second = router.match('/john/details');
      expect(second?.data, 'named-param');
      expect(second?.params, {'name': 'john'});
    });

    test('wildcard captures remainder and allows empty', () {
      final deep = router.match('/files/a/b/c');
      expect(deep?.data, 'files');
      expect(deep?.params, {'wildcard': 'a/b/c'});

      final empty = router.match('/files');
      expect(empty?.data, 'files');
      expect(empty?.params, {'wildcard': ''});
    });

    test('global wildcard captures remainder', () {
      final match = router.match('/foo/bar');
      expect(match?.data, 'global');
      expect(match?.params, {'wildcard': 'foo/bar'});
    });
  });

  group('normalization and invalid input', () {
    final router = Router<String>(
      routes: {'/a': 'a', '/Users': 'Users', '/a%2Fb': 'encoded'},
    );

    test('ignores trailing slash on input path', () {
      expect(router.match('/a/')?.data, 'a');
      expect(router.match('/a')?.data, 'a');
    });

    test('is case-sensitive', () {
      expect(router.match('/Users')?.data, 'Users');
      expect(router.match('/users'), isNull);
    });

    test('does not URL decode', () {
      expect(router.match('/a%2Fb')?.data, 'encoded');
      expect(router.match('/a/b'), isNull);
    });

    test('returns null for invalid lookup path', () {
      expect(router.match(''), isNull);
      expect(router.match('a'), isNull);
      expect(router.match('//a'), isNull);
      expect(router.match('/a//b'), isNull);
    });
  });

  group('route definition validation', () {
    test('requires leading slash', () {
      expect(() => Router<String>(routes: {'a': 'bad'}), throwsFormatException);
    });

    test('rejects wildcard in the middle', () {
      expect(
        () => Router<String>(routes: {'/a/*/b': 'bad'}),
        throwsFormatException,
      );
    });

    test('rejects invalid parameter name', () {
      expect(
        () => Router<String>(routes: {'/a/:123': 'bad'}),
        throwsFormatException,
      );
    });

    test('rejects embedded segment syntax', () {
      expect(
        () => Router<String>(routes: {'/a/:id.:ext': 'bad'}),
        throwsFormatException,
      );
    });

    test('rejects duplicate param shape', () {
      expect(
        () => Router<String>(routes: {'/users/:id': 'a', '/users/:name': 'b'}),
        throwsFormatException,
      );
    });

    test('rejects duplicate wildcard shape after normalization', () {
      expect(
        () => Router<String>(routes: {'/docs/*': 'a', '/docs/*/': 'b'}),
        throwsFormatException,
      );
    });

    test('rejects duplicate global fallback after normalization', () {
      expect(
        () => Router<String>(routes: {'/*': 'a', '/*/': 'b'}),
        throwsFormatException,
      );
    });
  });
}
