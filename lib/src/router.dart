export 'route_model.dart' show DuplicatePolicy, RouteMatch;

import 'route_path.dart';
import 'pattern_engine.dart';
import 'route_model.dart';
import 'simple_engine.dart';

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
       _sharedRoutes = RouteSet<T>(caseSensitive) {
    if (routes != null && routes.isNotEmpty) addAll(routes);
  }

  final RouteSet<T> _sharedRoutes;
  final MethodTable<T> _methodRoutes = MethodTable<T>();
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
    if (!_hasSharedRoutes && !_decodePath && !_normalizePath) {
      RouteSet<T>? routeSet;
      switch (method) {
        case 'GET':
          routeSet = _methodRoutes.commonRoutes[0];
        case 'POST':
          routeSet = _methodRoutes.commonRoutes[1];
        case 'PUT':
          routeSet = _methodRoutes.commonRoutes[2];
        case 'PATCH':
          routeSet = _methodRoutes.commonRoutes[3];
        case 'DELETE':
          routeSet = _methodRoutes.commonRoutes[4];
        case 'HEAD':
          routeSet = _methodRoutes.commonRoutes[5];
        case 'OPTIONS':
          routeSet = _methodRoutes.commonRoutes[6];
      }
      if (routeSet != null && !routeSet.needsStrictPathValidation) {
        if (path.isEmpty || path.codeUnitAt(0) != slashCode) return null;
        final last = path.length - 1;
        if (path.length > 1 &&
            path.codeUnitAt(last) == slashCode &&
            path.codeUnitAt(last - 1) != slashCode) {
          path = path.substring(0, last);
        }
        return routeSet.matchBest(path);
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
      return <RouteMatch<T>>[];
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
      if (path.isEmpty || path.codeUnitAt(0) != slashCode) return null;
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
    : simple = SimpleEngine<T>(caseSensitive),
      patterns = PatternEngine<T>(caseSensitive);

  static const int _hybridMode = 0, _simpleMode = 1, _straightMode = 2;

  final SimpleEngine<T> simple;
  final PatternEngine<T> patterns;
  int _matchMode = _straightMode;

  bool get needsSpecificitySort =>
      simple.hasBranchingChoices ||
      simple.root.paramChild != null ||
      patterns.hasRoutes;

  bool get needsStrictPathValidation =>
      simple.needsStrictPathValidation || patterns.hasRoutes;

  void addRoute(
    String patternPath,
    T data,
    DuplicatePolicy duplicatePolicy,
    int registrationOrder,
  ) {
    if (patternPath.isEmpty || patternPath.codeUnitAt(0) != slashCode) {
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
  final List<RouteSet<T>?> commonRoutes = List<RouteSet<T>?>.filled(7, null);
  Map<String, RouteSet<T>>? extraRoutes;

  RouteSet<T> forWriteMethod(String method, bool caseSensitive) {
    final commonIndex = commonMethodIndex(method);
    if (commonIndex >= 0) {
      return commonRoutes[commonIndex] ??= RouteSet<T>(caseSensitive);
    }
    final (index, normalized) = classifyMethod(method);
    if (index >= 0) {
      return commonRoutes[index] ??= RouteSet<T>(caseSensitive);
    }
    return (extraRoutes ??= <String, RouteSet<T>>{}).putIfAbsent(
      normalized!,
      () => RouteSet<T>(caseSensitive),
    );
  }

  RouteSet<T>? lookupMethod(String method) {
    final commonIndex = commonMethodIndex(method);
    if (commonIndex >= 0) return commonRoutes[commonIndex];
    final (index, normalized) = classifyMethod(method);
    return index >= 0 ? commonRoutes[index] : extraRoutes?[normalized!];
  }
}

int commonMethodIndex(String method) {
  switch (method.length) {
    case 3:
      if (method == 'GET') return 0;
      if (method == 'PUT') return 2;
    case 4:
      if (method == 'POST') return 1;
      if (method == 'HEAD') return 5;
    case 5:
      if (method == 'PATCH') return 3;
    case 6:
      if (method == 'DELETE') return 4;
    case 7:
      if (method == 'OPTIONS') return 6;
  }
  return -1;
}

(int, String?) classifyMethod(String method) {
  var start = 0;
  var end = method.length;
  while (start < end && method.codeUnitAt(start) <= 32) {
    start += 1;
  }
  while (end > start && method.codeUnitAt(end - 1) <= 32) {
    end -= 1;
  }
  if (start == end) {
    throw ArgumentError.value(method, 'method', 'Method must not be empty.');
  }
  final length = end - start;
  if (length <= 7) {
    final a = upperAsciiCode(method.codeUnitAt(start));
    switch (length) {
      case 3:
        final b = upperAsciiCode(method.codeUnitAt(start + 1));
        final c = upperAsciiCode(method.codeUnitAt(start + 2));
        if (a == 71 && b == 69 && c == 84) return (0, null);
        if (a == 80 && b == 85 && c == 84) return (2, null);
      case 4:
        final b = upperAsciiCode(method.codeUnitAt(start + 1));
        final c = upperAsciiCode(method.codeUnitAt(start + 2));
        final d = upperAsciiCode(method.codeUnitAt(start + 3));
        if (a == 80 && b == 79 && c == 83 && d == 84) return (1, null);
        if (a == 72 && b == 69 && c == 65 && d == 68) return (5, null);
      case 5:
        if (a == 80 &&
            upperAsciiCode(method.codeUnitAt(start + 1)) == 65 &&
            upperAsciiCode(method.codeUnitAt(start + 2)) == 84 &&
            upperAsciiCode(method.codeUnitAt(start + 3)) == 67 &&
            upperAsciiCode(method.codeUnitAt(start + 4)) == 72) {
          return (3, null);
        }
      case 6:
        if (a == 68 &&
            upperAsciiCode(method.codeUnitAt(start + 1)) == 69 &&
            upperAsciiCode(method.codeUnitAt(start + 2)) == 76 &&
            upperAsciiCode(method.codeUnitAt(start + 3)) == 69 &&
            upperAsciiCode(method.codeUnitAt(start + 4)) == 84 &&
            upperAsciiCode(method.codeUnitAt(start + 5)) == 69) {
          return (4, null);
        }
      case 7:
        if (a == 79 &&
            upperAsciiCode(method.codeUnitAt(start + 1)) == 80 &&
            upperAsciiCode(method.codeUnitAt(start + 2)) == 84 &&
            upperAsciiCode(method.codeUnitAt(start + 3)) == 73 &&
            upperAsciiCode(method.codeUnitAt(start + 4)) == 79 &&
            upperAsciiCode(method.codeUnitAt(start + 5)) == 78 &&
            upperAsciiCode(method.codeUnitAt(start + 6)) == 83) {
          return (6, null);
        }
    }
  }
  final buffer = StringBuffer();
  for (var i = start; i < end; i++) {
    buffer.writeCharCode(upperAsciiCode(method.codeUnitAt(i)));
  }
  return (-1, buffer.toString());
}

int upperAsciiCode(int code) => code >= 97 && code <= 122 ? code - 32 : code;
