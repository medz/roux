## 1.0.0

### Breaking Changes

- Simplify the public router API around `add`, `find`, `findAll`, and `remove`.
- Remove constructor `routes`, `addAll`, `match`, and `matchAll`.
- Remove `DuplicatePolicy` and appended duplicate-route retention. Registering the same method/path shape now replaces the previous route in that slot.
- Remove configurable `decodePath` and `normalizePath`. Path normalization is now always applied during registration and lookup, while percent-encoded bytes are matched literally and are not URI-decoded.
- Change the default matching mode to case-insensitive. Use `Router(caseSensitive: true)` for strict matching.
- Make `RouteMatch.params` non-nullable. Routes without params now return an empty map instead of `null`.
- Narrow `findAll(...)` to the selected method bucket. Exact-method matches no longer include method-agnostic entries in the same result list.

### Migration Guide

#### API Renames

From 0.5.0:

```dart
final router = Router<String>(
  routes: {'/users/:id': 'user'},
);

final match = router.match('/users/42', method: 'GET');
final matches = router.matchAll('/users/42', method: 'GET');
```

To 1.0.0:

```dart
final router = Router<String>();
router.add('/users/:id', 'user', method: 'GET');

final match = router.find('/users/42', method: 'GET');
final matches = router.findAll('/users/42', method: 'GET');
```

- Replace `match(...)` with `find(...)`.
- Replace `matchAll(...)` with `findAll(...)`.
- Replace constructor `routes:` with repeated `add(...)` calls.
- Replace `addAll(...)` with repeated `add(...)` calls.

#### Duplicate Routes

0.5.0 exposed `DuplicatePolicy` and could retain multiple handlers in the same
normalized route slot.

1.0.0 removes that configuration entirely. If you register the same method/path
shape again, the later route replaces the previous one in that slot.

If you relied on appended duplicates such as middleware-like stacking in one
slot, move those handlers into distinct route patterns or compose them outside
the router.

#### Path Processing

0.5.0:

- `decodePath` and `normalizePath` were configurable.
- `match('/a//b')` could fail when normalization was disabled.
- `decodePath: true` could turn `%2F` into `/` before matching.

1.0.0:

- Path normalization is always on for registration and lookup.
- Leading slash, trailing slash, repeated `/`, `.` and `..` are normalized.
- Percent-encoded bytes are matched literally and are never URI-decoded.

Examples:

```dart
final router = Router<String>();
router.add('users/:id', 'user');
router.add('/caf%C3%A9', 'cafe');

router.find('/users/42');   // matches
router.find('/users/./42'); // matches
router.find('/caf%C3%A9');  // matches
router.find('/café');       // does not match
```

#### Case Sensitivity

0.5.0 defaulted to `caseSensitive: true`.

1.0.0 defaults to `caseSensitive: false`.

To preserve 0.5.0 behavior, construct the router explicitly:

```dart
final router = Router<String>(caseSensitive: true);
```

#### RouteMatch.params

0.5.0:

```dart
if (match?.params == null) {
  // no params
}
```

1.0.0:

```dart
if (match != null && match.params.isEmpty) {
  // no params
}
```

`params` is now always a mutable `Map<String, String>`.

#### `findAll(...)` Method Behavior

0.5.0 `matchAll(path, method: 'GET')` could collect both:

- method-agnostic matches
- exact `GET` matches

1.0.0 `findAll(path, method: 'GET')` returns only the selected method bucket.

If you relied on combined `ANY + exact-method` collection, you now need to
query both buckets explicitly in application code.

### Features

- Add `Cache<T>` and `LRUCache<T>` for optional lookup memoization.
- Support unnamed regex groups such as `/path/(\\d+)` and `/path/(\\d+)/(\\w+)`.
- Normalize missing leading slashes and trailing slashes during both registration and lookup.
- Normalize repeated `/`, `.` and `..` segments during both registration and lookup.
- Match literal percent-encoded static paths without URI decoding, such as `/caf%C3%A9`.

### Improvements

- Rewrite the router core around a smaller node model and direct route operations, replacing the previous `RouteSet` / `PatternEngine` / `TrieEngine` split.
- Reduce library size substantially while keeping the current pathname syntax surface.
- Rewrite the test suite and README to reflect the current API and matching behavior.

## 0.5.0

### Breaking Changes

- Pathname syntax is expanded and aligned around the new route model.
- `*` now means a single-segment wildcard. Multi-segment remainder matching is
  represented with `**` / `**:name`.
- The router core is reorganized around `RouteSet`, `MethodTable`,
  `TrieEngine`, and `PatternEngine`.
- Legacy benchmark scripts were replaced by the current feature-based benchmark
  suite.

### Features

- Add embedded pathname params such as `/files/:name.:ext`.
- Add embedded wildcard segments such as `/files/file-*.png`.
- Add regex params such as `/users/:id(\d+)`.
- Add optional params and grouped pathname syntax such as `:id?`, `/book{s}?`,
  and `/users{/:id}?`.
- Add repeated params such as `:path+` and `:path*`.
- Add configurable input processing with `caseSensitive`, `decodePath`, and
  `normalizePath`.
- Add explicit `matchAll(...)` specificity ordering and feature-focused
  benchmark suites.

### Fixes

- Correct grouped and compiled route precedence in `match(...)` /
  `matchAll(...)`.
- Reject duplicate capture names consistently across trie and compiled routes.
- Keep regex quantifiers such as `\d{2}` from being misclassified as grouped
  pathname syntax.
- Harden benchmark argument validation and execution checks.

### Performance

- Replace lazy params with eager materialization and keep dynamic lookup
  performance competitive under fairer benchmark contracts.
- Improve normalized lookup throughput with specialized normalization and dirty
  path handling.
- Restore strong lookup performance in the official relic-style benchmark
  scenarios.

## 0.4.0

### Features

- Add `DuplicatePolicy.append` so a normalized route slot can retain multiple
  handlers in registration order.
- `Router.matchAll(...)` now expands appended entries from the same slot while
  keeping deterministic route priority ordering.

### Fixes

- `matchAll(...)` now snapshots captured params before backtracking so lazy
  parameter materialization stays stable for every collected match.
- Lookup normalization now rejects interior empty path segments such as
  `"/users//42"` instead of letting fallback wildcards match them.

### Performance

- Reduced matcher hot-path overhead by removing recursive traversal and
  streamlining slot collection/materialization.
- Improved `matchAll(...)` throughput across static, dynamic, and appended-route
  scenarios with dedicated benchmarks.

## 0.3.0

### Features

- Add `Router.matchAll(...)` to collect every matching route in deterministic
  less-specific-to-more-specific order.
- Method-aware multi-match lookups now include both `ANY` and exact-method
  matches, with `ANY` ordered first at the same scope.
- Add configurable duplicate route registration via `DuplicatePolicy.reject`,
  `DuplicatePolicy.replace`, `DuplicatePolicy.keepFirst`, and
  `DuplicatePolicy.append`.
- Duplicate slots retained with `DuplicatePolicy.append` now preserve
  registration order in `matchAll(...)`, while `match(...)` continues to
  return the first retained entry in the winning slot.

## 0.2.0

### Breaking Changes

- Router core is rebooted around `Router<T>` and trie-based matching internals.
- Legacy function-style APIs are removed in favor of `Router` methods.
- Method-aware routing is introduced via `add` / `addAll` / `match` optional `method`.

### Features

- Route registration supports constructor `routes`, incremental `add`, and batch `addAll`.
- Matching precedence is deterministic: static > param > wildcard > global fallback.
- Parameters and wildcard values are materialized lazily to reduce lookup allocations.

### Performance

- New benchmark matrix compares lookup latency across static/dynamic and hot/round-robin scenarios.
- Added relic-style benchmark and single-route add benchmark for fairer cross-router comparison.

### Documentation

- Added inline implementation comments for router hot paths and internal structures.

## 0.1.1

### Features

- Add a runnable `example/main.dart` showcasing router setup and matching.

## 0.1.0

### Features

- Rebranded as Roux with refreshed documentation and examples.
- Function-based routing API (createRouter, addRoute, findRoute, findAllRoutes, removeRoute, routeToRegExp).
- Comprehensive test suite for routing operations.
- Benchmarks for route matching.

### Documentation

- README redesigned with clearer installation and usage guidance.

### Continuous Integration

- GitHub Actions workflow updated for testing.

### Chore

- Project versioning, dependencies, and build configuration updated.
