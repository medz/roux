import 'route_model.dart';
import 'route_path.dart';
import 'method_table.dart';
import 'route_set.dart';

/// Experimental router facade with RouteSet/Input/MethodTable split.
class Router<T> {
  /// Creates an experimental router with the same surface as the main router.
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
    if (method == null) _hasSharedRoutes = true;
    _routeSetFor(method).addRoute(
      path,
      data,
      duplicatePolicy ?? _duplicatePolicy,
      _nextRegistrationOrder++,
    );
  }

  /// Registers multiple routes under a shared configuration.
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

  /// Returns the best route match for [path].
  @pragma('vm:prefer-inline')
  RouteMatch<T>? match(String path, {String? method}) {
    if (!_hasSharedRoutes && !_decodePath) {
      RouteSet<T>? routeSet;
      if (method != null) {
        final commonIndex = commonMethodIndex(method);
        routeSet = commonIndex < 0
            ? null
            : _methodRoutes.commonRoutes[commonIndex];
      }
      if (routeSet != null && !routeSet.needsStrict) {
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
        if (routeSet.canNormBest || routeSet.canNormExact) {
          return routeSet.matchBestNormalized(path);
        }
        final normalized = normalizeRoutePath(path);
        return normalized == null ? null : routeSet.matchBest(normalized);
      }
    }
    final routeSet = method == null ? null : _methodRoutes.lookupMethod(method);
    final strict =
        _sharedRoutes.needsStrict || (routeSet?.needsStrict ?? false);
    final normalized = _preparePath(path, strict);
    if (normalized == null) return null;
    return routeSet?.matchBest(normalized) ??
        _sharedRoutes.matchBest(normalized);
  }

  /// Returns every route match for [path] from broadest to most specific.
  @pragma('vm:prefer-inline')
  List<RouteMatch<T>> matchAll(String path, {String? method}) {
    final routeSet = method == null ? null : _methodRoutes.lookupMethod(method);
    final strict =
        _sharedRoutes.needsStrict || (routeSet?.needsStrict ?? false);
    final normalized = _preparePath(path, strict);
    if (normalized == null) return [];
    final collected = MatchAccumulator<T>(
      routeSet != null || _sharedRoutes.needsSort,
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
      return hasEmptySegments(trimmed) ? null : trimmed;
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
    return hasEmptySegments(normalized) ? null : normalized;
  }
}
