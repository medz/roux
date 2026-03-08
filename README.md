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

final stack = router.matchAll('/users/123');
print(stack.map((match) => match.data)); // (global-fallback, users-wildcard, users-id)
```

## Duplicate Policy

Duplicate route handling is configurable at both router and call level:

```dart
final router = Router<String>(
  duplicatePolicy: DuplicatePolicy.replace,
  routes: {'/users/:id': 'first'},
);

router.add('/users/:id', 'second');
print(router.match('/users/42')?.data); // second
```

Available policies:

- `DuplicatePolicy.reject` keeps the current default and throws on duplicates
- `DuplicatePolicy.replace` keeps the latest retained entry
- `DuplicatePolicy.keepFirst` keeps the earliest retained entry
- `DuplicatePolicy.append` retains all entries in registration order

Per-call overrides are also supported:

```dart
router.add(
  '/users/:id',
  'third',
  duplicatePolicy: DuplicatePolicy.keepFirst,
);
```

To retain multiple handlers in the same normalized slot:

```dart
final router = Router<String>(duplicatePolicy: DuplicatePolicy.append);
router.add('/*', 'global-logger');
router.add('/*', 'root-scope-middleware');

print(router.match('/users/42')?.data); // global-logger
print(
  router.matchAll('/users/42').map((match) => match.data),
); // (global-logger, root-scope-middleware)
```

Parameter-name drift remains a hard error under all policies. For example,
`/users/:id` and `/users/:name` still conflict.

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

For `match(...)`:

1. Exact route (`/users/all`)
2. Parameter route (`/users/:id`)
3. Wildcard route (`/users/*`)
4. Global fallback (`/*`)

For `matchAll(...)`:

1. Global fallback (`/*`)
2. Wildcard scope (`/users/*`)
3. Parameter route (`/users/:id`)
4. Exact route (`/users/all`)

`matchAll(...)` returns every matching route from less specific to more
specific. When a `method` is provided, both `ANY` and exact-method entries
participate, with `ANY` ordered first at the same scope. When duplicate slots
are retained via `DuplicatePolicy.append`, entries from the same slot stay in
registration order.

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
