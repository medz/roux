# roux

[![Pub Version](https://img.shields.io/pub/v/roux?logo=dart)](https://pub.dev/packages/roux)
[![Test](https://github.com/medz/roux/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/medz/roux/actions/workflows/test.yml)

Lightweight, fast router for Dart with expressive pathname syntax.

## Install

```bash
dart pub add roux
```

With Flutter:

```bash
flutter pub add roux
```

## Quick Start

```dart
import 'package:roux/roux.dart';

void main() {
  final router = Router<String>();

  router.add('/', 'root');
  router.add('/users/all', 'usersAll');
  router.add('/users/:id', 'userDetail');
  router.add('/users/*', 'usersWildcard');
  router.add('/**', 'globalFallback');

  final match = router.find('/users/42');
  print(match?.data);   // userDetail
  print(match?.params); // {id: 42}

  final all = router.findAll('/users/all');
  print(all.map((m) => m.data)); // (globalFallback, usersWildcard, usersAll)
}
```

## API

```dart
final router = Router<String>(
  caseSensitive: false,
  cache: LRUCache<String>(),
);

router.add('/posts', 'posts');
router.add('/posts/:id', 'post', method: 'GET');

final match = router.find('/posts/42', method: 'GET');
final matches = router.findAll('/posts/42', method: 'GET');

router.remove('GET', '/posts/:id');
```

### `Router`

- `Router({bool caseSensitive = false, Cache<T>? cache})`
- `void add(String path, T data, {String? method})`
- `RouteMatch<T>? find(String path, {String? method})`
- `List<RouteMatch<T>> findAll(String path, {String? method})`
- `bool remove(String method, String path)`

### `RouteMatch`

- `data` is the registered payload.
- `params` is always a `Map<String, String>`.
- Routes without params return an empty map.

## Route Syntax

| Syntax                      | Meaning                           | Example params                          |
| --------------------------- | --------------------------------- | --------------------------------------- |
| `/users/all`                | Exact static route                | `{}`                                    |
| `/users/:id`                | Named single-segment param        | `{id: 42}`                              |
| `/users/*`                  | Unnamed single-segment wildcard   | `{0: 42}`                               |
| `/users/**:rest`            | Named remainder wildcard          | `{rest: a/b}`                           |
| `/users/**`                 | Unnamed remainder wildcard        | `{_: a/b}`                              |
| `/files/:name.:ext`         | Embedded params in one segment    | `{name: readme, ext: md}`               |
| `/files/file-*-*.png`       | Embedded wildcards in one segment | `{0: a, 1: b}`                          |
| `/users/:id(\\d+)`          | Named regex param                 | `{id: 42}`                              |
| `/path/(\\d+)`              | Unnamed regex group               | `{0: 42}`                               |
| `/users/:id?`               | Optional segment param            | `{}` or `{id: 42}`                      |
| `/files/:path+`             | One-or-more repeated segments     | `{path: a/b}`                           |
| `/assets/:rest*`            | Zero-or-more repeated segments    | `{}` or `{rest: a/b}`                   |
| `/foo{bar}`                 | Mandatory group suffix            | `{}`                                    |
| `/book{s}?`                 | Optional group suffix             | `{}`                                    |
| `/users{/:id}?`             | Optional grouped suffix           | `{}` or `{id: 42}`                      |
| `/blog/:id(\\d+){-:title}?` | Mixed regex, params, and groups   | `{id: 123}` or `{id: 123, title: post}` |

## Path Handling

`roux` matches pathnames only.

- Leading slash is normalized: `users/:id` behaves like `/users/:id`.
- Trailing slash is ignored: `/users` and `/users/` match the same route.
- Repeated slashes are collapsed during registration and lookup.
- `.` and `..` segments are normalized during registration and lookup.
- Percent-encoded bytes are matched literally and are not URI-decoded.

Examples:

```dart
final router = Router<String>();

router.add('users/:id', 'user');
router.add('/users/./profile', 'profile');
router.add('/caf%C3%A9', 'cafe');

print(router.find('/users/42')?.params);       // {id: 42}
print(router.find('/users/profile')?.data);    // profile
print(router.find('/caf%C3%A9')?.data);        // cafe
print(router.find('/café'));                   // null
```

## Matching Rules

For `find(...)`, the broad precedence is:

- static routes beat params
- params beat wildcards
- more specific regex or embedded param routes can beat plain params
- method-specific routes beat method-agnostic routes in the same slot

For `findAll(...)`, matches are returned from broad to specific.

Example:

```dart
final router = Router<String>();
router.add('/users/**', 'wildcard');
router.add('/users/:id', 'param');
router.add('/users/all', 'static');

print(router.find('/users/all')?.data); // static
print(router.findAll('/users/all').map((m) => m.data));
// (wildcard, param, static)
```

## HTTP Method Matching

Method names are trimmed and uppercased internally.

```dart
final router = Router<String>();
router.add('/users/:id', 'any');
router.add('/users/:id', 'get', method: ' get ');

print(router.find('/users/1')?.data);                 // any
print(router.find('/users/1', method: 'GET')?.data);  // get
print(router.find('/users/1', method: 'POST')?.data); // any
```

`findAll` returns only the selected method bucket:

```dart
final router = Router<String>();
router.add('/api/:id', 'any');
router.add('/api/:id', 'get', method: 'GET');

print(router.findAll('/api/1', method: 'GET').map((m) => m.data));
// (get)
```

## Cache

You can provide any `Cache<T>` implementation, or use `LRUCache<T>`.

```dart
final router = Router<String>(cache: LRUCache(256));
router.add('/users/:id', 'user');

final first = router.find('/users/42');
final second = router.find('/users/42');

print(identical(first, second)); // true
```

The cache is cleared after `add(...)` and `remove(...)`.

## Validation and Escapes

Invalid param names or unclosed regex / group syntax throw `FormatException`.

Escaped syntax characters are treated literally:

```dart
final router = Router<String>();

router.add(r'/v\:1/users', 'versioned');
router.add(r'/files/\*', 'star-file');

print(router.find('/v:1/users')?.data); // versioned
print(router.find('/files/*')?.data);   // star-file
```

## Example

See [`example/main.dart`](example/main.dart) for a runnable example.

## License

MIT. See [LICENSE](LICENSE).
