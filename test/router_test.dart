import 'package:roux/roux.dart';
import 'package:test/test.dart';

void main() {
  test(
    'removing real siblings leaves the shared branch and its other rows live',
    () {
      final router = Router<String>();
      for (final key in ['One', 'Two', 'Three']) {
        router.add('/API/$key/users/:id/orders/:order', key, method: 'GET');
      }
      for (final name in ['audit', 'history', 'export']) {
        router.add('/api/two/$name/:item', name, method: 'POST');
      }
      for (final name in ['history', 'audit', 'export']) {
        expect(router.find('/api/two/$name/X', method: 'post')?.params, {
          'item': 'X',
        });
        expect(router.remove('POST', '/api/two/$name/:other'), isTrue);
        expect(router.remove('POST', '/api/two/$name/:other'), isFalse);
        expect(
          router.find('/api/two/users/A/orders/B', method: 'get')?.data,
          'Two',
        );
        expect(
          router.find('/api/one/users/C/orders/D', method: 'get')?.data,
          'One',
        );
      }
    },
  );

  test('canonical named segments keep the same grammar as expanded paths', () {
    final router = Router<String>();
    router.add('/items/:item-id/part/:v_2', 'first');
    router.add('items//:item-id/./part/:v_2/', 'second');
    final matches = router.findAll('/ITEMS/42/part/A');
    expect(matches.map((m) => m.data), ['first', 'second']);
    expect(matches.first.params, {'item-id': '42', 'v_2': 'A'});
    expect(router.remove('', 'items/tmp/../:x/part/:y/'), isTrue);
    expect(router.find('/items/42/part/A'), isNull);
    expect(() => router.add('/items/:9bad', 'invalid'), throwsFormatException);
    router.add(r'/literal/\:id/:name?', 'escaped');
    expect(router.find('/literal/:id')?.params, isEmpty);
    expect(router.find('/literal/:id/X')?.params, {'name': 'X'});
  });

  test('an escaped first segment remains visible to both lookup paths', () {
    final router = Router<int>()
      ..add(r'/\*/:id', 1)
      ..add(r'/\:key/:id', 2);
    expect(router.find('/*/A')?.params, {'id': 'A'});
    expect(router.find('/:key/B')?.data, 2);
    expect(router.findAll('/*/A').single.data, 1);
    expect(router.remove('', r'/\*/:other'), isTrue);
    expect(router.find('/*/A'), isNull);
    expect(router.remove('', r'/\:key/:other'), isTrue);
    expect(router.find('/:key/B'), isNull);
  });

  test('regex prefixes stay searchable as the common prefix shortens', () {
    final router = Router<int>();
    const prefixes = ['abcd-a', 'abcd-b', 'azzz-c', 'qb', 'abc'];
    for (var i = 0; i < prefixes.length; i++) {
      router.add(
        '/r/:id(${prefixes[i]}'
        r'\d+)',
        i,
      );
      for (var j = 0; j <= i; j++) {
        final id = '${prefixes[j].toUpperCase()}42';
        final match = router.find('/r/$id');
        expect(match?.data, j);
        expect(match?.params['id'], id);
      }
    }
    expect(router.find('/r/wrong42'), isNull);
  });

  test('literal selectors round-trip short, long and Unicode text', () {
    for (final sensitive in [true, false]) {
      final router = Router<String>(caseSensitive: sensitive);
      const keys = [
        'a',
        'A',
        'a\x00',
        '\x00a',
        'K',
        'k',
        'İ',
        'i\u0307',
        'ABcd',
        'long-service-name',
      ];
      final byKey = <String, List<String>>{};
      for (final key in keys) {
        router.add('/$key/item/:id', key);
        (byKey[sensitive ? key : key.toLowerCase()] ??= []).add(key);
      }
      router.add('/:parent/item/:id', 'fallback');
      for (final key in keys) {
        final expected = byKey[sensitive ? key : key.toLowerCase()]!;
        final path = '/$key/item/é';
        expect(router.find(path)?.data, expected.first);
        expect(router.find(path)?.params, {'id': 'é'});
        expect(router.findAll(path).map((m) => m.data), [
          'fallback',
          ...expected,
        ]);
      }
      expect(router.remove('', '/ABcd/item/:other'), isTrue);
      expect(router.find('/ABcd/item/x')?.data, 'fallback');
    }
  });

  test('literal rows keep nullable payloads, method order and duplicates', () {
    final router = Router<Object?>();
    final payload = ['data'];
    router.add('/rows/a', null);
    for (var i = 0; i < 12; i++) {
      router.add('/rows/a', i, method: ' x-$i ');
    }
    router.add('/rows/a', payload, method: 'X-9');
    expect(router.find('/rows/a', method: 'OTHER')!.data, isNull);
    expect(router.find('/ROWS/./a', method: ' x-9 ')!.data, 9);
    expect(
      router
          .findAll('/rows/a', method: 'x-9', includeAny: true)
          .map((m) => m.data),
      [null, 9, same(payload)],
    );
    for (var i = 11; i >= 0; i--) {
      expect(router.remove('x-$i', 'rows//a/'), isTrue);
    }
    expect(router.remove('', '/rows/a'), isTrue);
    router.add('/rows/a', payload, method: 'CUSTOM');
    expect(router.find('/rows/a', method: 'custom')!.data, same(payload));
  });

  test(
    'shared suffixes preserve precedence through removal and new shapes',
    () {
      final router = Router<int>();
      for (final id in ['red', 'green', 'blue']) {
        router.add('/org/$id/u/:User/FILES/:File', 1, method: 'READ');
      }
      router.add('/org/blue/u/:User/FILES/:File', 2, method: 'READ');
      const query = '/org/blue/u/Alice/files/README';
      expect(router.remove('READ', '/org/blue/unrelated/:x'), isFalse);
      final all = router.findAll(query, method: 'read', includeAny: true);
      expect(all.map((m) => m.data), [1, 2]);
      expect(all[0].params, {'User': 'Alice', 'File': 'README'});
      all[0].params.clear();
      expect(all[1].params.keys, ['User', 'File']);
      expect(router.find('/org/red/u/x/files/y', method: 'READ')!.data, 1);
      expect(router.remove('read', '/org/green/u/:other/files/:name'), isTrue);
      router.add('/org/blue/u/Alice/files/README', 3);
      expect(router.find(query, method: 'read')!.data, 3);
      router.add('/org/blue/u/:who/files/:which', 4, method: 'READ');
      router.add('/:head/**:rest', 0);
      expect(
        router
            .findAll(query, method: 'read', includeAny: true)
            .map((m) => m.data),
        [0, 1, 2, 4, 3],
      );
      expect(router.remove('READ', '/org/blue/u/:x/files/:y'), isTrue);
      expect(router.find('/org/green/u/A/files/B', method: 'READ')!.data, 0);
    },
  );

  group('basic add and find', () {
    test('returns null when no routes are registered', () {
      expect(Router<String>().find('/users/42'), isNull);
    });

    test('finds static and param routes', () {
      final router = Router<String>();
      router.add('/', 'root');
      router.add('/users/all', 'all');
      router.add('/users/:id', 'user');

      expect(router.find('/')?.data, 'root');
      expect(router.find('/users/all')?.data, 'all');
      expect(router.find('/users/42')?.data, 'user');
      expect(router.find('/users/42')?.params, {'id': '42'});
    });

    test('static routes win over params', () {
      final router = Router<String>();
      router.add('/users/:id', 'param');
      router.add('/users/all', 'static');

      expect(router.find('/users/all')?.data, 'static');
      expect(router.find('/users/42')?.data, 'param');
    });

    test('lookup normalizes repeated and trailing slashes', () {
      final router = Router<String>();
      router.add('/users/:id', 'user');

      expect(router.find('//users///42/')?.params, {'id': '42'});
    });

    test('route registration canonicalizes missing and trailing slashes', () {
      final router = Router<String>();
      router.add('users/:id', 'user');
      router.add('/with-trailing/', 'trailing');

      expect(router.find('/users/42')?.params, {'id': '42'});
      expect(router.find('/with-trailing')?.data, 'trailing');
      expect(router.find('/with-trailing/')?.data, 'trailing');
    });

    test('matches literal percent-encoded static paths', () {
      final router = Router<String>(caseSensitive: true);
      router.add('/caf%C3%A9', 'cafe');

      expect(router.find('/caf%C3%A9')?.data, 'cafe');
      expect(router.find('/café'), isNull);
      expect(router.find('/caf%c3%a9'), isNull);
    });

    test('lookup normalizes dot segments without Uri decoding', () {
      final router = Router<String>();
      router.add('/users/profile', 'profile');
      router.add('/profile', 'root-profile');

      expect(router.find('/users/./profile')?.data, 'profile');
      expect(router.find('/users/team/../profile')?.data, 'profile');
      expect(router.find('/users/../profile')?.data, 'root-profile');
    });

    test('route registration also normalizes dot segments', () {
      final router = Router<String>();
      router.add('/users/./profile', 'profile');
      router.add('/users/../root', 'root');

      expect(router.find('/users/profile')?.data, 'profile');
      expect(router.find('/root')?.data, 'root');
    });

    test('both lookups stop at root and preserve encoded captures', () {
      final router = Router<String>();
      router.add('/', 'root');
      router.add('/users/:id', 'user');

      for (final path in ['', '/./', '../../..//']) {
        expect(router.find(path)?.data, 'root');
        expect(router.findAll(path).single.data, 'root');
      }
      const path = '../users//tmp/../%2F/';
      expect(router.find(path)?.params, {'id': '%2F'});
      expect(router.findAll(path).single.params, {'id': '%2F'});
    });
  });

  group('params and patterns', () {
    test('preserves capture positions across literal runs', () {
      final router = Router<int>()..add('/a/:x/b/c/d/:y/**:tail', 1);
      expect(router.find('/a/one/b/c/d/two/three/four')?.params, {
        'x': 'one',
        'y': 'two',
        'tail': 'three/four',
      });
    });

    test(
      'keeps inner capture numbers across adjacent constrained parameters',
      () {
        final router = Router<int>()..add(r'/x/:a(([()])[)])_:b((c)(d)?)', 1);
        final params = router.find('/x/()_cd')!.params;
        expect(params.entries.map((e) => (e.key, e.value)), [
          ('0', '('),
          ('a', '()'),
          ('1', 'c'),
          ('2', 'd'),
          ('b', 'cd'),
        ]);
        expect(router.find('/x/()_c')!.params.containsKey('2'), isFalse);
      },
    );

    test(
      'captures nested runs in RegExp order, including fallback patterns',
      () {
        for (final sensitive in [true, false]) {
          final router = Router<int>(caseSensitive: sensitive);
          final patterns = [
            r'(([a-f]{2,4})(\d{1,3}))_([W-Z]+)',
            r'(\w+)-(\d+)(\s*)',
            r'(a+)(a*)',
            r'([^0-9]+)(\d*)',
            r'(a?)(b{0,2})(c+)',
            r'([()]+)\+([a-z]{2,})',
          ];
          for (final (i, body) in patterns.indexed) {
            router.add('/$i/:value($body)', i);
            final re = RegExp('^($body)\$', caseSensitive: sensitive);
            for (final value in [
              'ab12_Z',
              'ABCD007_w',
              'team-42 ',
              'aaaa',
              'λ9',
              '🐈',
              'bcc',
              'c',
              '()+abc',
              '!',
            ]) {
              final expected = re.firstMatch(value);
              final params = <String, String>{};
              if (expected != null) {
                for (var j = 2; j <= expected.groupCount; j++) {
                  if (expected[j] case final part?) params['${j - 2}'] = part;
                }
                params['value'] = value;
              }
              final path = '/$i/$value';
              expect(
                router.find(path)?.params,
                expected == null ? null : params,
                reason: '$body $value',
              );
              expect(router.findAll(path).single.params, params);
            }
          }
        }
      },
    );

    test(
      'decimal constraints preserve the original string and ASCII bounds',
      () {
        final router = Router<String>();
        router.add(r'/ids/:id(v\d+)', 'variable');
        router.add('/fixed/:id([0-9]{2})', 'fixed');
        final digits = '0' * 80;
        expect(router.find('/ids/V$digits')?.params, {'id': 'V$digits'});
        for (final id in ['v', 'v+1', 'v０', 'v2\n']) {
          expect(router.find('/ids/$id'), isNull);
        }
        expect(router.find('/fixed/01')?.params, {'id': '01'});
        expect(router.find('/fixed/012'), isNull);
      },
    );

    test('delimited captures leave both sides nonempty and split greedily', () {
      final router = Router<String>();
      router.add('/files/:name.:ext', 'file');
      expect(router.find('/files/a.b.c.')?.params, {
        'name': 'a.b',
        'ext': 'c.',
      });
      expect(router.find('/files/a..')?.params, {'name': 'a', 'ext': '.'});
      expect(router.find('/files/.x'), isNull);
      expect(router.findAll('/files/x.').single.params, isEmpty);
    });

    test(
      'keeps capture positions and named backreferences inside constraints',
      () {
        final router = Router<String>();
        router.add(r'/a/:id((x)(y)?)', 'positional');
        router.add(r'/b/:id((?<letter>[a-z])\k<letter>(\d+))', 'named');
        expect(
          router.find('/a/x')?.params.entries.map((e) => (e.key, e.value)),
          [('0', 'x'), ('id', 'x')],
        );
        expect(router.find('/b/aa42')?.params, {'0': '42', 'id': 'aa42'});
        expect(router.find('/b/ab42'), isNull);
      },
    );

    test('captures multiple params', () {
      final router = Router<String>();
      router.add('/users/:id/items/:itemId', 'item');

      expect(router.find('/users/42/items/7')?.params, {
        'id': '42',
        'itemId': '7',
      });
    });

    test('each lookup gets its own mutable params map', () {
      final router = Router<String>();
      router.add('/users/:id', 'user');

      final params = router.find('/users/42')!.params;
      params['extra'] = 'ok';

      expect(params, {'id': '42', 'extra': 'ok'});
      expect(router.find('/users/42')!.params, {'id': '42'});
    });

    test('supports embedded params', () {
      final router = Router<String>();
      router.add('/files/:name.:ext', 'asset');

      expect(router.find('/files/readme.md')?.params, {
        'name': 'readme',
        'ext': 'md',
      });
    });

    test('supports regex params', () {
      final router = Router<String>();
      router.add(r'/users/:id(\d+)', 'user');

      expect(router.find('/users/42')?.params, {'id': '42'});
      expect(router.find('/users/nope'), isNull);
    });

    test('supports unnamed regex groups', () {
      final router = Router<String>();
      router.add(r'/path/(\d+)', 'group');

      expect(router.find('/path/123')?.params, {'0': '123'});
      expect(router.find('/path/abc'), isNull);
    });

    test('supports multiple unnamed regex groups across segments', () {
      final router = Router<String>();
      router.add(r'/path/(\d+)/(\w+)', 'groups');

      expect(router.find('/path/123/abc')?.params, {'0': '123', '1': 'abc'});
      expect(router.find('/path/123/!'), isNull);
      expect(router.findAll('/path/123/!').first.params, {'0': '123'});
      expect(router.findAll('/path/!/abc').first.params, {'1': 'abc'});
    });

    test('supports optional params', () {
      final router = Router<String>();
      router.add('/users/:id?', 'user');

      expect(router.find('/users/42')?.params, {'id': '42'});
      expect(router.find('/users')?.data, 'user');
      expect(router.find('/users')?.params, isEmpty);
    });

    test('supports repeated params with plus and star', () {
      final router = Router<String>();
      router.add('/files/:path+', 'plus');
      router.add('/assets/:rest*', 'star');

      expect(router.find('/files'), isNull);
      expect(router.find('/files/a/b')?.params, {'path': 'a/b'});
      expect(router.find('/assets')?.params, isEmpty);
      expect(router.find('/assets/a/b')?.params, {'rest': 'a/b'});
    });

    test('supports single-segment wildcards', () {
      final router = Router<String>();
      router.add('/users/*', 'star');
      router.add('/teams/*/members', 'members');

      expect(router.find('/users/a')?.params, {'0': 'a'});
      expect(router.find('/users/a/b'), isNull);
      expect(router.find('/teams/core/members')?.params, {'0': 'core'});
    });

    test('supports embedded wildcards in a segment', () {
      final router = Router<String>();
      router.add('/files/file-*-*.png', 'asset');

      expect(router.find('/files/file-a-b.png')?.params, {'0': 'a', '1': 'b'});
      expect(router.find('/files/file--.png')?.params, {'0': '', '1': ''});
    });

    test('supports remainder wildcards', () {
      final router = Router<String>();
      router.add('/users/**:wildcard', 'users');
      router.add('/files/**', 'files');

      expect(router.find('/users/a/b')?.params, {'wildcard': 'a/b'});
      expect(router.find('/files/a/b/c')?.params, {'_': 'a/b/c'});
    });
  });

  group('group syntax', () {
    test('preserves repetition when expanding a group after a parameter', () {
      final router = Router<int>()..add('/:x{foo}+', 1);
      expect(router.find('/'), isNull);
      expect(router.find('/a/b')?.params, {'x': 'a/b'});
      expect(router.remove('', '/:x{foo}+'), isTrue);
      expect(router.find('/a/b'), isNull);
    });

    test('supports optional and mandatory groups', () {
      final router = Router<String>();
      router.add('/book{s}?', 'book');
      router.add('/foo{bar}', 'foobar');

      expect(router.find('/book')?.data, 'book');
      expect(router.find('/books')?.data, 'book');
      expect(router.find('/foo'), isNull);
      expect(router.find('/foobar')?.data, 'foobar');
    });

    test('supports grouped params', () {
      final router = Router<String>();
      router.add('/users{/:id}?', 'user');
      router.add('/blog/:id(\\d+){-:title}?', 'blog');

      expect(router.find('/users')?.params, isEmpty);
      expect(router.find('/users/42')?.params, {'id': '42'});
      expect(router.find('/blog/123')?.params, {'id': '123'});
      expect(router.find('/blog/123-post')?.params, {
        'id': '123',
        'title': 'post',
      });
    });
  });

  group('method matching', () {
    test(
      'preserves registration order in both method buckets after removal',
      () {
        final router = Router<int>()
          ..add('/x/:a', 1, method: 'GET')
          ..add('/x/:b', 2)
          ..add('/x/:c', 3, method: 'GET')
          ..add('/x/:d', 4);
        List<int> all() => router
            .findAll('/x/1', method: ' get ', includeAny: true)
            .map((m) => m.data)
            .toList();
        expect(all(), [2, 4, 1, 3]);
        expect(router.remove('GET', '/x/:id'), isTrue);
        expect(all(), [2, 4]);
        router.add('/x/:e', 5, method: 'GET');
        expect(all(), [2, 4, 5]);
      },
    );

    test('method-specific routes require the matching method', () {
      final router = Router<String>();
      router.add('/users/:id', 'get-user', method: 'GET');

      expect(router.find('/users/1'), isNull);
      expect(router.find('/users/1', method: 'GET')?.data, 'get-user');
    });

    test('any-method routes match specific methods', () {
      final router = Router<String>();
      router.add('/users/:id', 'any-user');

      expect(router.find('/users/1', method: 'GET')?.data, 'any-user');
      expect(router.find('/users/1', method: 'POST')?.data, 'any-user');
    });

    test('specific methods win over any-method routes', () {
      final router = Router<String>();
      router.add('/users/:id', 'any');
      router.add('/users/:id', 'get', method: 'GET');

      expect(router.find('/users/1', method: 'GET')?.data, 'get');
      expect(router.find('/users/1', method: 'POST')?.data, 'any');
    });

    test('method names are trimmed and uppercased', () {
      final router = Router<String>();
      router.add('/ping', 'pong', method: ' get ');

      expect(router.find('/ping', method: 'GET')?.data, 'pong');
    });

    test('findAll prefers exact method and falls back to any-method', () {
      final router = Router<String>();
      router.add('/api/:id', 'any');
      router.add('/api/:id', 'get', method: 'GET');

      expect(router.findAll('/api/1', method: 'GET').map((m) => m.data), [
        'get',
      ]);
      expect(router.findAll('/api/1', method: 'POST').map((m) => m.data), [
        'any',
      ]);
    });

    test('findAll can include any-method matches before exact matches', () {
      final router = Router<String>();
      router.add('/api/:id', 'any');
      router.add('/api/:id', 'get', method: 'GET');

      expect(
        router
            .findAll('/api/1', method: 'GET', includeAny: true)
            .map((m) => m.data),
        ['any', 'get'],
      );
      expect(
        router
            .findAll('/api/1', method: 'POST', includeAny: true)
            .map((m) => m.data),
        ['any'],
      );
    });

    test('findAll does not duplicate any-method matches without a method', () {
      final router = Router<String>();
      router.add('/api/:id', 'any');

      expect(router.findAll('/api/1', includeAny: true).map((m) => m.data), [
        'any',
      ]);
    });
  });

  group('match priority', () {
    test('static beats param beats wildcard in find', () {
      final router = Router<String>();
      router.add('/users/:id', 'param');
      router.add('/users/**', 'wildcard');
      router.add('/users/all', 'static');

      expect(router.find('/users/all')?.data, 'static');
      expect(router.find('/users/42')?.data, 'param');
      expect(router.find('/users/42/extra')?.data, 'wildcard');
    });

    test('findAll returns wildcard then param then static', () {
      final router = Router<String>();
      router.add('/users/**', 'wildcard');
      router.add('/users/:id', 'param');
      router.add('/users/all', 'static');

      final matches = router.findAll('/users/all');
      expect(matches.map((m) => m.data), ['wildcard', 'param', 'static']);
      expect(matches[0].params, {'_': 'all'});
      expect(matches[1].params, {'id': 'all'});
      expect(matches[2].params, isEmpty);
    });

    test('findAll includes optional tail and exact route', () {
      final router = Router<String>();
      router.add('/users/:id?', 'optional');
      router.add('/users', 'exact');

      expect(router.findAll('/users').map((m) => m.data), [
        'optional',
        'exact',
      ]);
    });
  });

  group('remove', () {
    test(
      'removing and re-adding the first child and method preserves siblings',
      () {
        final router = Router<int>()
          ..add('/.well-known', 1, method: 'GET')
          ..add('/.well-known', 2, method: 'POST')
          ..add('/other', 3);

        expect(router.remove('GET', '/.well-known'), isTrue);
        expect(router.remove('GET', '/.well-known'), isFalse);
        expect(router.find('/.well-known', method: 'POST')?.data, 2);
        router.add('/.well-known', 4, method: 'GET');
        expect(router.find('/.well-known', method: 'GET')?.data, 4);

        expect(router.remove('POST', '/.well-known'), isTrue);
        expect(router.remove('GET', '/.well-known'), isTrue);
        expect(router.findAll('/.well-known'), isEmpty);
        router.add('/.well-known', 5);
        expect(router.findAll('/tmp/..//.well-known/').single.data, 5);
        expect(router.find('/other')?.data, 3);
      },
    );

    test('removes static, param, and wildcard routes', () {
      final router = Router<String>();
      router.add('/users', 'users');
      router.add('/users/:id', 'user');
      router.add('/files/**', 'files');

      expect(router.remove('', '/users'), isTrue);
      expect(router.remove('', '/users/:id'), isTrue);
      expect(router.remove('', '/files/**'), isTrue);

      expect(router.find('/users'), isNull);
      expect(router.find('/users/42'), isNull);
      expect(router.find('/files/a/b'), isNull);
    });

    test('removes only the requested method', () {
      final router = Router<String>();
      router.add('/users', 'list', method: 'GET');
      router.add('/users', 'create', method: 'POST');

      expect(router.remove('GET', '/users'), isTrue);
      expect(router.find('/users', method: 'GET'), isNull);
      expect(router.find('/users', method: 'POST')?.data, 'create');
    });

    test('removes expanded optional routes', () {
      final router = Router<String>();
      router.add('/users/:id?', 'user');

      expect(router.remove('', '/users/:id?'), isTrue);
      expect(router.find('/users'), isNull);
      expect(router.find('/users/42'), isNull);
    });

    test('returns false when the route does not exist', () {
      expect(Router<String>().remove('', '/missing'), isFalse);
    });
  });

  group('case sensitivity', () {
    test('is case-insensitive by default', () {
      final router = Router<String>();
      router.add('/Users/:id', 'user');

      expect(router.find('/users/42')?.data, 'user');
      expect(router.find('/USERS/42')?.data, 'user');
    });

    test('supports case-sensitive matching when configured', () {
      final router = Router<String>(caseSensitive: true);
      router.add('/Users/:id', 'user');

      expect(router.find('/Users/42')?.data, 'user');
      expect(router.find('/users/42'), isNull);
    });
  });

  group('complete find candidates', () {
    test('keeps indexed prefixes distinct across lengths and letter case', () {
      for (final prefix in ['', 'x', 'xy', 'long_']) {
        final router = Router<int>()
          ..add(
            '/x/:id(${prefix}ao'
            r'\d+)',
            1,
          )
          ..add(
            '/x/:id(${prefix}c1'
            r'\d+)',
            2,
          );
        final upper = prefix.toUpperCase();
        expect(router.find('/x/${upper}aO7')?.data, 1);
        expect(router.find('/x/${upper}C17')?.data, 2);
        expect(router.find('/x/${prefix}c1nope'), isNull);
      }
    });

    test(
      'narrows candidates without changing order or rejecting broader routes',
      () {
        final router = Router<String>();
        router.add(r'/items/:id(abcd\d+)', 'long');
        router.add(r'/items/:id(abce\d+)', 'other');
        router.add(r'/items/:id(ab\w+)', 'shorter');
        expect(router.find('/items/ABCD01')?.data, 'long');
        expect(router.find('/items/abz')?.data, 'shorter');
        expect(router.find('/items/a'), isNull);
        expect(router.findAll('/items/a').map((m) => m.data), [
          'long',
          'other',
          'shorter',
        ]);
        router.add('/items/:any', 'fallback');
        expect(router.find('/items/a')?.data, 'fallback');
        expect(router.remove('', '/items/:any'), isTrue);
        router.add(r'/items/:id(x\d+)', 'new');
        expect(router.find('/items/x1')?.data, 'new');
      },
    );

    test(
      'fixed-width alternatives use UTF-16 width and validate the segment',
      () {
        final router = Router<String>();
        router.add(r'/x/:id(.{1})', 'one');
        router.add(r'/x/:id([0-9]{2})', 'digits');
        router.add(r'/x/:id(.{2})', 'two');
        expect(router.find('/x/42')?.data, 'digits');
        expect(router.find('/x/🐈')?.data, 'two');
        expect(router.find('/x/a')?.data, 'one');
        expect(router.find('/x/abc'), isNull);
        router.add('/x/:id(a|abc)', 'any-width');
        expect(router.find('/x/abc')?.data, 'any-width');
      },
    );

    test('falls back to wildcard after a regex candidate is rejected', () {
      final router = Router<String>();
      router.add(r'/users/:id(\d+)', 'numeric');
      router.add('/users/**', 'fallback');

      expect(router.find('/users/42')?.data, 'numeric');
      expect(router.find('/users/42')?.params, {'id': '42'});
      expect(router.find('/users/abc')?.data, 'fallback');
      expect(router.find('/users/abc')?.params, {'_': 'abc'});
      final all = router.findAll('/users/abc');
      expect(all.map((m) => m.data), ['fallback', 'numeric']);
      expect(all.last.params, isEmpty);
    });

    test('validates all regex segments before selecting a candidate', () {
      final router = Router<String>();
      router.add(r'/catalog/:locale(en)/:id(\d+)', 'en');
      router.add(r'/catalog/:locale(fr)/:id(\d+)', 'fr');
      router.add('/catalog/**', 'fallback');

      expect(router.find('/catalog/en/42')?.data, 'en');
      expect(router.find('/catalog/fr/42')?.data, 'fr');
      expect(router.find('/catalog/fr/42')?.params, {
        'locale': 'fr',
        'id': '42',
      });
      expect(router.find('/catalog/fr/nope')?.data, 'fallback');
      expect(router.find('/catalog/de/42')?.data, 'fallback');
    });

    test('validates regex prefixes of remainder wildcards', () {
      final router = Router<String>();
      router.add(r'/users/:id(\d+)/**:rest', 'numeric-files');
      router.add('/**', 'fallback');

      expect(router.find('/users/42/a/b')?.data, 'numeric-files');
      expect(router.find('/users/42/a/b')?.params, {'id': '42', 'rest': 'a/b'});
      expect(router.find('/users/abc/a/b')?.data, 'fallback');
      expect(router.find('/users/abc/a/b')?.params, {'_': 'users/abc/a/b'});
    });

    test(
      'tries a param branch after a static branch has no valid candidate',
      () {
        final router = Router<String>();
        router.add(r'/users/admin/:id(\d+)', 'admin');
        router.add('/users/:name/:slug', 'param');
        router.add('/users/**', 'wildcard');

        expect(router.find('/users/admin/42')?.data, 'admin');
        expect(router.find('/users/admin/nope')?.data, 'param');
        expect(router.find('/users/admin/nope')?.params, {
          'name': 'admin',
          'slug': 'nope',
        });
        expect(router.find('/users/admin/nope/extra')?.data, 'wildcard');
      },
    );

    test('prefers matching regex candidates over earlier plain params', () {
      final router = Router<String>();
      router.add('/users/:name', 'plain');
      router.add(r'/users/:id(\d+)', 'numeric');

      expect(router.find('/users/42')?.data, 'numeric');
      expect(router.find('/users/42')?.params, {'id': '42'});
      expect(router.find('/users/abc')?.data, 'plain');
      expect(router.find('/users/abc')?.params, {'name': 'abc'});
    });

    test('retains priority of the deepest matching constrained segment', () {
      final router = Router<String>();
      router.add(r'/catalog/:locale(en)/:id', 'locale');
      router.add(r'/catalog/:locale/:id(\d+)', 'id');

      expect(router.find('/catalog/en/42')?.data, 'id');
      expect(router.find('/catalog/en/42')?.params, {
        'locale': 'en',
        'id': '42',
      });
      expect(router.find('/catalog/en/abc')?.data, 'locale');
      expect(router.find('/catalog/fr/42')?.data, 'id');
    });

    test('keeps method bucket selection during candidate fallback', () {
      final router = Router<String>();
      router.add('/users/:id', 'any');
      router.add(r'/users/:id(\d+)', 'get', method: 'GET');
      router.add('/users/**', 'fallback');

      expect(router.find('/users/42', method: ' get ')?.data, 'get');
      expect(router.find('/users/abc', method: 'GET')?.data, 'fallback');
      expect(router.find('/users/abc', method: 'POST')?.data, 'any');
      expect(router.find('/users/42')?.data, 'any');
    });

    test('selects only optional single-segment tails on an empty suffix', () {
      final router = Router<String>();
      router.add('/users/:id', 'required');
      router.add('/users/*', 'optional');
      router.add(r'/users/:id(.*)', 'regex');

      expect(router.find('/users')?.data, 'optional');
      expect(router.findAll('/users').map((m) => m.data), ['optional']);
      expect(router.find('/users/42')?.data, 'regex');
    });

    test('matches escaped static routes through the same tree as findAll', () {
      final router = Router<String>(caseSensitive: true);
      router.add(r'/files/\*', 'literal-star');

      expect(router.find(r'/files/\*'), isNull);
      expect(router.findAll(r'/files/\*'), isEmpty);
      expect(router.find('/files/*')?.data, 'literal-star');
      expect(router.find('/files/*')?.params, isEmpty);
      expect(router.findAll('/files/*').single.data, 'literal-star');
      expect(router.remove('', r'/files/\*'), isTrue);
      expect(router.find('/files/*'), isNull);
    });

    test('retains appended registrations and removes the selected slot', () {
      final router = Router<String>();
      router.add('/ping', 'first');
      router.add('/ping', 'second');
      router.add('/users/:id', 'first-param');
      router.add('/users/:name', 'second-param');

      expect(router.find('/ping')?.data, 'first');
      expect(router.findAll('/ping').map((m) => m.data), ['first', 'second']);
      expect(router.find('/users/42')?.params, {'id': '42'});
      expect(router.findAll('/users/42').map((m) => m.data), [
        'first-param',
        'second-param',
      ]);
      expect(router.remove('', '/ping'), isTrue);
      expect(router.findAll('/ping'), isEmpty);
      expect(router.remove('', '/users/:id'), isTrue);
      expect(router.findAll('/users/42'), isEmpty);
    });
  });

  group('validation', () {
    test('rejects invalid params and unclosed patterns', () {
      expect(
        () => Router<String>().add('/users/:', 'x'),
        throwsFormatException,
      );
      expect(
        () => Router<String>().add(r'/users/:id(\d+', 'x'),
        throwsFormatException,
      );
      expect(
        () => Router<String>().add('/foo{bar', 'x'),
        throwsFormatException,
      );
    });
  });

  group('escape sequences', () {
    test(r'escaped \: is treated as a literal colon', () {
      final router = Router<String>();
      router.add(r'/v\:1/users', 'versioned');

      expect(router.find('/v:1/users')?.data, 'versioned');
    });

    test(r'escaped \* is treated as a literal asterisk', () {
      final router = Router<String>();
      router.add(r'/files/\*', 'star-file');

      expect(router.find('/files/*')?.data, 'star-file');
    });
  });
}
