import 'cache.dart';
import 'model.dart';
import 'operations.dart';
import 'path.dart';

/// A lightweight, expressive path router.
class Router<T> {
  /// Creates a router with optional case sensitivity and match caching.
  Router({this.caseSensitive = false, this.cache});

  /// Whether static path matching treats letter case as significant.
  final bool caseSensitive;

  /// Optional cache used to memoize successful lookups.
  final Cache<T>? cache;

  final _root = RouterNode<T>();
  final _staticRoutes = <String, RouterNode<T>>{};

  /// Registers a route pattern and its associated data.
  void add(String path, T data, {String? method}) {
    addRoute(
      _root,
      _staticRoutes,
      caseSensitive,
      _m(method),
      normalizePath(path),
      data,
    );
    cache?.clear();
  }

  /// Returns the best match for [path], or `null` when none exists.
  RouteMatch<T>? find(String path, {String? method}) {
    final m = _m(method);
    final p = normalizePath(path);
    final key = m.isEmpty ? p : '$m\x00$p';
    if (cache?.get(key) case final RouteMatch<T> value) {
      return value;
    }

    final result = findRoute(_root, _staticRoutes, caseSensitive, m, p);
    if (result != null) cache?.put(key, result);
    return result;
  }

  /// Returns all matches for [path] in broad-to-specific order.
  List<RouteMatch<T>> findAll(String path, {String? method}) =>
      findAllRoutes(_root, caseSensitive, _m(method), normalizePath(path));

  /// Removes all routes stored under the exact method and path pattern.
  bool remove(String method, String path) {
    final removed = removeRoute(
      _root,
      _staticRoutes,
      caseSensitive,
      _m(method),
      normalizePath(path),
    );
    if (removed) cache?.clear();
    return removed;
  }

  static String _m(String? method) => method?.trim().toUpperCase() ?? '';
}
