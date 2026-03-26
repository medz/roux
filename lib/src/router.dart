import 'cache.dart';
import 'model.dart';
import 'operations.dart';

/// A lightweight, expressive path router.
class Router<T> {
  Router({this.caseSensitive = false, this.cache});

  final bool caseSensitive;
  final Cache<T>? cache;

  final _root = RouterNode<T>();
  final _staticRoutes = <String, RouterNode<T>>{};

  void add(String path, T data, {String? method}) {
    addRoute(_root, _staticRoutes, caseSensitive, _m(method), path, data);
    cache?.clear();
  }

  RouteMatch<T>? find(String path, {String? method}) {
    final m = _m(method);
    final p = _p(path);
    final key = m.isEmpty ? p : '$m\x00$p';
    if (cache?.get(key) case final RouteMatch<T> value) {
      return value;
    }

    final result = findRoute(_root, _staticRoutes, caseSensitive, m, p);
    if (result != null) cache?.put(key, result);
    return result;
  }

  List<RouteMatch<T>> findAll(String path, {String? method}) =>
      findAllRoutes(_root, caseSensitive, _m(method), _p(path));

  bool remove(String method, String path) {
    final removed = removeRoute(
      _root,
      _staticRoutes,
      caseSensitive,
      _m(method),
      path,
    );
    if (removed) cache?.clear();
    return removed;
  }

  static String _m(String? method) => method?.trim().toUpperCase() ?? '';
  static String _p(String path) =>
      '/${Uri(path: path).pathSegments.where((s) => s.isNotEmpty).join('/')}';
}
