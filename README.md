# roux

[![Pub Version](https://img.shields.io/pub/v/roux?logo=dart)](https://pub.dev/packages/roux)
[![Test](https://github.com/medz/roux/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/medz/roux/actions/workflows/test.yml)

Lightweight, fast router for Dart with static, parameterized, and wildcard route
matching.

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

final router = createRouter<String>();

addRoute(router, 'GET', '/users', 'users');
addRoute(router, 'GET', '/users/:id', 'user');
addRoute(router, 'POST', '/users', 'create-user');
addRoute(router, null, '/health', 'any-method');

final match = findRoute(router, 'GET', '/users/123');
print(match?.data);   // user
print(match?.params); // {id: 123}

final all = findAllRoutes(router, 'GET', '/users/123');
for (final m in all) {
  print(m.data);
}
```

## Route Syntax

- Static: `/users`
- Named param: `/users/:id`
- Embedded params: `/files/:name.:ext`
- Single-segment wildcard: `*` (unnamed, captured as `_0`, `_1`, ...)
- Multi-segment wildcard: `**` (unnamed, captured as `_`) or `**:path` (named)
- `**` can match an empty remainder; `**:name` requires at least one segment.
- Escape literal tokens with `\\`: `/static\\:path/\\*/\\*\\*` matches
  `/static%3Apath/*/**`
- Paths are normalized to start with `/`.
- Methods are case-insensitive. `null` uses the any-method token.

## Matching Order

- Static > param > wildcard.
- Method matching tries the requested method first, then the any-method token.

## Options

```dart
final router = createRouter<String>(
  caseSensitive: false,
  anyMethodToken: 'any',
);
```

## Examples

### Any-method route

```dart
addRoute(router, null, '/status', 'ok');
```

### Find all matches

```dart
final matches = findAllRoutes(router, 'GET', '/files/report.pdf');
for (final m in matches) {
  print(m.data);
}
```

### Convert a pattern to RegExp

```dart
final re = routeToRegExp('/users/:id');
```

## License

MIT. See [LICENSE](LICENSE).
