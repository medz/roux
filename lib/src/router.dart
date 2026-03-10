import 'route_path.dart';
import 'pattern_engine.dart';
import 'route_model.dart';
import 'trie_engine.dart';

/// Public facade for pathname route registration and lookup.
class Router<T> {
  /// Creates a router with duplicate, case, decode, and normalization options.
  Router({
    Map<String, T>? routes,
    DuplicatePolicy duplicatePolicy = DuplicatePolicy.reject,
    bool caseSensitive = true,
    bool decodePath = false,
    bool normalizePath = false,
  }) : _duplicatePolicy = duplicatePolicy,
       _caseSensitive = caseSensitive,
       _decodePath = decodePath,
       _normalizePath = normalizePath,
       _sharedRoutes = RouteSet(caseSensitive) {
    if (routes != null && routes.isNotEmpty) addAll(routes);
  }

  final RouteSet<T> _sharedRoutes;
  final _methodRoutes = MethodTable<T>();
  final DuplicatePolicy _duplicatePolicy;
  final bool _caseSensitive, _decodePath, _normalizePath;
  bool _hasSharedRoutes = false;
  int _nextRegistrationOrder = 0;

  /// Registers a single route.
  void add(
    String path,
    T data, {
    String? method,
    DuplicatePolicy? duplicatePolicy,
  }) {
    if (method == null) {
      _hasSharedRoutes = true;
    }
    _routeSetFor(method).addRoute(
      path,
      data,
      duplicatePolicy ?? _duplicatePolicy,
      _nextRegistrationOrder++,
    );
  }

  /// Registers multiple routes with shared options.
  void addAll(
    Map<String, T> routes, {
    String? method,
    DuplicatePolicy? duplicatePolicy,
  }) {
    if (method == null && routes.isNotEmpty) _hasSharedRoutes = true;
    final routeSet = _routeSetFor(method);
    final policy = duplicatePolicy ?? _duplicatePolicy;
    for (final entry in routes.entries) {
      routeSet.addRoute(
        entry.key,
        entry.value,
        policy,
        _nextRegistrationOrder++,
      );
    }
  }

  /// Returns the best match for [path].
  RouteMatch<T>? match(String path, {String? method}) {
    if (!_hasSharedRoutes && !_decodePath) {
      RouteSet<T>? routeSet;
      if (method != null) {
        final commonIndex = commonMethodIndex(method);
        if (commonIndex >= 0) {
          routeSet = _methodRoutes.commonRoutes[commonIndex];
        }
      }
      if (routeSet != null && !routeSet.needsStrictPathValidation) {
        if (path.isEmpty || path.codeUnitAt(0) != slashCode) return null;
        if (!_normalizePath) {
          final last = path.length - 1;
          if (path.length > 1 &&
              path.codeUnitAt(last) == slashCode &&
              path.codeUnitAt(last - 1) != slashCode) {
            path = path.substring(0, last);
          }
          return routeSet.matchBest(path);
        }
        if (routeSet.canMatchBestNormalized ||
            routeSet.canMatchExactNormalized) {
          return routeSet.matchBestNormalized(path);
        }
        final normalized = normalizeRoutePath(path);
        return normalized == null ? null : routeSet.matchBest(normalized);
      }
    }
    final routeSet = method == null ? null : _methodRoutes.lookupMethod(method);
    final strict =
        _sharedRoutes.needsStrictPathValidation ||
        (routeSet?.needsStrictPathValidation ?? false);
    final normalized = _preparePath(path, strict);
    if (normalized == null) return null;
    return routeSet?.matchBest(normalized) ??
        _sharedRoutes.matchBest(normalized);
  }

  /// Returns every match for [path] from broadest to most specific.
  List<RouteMatch<T>> matchAll(String path, {String? method}) {
    final routeSet = method == null ? null : _methodRoutes.lookupMethod(method);
    final strict =
        _sharedRoutes.needsStrictPathValidation ||
        (routeSet?.needsStrictPathValidation ?? false);
    final normalized = _preparePath(path, strict);
    if (normalized == null) {
      return [];
    }
    final collected = MatchAccumulator<T>(
      routeSet != null || _sharedRoutes.needsSpecificitySort,
    );
    _sharedRoutes.collectMatches(normalized, 0, collected);
    if (routeSet != null) routeSet.collectMatches(normalized, 1, collected);
    return collected.matches;
  }

  RouteSet<T> _routeSetFor(String? method) => method == null
      ? _sharedRoutes
      : _methodRoutes.forWriteMethod(method, _caseSensitive);

  /// Applies decode and normalization options to an input path.
  String? _preparePath(String path, bool strict) {
    if (!_decodePath && !_normalizePath) {
      if (!path.startsWith('/')) return null;
      if (!strict) return trimTrailingSlash(path);
      final trimmed = trimTrailingSlash(path);
      return containsEmptySegments(trimmed) ? null : trimmed;
    }
    if (_decodePath && path.contains('%')) {
      try {
        path = Uri.decodeFull(path);
      } on ArgumentError {
        return null;
      }
    }
    final normalized = _normalizePath
        ? normalizeRoutePath(path)
        : path.startsWith('/')
        ? trimTrailingSlash(path)
        : null;
    if (normalized == null || !strict) return normalized;
    return containsEmptySegments(normalized) ? null : normalized;
  }
}

/// Stores the simple trie and compiled pattern engines for one method bucket.
class RouteSet<T> {
  /// Creates an empty route set.
  RouteSet(bool caseSensitive)
    : simple = TrieEngine(caseSensitive),
      patterns = PatternEngine(caseSensitive);

  static const int _hybridMode = 0, _simpleMode = 1, _straightMode = 2;

  /// The trie engine for exact and segment-level routes.
  final TrieEngine<T> simple;

  /// The compiled matcher for richer pathname syntax.
  final PatternEngine<T> patterns;
  int _matchMode = _straightMode;

  /// Whether collected matches must be sorted by specificity.
  bool get needsSpecificitySort =>
      simple.hasBranchingChoices ||
      simple.root.paramChild != null ||
      patterns.hasRoutes;

  /// Whether the route set requires strict path validation.
  bool get needsStrictPathValidation =>
      simple.needsStrictPathValidation || patterns.hasRoutes;

  /// Whether normalized matching can stay on the straight fast path.
  bool get canMatchBestNormalized =>
      _matchMode == _straightMode &&
      !patterns.hasRoutes &&
      simple.canMatchStraightNormalized;

  /// Whether normalized matching can use exact lookup only.
  bool get canMatchExactNormalized =>
      !patterns.hasRoutes &&
      simple.exactRoutes.isNotEmpty &&
      !simple.hasBranchingChoices &&
      simple.root.paramChild == null &&
      simple.root.wildcardRoute == null &&
      simple.globalFallback == null;

  /// Adds a route to the route set.
  void addRoute(
    String patternPath,
    T data,
    DuplicatePolicy duplicatePolicy,
    int registrationOrder,
  ) {
    if (!patternPath.startsWith('/')) {
      throw FormatException('Route pattern must start with "/": $patternPath');
    }

    final normalized = trimTrailingSlash(patternPath);
    if (simple.add(normalized, data, duplicatePolicy, registrationOrder)) {
      _refreshMatchMode();
      return;
    }
    patterns.add(normalized, data, duplicatePolicy, registrationOrder);
    _refreshMatchMode();
  }

  /// Returns the highest-priority match for a normalized path.
  RouteMatch<T>? matchBest(String normalized) {
    switch (_matchMode) {
      case _straightMode:
        return simple.matchStraight(normalized);
      case _simpleMode:
        final exact = simple.matchExact(normalized);
        if (exact != null) return exact;
        return simple.match(normalized, true);
    }
    final exact = simple.matchExact(normalized);
    if (exact != null) return exact;
    return patterns.matchBucket(compiledBucketHigh, normalized) ??
        simple.match(normalized, false) ??
        patterns.matchBucket(compiledBucketLate, normalized) ??
        patterns.matchBucket(compiledBucketRepeated, normalized) ??
        simple.match(normalized, true) ??
        patterns.matchBucket(compiledBucketDeferred, normalized) ??
        (simple.globalFallback == null
            ? null
            : simple.materialize(simple.globalFallback!, normalized, null, 1));
  }

  /// Returns the highest-priority match for a path that may need normalization.
  RouteMatch<T>? matchBestNormalized(String path) {
    if (!canMatchExactNormalized) return simple.matchStraightNormalized(path);
    final normalized = normalizeRoutePath(path);
    return normalized == null
        ? null
        : simple.exactRoutes[normalized]?.noParamsMatch;
  }

  /// Refreshes the internal matching strategy after route changes.
  void _refreshMatchMode() {
    _matchMode = patterns.hasRoutes || simple.globalFallback != null
        ? _hybridMode
        : simple.exactRoutes.isEmpty && !simple.hasBranchingChoices
        ? _straightMode
        : _simpleMode;
  }

  /// Collects every match for a normalized path.
  void collectMatches(
    String normalized,
    int methodRank,
    MatchAccumulator<T> output,
  ) {
    final fallback = simple.globalFallback;
    if (fallback != null) {
      simple.collectSlot(fallback, normalized, null, 1, methodRank, output);
    }
    patterns.collectBucket(
      compiledBucketRepeated,
      normalized,
      methodRank,
      output,
    );
    simple.collect(normalized, methodRank, output);
    patterns.collectBucket(compiledBucketHigh, normalized, methodRank, output);
    patterns.collectBucket(compiledBucketLate, normalized, methodRank, output);
    if (simple.exactRoutes.isNotEmpty) {
      final exact = simple
          .exactRoutes[canonicalizeRoutePath(normalized, simple.caseSensitive)];
      if (exact != null) {
        simple.collectSlot(exact, normalized, null, 0, methodRank, output);
      }
    }
    patterns.collectBucket(
      compiledBucketDeferred,
      normalized,
      methodRank,
      output,
    );
  }
}

/// Stores shared and per-method route sets.
class MethodTable<T> {
  /// Slots for common HTTP methods.
  final commonRoutes = List<RouteSet<T>?>.filled(7, null);

  /// Lazily allocated route sets for uncommon HTTP methods.
  final extraRoutes = <String, RouteSet<T>>{};

  /// Returns the route set used when registering [method].
  RouteSet<T> forWriteMethod(String method, bool caseSensitive) {
    final normalized = canonicalizeMethod(method);
    final commonIndex = commonMethodIndex(normalized);
    if (commonIndex >= 0) {
      return commonRoutes[commonIndex] ??= RouteSet(caseSensitive);
    }
    return extraRoutes.putIfAbsent(normalized, () => RouteSet(caseSensitive));
  }

  /// Returns the route set used when matching [method].
  RouteSet<T>? lookupMethod(String method) {
    final normalized = canonicalizeMethod(method);
    final commonIndex = commonMethodIndex(normalized);
    return commonIndex >= 0
        ? commonRoutes[commonIndex]
        : extraRoutes[normalized];
  }
}

/// Maps common HTTP methods to their fixed route-set slots.
int commonMethodIndex(String method) {
  return switch (method) {
    'GET' => 0,
    'POST' => 1,
    'PUT' => 2,
    'PATCH' => 3,
    'DELETE' => 4,
    'HEAD' => 5,
    'OPTIONS' => 6,
    _ => -1,
  };
}

/// Normalizes an HTTP method name for lookup and registration.
String canonicalizeMethod(String method) {
  final normalized = method.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(method, 'method', 'Method must not be empty.');
  }
  return normalized.toUpperCase();
}
