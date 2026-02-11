# roux

[![Pub Version](https://img.shields.io/pub/v/roux?logo=dart)](https://pub.dev/packages/roux)
[![Test](https://github.com/medz/roux/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/medz/roux/actions/workflows/test.yml)

Lightweight, fast router for Dart with static, parameterized, and
wildcard path matching.

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

final router = Router<String>(
  routes: {
    '/': 'root',
    '/users/all': 'users-all',
    '/users/:id': 'users-id',
    '/users/*': 'users-wildcard',
    '/*': 'global-fallback',
  },
);

final match = router.match('/users/123');
print(match?.data);   // users-id
print(match?.params); // {id: 123}
```

## Route Syntax

- Static: `/users`
- Named param: `/users/:id`
- Wildcard tail: `/users/*`
- Global fallback: `/*`

Notes:
- Paths must start with `/`.
- `*` is only allowed as the final segment.
- Embedded syntax like `/files/:name.:ext` is intentionally unsupported.
- Matching is case-sensitive.
- Trailing slash on input is ignored (`/users` equals `/users/`).
- You can register routes via constructor (`Router(routes: {...})`) or
  incrementally (`add` / `addAll`).

## Matching Order

1. Exact route (`/users/all`)
2. Parameter route (`/users/:id`)
3. Wildcard route (`/users/*`)
4. Global fallback (`/*`)

## Benchmarks

Relic-style comparison benchmark:

```bash
dart run bench/relic_compare.dart 500
```

Lookup scenario matrix benchmark:

```bash
dart run bench/compare.dart 500
```

## License

MIT. See [LICENSE](LICENSE).
