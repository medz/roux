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
