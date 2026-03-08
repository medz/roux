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

  group('duplicate policy', () {
    test('uses reject as the default router policy', () {
      final router = Router<String>(routes: {'/users/:id': 'first'});

      expect(() => router.add('/users/:id', 'second'), throwsFormatException);
    });

    test('supports replace at router level for static routes', () {
      final router = Router<String>(
        routes: {'/users/all': 'first'},
        duplicatePolicy: DuplicatePolicy.replace,
      );

      router.add('/users/all', 'second');

      expect(router.match('/users/all')?.data, 'second');
    });

    test('supports keepFirst at router level for static routes', () {
      final router = Router<String>(
        routes: {'/users/all': 'first'},
        duplicatePolicy: DuplicatePolicy.keepFirst,
      );

      router.add('/users/all', 'second');

      expect(router.match('/users/all')?.data, 'first');
    });

    test('supports append at router level for static routes', () {
      final router = Router<String>(duplicatePolicy: DuplicatePolicy.append);
      router.add('/users/all', 'first');
      router.add('/users/all', 'second');

      expect(router.match('/users/all')?.data, 'first');
      expect(router.matchAll('/users/all').map((match) => match.data), [
        'first',
        'second',
      ]);
    });

    test('supports call-level override over router default', () {
      final router = Router<String>(
        routes: {'/users/all': 'first'},
        duplicatePolicy: DuplicatePolicy.reject,
      );

      router.add(
        '/users/all',
        'second',
        duplicatePolicy: DuplicatePolicy.replace,
      );

      expect(router.match('/users/all')?.data, 'second');
    });

    test('supports replace for wildcard routes', () {
      final router = Router<String>();

      router.add('/files/*', 'first');
      router.add(
        '/files/*',
        'second',
        duplicatePolicy: DuplicatePolicy.replace,
      );

      expect(router.match('/files/a/b')?.data, 'second');
      expect(router.match('/files/a/b')?.params, {'wildcard': 'a/b'});
    });

    test('supports keepFirst for wildcard routes', () {
      final router = Router<String>();

      router.add('/files/*', 'first');
      router.add(
        '/files/*',
        'second',
        duplicatePolicy: DuplicatePolicy.keepFirst,
      );

      expect(router.match('/files/a/b')?.data, 'first');
      expect(router.match('/files/a/b')?.params, {'wildcard': 'a/b'});
    });

    test('supports append for wildcard routes', () {
      final router = Router<String>();

      router.add('/files/*', 'first');
      router.add('/files/*', 'second', duplicatePolicy: DuplicatePolicy.append);

      expect(router.match('/files/a/b')?.data, 'first');
      expect(router.matchAll('/files/a/b').map((match) => match.data), [
        'first',
        'second',
      ]);
    });

    test('supports replace for global fallback routes', () {
      final router = Router<String>();

      router.add('/*', 'first');
      router.add('/*', 'second', duplicatePolicy: DuplicatePolicy.replace);

      expect(router.match('/unknown')?.data, 'second');
      expect(router.match('/unknown')?.params, {'wildcard': 'unknown'});
    });

    test('supports keepFirst for global fallback routes', () {
      final router = Router<String>();

      router.add('/*', 'first');
      router.add('/*', 'second', duplicatePolicy: DuplicatePolicy.keepFirst);

      expect(router.match('/unknown')?.data, 'first');
      expect(router.match('/unknown')?.params, {'wildcard': 'unknown'});
    });

    test('supports append for global fallback routes', () {
      final router = Router<String>();

      router.add('/*', 'first');
      router.add('/*', 'second', duplicatePolicy: DuplicatePolicy.append);

      expect(router.match('/unknown')?.data, 'first');
      expect(router.matchAll('/unknown').map((match) => match.data), [
        'first',
        'second',
      ]);
    });

    test('supports replace for parameter routes with identical names', () {
      final router = Router<String>();

      router.add('/users/:id', 'first');
      router.add(
        '/users/:id',
        'second',
        duplicatePolicy: DuplicatePolicy.replace,
      );

      expect(router.match('/users/42')?.data, 'second');
      expect(router.match('/users/42')?.params, {'id': '42'});
    });

    test('supports keepFirst for parameter routes with identical names', () {
      final router = Router<String>();

      router.add('/users/:id', 'first');
      router.add(
        '/users/:id',
        'second',
        duplicatePolicy: DuplicatePolicy.keepFirst,
      );

      expect(router.match('/users/42')?.data, 'first');
      expect(router.match('/users/42')?.params, {'id': '42'});
    });

    test('supports append for parameter routes with identical names', () {
      final router = Router<String>();

      router.add('/users/:id', 'first');
      router.add(
        '/users/:id',
        'second',
        duplicatePolicy: DuplicatePolicy.append,
      );

      expect(router.match('/users/42')?.data, 'first');
      expect(router.matchAll('/users/42').map((match) => match.data), [
        'first',
        'second',
      ]);
      expect(router.matchAll('/users/42')[0].params, {'id': '42'});
      expect(router.matchAll('/users/42')[1].params, {'id': '42'});
    });

    test('keeps parameter-name drift as an error under replace', () {
      final router = Router<String>();
      router.add('/users/:id', 'first');

      expect(
        () => router.add(
          '/users/:name',
          'second',
          duplicatePolicy: DuplicatePolicy.replace,
        ),
        throwsFormatException,
      );
    });

    test('keeps parameter-name drift as an error under keepFirst', () {
      final router = Router<String>();
      router.add('/users/:id', 'first');

      expect(
        () => router.add(
          '/users/:name',
          'second',
          duplicatePolicy: DuplicatePolicy.keepFirst,
        ),
        throwsFormatException,
      );
    });

    test('keeps parameter-name drift as an error under append', () {
      final router = Router<String>();
      router.add('/users/:id', 'first');

      expect(
        () => router.add(
          '/users/:name',
          'second',
          duplicatePolicy: DuplicatePolicy.append,
        ),
        throwsFormatException,
      );
    });

    test('applies duplicate policy per method bucket only', () {
      final router = Router<String>();
      router.add('/users/:id', 'any');
      router.add('/users/:id', 'get', method: 'GET');
      router.add(
        '/users/:id',
        'get-replaced',
        method: 'GET',
        duplicatePolicy: DuplicatePolicy.replace,
      );

      expect(router.match('/users/1')?.data, 'any');
      expect(router.match('/users/1', method: 'GET')?.data, 'get-replaced');
    });

    test('keeps addAll sequential under replace', () {
      final router = Router<String>(duplicatePolicy: DuplicatePolicy.replace);

      router.addAll({'/users/all': 'first', '/users/all/': 'second'});

      expect(router.match('/users/all')?.data, 'second');
    });

    test('keeps addAll sequential under keepFirst', () {
      final router = Router<String>(duplicatePolicy: DuplicatePolicy.keepFirst);

      router.addAll({'/users/all': 'first', '/users/all/': 'second'});

      expect(router.match('/users/all')?.data, 'first');
    });

    test('keeps addAll sequential under append', () {
      final router = Router<String>(duplicatePolicy: DuplicatePolicy.append);

      router.addAll({'/users/all': 'first', '/users/all/': 'second'});

      expect(router.match('/users/all')?.data, 'first');
      expect(router.matchAll('/users/all').map((match) => match.data), [
        'first',
        'second',
      ]);
    });

    test('keeps addAll non-transactional under reject', () {
      final router = Router<String>();

      expect(
        () => router.addAll({'/users/all': 'first', '/users/all/': 'second'}),
        throwsFormatException,
      );

      expect(router.match('/users/all')?.data, 'first');
    });

    test('supports addAll call-level override over router default', () {
      final router = Router<String>(duplicatePolicy: DuplicatePolicy.reject);
      router.add('/users/all', 'first');

      router.addAll({
        '/users/all/': 'second',
      }, duplicatePolicy: DuplicatePolicy.replace);

      expect(router.match('/users/all')?.data, 'second');
    });

    test('matchAll sees only the retained route entry', () {
      final router = Router<String>(duplicatePolicy: DuplicatePolicy.replace);
      router.add('/*', 'global');
      router.add('/api/*', 'first');
      router.add('/api/*', 'second');

      final matches = router.matchAll('/api/demo');

      expect(matches.map((match) => match.data), ['global', 'second']);
    });

    test('matchAll expands appended entries in registration order', () {
      final router = Router<String>(duplicatePolicy: DuplicatePolicy.append);
      router.add('/*', 'global-1');
      router.add('/*', 'global-2');
      router.add('/api/*', 'api-1');
      router.add('/api/*', 'api-2');

      final matches = router.matchAll('/api/demo');

      expect(matches.map((match) => match.data), [
        'global-1',
        'global-2',
        'api-1',
        'api-2',
      ]);
    });

    test(
      'matchAll keeps the earliest retained route entry under keepFirst',
      () {
        final router = Router<String>(
          duplicatePolicy: DuplicatePolicy.keepFirst,
        );
        router.add('/*', 'global');
        router.add('/api/*', 'first');
        router.add('/api/*', 'second');

        final matches = router.matchAll('/api/demo');

        expect(matches.map((match) => match.data), ['global', 'first']);
      },
    );

    test('matchAll keeps the original retained entry after reject failure', () {
      final router = Router<String>();
      router.add('/*', 'global');
      router.add('/api/*', 'first');

      expect(() => router.add('/api/*', 'second'), throwsFormatException);

      final matches = router.matchAll('/api/demo');

      expect(matches.map((match) => match.data), ['global', 'first']);
    });

    test(
      'matchAll reflects retained entries independently per method bucket',
      () {
        final router = Router<String>();
        router.add('/*', 'global-any');
        router.add('/api/*', 'api-any-first');
        router.add(
          '/api/*',
          'api-any-second',
          duplicatePolicy: DuplicatePolicy.replace,
        );
        router.add('/api/*', 'api-get-first', method: 'GET');
        router.add(
          '/api/*',
          'api-get-second',
          method: 'GET',
          duplicatePolicy: DuplicatePolicy.keepFirst,
        );

        final matches = router.matchAll('/api/demo', method: 'GET');

        expect(matches.map((match) => match.data), [
          'global-any',
          'api-any-second',
          'api-get-first',
        ]);
      },
    );

    test('replace collapses an appended slot back to the latest entry', () {
      final router = Router<String>(duplicatePolicy: DuplicatePolicy.append);
      router.add('/api/*', 'first');
      router.add('/api/*', 'second');
      router.add('/api/*', 'third', duplicatePolicy: DuplicatePolicy.replace);

      expect(router.matchAll('/api/demo').map((match) => match.data), [
        'third',
      ]);
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

  group('matchAll', () {
    List<RouteMatch<String>> matchAll(
      Router<String> router,
      String path, {
      String? method,
    }) {
      return router.matchAll(path, method: method);
    }

    test('returns empty list when nothing matches', () {
      final router = Router<String>(routes: {'/users/:id': 'detail'});

      expect(matchAll(router, '/posts/1'), isEmpty);
    });

    test('returns empty list for invalid lookup path', () {
      final router = Router<String>(routes: {'/users/:id': 'detail'});

      expect(matchAll(router, ''), isEmpty);
      expect(matchAll(router, 'users/1'), isEmpty);
      expect(matchAll(router, '//users/1'), isEmpty);
      expect(matchAll(router, '/users//1'), isEmpty);
    });

    test('returns matches from less specific to more specific', () {
      final router = Router<String>(
        routes: {
          '/*': 'global',
          '/api/*': 'api-wildcard',
          '/api/:id': 'api-param',
          '/api/demo': 'api-demo',
        },
      );

      final matches = matchAll(router, '/api/demo');

      expect(matches.map((match) => match.data), [
        'global',
        'api-wildcard',
        'api-param',
        'api-demo',
      ]);
    });

    test('returns route-local params for each matched route', () {
      final router = Router<String>(
        routes: {
          '/*': 'global',
          '/api/*': 'api-wildcard',
          '/api/:id': 'api-param',
          '/api/demo': 'api-demo',
        },
      );

      final matches = matchAll(router, '/api/demo');

      expect(matches[0].params, {'wildcard': 'api/demo'});
      expect(matches[1].params, {'wildcard': 'demo'});
      expect(matches[2].params, {'id': 'demo'});
      expect(matches[3].params, isNull);
    });

    test('includes ANY and exact method matches when method is provided', () {
      final router = Router<String>();
      router.add('/*', 'global-any');
      router.add('/*', 'global-get', method: 'GET');
      router.add('/api/*', 'api-any');
      router.add('/api/*', 'api-get', method: 'GET');

      final matches = matchAll(router, '/api/demo', method: 'GET');

      expect(matches.map((match) => match.data), [
        'global-any',
        'global-get',
        'api-any',
        'api-get',
      ]);
    });

    test('preserves registration order for appended entries within a slot', () {
      final router = Router<String>();
      router.add('/*', 'global-any-1', duplicatePolicy: DuplicatePolicy.append);
      router.add('/*', 'global-any-2', duplicatePolicy: DuplicatePolicy.append);
      router.add(
        '/api/*',
        'api-any-1',
        duplicatePolicy: DuplicatePolicy.append,
      );
      router.add(
        '/api/*',
        'api-any-2',
        duplicatePolicy: DuplicatePolicy.append,
      );
      router.add(
        '/api/*',
        'api-get-1',
        method: 'GET',
        duplicatePolicy: DuplicatePolicy.append,
      );
      router.add(
        '/api/*',
        'api-get-2',
        method: 'GET',
        duplicatePolicy: DuplicatePolicy.append,
      );

      final matches = matchAll(router, '/api/demo', method: 'GET');

      expect(matches.map((match) => match.data), [
        'global-any-1',
        'global-any-2',
        'api-any-1',
        'api-any-2',
        'api-get-1',
        'api-get-2',
      ]);
    });

    test('uses only ANY routes when method is omitted', () {
      final router = Router<String>();
      router.add('/*', 'global-any');
      router.add('/*', 'global-get', method: 'GET');
      router.add('/api/*', 'api-any');
      router.add('/api/*', 'api-get', method: 'GET');

      final matches = matchAll(router, '/api/demo');

      expect(matches.map((match) => match.data), ['global-any', 'api-any']);
    });

    test('rejects empty method input', () {
      final router = Router<String>(routes: {'/users/:id': 'detail'});

      expect(
        () => matchAll(router, '/users/1', method: ''),
        throwsArgumentError,
      );
    });

    test('keeps single-match behavior unchanged', () {
      final router = Router<String>();
      router.add('/*', 'global');
      router.add('/api/*', 'api-wildcard');
      router.add('/api/:id', 'api-param');
      router.add('/api/demo', 'api-demo');

      expect(router.match('/api/demo')?.data, 'api-demo');
      expect(router.match('/api/demo')?.params, isNull);
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
