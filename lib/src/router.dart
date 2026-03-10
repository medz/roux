import 'route_path.dart';
import 'pattern_engine.dart';
import 'route_model.dart';
import 'trie_engine.dart';

class Router<T> {
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
  final bool _caseSensitive;
  final bool _decodePath;
  final bool _normalizePath;
  bool _hasSharedRoutes = false;
  int _nextRegistrationOrder = 0;

  void add(
    String path,
    T data, {
    String? method,
    DuplicatePolicy? duplicatePolicy,
  }) {
    if (method == null) _hasSharedRoutes = true;
    _routeSetFor(method).addRoute(
      path,
      data,
      duplicatePolicy ?? _duplicatePolicy,
      _nextRegistrationOrder++,
    );
  }

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

  RouteMatch<T>? match(String path, {String? method}) {
    if (!_hasSharedRoutes && !_decodePath) {
      RouteSet<T>? routeSet;
      if (method != null) {
        final commonIndex = commonMethodIndex(method);
        if (commonIndex >= 0)
          routeSet = _methodRoutes.commonRoutes[commonIndex];
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
    if (normalized == null) {
      return null;
    }
    return routeSet?.matchBest(normalized) ??
        _sharedRoutes.matchBest(normalized);
  }

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
      routeSet != null ||
          _sharedRoutes.needsSpecificitySort ||
          routeSet?.needsSpecificitySort == true,
    );
    _sharedRoutes.collectMatches(normalized, 0, collected);
    if (routeSet != null) routeSet.collectMatches(normalized, 1, collected);
    return collected.matches;
  }

  RouteSet<T> _routeSetFor(String? method) => method == null
      ? _sharedRoutes
      : _methodRoutes.forWriteMethod(method, _caseSensitive);

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
        : sanitizeRoutePath(path);
    if (normalized == null || !strict) return normalized;
    return containsEmptySegments(normalized) ? null : normalized;
  }
}

class RouteSet<T> {
  RouteSet(bool caseSensitive)
    : simple = TrieEngine(caseSensitive),
      patterns = PatternEngine(caseSensitive);

  static const int _hybridMode = 0, _simpleMode = 1, _straightMode = 2;

  final TrieEngine<T> simple;
  final PatternEngine<T> patterns;
  int _matchMode = _straightMode;

  bool get needsSpecificitySort =>
      simple.hasBranchingChoices ||
      simple.root.paramChild != null ||
      patterns.hasRoutes;

  bool get needsStrictPathValidation =>
      simple.needsStrictPathValidation || patterns.hasRoutes;

  bool get canMatchBestNormalized =>
      _matchMode == _straightMode &&
      !patterns.hasRoutes &&
      simple.canMatchStraightNormalized;

  bool get canMatchExactNormalized =>
      !patterns.hasRoutes &&
      simple.exactRoutes.isNotEmpty &&
      !simple.hasBranchingChoices &&
      simple.root.paramChild == null &&
      simple.root.wildcardRoute == null &&
      simple.globalFallback == null;

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

  RouteMatch<T>? matchBestNormalized(String path) => canMatchExactNormalized
      ? simple.matchExactNormalized(path)
      : simple.matchStraightNormalized(path);

  void _refreshMatchMode() {
    if (patterns.hasRoutes || simple.globalFallback != null) {
      _matchMode = _hybridMode;
      return;
    }
    _matchMode = simple.exactRoutes.isEmpty && !simple.hasBranchingChoices
        ? _straightMode
        : _simpleMode;
  }

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
    simple.collectExact(normalized, methodRank, output);
    patterns.collectBucket(
      compiledBucketDeferred,
      normalized,
      methodRank,
      output,
    );
  }
}

class MethodTable<T> {
  final commonRoutes = List<RouteSet<T>?>.filled(7, null);
  Map<String, RouteSet<T>>? extraRoutes;

  RouteSet<T> forWriteMethod(String method, bool caseSensitive) {
    final normalized = canonicalizeMethod(method);
    final commonIndex = commonMethodIndex(normalized);
    if (commonIndex >= 0) {
      return commonRoutes[commonIndex] ??= RouteSet(caseSensitive);
    }
    return (extraRoutes ??= {}).putIfAbsent(
      normalized,
      () => RouteSet(caseSensitive),
    );
  }

  RouteSet<T>? lookupMethod(String method) {
    final normalized = canonicalizeMethod(method);
    final commonIndex = commonMethodIndex(normalized);
    return commonIndex >= 0
        ? commonRoutes[commonIndex]
        : extraRoutes?[normalized];
  }
}

int commonMethodIndex(String method) {
  switch (method.length) {
    case 3:
      if (method.codeUnitAt(0) == 71 &&
          method.codeUnitAt(1) == 69 &&
          method.codeUnitAt(2) == 84) {
        return 0;
      }
      if (method.codeUnitAt(0) == 80 &&
          method.codeUnitAt(1) == 85 &&
          method.codeUnitAt(2) == 84) {
        return 2;
      }
    case 4:
      if (method.codeUnitAt(0) == 80 &&
          method.codeUnitAt(1) == 79 &&
          method.codeUnitAt(2) == 83 &&
          method.codeUnitAt(3) == 84) {
        return 1;
      }
      if (method.codeUnitAt(0) == 72 &&
          method.codeUnitAt(1) == 69 &&
          method.codeUnitAt(2) == 65 &&
          method.codeUnitAt(3) == 68) {
        return 5;
      }
    case 5:
      if (method.codeUnitAt(0) == 80 &&
          method.codeUnitAt(1) == 65 &&
          method.codeUnitAt(2) == 84 &&
          method.codeUnitAt(3) == 67 &&
          method.codeUnitAt(4) == 72) {
        return 3;
      }
    case 6:
      if (method.codeUnitAt(0) == 68 &&
          method.codeUnitAt(1) == 69 &&
          method.codeUnitAt(2) == 76 &&
          method.codeUnitAt(3) == 69 &&
          method.codeUnitAt(4) == 84 &&
          method.codeUnitAt(5) == 69) {
        return 4;
      }
    case 7:
      if (method.codeUnitAt(0) == 79 &&
          method.codeUnitAt(1) == 80 &&
          method.codeUnitAt(2) == 84 &&
          method.codeUnitAt(3) == 73 &&
          method.codeUnitAt(4) == 79 &&
          method.codeUnitAt(5) == 78 &&
          method.codeUnitAt(6) == 83) {
        return 6;
      }
  }
  return -1;
}

String canonicalizeMethod(String method) {
  final normalized = method.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(method, 'method', 'Method must not be empty.');
  }
  return normalized.toUpperCase();
}
