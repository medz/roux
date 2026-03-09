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

Method-specific routes use `method:` on `add`, `addAll`, `match`, and
`matchAll`.

## Route Patterns

Supported route shapes:

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
- `roux` routes pathnames only. It does not parse `protocol`, `hostname`,
  `search`, or `hash`.

## Input Processing

Path preprocessing is conservative by default:

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

- `caseSensitive: false` ignores case for static and compiled matching while
  preserving original parameter values.
- `decodePath: true` decodes `%xx` sequences before matching. Invalid encodings
  fail closed and return no match.
- `normalizePath: true` collapses repeated `/`, removes `.` segments, resolves
  `..`, and rejects paths that would escape above `/`.

Lookup processing order:

1. URL decoding, if enabled
2. Path normalization, if enabled
3. Route matching

Because decoding runs first, `decodePath: true` can change segment boundaries.
For example, `/a%2Fb` becomes `/a/b` before matching.

`match(...)` priority is path-dependent, but the broad rules are:

- Exact static routes win first.
- Structured dynamic routes participate in single-match precedence too. This
  includes embedded patterns, regex params, grouped patterns, optional
  segments, and repeated segments.
- Regex and shell-style structured patterns can beat plain `:param` routes.
- Plain `:param` routes beat single-segment wildcards.
- Single-segment wildcards beat remainder wildcards.
- Global fallback is always last.

Examples:

- `/users/:id(\\d+)` beats `/users/:id` for `/users/42`.
- `/files/file-*.png` beats `/files/:name.:ext` for `/files/file-a.png`.
- `/users/:id` beats `/users{/:id}?` for `/users/42`.

`matchAll(...)` order is always less specific to more specific. Broadly:

- remainder routes
- single-segment dynamic routes
- structured dynamic routes, including embedded, regex, grouped, optional, and
  repeated patterns
- exact static routes

## Differences from URLPattern

- `roux` routes pathname only. There is no `protocol`, `hostname`, `port`,
  `search`, `hash`, or `baseURL` matching.
- Patterns must start with `/`.
- `*` matches exactly one segment. `**` and `**:name` match the remaining path.
  This differs from `URLPattern`, where `*` is more permissive.
- URL decoding is configurable and off by default with `decodePath: false`.
- Path normalization is configurable and off by default with
  `normalizePath: false`.
- Case sensitivity is configurable through `caseSensitive`.
- Trailing slash on lookup input is ignored, so `/users` and `/users/` match
  the same route.

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
