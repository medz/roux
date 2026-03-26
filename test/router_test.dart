import 'package:roux/roux.dart';
import 'package:test/test.dart';

void main() {
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
  });

  group('params and patterns', () {
    test('captures multiple params', () {
      final router = Router<String>();
      router.add('/users/:id/items/:itemId', 'item');

      expect(router.find('/users/42/items/7')?.params, {
        'id': '42',
        'itemId': '7',
      });
    });

    test('params map is mutable', () {
      final router = Router<String>();
      router.add('/users/:id', 'user');

      final params = router.find('/users/42')!.params!;
      params['extra'] = 'ok';

      expect(params, {'id': '42', 'extra': 'ok'});
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
    });

    test('supports optional params', () {
      final router = Router<String>();
      router.add('/users/:id?', 'user');

      expect(router.find('/users/42')?.params, {'id': '42'});
      expect(router.find('/users')?.data, 'user');
      expect(router.find('/users')?.params, isNull);
    });

    test('supports repeated params with plus and star', () {
      final router = Router<String>();
      router.add('/files/:path+', 'plus');
      router.add('/assets/:rest*', 'star');

      expect(router.find('/files'), isNull);
      expect(router.find('/files/a/b')?.params, {'path': 'a/b'});
      expect(router.find('/assets')?.params, isNull);
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

      expect(router.find('/users')?.params, isNull);
      expect(router.find('/users/42')?.params, {'id': '42'});
      expect(router.find('/blog/123')?.params, {'id': '123'});
      expect(router.find('/blog/123-post')?.params, {
        'id': '123',
        'title': 'post',
      });
    });
  });

  group('method matching', () {
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

    test('findAll returns the selected method bucket only', () {
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
      expect(matches[2].params, isNull);
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

  group('cache', () {
    test('uses cache when configured', () {
      final router = Router<String>(cache: LRUCache<String>());
      router.add('/users/:id', 'user');

      final first = router.find('/users/42');
      final second = router.find('/users/42');

      expect(identical(first, second), isTrue);
    });

    test('clears cache after add and remove', () {
      final router = Router<String>(cache: LRUCache<String>());
      router.add('/ping', 'first');

      final first = router.find('/ping');
      router.add('/ping', 'second');
      final afterAdd = router.find('/ping');
      expect(identical(first, afterAdd), isFalse);

      expect(router.remove('', '/ping'), isTrue);
      expect(router.find('/ping'), isNull);
    });

    test('uses a custom cache implementation', () {
      var gets = 0;
      var puts = 0;
      final cache = _CountingCache<String>(
        onGet: () => gets++,
        onPut: () => puts++,
      );
      final router = Router<String>(cache: cache);
      router.add('/ping', 'pong');

      router.find('/ping');
      router.find('/ping');

      expect(gets, 2);
      expect(puts, 1);
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

class _CountingCache<T> implements Cache<T> {
  _CountingCache({required this.onGet, required this.onPut});

  final void Function() onGet;
  final void Function() onPut;
  final _inner = LRUCache<T>();

  @override
  RouteMatch<T>? get(String key) {
    onGet();
    return _inner.get(key);
  }

  @override
  void put(String key, RouteMatch<T> value) {
    onPut();
    _inner.put(key, value);
  }

  @override
  void clear() => _inner.clear();
}
