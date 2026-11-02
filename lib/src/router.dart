import 'model.dart';
import 'operations.dart';
import 'path.dart';

/// A lightweight, expressive path router.
class Router<T> {
  /// Creates a router with optional case sensitivity.
  Router({this.caseSensitive = false});

  /// Whether static path matching treats letter case as significant.
  final bool caseSensitive;

  final _root = RouterNode<T>();

  /// Registers a route pattern and its associated data.
  void add(String path, T data, {String? method}) =>
      addRoute(_root, caseSensitive, normalizeMethod(method), path, data);

  /// Returns the best match for [path], or `null` when none exists.
  RouteMatch<T>? find(String path, {String? method}) =>
      findRoute(_root, caseSensitive, method ?? '', normalizedSegments(path));

  /// Returns all matches for [path] in broad-to-specific order.
  // dart format off
  List<RouteMatch<T>> findAll(String path, {String? method, bool includeAny = false}) =>
      findAllRoutes(_root, caseSensitive, normalizeMethod(method), path, includeAny); // dart format on

  /// Removes all routes stored under the exact method and path pattern.
  bool remove(String method, String path) =>
      removeRoute(_root, caseSensitive, normalizeMethod(method), path);
}
