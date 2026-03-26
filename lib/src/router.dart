// Public router API.

import 'cache.dart';
import 'model.dart';
import 'path.dart';
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
       _caseSensitive = caseSensitive,
       _decodePath = decodePath,
       _normalizePath = normalizePath,
       _root = RouterNode<T>(),
       _staticRoutes = <String, RouterNode<T>>{},
       _cache = cacheSize > 0 ? RouteCache(cacheSize) : null {
    if (routes != null && routes.isNotEmpty) addAll(routes);
  }

  final DuplicatePolicy _policy;
  final bool _caseSensitive;
  final bool _decodePath;
  final bool _normalizePath;
  final RouterNode<T> _root;
  final Map<String, RouterNode<T>> _staticRoutes;
  final RouteCache<String, RouteMatch<T>>? _cache;
  int _order = 0;

  static String _normalizeMethod(String method) {
    final normalized = method.trim().toUpperCase();
    if (normalized.isEmpty) {
      throw ArgumentError.value(method, 'method', 'Method must not be empty.');
    }
    return normalized;
  }

  /// Registers a single route.
  void add(
    String path,
    T data, {
    String? method,
    DuplicatePolicy? duplicatePolicy,
  }) {
    final normalized = normalizeRoutePath(path);
    if (normalized == null) {
      throw FormatException('Route patterns must start with "/": $path');
    }
    addRoute(
      _root,
      _staticRoutes,
      _caseSensitive,
      method != null ? _normalizeMethod(method) : '',
      normalized,
      data,
      duplicatePolicy ?? _policy,
      _order++,
    );
    _cache?.clear();
  }

  /// Registers multiple routes.
  void addAll(
    Map<String, T> routes, {
    String? method,
    DuplicatePolicy? duplicatePolicy,
  }) {
    final normalizedMethod = method != null ? _normalizeMethod(method) : '';
    final policy = duplicatePolicy ?? _policy;
    for (final entry in routes.entries) {
      final normalizedPath = normalizeRoutePath(entry.key);
      if (normalizedPath == null) {
        throw FormatException(
          'Route patterns must start with "/": ${entry.key}',
        );
      }
      addRoute(
        _root,
        _staticRoutes,
        _caseSensitive,
        normalizedMethod,
        normalizedPath,
        entry.value,
        policy,
        _order++,
      );
    }
    _cache?.clear();
  }

  /// Returns the best matching route for [path].
  RouteMatch<T>? match(String path, {String? method}) {
    final normalizedMethod = method != null ? _normalizeMethod(method) : '';
    final prepared = _preparePath(path);
    if (prepared == null) return null;

    final cache = _cache;
    if (cache == null) {
      return findRoute(
        _root,
        _staticRoutes,
        _caseSensitive,
        normalizedMethod,
        prepared,
      );
    }

    final key = normalizedMethod.isEmpty ? prepared : '$normalizedMethod\x00$prepared';
    final cached = cache.get(key);
    if (cached != null) return cached;

    final result = findRoute(
      _root,
      _staticRoutes,
      _caseSensitive,
      normalizedMethod,
      prepared,
    );
    if (result != null) {
      cache.put(key, result);
    }
    return result;
  }

  /// Returns all matching routes for [path], least specific to most specific.
  List<RouteMatch<T>> matchAll(String path, {String? method}) {
    final prepared = _preparePath(path);
    if (prepared == null) return const [];
    return findAllRoutes(
      _root,
      _caseSensitive,
      method != null ? _normalizeMethod(method) : '',
      prepared,
    );
  }

  String? _preparePath(String path) {
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
    if (normalized == null || hasEmptySegments(normalized)) {
      return null;
    }
    return normalized;
  }
}
