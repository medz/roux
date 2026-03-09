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
    '/users/*': 'users-one-segment',
    '/users/**:wildcard': 'users-wildcard',
    '/**:wildcard': 'global-fallback',
  },
);

final match = router.match('/users/123');
print(match?.data);   // users-id
print(match?.params); // {id: 123}

final stack = router.matchAll('/users/123');
print(
  stack.map((match) => match.data),
); // (global-fallback, users-wildcard, users-id, users-one-segment)
```

## Duplicate Policy

Duplicate route handling is configurable at both router and call level:

```dart
final router = Router<String>(
  duplicatePolicy: DuplicatePolicy.replace,
  caseSensitive: false,
  decodePath: true,
  normalizePath: true,
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
router.add('/**:wildcard', 'global-logger');
router.add('/**:wildcard', 'root-scope-middleware');

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
- Single-segment wildcard: `/users/*`
- Embedded wildcard: `/files/file-*.png`, `/files/*.:ext`
- Named repeated param: `/files/:path+`, `/files/:path*`
- Named regex param: `/users/:id(\\d+)`
- Embedded params: `/files/:name.:ext`
- Group syntax: `/foo{bar}`, `/book{s}?`, `/users{/:id}?`
- Double wildcard tail: `/users/**:wildcard`
- Global fallback: `/**:wildcard`

Notes:
- Paths must start with `/`.
- `*` matches exactly one segment.
- `**` and `**:name` match the remaining path and must be the final segment.
- Trailing slash on input is ignored (`/users` equals `/users/`).
- You can register routes via constructor (`Router(routes: {...})`) or
  incrementally (`add` / `addAll`).

## Input Options

Input preprocessing is conservative by default:

```dart
final router = Router<String>(
  caseSensitive: true,
  decodePath: false,
  normalizePath: false,
);
```

- `caseSensitive: true` keeps path matching case-sensitive.
- `decodePath: false` keeps `%xx` sequences untouched.
- `normalizePath: false` keeps repeated `/`, `.` and `..` untouched.

When enabled:

- `caseSensitive: false` ignores casing for static and pattern matching while
  preserving original parameter values.
- `decodePath: true` decodes `%xx` sequences before matching. Invalid encodings
  fail closed and return no match.
- `normalizePath: true` collapses repeated `/`, removes `.` segments, resolves
  `..`, and rejects paths that would escape above `/`.

Processing order for lookups is:

1. URL decoding, if enabled
2. Path normalization, if enabled
3. Route matching

This means `decodePath: true` can change segment boundaries. For example,
`/a%2Fb` becomes `/a/b` before matching.

## Matching Order

For `match(...)`:

1. Exact route (`/users/all`)
2. Parameter route (`/users/:id`)
3. Single-segment wildcard (`/users/*`)
4. Double wildcard route (`/users/**:wildcard`)
5. Global fallback (`/**:wildcard`)

For `matchAll(...)`:

`matchAll(...)` returns every matching route from less specific to more
specific using an explicit specificity sort:

1. Remainder routes (`/**:wildcard`, `/files/:path*`, `/files/:path+`)
2. Single-segment dynamic routes (`/users/:id`, `/users/*`)
3. Structured dynamic routes (`/files/:name.:ext`, `/book{s}?`, `/foo{bar}`)
4. Exact static routes (`/users/all`)

At the same specificity level, shallower routes come first, then routes with
less literal structure, then routes with fewer extra constraints. When a
`method` is provided, both `ANY` and exact-method entries participate, with
`ANY` ordered first at the same specificity. When duplicate slots are retained
via `DuplicatePolicy.append`, entries from the same slot stay in registration
order.

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
