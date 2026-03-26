import 'package:roux/roux.dart';
import 'package:test/test.dart';

// Helpers
Router<String> _router({bool caseSensitive = true}) =>
    Router<String>(caseSensitive: caseSensitive);

void main() {
  group('basic add and find', () {
    test('returns null when no routes registered', () {
      expect(_router().find('', '/users/42'), isNull);
    });

    test('finds a simple param route', () {
      final r = _router();
      r.add('', '/users/:id', 'user');
      expect(r.find('', '/users/42')?.data, 'user');
      expect(r.find('', '/users/42')?.params, {'id': '42'});
    });

    test('finds a static route', () {
      final r = _router();
      r.add('', '/users/all', 'all');
      expect(r.find('', '/users/all')?.data, 'all');
    });

    test('static route takes priority over param route', () {
      final r = _router();
      r.add('', '/users/:id', 'param');
      r.add('', '/users/all', 'static');
      expect(r.find('', '/users/all')?.data, 'static');
      expect(r.find('', '/users/42')?.data, 'param');
    });

    test('multiple routes coexist', () {
      final r = _router();
      r.add('', '/', 'root');
      r.add('', '/users/all', 'all');
      r.add('', '/users/:id', 'detail');
      expect(r.find('', '/')?.data, 'root');
      expect(r.find('', '/users/all')?.data, 'all');
      expect(r.find('', '/users/7')?.data, 'detail');
      expect(r.find('', '/users/7')?.params, {'id': '7'});
    });

    test('ignores trailing slash on lookup', () {
      final r = _router();
      r.add('', '/users/:id', 'user');
      expect(r.find('', '/users/42/')?.data, 'user');
    });

    test('does not require leading slash on add', () {
      final r = _router();
      r.add('', 'users/:id', 'user');
      expect(r.find('', '/users/42')?.data, 'user');
    });
  });

  group('param routes', () {
    test('captures a single param', () {
      final r = _router();
      r.add('', '/users/:id', 'user');
      expect(r.find('', '/users/42')?.params, {'id': '42'});
    });

    test('captures multiple params', () {
      final r = _router();
      r.add('', '/users/:id/items/:itemId', 'item');
      expect(r.find('', '/users/42/items/7')?.params, {'id': '42', 'itemId': '7'});
    });

    test('params map is mutable', () {
      final r = _router();
      r.add('', '/users/:id', 'user');
      final params = r.find('', '/users/42')!.params!;
      params['extra'] = 'ok';
      expect(params, {'id': '42', 'extra': 'ok'});
    });

    test('embedded param segment', () {
      final r = _router();
      r.add('', '/files/:name.:ext', 'asset');
      expect(r.find('', '/files/readme.md')?.params, {'name': 'readme', 'ext': 'md'});
    });

    test('named regex param — matches', () {
      final r = _router();
      r.add('', '/users/:id(\\d+)', 'numeric');
      expect(r.find('', '/users/42')?.data, 'numeric');
      expect(r.find('', '/users/42')?.params, {'id': '42'});
    });

    test('named regex param — does not match non-digits', () {
      final r = _router();
      r.add('', '/users/:id(\\d+)', 'numeric');
      expect(r.find('', '/users/nope'), isNull);
    });

    test('regex quantifiers in braces do not trigger group parsing', () {
      final r = _router();
      r.add('', '/users/:id(\\d{2})/:tab?', 'user');
      expect(r.find('', '/users/42')?.params, {'id': '42'});
      expect(r.find('', '/users/42/profile')?.params, {'id': '42', 'tab': 'profile'});
      expect(r.find('', '/users/420'), isNull);
    });
  });

  group('optional and rest params', () {
    test('optional param — present', () {
      final r = _router();
      r.add('', '/users/:id?', 'user');
      expect(r.find('', '/users/42')?.params, {'id': '42'});
    });

    test('optional param — absent returns null params', () {
      final r = _router();
      r.add('', '/users/:id?', 'user');
      expect(r.find('', '/users')?.data, 'user');
      expect(r.find('', '/users')?.params, isNull);
    });

    test('rest param with + — requires at least one segment', () {
      final r = _router();
      r.add('', '/files/:path+', 'files');
      expect(r.find('', '/files'), isNull);
      expect(r.find('', '/files/a/b')?.params, {'path': 'a/b'});
    });

    test('rest param with * — matches zero or more segments', () {
      final r = _router();
      r.add('', '/assets/:rest*', 'assets');
      expect(r.find('', '/assets')?.data, 'assets');
      expect(r.find('', '/assets')?.params, isNull);
      expect(r.find('', '/assets/a/b')?.params, {'rest': 'a/b'});
    });

    test('rest param with + inside regex-quantifier path', () {
      final r = _router();
      r.add('', '/files/:id(\\d{2})/:path+', 'file');
      expect(r.find('', '/files/42/a/b')?.params, {'id': '42', 'path': 'a/b'});
      expect(r.find('', '/files/7/a/b'), isNull);
    });
  });

  group('wildcard routes', () {
    test('single-segment wildcard captures one segment', () {
      final r = _router();
      r.add('', '/users/*', 'star');
      expect(r.find('', '/users/a')?.params, {'0': 'a'});
      expect(r.find('', '/users/a/b'), isNull);
    });

    test('single-segment wildcard in the middle', () {
      final r = _router();
      r.add('', '/teams/*/members', 'members');
      expect(r.find('', '/teams/core/members')?.params, {'0': 'core'});
    });

    test('embedded wildcards in a segment', () {
      final r = _router();
      r.add('', '/files/file-*-*.png', 'asset');
      expect(r.find('', '/files/file-a-b.png')?.params, {'0': 'a', '1': 'b'});
      expect(r.find('', '/files/file--.png')?.params, {'0': '', '1': ''});
    });

    test('double-wildcard named capture', () {
      final r = _router();
      r.add('', '/users/**:wildcard', 'users');
      expect(r.find('', '/users/a/b')?.params, {'wildcard': 'a/b'});
    });

    test('bare double-wildcard captures under _ key', () {
      final r = _router();
      r.add('', '/files/**', 'files');
      expect(r.find('', '/files/a/b/c')?.params, {'_': 'a/b/c'});
    });

    test('double-wildcard at root acts as global fallback', () {
      final r = _router();
      r.add('', '/**', 'fallback');
      expect(r.find('', '/anything/at/all')?.data, 'fallback');
    });

    test('double wildcard must be the final segment', () {
      final r = _router();
      expect(() => r.add('', '/users/**/extra', 'bad'), throwsFormatException);
    });

    test('param matches before wildcard', () {
      final r = _router();
      r.add('', '/users/:id', 'param');
      r.add('', '/users/**', 'wildcard');
      expect(r.find('', '/users/42')?.data, 'param');
    });
  });

  group('group syntax', () {
    test('optional group expands to with and without', () {
      final r = _router();
      r.add('', '/book{s}?', 'book');
      expect(r.find('', '/book')?.data, 'book');
      expect(r.find('', '/books')?.data, 'book');
    });

    test('optional group with param', () {
      final r = _router();
      r.add('', '/users{/:id}?', 'user');
      expect(r.find('', '/users')?.params, isNull);
      expect(r.find('', '/users/42')?.params, {'id': '42'});
    });

    test('mandatory group inlines body', () {
      final r = _router();
      r.add('', '/foo{bar}', 'foobar');
      expect(r.find('', '/foo'), isNull);
      expect(r.find('', '/foobar')?.data, 'foobar');
    });

    test('nested optional groups', () {
      final r = _router();
      r.add('', '/docs{/:section}{/:page}?', 'docs');
      expect(r.find('', '/docs'), isNull);
      expect(r.find('', '/docs/api')?.params, {'section': 'api'});
      expect(r.find('', '/docs/api/intro')?.params, {'section': 'api', 'page': 'intro'});
    });

    test('blog with optional titled segment', () {
      final r = _router();
      r.add('', '/blog/:id(\\d+){-:title}?', 'blog');
      expect(r.find('', '/blog/123')?.params, {'id': '123'});
      expect(r.find('', '/blog/123-post')?.params, {'id': '123', 'title': 'post'});
    });

    test('rejects unclosed group', () {
      expect(() => _router().add('', '/foo{bar', 'x'), throwsFormatException);
    });
  });

  group('method matching', () {
    test("empty string method matches any route's method", () {
      final r = _router();
      r.add('GET', '/users/:id', 'get-user');
      expect(r.find('GET', '/users/1')?.data, 'get-user');
      expect(r.find('', '/users/1')?.data, 'get-user');
    });

    test('empty-method route serves as ANY and is found by specific method', () {
      final r = _router();
      r.add('', '/users/:id', 'any-user');
      expect(r.find('GET', '/users/1')?.data, 'any-user');
      expect(r.find('POST', '/users/1')?.data, 'any-user');
    });

    test('specific method takes priority over any-method route', () {
      final r = _router();
      r.add('', '/users/:id', 'any');
      r.add('GET', '/users/:id', 'get');
      expect(r.find('GET', '/users/1')?.data, 'get');
      expect(r.find('POST', '/users/1')?.data, 'any');
    });

    test('method names are normalized to uppercase', () {
      final r = _router();
      r.add('get', '/ping', 'pong');
      expect(r.find('GET', '/ping')?.data, 'pong');
    });

    test('method names are trimmed', () {
      final r = _router();
      r.add(' GET ', '/ping', 'pong');
      expect(r.find('GET', '/ping')?.data, 'pong');
    });

    test('multiple methods on same path', () {
      final r = _router();
      r.add('GET', '/users', 'list');
      r.add('POST', '/users', 'create');
      expect(r.find('GET', '/users')?.data, 'list');
      expect(r.find('POST', '/users')?.data, 'create');
      expect(r.find('DELETE', '/users'), isNull);
    });
  });

  group('match priority', () {
    test('static beats param beats wildcard', () {
      final r = _router();
      r.add('', '/users/:id', 'param');
      r.add('', '/users/**', 'wildcard');
      r.add('', '/users/all', 'static');
      expect(r.find('', '/users/all')?.data, 'static');
      expect(r.find('', '/users/42')?.data, 'param');
      expect(r.find('', '/users/42/extra')?.data, 'wildcard');
    });

    test('double-wildcard is the last resort', () {
      final r = _router();
      r.add('', '/**', 'fallback');
      r.add('', '/known', 'known');
      expect(r.find('', '/known')?.data, 'known');
      expect(r.find('', '/unknown')?.data, 'fallback');
    });

    test('longer static prefix wins', () {
      final r = _router();
      r.add('', '/a/:x', 'shallow');
      r.add('', '/a/b/:x', 'deep');
      expect(r.find('', '/a/b/42')?.data, 'deep');
      expect(r.find('', '/a/42')?.data, 'shallow');
    });
  });

  group('findAll', () {
    test('returns empty list when nothing matches', () {
      expect(_router().findAll('', '/unknown'), isEmpty);
    });

    test('returns wildcard match, then param match, then static match', () {
      final r = _router();
      r.add('', '/users/**', 'wildcard');
      r.add('', '/users/:id', 'param');
      r.add('', '/users/all', 'static');
      final matches = r.findAll('', '/users/all').map((m) => m.data).toList();
      expect(matches, ['wildcard', 'param', 'static']);
    });

    test('includes params for each match', () {
      final r = _router();
      r.add('', '/users/**:wild', 'wildcard');
      r.add('', '/users/:id', 'param');
      final matches = r.findAll('', '/users/42');
      expect(matches[0].params, {'wild': '42'});
      expect(matches[1].params, {'id': '42'});
    });

    test('optional tail is included in findAll', () {
      final r = _router();
      r.add('', '/users/:id?', 'optional');
      r.add('', '/users', 'exact');
      final matches = r.findAll('', '/users').map((m) => m.data).toList();
      expect(matches, containsAll(['optional', 'exact']));
    });

    test('findAll with method returns method-specific and any-method routes', () {
      final r = _router();
      r.add('', '/api/:id', 'any');
      r.add('GET', '/api/:id', 'get');
      final matches = r.findAll('GET', '/api/1').map((m) => m.data).toList();
      expect(matches, containsAll(['any', 'get']));
    });
  });

  group('remove', () {
    test('removes a static route', () {
      final r = _router();
      r.add('', '/users', 'users');
      expect(r.remove('', '/users'), isTrue);
      expect(r.find('', '/users'), isNull);
    });

    test('removes a param route', () {
      final r = _router();
      r.add('', '/users/:id', 'user');
      expect(r.remove('', '/users/:id'), isTrue);
      expect(r.find('', '/users/42'), isNull);
    });

    test('returns false when route does not exist', () {
      final r = _router();
      expect(r.remove('', '/nonexistent'), isFalse);
    });

    test('removes only the specified method', () {
      final r = _router();
      r.add('GET', '/users', 'list');
      r.add('POST', '/users', 'create');
      r.remove('GET', '/users');
      expect(r.find('GET', '/users'), isNull);
      expect(r.find('POST', '/users')?.data, 'create');
    });

    test('removes a wildcard route', () {
      final r = _router();
      r.add('', '/files/**', 'files');
      r.remove('', '/files/**');
      expect(r.find('', '/files/a/b'), isNull);
    });

    test('removes expanded modifier routes', () {
      final r = _router();
      r.add('', '/users/:id?', 'user');
      r.remove('', '/users/:id?');
      expect(r.find('', '/users/42'), isNull);
      expect(r.find('', '/users'), isNull);
    });

    test('clears cache after remove', () {
      final r = _router();
      r.add('', '/ping', 'pong');
      r.find('', '/ping'); // cache it
      r.remove('', '/ping');
      expect(r.find('', '/ping'), isNull);
    });
  });

  group('case sensitivity', () {
    test('is case-sensitive by default', () {
      final r = _router();
      r.add('', '/Users/:id', 'user');
      expect(r.find('', '/Users/42')?.data, 'user');
      expect(r.find('', '/users/42'), isNull);
    });

    test('case-insensitive matching when configured', () {
      final r = _router(caseSensitive: false);
      r.add('', '/Users/:id', 'user');
      expect(r.find('', '/users/42')?.data, 'user');
      expect(r.find('', '/USERS/42')?.data, 'user');
    });

    test('case-insensitive static routes share a node', () {
      final r = _router(caseSensitive: false);
      r.add('', '/About', 'about');
      expect(r.find('', '/about')?.data, 'about');
      expect(r.find('', '/ABOUT')?.data, 'about');
    });
  });

  group('cache', () {
    test('find returns cached results', () {
      final r = _router();
      r.add('', '/users/:id', 'user');
      final first = r.find('', '/users/42');
      final second = r.find('', '/users/42');
      expect(identical(first, second), isTrue);
    });

    test('cache is cleared after add', () {
      final r = _router();
      r.add('', '/ping', 'first');
      r.find('', '/ping');
      r.add('', '/ping', 'second');
      // Both routes exist now (no dedup); first-added wins
      expect(r.find('', '/ping')?.data, 'first');
    });

    test('custom cache implementation is used', () {
      var gets = 0;
      var puts = 0;

      final customCache = _CountingCache<String, RouteMatch<String>>(
        onGet: () => gets++,
        onPut: () => puts++,
      );

      final r = Router<String>(cache: customCache);
      r.add('', '/ping', 'pong');
      r.find('', '/ping');
      r.find('', '/ping');

      expect(gets, 2);
      expect(puts, 1);
    });
  });

  group('validation', () {
    test('rejects double wildcard in the middle', () {
      expect(() => _router().add('', '/a/**/b', 'x'), throwsFormatException);
    });

    test('rejects invalid param name', () {
      expect(() => _router().add('', '/users/:', 'x'), throwsFormatException);
    });

    test('rejects unclosed regex in param', () {
      expect(() => _router().add('', '/users/:id(\\d+', 'x'), throwsFormatException);
    });

    test('rejects unclosed group delimiter', () {
      expect(() => _router().add('', '/foo{bar', 'x'), throwsFormatException);
    });
  });

  group('escape sequences', () {
    test(r'escaped \: is treated as literal colon', () {
      final r = _router();
      r.add('', r'/v\:1/users', 'versioned');
      expect(r.find('', '/v:1/users')?.data, 'versioned');
    });

    test(r'escaped \* is treated as literal asterisk in static segment', () {
      final r = _router();
      r.add('', r'/files/\*', 'star-file');
      expect(r.find('', '/files/*')?.data, 'star-file');
    });
  });
}

// ---------------------------------------------------------------------------
// Test helper: counting cache
// ---------------------------------------------------------------------------

class _CountingCache<K, V> implements Cache<K, V> {
  _CountingCache({required this.onGet, required this.onPut});

  final void Function() onGet;
  final void Function() onPut;
  final _inner = LRUCache<K, V>();

  @override
  V? get(K key) {
    onGet();
    return _inner.get(key);
  }

  @override
  void put(K key, V value) {
    onPut();
    _inner.put(key, value);
  }

  @override
  void clear() => _inner.clear();
}
