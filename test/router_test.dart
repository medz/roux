import 'package:roux/roux.dart';
import 'package:test/test.dart';

void main() {
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
