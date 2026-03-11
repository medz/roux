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
