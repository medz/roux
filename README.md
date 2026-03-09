# roux

[![Pub Version](https://img.shields.io/pub/v/roux?logo=dart)](https://pub.dev/packages/roux)
[![Test](https://github.com/medz/roux/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/medz/roux/actions/workflows/test.yml)

Lightweight, fast router for Dart with rou3-style pathname syntax.

`roux` focuses on pathname routing. It supports exact routes, named params,
single-segment wildcards, remainder wildcards, embedded segment patterns,
group syntax, and configurable input preprocessing.

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

Register incrementally:

```dart
final router = Router<String>();

router.add('/posts', 'posts');
router.add('/posts/:id', 'post-detail');
router.add('/posts/**:rest', 'post-fallback');
```

Method-specific routes are supported through `method:` on `add`, `addAll`,
`match`, and `matchAll`.

## Pathname Syntax

The router accepts the following route shapes:

| Syntax | Meaning | Example |
| --- | --- | --- |
| `/users/all` | Exact static route | `/users/all` |
| `/users/:id` | Named single-segment param | `/users/:id` |
| `/users/*` | Single-segment wildcard | `/users/*` |
| `/users/**:rest` | Named remainder wildcard | `/users/**:rest` |
| `/users/**` | Unnamed remainder wildcard | `/users/**` |
| `/files/:name.:ext` | Embedded params inside one segment | `/files/:name.:ext` |
| `/files/file-*.png` | Embedded wildcard inside one segment | `/files/file-*.png` |
| `/users/:id(\\d+)` | Named regex param | `/users/:id(\\d+)` |
| `/users/:id?` | Optional param segment | `/users/:id?` |
| `/files/:path+` | One-or-more repeated segments | `/files/:path+` |
| `/files/:path*` | Zero-or-more repeated segments | `/files/:path*` |
| `/foo{bar}` | Mandatory non-capturing group | `/foo{bar}` |
| `/book{s}?` | Optional non-capturing group | `/book{s}?` |
| `/users{/:id}?` | Optional grouped suffix | `/users{/:id}?` |
| `/blog/:id(\\d+){-:title}?` | Mixed params, regex, and optional group | `/blog/:id(\\d+){-:title}?` |

Rules:

- Route patterns must start with `/`.
- `*` matches exactly one segment.
- `**` and `**:name` match the remaining path and must be the final segment.
- Trailing slash on lookup input is ignored, so `/users` and `/users/` match
  the same route.
- `roux` routes pathnames only. It does not parse `protocol`, `hostname`,
  `search`, or `hash`.

## Input Options

Input preprocessing is conservative by default:

```dart
final router = Router<String>(
  caseSensitive: true,
  decodePath: false,
  normalizePath: false,
);
```

| Option | Default | Effect |
| --- | --- | --- |
| `caseSensitive` | `true` | Match paths with case sensitivity. |
| `decodePath` | `false` | Leave `%xx` sequences untouched. |
| `normalizePath` | `false` | Leave repeated `/`, `.` and `..` untouched. |

When enabled:

- `caseSensitive: false` ignores case for static and compiled matching while
  preserving original parameter values.
- `decodePath: true` decodes `%xx` sequences before matching. Invalid encodings
  fail closed and return no match.
- `normalizePath: true` collapses repeated `/`, removes `.` segments, resolves
  `..`, and rejects paths that would escape above `/`.

Lookup processing order is:

1. URL decoding, if enabled
2. Path normalization, if enabled
3. Route matching

Because decoding runs first, `decodePath: true` can change segment boundaries.
For example, `/a%2Fb` becomes `/a/b` before matching.

## Matching Behavior

For `match(...)`, `roux` returns the highest-priority route:

1. Exact route
2. Parameter route
3. Single-segment wildcard
4. Double wildcard route
5. Global fallback

For `matchAll(...)`, `roux` returns every matching route from less specific to
more specific:

1. Remainder routes like `/**:wildcard`, `/files/:path*`, `/files/:path+`
2. Single-segment dynamic routes like `/users/:id`, `/users/*`
3. Structured dynamic routes like `/files/:name.:ext`, `/book{s}?`,
   `/foo{bar}`
4. Exact static routes like `/users/all`

At the same specificity level:

- Shallower routes come first.
- Routes with less literal structure come first.
- Routes with fewer extra constraints come first.
- `ANY` method routes come before exact-method routes.
- Entries retained through `DuplicatePolicy.append` stay in registration order
  inside the same slot.

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

- `DuplicatePolicy.reject` throws on duplicate route shapes.
- `DuplicatePolicy.replace` keeps the latest retained entry.
- `DuplicatePolicy.keepFirst` keeps the earliest retained entry.
- `DuplicatePolicy.append` retains all entries in registration order.

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
