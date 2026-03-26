// Public router API.

import 'model.dart';
import 'path.dart';
import 'cache.dart';
import 'radix.dart';

/// A lightweight, expressive path router.
class Router<T> {
  /// Creates a router with optional initial [routes] and configuration.
  Router({
    Map<String, T>? routes,
    DuplicatePolicy duplicatePolicy = DuplicatePolicy.reject,
    bool caseSensitive = true,
    bool decodePath = false,
    bool normalizePath = false,
    int cacheSize = 256,
  }) : _policy = duplicatePolicy,
       _decodePath = decodePath,
       _normalizePath = normalizePath,
       _engine = Radix<T>(caseSensitive),
       _cache = cacheSize > 0 ? RouteCache(cacheSize) : null {
    if (routes != null && routes.isNotEmpty) addAll(routes);
  }

  final DuplicatePolicy _policy;
  final bool _decodePath, _normalizePath;
  final Radix<T> _engine;
  // Only caches successful matches; misses are not stored.
  final RouteCache<String, RouteMatch<T>>? _cache;
  int _order = 0;

  static String _normalizeMethod(String method) {
    final m = method.trim().toUpperCase();
    if (m.isEmpty) {
      throw ArgumentError.value(method, 'method', 'Method must not be empty.');
    }
    return m;
  }

  /// Registers a single route.
  void add(
    String path,
    T data, {
    String? method,
    DuplicatePolicy? duplicatePolicy,
  }) {
    final m = method != null ? _normalizeMethod(method) : null;
    _engine.add(path, data, m, duplicatePolicy ?? _policy, _order++);
    _cache?.clear();
  }

  /// Registers multiple routes.
  void addAll(
    Map<String, T> routes, {
    String? method,
    DuplicatePolicy? duplicatePolicy,
  }) {
    final m = method != null ? _normalizeMethod(method) : null;
    final policy = duplicatePolicy ?? _policy;
    for (final e in routes.entries) {
      _engine.add(e.key, e.value, m, policy, _order++);
    }
    _cache?.clear();
  }

  /// Returns the best matching route for [path].
  RouteMatch<T>? match(String path, {String? method}) {
    final m = method != null ? _normalizeMethod(method) : null;
    final prepared = _preparePath(path);
    if (prepared == null) return null;

    if (_cache != null) {
      final key = m != null ? '$m\x00$prepared' : prepared;
      final cached = _cache.get(key);
      if (cached != null) return cached;
      final result = _engine.match(prepared, m);
      if (result != null) _cache.put(key, result);
      return result;
    }
    return _engine.match(prepared, m);
  }

  /// Returns all matching routes for [path], least specific to most specific.
  List<RouteMatch<T>> matchAll(String path, {String? method}) {
    final m = method != null ? _normalizeMethod(method) : null;
    final prepared = _preparePath(path);
    if (prepared == null) return const [];
    return _engine.matchAll(prepared, m);
  }

  String? _preparePath(String path) {
    if (_decodePath && path.contains('%')) {
      try {
        path = Uri.decodeFull(path);
      } on ArgumentError {
        return null;
      }
    }
    final String? normalized;
    if (_normalizePath) {
      normalized = normalizeRoutePath(path);
    } else if (path.startsWith('/')) {
      normalized = trimTrailingSlash(path);
    } else {
      return null;
    }
    if (normalized == null) return null;
    if (_engine.needsStrict && hasEmptySegments(normalized)) return null;
    return normalized;
  }
}
