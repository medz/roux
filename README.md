# roux

[![Pub Version](https://img.shields.io/pub/v/roux?logo=dart)](https://pub.dev/packages/roux)
[![Test](https://github.com/medz/roux/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/medz/roux/actions/workflows/test.yml)

Lightweight and fast router for Dart.

## Install

```bash
dart pub add roux
```

With Flutter:

```bash
flutter pub add roux
```

## Usage

```dart
import 'package:roux/roux.dart';

final router = createRouter<String>();

addRoute(router, 'GET', '/users', 'Users list');
addRoute(router, 'GET', '/users/:id', 'User details');
addRoute(router, 'GET', '/assets/**', 'Static assets');
addRoute(router, 'POST', '/users', 'Create user');

final match = findRoute(router, 'GET', '/users/123');
print(match?.data);   // User details
print(match?.params); // {id: 123}

final matches = findAllRoutes(router, 'GET', '/users/123/settings');

removeRoute(router, 'GET', '/users/:id');
```

## Notes

- Paths should start with `/`. (If not, it will be normalized.)
- Methods are normalized to uppercase. `get`, `GET`, `Get` are the same.
- To register literal `:` or `*`, escape them with `\\`. Example: `/static\\:path/\\*/\\*\\*` matches `/static:path/*/**`.

## Options

```dart
// Case-insensitive routing
final router = createRouter<String>(caseSensitive: false);

// Custom token for "any" method
final router2 = createRouter<String>(anyMethodToken: '*');
addRoute(router2, null, '/api', 'any-method');
```

## Helpers

```dart
// Convert a route pattern to a RegExp.
final re = routeToRegExp('/users/:id');
```

## License

MIT. See [LICENSE](LICENSE).
