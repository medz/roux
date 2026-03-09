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
      router.add('/users/**:wildcard', 'users');

      expect(router.match('/')?.data, 'root');
      expect(router.match('/users/a/b')?.data, 'users');
      expect(router.match('/users/a/b')?.params, {'wildcard': 'a/b'});
    });

    test('rejects duplicate route shape on add', () {
      final router = Router<String>();
      router.add('/users/:id', 'a');

      expect(() => router.add('/users/:name', 'b'), throwsFormatException);
    });

    test('supports embedded parameter segments', () {
      final router = Router<String>();
      router.add('/files/:name.:ext', 'asset');

      expect(router.match('/files/readme.md')?.data, 'asset');
      expect(router.match('/files/readme.md')?.params, {
        'name': 'readme',
        'ext': 'md',
      });
    });

    test('supports named regex parameter segments', () {
      final router = Router<String>();
      router.add('/users/:id(\\d+)', 'numeric-user');

      expect(router.match('/users/42')?.data, 'numeric-user');
      expect(router.match('/users/42')?.params, {'id': '42'});
      expect(router.match('/users/nope'), isNull);
    });

    test('returns writable params maps for small dynamic matches', () {
      final router = Router<String>();
      router.add('/users/:id/items/:itemId', 'item');

      final params = router.match('/users/42/items/7')!.params!;
      params['extra'] = 'ok';

      expect(params, {'id': '42', 'itemId': '7', 'extra': 'ok'});
    });

    test('supports optional parameter segments', () {
      final router = Router<String>();
      router.add('/users/:id?', 'maybe-user');

      expect(router.match('/users/42')?.data, 'maybe-user');
      expect(router.match('/users/42')?.params, {'id': '42'});
      expect(router.match('/users')?.data, 'maybe-user');
      expect(router.match('/users')?.params, isEmpty);
    });

    test('supports repeated parameter segments', () {
      final router = Router<String>();
      router.add('/files/:path+', 'plus');
      router.add('/assets/:rest*', 'star');

      expect(router.match('/files'), isNull);
      expect(router.match('/files/a/b')?.params, {'path': 'a/b'});
      expect(router.match('/assets')?.params, isEmpty);
      expect(router.match('/assets/a/b')?.params, {'rest': 'a/b'});
    });

    test('supports single-segment wildcard routes', () {
      final router = Router<String>();
      router.add('/users/*', 'star');
      router.add('/teams/*/members', 'middle');

      expect(router.match('/users/a')?.params, {'0': 'a'});
      expect(router.match('/users/a/b'), isNull);
      expect(router.match('/teams/core/members')?.params, {'0': 'core'});
    });

    test('supports embedded wildcard segments', () {
      final assetRouter = Router<String>();
      assetRouter.add('/files/file-*-*.png', 'asset');
      final genericRouter = Router<String>();
      genericRouter.add('/files/*.:ext', 'generic');

      expect(assetRouter.match('/files/file-a-b.png')?.params, {
        '0': 'a',
        '1': 'b',
      });
      expect(assetRouter.match('/files/file-a-b-c.png')?.params, {
        '0': 'a-b',
        '1': 'c',
      });
      expect(assetRouter.match('/files/file--.png')?.params, {
        '0': '',
        '1': '',
      });
      expect(genericRouter.match('/files/.png')?.params, {
        '0': '',
        'ext': 'png',
      });
    });

    test('supports grouped pathname syntax', () {
      final pluralRouter = Router<String>();
      pluralRouter.add('/book{s}?', 'plural');
      final userRouter = Router<String>();
      userRouter.add('/users{/:id}?', 'user');
      final blogRouter = Router<String>();
      blogRouter.add('/blog/:id(\\d+){-:title}?', 'blog');
      final nestedRouter = Router<String>();
      nestedRouter.add('/docs{/:section}{/:page}?', 'docs');
      final mandatoryRouter = Router<String>();
      mandatoryRouter.add('/foo{bar}', 'foobar');

      expect(pluralRouter.match('/book')?.data, 'plural');
      expect(pluralRouter.match('/books')?.data, 'plural');
      expect(userRouter.match('/users')?.params, isEmpty);
      expect(userRouter.match('/users/42')?.params, {'id': '42'});
      expect(blogRouter.match('/blog/123')?.params, {'id': '123'});
      expect(blogRouter.match('/blog/123-post')?.params, {
        'id': '123',
        'title': 'post',
      });
      expect(nestedRouter.match('/docs'), isNull);
      expect(nestedRouter.match('/docs/api')?.params, {'section': 'api'});
      expect(nestedRouter.match('/docs/api/intro')?.params, {
        'section': 'api',
        'page': 'intro',
      });
      expect(mandatoryRouter.match('/foo'), isNull);
      expect(mandatoryRouter.match('/foobar')?.data, 'foobar');
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

      router.add('/files/**:wildcard', 'first');
      router.add(
        '/files/**:wildcard',
        'second',
        duplicatePolicy: DuplicatePolicy.replace,
      );

      expect(router.match('/files/a/b')?.data, 'second');
      expect(router.match('/files/a/b')?.params, {'wildcard': 'a/b'});
    });

    test('supports keepFirst for wildcard routes', () {
      final router = Router<String>();

      router.add('/files/**:wildcard', 'first');
      router.add(
        '/files/**:wildcard',
        'second',
        duplicatePolicy: DuplicatePolicy.keepFirst,
      );

      expect(router.match('/files/a/b')?.data, 'first');
      expect(router.match('/files/a/b')?.params, {'wildcard': 'a/b'});
    });

    test('supports append for wildcard routes', () {
      final router = Router<String>();

      router.add('/files/**:wildcard', 'first');
      router.add(
        '/files/**:wildcard',
        'second',
        duplicatePolicy: DuplicatePolicy.append,
      );

      expect(router.match('/files/a/b')?.data, 'first');
      expect(router.matchAll('/files/a/b').map((match) => match.data), [
        'first',
        'second',
      ]);
    });

    test('supports replace for global fallback routes', () {
      final router = Router<String>();

      router.add('/**:wildcard', 'first');
      router.add(
        '/**:wildcard',
        'second',
        duplicatePolicy: DuplicatePolicy.replace,
      );

      expect(router.match('/unknown')?.data, 'second');
      expect(router.match('/unknown')?.params, {'wildcard': 'unknown'});
    });

    test('supports keepFirst for global fallback routes', () {
      final router = Router<String>();

      router.add('/**:wildcard', 'first');
      router.add(
        '/**:wildcard',
        'second',
        duplicatePolicy: DuplicatePolicy.keepFirst,
      );

      expect(router.match('/unknown')?.data, 'first');
      expect(router.match('/unknown')?.params, {'wildcard': 'unknown'});
    });

    test('supports append for global fallback routes', () {
      final router = Router<String>();

      router.add('/**:wildcard', 'first');
      router.add(
        '/**:wildcard',
        'second',
        duplicatePolicy: DuplicatePolicy.append,
      );

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
      router.add('/**:wildcard', 'global');
      router.add('/api/**:wildcard', 'first');
      router.add('/api/**:wildcard', 'second');

      final matches = router.matchAll('/api/demo');

      expect(matches.map((match) => match.data), ['global', 'second']);
    });

    test('matchAll expands appended entries in registration order', () {
      final router = Router<String>(duplicatePolicy: DuplicatePolicy.append);
      router.add('/**:wildcard', 'global-1');
      router.add('/**:wildcard', 'global-2');
      router.add('/api/**:wildcard', 'api-1');
      router.add('/api/**:wildcard', 'api-2');

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
        router.add('/**:wildcard', 'global');
        router.add('/api/**:wildcard', 'first');
        router.add('/api/**:wildcard', 'second');

        final matches = router.matchAll('/api/demo');

        expect(matches.map((match) => match.data), ['global', 'first']);
      },
    );

    test('matchAll keeps the original retained entry after reject failure', () {
      final router = Router<String>();
      router.add('/**:wildcard', 'global');
      router.add('/api/**:wildcard', 'first');

      expect(
        () => router.add('/api/**:wildcard', 'second'),
        throwsFormatException,
      );

      final matches = router.matchAll('/api/demo');

      expect(matches.map((match) => match.data), ['global', 'first']);
    });

    test(
      'matchAll reflects retained entries independently per method bucket',
      () {
        final router = Router<String>();
        router.add('/**:wildcard', 'global-any');
        router.add('/api/**:wildcard', 'api-any-first');
        router.add(
          '/api/**:wildcard',
          'api-any-second',
          duplicatePolicy: DuplicatePolicy.replace,
        );
        router.add('/api/**:wildcard', 'api-get-first', method: 'GET');
        router.add(
          '/api/**:wildcard',
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
      router.add('/api/**:wildcard', 'first');
      router.add('/api/**:wildcard', 'second');
      router.add(
        '/api/**:wildcard',
        'third',
        duplicatePolicy: DuplicatePolicy.replace,
      );

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
        '/users/**:wildcard': 'users-wildcard',
        '/**:wildcard': 'global',
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
        '/files/**:wildcard': 'files',
        '/**:wildcard': 'global',
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
      final local = Router<String>(routes: {'/files/**:wildcard': 'files'});

      final deep = local.match('/files/a/b/c');
      expect(deep?.data, 'files');
      expect(deep?.params, {'wildcard': 'a/b/c'});

      final empty = local.match('/files');
      expect(empty?.data, 'files');
      expect(empty?.params, {'wildcard': ''});
    });

    test('global wildcard captures remainder', () {
      final local = Router<String>(routes: {'/**:wildcard': 'global'});

      final match = local.match('/foo/bar');
      expect(match?.data, 'global');
      expect(match?.params, {'wildcard': 'foo/bar'});
    });

    test('single-segment wildcard captures one segment only', () {
      final router = Router<String>(
        routes: {'/users/*': 'single', '/users/**:wildcard': 'double'},
      );

      expect(router.match('/users/demo')?.data, 'single');
      expect(router.match('/users/demo')?.params, {'0': 'demo'});
      expect(router.match('/users/demo/profile')?.data, 'double');
      expect(router.match('/users/demo/profile')?.params, {
        'wildcard': 'demo/profile',
      });
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
          '/**:wildcard': 'global',
          '/api/**:wildcard': 'api-wildcard',
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
          '/**:wildcard': 'global',
          '/api/**:wildcard': 'api-wildcard',
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

    test('snapshots params for each lazy match before backtracking', () {
      final router = Router<String>(
        routes: {
          '/:section/**:wildcard': 'section-wildcard',
          '/users/:id': 'user-detail',
        },
      );

      final matches = matchAll(router, '/users/42');

      expect(matches.map((match) => match.data), [
        'section-wildcard',
        'user-detail',
      ]);
      expect(matches[0].params, {'section': 'users', 'wildcard': '42'});
      expect(matches[1].params, {'id': '42'});
    });

    test('includes ANY and exact method matches when method is provided', () {
      final router = Router<String>();
      router.add('/**:wildcard', 'global-any');
      router.add('/**:wildcard', 'global-get', method: 'GET');
      router.add('/api/**:wildcard', 'api-any');
      router.add('/api/**:wildcard', 'api-get', method: 'GET');

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
      router.add(
        '/**:wildcard',
        'global-any-1',
        duplicatePolicy: DuplicatePolicy.append,
      );
      router.add(
        '/**:wildcard',
        'global-any-2',
        duplicatePolicy: DuplicatePolicy.append,
      );
      router.add(
        '/api/**:wildcard',
        'api-any-1',
        duplicatePolicy: DuplicatePolicy.append,
      );
      router.add(
        '/api/**:wildcard',
        'api-any-2',
        duplicatePolicy: DuplicatePolicy.append,
      );
      router.add(
        '/api/**:wildcard',
        'api-get-1',
        method: 'GET',
        duplicatePolicy: DuplicatePolicy.append,
      );
      router.add(
        '/api/**:wildcard',
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
      router.add('/**:wildcard', 'global-any');
      router.add('/**:wildcard', 'global-get', method: 'GET');
      router.add('/api/**:wildcard', 'api-any');
      router.add('/api/**:wildcard', 'api-get', method: 'GET');

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
      router.add('/**:wildcard', 'global');
      router.add('/api/**:wildcard', 'api-wildcard');
      router.add('/api/:id', 'api-param');
      router.add('/api/demo', 'api-demo');

      expect(router.match('/api/demo')?.data, 'api-demo');
      expect(router.match('/api/demo')?.params, isNull);
    });

    test('orders embedded parameter routes between param and exact routes', () {
      final router = Router<String>(
        routes: {
          '/files/:id': 'param',
          '/files/:name.:ext': 'pattern',
          '/files/readme.md': 'exact',
        },
      );

      expect(router.match('/files/readme.md')?.data, 'exact');
      expect(router.match('/files/guide.md')?.data, 'pattern');
      expect(router.matchAll('/files/guide.md').map((match) => match.data), [
        'param',
        'pattern',
      ]);
    });

    test('matches embedded wildcard routes before plain params', () {
      final router = Router<String>(
        routes: {'/files/:id': 'param', '/files/file-*.png': 'wild'},
      );

      expect(router.match('/files/file-z.png')?.data, 'wild');
      expect(router.match('/files/file-z.png')?.params, {'0': 'z'});
    });

    test(
      'orders grouped routes before exact routes but after plain params',
      () {
        final router = Router<String>(
          routes: {
            '/book': 'exact-book',
            '/book{s}?': 'group-book',
            '/users/:id': 'param-user',
            '/users{/:id}?': 'group-user',
          },
        );

        expect(router.match('/book')?.data, 'exact-book');
        expect(router.matchAll('/book').map((match) => match.data), [
          'group-book',
          'exact-book',
        ]);
        expect(router.match('/users/42')?.data, 'param-user');
        expect(router.matchAll('/users/42').map((match) => match.data), [
          'param-user',
          'group-user',
        ]);
      },
    );

    test('orders mandatory group routes before exact routes', () {
      final router = Router<String>(
        routes: {'/foobar': 'exact', '/foo{bar}': 'group'},
      );

      expect(router.match('/foobar')?.data, 'exact');
      expect(router.matchAll('/foobar').map((match) => match.data), [
        'group',
        'exact',
      ]);
    });

    test(
      'matches regex parameter routes before plain params in single match',
      () {
        final router = Router<String>(
          routes: {'/users/:id': 'param', '/users/:id(\\d+)': 'regex'},
        );

        expect(router.match('/users/42')?.data, 'regex');
        expect(router.matchAll('/users/42').map((match) => match.data), [
          'param',
          'regex',
        ]);
      },
    );

    test(
      'orders optional params before exact routes when param is missing',
      () {
        final router = Router<String>(
          routes: {'/users': 'exact', '/users/:id?': 'optional'},
        );

        expect(router.match('/users')?.data, 'exact');
        expect(router.matchAll('/users').map((match) => match.data), [
          'optional',
          'exact',
        ]);
      },
    );

    test(
      'matches plain params before optional params when param is present',
      () {
        final router = Router<String>(
          routes: {'/users/:id': 'param', '/users/:id?': 'optional'},
        );

        expect(router.match('/users/42')?.data, 'param');
        expect(router.matchAll('/users/42').map((match) => match.data), [
          'param',
          'optional',
        ]);
        expect(router.match('/users')?.data, 'optional');
      },
    );

    test(
      'matches repeated params before single params in multi-segment lookups',
      () {
        final router = Router<String>(
          routes: {'/files/:id': 'param', '/files/:path+': 'plus'},
        );

        expect(router.match('/files/a')?.data, 'param');
        expect(router.matchAll('/files/a').map((match) => match.data), [
          'plus',
          'param',
        ]);
        expect(router.match('/files/a/b')?.data, 'plus');
      },
    );

    test('collects star params before exact routes when param is empty', () {
      final router = Router<String>(
        routes: {'/files': 'exact', '/files/:path*': 'star'},
      );

      expect(router.match('/files')?.data, 'exact');
      expect(router.matchAll('/files').map((match) => match.data), [
        'star',
        'exact',
      ]);
    });

    test(
      'orders double wildcard before param before single wildcard before exact',
      () {
        final router = Router<String>(
          routes: {
            '/users/all': 'exact',
            '/users/:id': 'param',
            '/users/*': 'star',
            '/users/**:rest': 'double',
          },
        );

        expect(router.match('/users/all')?.data, 'exact');
        expect(router.matchAll('/users/all').map((match) => match.data), [
          'double',
          'param',
          'star',
          'exact',
        ]);
        expect(router.match('/users/demo')?.data, 'param');
        expect(router.matchAll('/users/demo').map((match) => match.data), [
          'double',
          'param',
          'star',
        ]);
      },
    );

    test(
      'orders single params before structured patterns before shell wildcards before exact',
      () {
        final router = Router<String>(
          routes: {
            '/files/:id': 'param',
            '/files/:name.:ext': 'pattern',
            '/files/file-*.png': 'wild',
            '/files/file-a.png': 'exact',
          },
        );

        expect(
          router.matchAll('/files/file-a.png').map((match) => match.data),
          ['param', 'pattern', 'wild', 'exact'],
        );
      },
    );
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

    test('supports case-insensitive matching when configured', () {
      final local = Router<String>(
        caseSensitive: false,
        routes: {
          '/Users': 'users',
          '/files/:name.:ext': 'asset',
          '/book{s}?': 'books',
        },
      );

      expect(local.match('/users')?.data, 'users');
      expect(local.match('/FILES/ReadMe.MD')?.data, 'asset');
      expect(local.match('/FILES/ReadMe.MD')?.params, {
        'name': 'ReadMe',
        'ext': 'MD',
      });
      expect(local.match('/BOOKS')?.data, 'books');
    });

    test('does not URL decode', () {
      expect(router.match('/a%2Fb')?.data, 'encoded');
      expect(router.match('/a/b'), isNull);
    });

    test('supports URL decoding when configured', () {
      final local = Router<String>(
        decodePath: true,
        routes: {
          '/a/b': 'decoded',
          '/a%2Fb': 'encoded-literal',
          '/files/:name.:ext': 'asset',
        },
      );

      expect(local.match('/a%2Fb')?.data, 'decoded');
      expect(local.match('/files/Read%20Me.MD')?.params, {
        'name': 'Read Me',
        'ext': 'MD',
      });
      expect(local.match('/a%20b'), isNull);
    });

    test('supports combining decodePath with case-insensitive matching', () {
      final local = Router<String>(
        decodePath: true,
        caseSensitive: false,
        routes: {'/files/:name.:ext': 'asset'},
      );

      expect(local.match('/FILES/Read%20Me.MD')?.params, {
        'name': 'Read Me',
        'ext': 'MD',
      });
    });

    test('supports path normalization when configured', () {
      final local = Router<String>(
        normalizePath: true,
        routes: {'/a/b': 'ab', '/users/:id': 'user'},
      );

      expect(local.match('/a/b/')?.data, 'ab');
      expect(local.match('/a//b')?.data, 'ab');
      expect(local.match('/a/./b')?.data, 'ab');
      expect(local.match('/a/c/../b')?.data, 'ab');
      expect(local.match('/users//42')?.params, {'id': '42'});
    });

    test('supports combining decodePath with path normalization', () {
      final local = Router<String>(
        decodePath: true,
        normalizePath: true,
        routes: {'/files/:name': 'file'},
      );

      expect(local.match('/files/%2E/Read%20Me')?.params, {'name': 'Read Me'});
    });

    test('returns null for invalid lookup path', () {
      expect(router.match(''), isNull);
      expect(router.match('a'), isNull);
      expect(router.match('//a'), isNull);
      expect(router.match('/a//b'), isNull);
    });

    test(
      'returns null for invalid URL encoding when decodePath is enabled',
      () {
        final local = Router<String>(
          decodePath: true,
          routes: {'/files/:name': 'file', '/**:wildcard': 'fallback'},
        );

        expect(local.match('/files/%ZZ'), isNull);
        expect(local.matchAll('/files/%ZZ'), isEmpty);
      },
    );

    test(
      'returns null for root-escaping paths when normalization is enabled',
      () {
        final local = Router<String>(
          normalizePath: true,
          routes: {'/files/:name': 'file', '/**:wildcard': 'fallback'},
        );

        expect(local.match('/files/../../readme'), isNull);
        expect(local.matchAll('/files/../../readme'), isEmpty);
      },
    );

    test('does not let invalid paths hit wildcard fallback routes', () {
      final wildcardRouter = Router<String>(
        routes: {'/**:wildcard': 'fallback'},
      );

      expect(wildcardRouter.match('/users//42'), isNull);
      expect(wildcardRouter.matchAll('/users//42'), isEmpty);
    });
  });

  group('route definition validation', () {
    test('requires leading slash', () {
      expect(() => Router<String>(routes: {'a': 'bad'}), throwsFormatException);
    });

    test('rejects double wildcard in the middle', () {
      expect(
        () => Router<String>(routes: {'/a/**:rest/b': 'bad'}),
        throwsFormatException,
      );
    });

    test('rejects invalid parameter name', () {
      expect(
        () => Router<String>(routes: {'/a/:123': 'bad'}),
        throwsFormatException,
      );
    });

    test('rejects unsupported embedded segment syntax', () {
      expect(
        () => Router<String>(routes: {'/a/:id:ext': 'bad'}),
        throwsFormatException,
      );
    });

    test('rejects duplicate param shape', () {
      expect(
        () => Router<String>(routes: {'/users/:id': 'a', '/users/:name': 'b'}),
        throwsFormatException,
      );
    });

    test('rejects case-insensitive duplicate static paths', () {
      expect(
        () => Router<String>(
          caseSensitive: false,
          routes: {'/Users': 'a', '/users': 'b'},
        ),
        throwsFormatException,
      );
    });

    test('rejects case-insensitive duplicate compiled shapes', () {
      expect(
        () => Router<String>(
          caseSensitive: false,
          routes: {'/Files/:name.:ext': 'a', '/files/:name.:ext': 'b'},
        ),
        throwsFormatException,
      );
    });

    test('rejects duplicate embedded param shape', () {
      expect(
        () => Router<String>(
          routes: {'/files/:name.:ext': 'a', '/files/:base.:suffix': 'b'},
        ),
        throwsFormatException,
      );
    });

    test('rejects duplicate embedded wildcard shape', () {
      expect(
        () => Router<String>(
          routes: {'/files/*.:ext': 'a', '/files/*.:type': 'b'},
        ),
        throwsFormatException,
      );
    });

    test('rejects unclosed optional groups', () {
      expect(
        () => Router<String>(routes: {'/users{/:id?': 'bad'}),
        throwsFormatException,
      );
    });

    test('rejects duplicate optional param shape', () {
      expect(
        () =>
            Router<String>(routes: {'/users/:id?': 'a', '/users/:name?': 'b'}),
        throwsFormatException,
      );
    });

    test('rejects duplicate repeated param shape', () {
      expect(
        () => Router<String>(
          routes: {'/files/:path+': 'a', '/files/:rest+': 'b'},
        ),
        throwsFormatException,
      );
    });

    test('rejects duplicate wildcard shape after normalization', () {
      expect(
        () => Router<String>(
          routes: {'/docs/**:wildcard': 'a', '/docs/**:wildcard/': 'b'},
        ),
        throwsFormatException,
      );
    });

    test('rejects duplicate global fallback after normalization', () {
      expect(
        () =>
            Router<String>(routes: {'/**:wildcard': 'a', '/**:wildcard/': 'b'}),
        throwsFormatException,
      );
    });
  });
}
