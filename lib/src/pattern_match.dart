part of 'router.dart';

RouteMatch<T>? _matchCompiled<T>(_CompiledSlot<T> current, String path) {
  while (true) {
    final match = current.regex.firstMatch(path);
    if (match != null) {
      return _materializeCompiled(current.route, current.groupIndexes, match);
    }
    final next = current.next;
    if (next == null) return null;
    current = next;
  }
}

void _collectCompiled<T>(
  _CompiledSlot<T> current,
  String path,
  int methodRank,
  _MatchCollector<T> output,
) {
  while (true) {
    final match = current.regex.firstMatch(path);
    if (match != null) {
      for (
        _Route<T>? route = current.route;
        route != null;
        route = route.next
      ) {
        output.add(
          _materializeCompiled(route, current.groupIndexes, match),
          route,
          methodRank,
        );
      }
    }
    final next = current.next;
    if (next == null) return;
    current = next;
  }
}

void _addCompiled<T>(
  Router<T> router,
  _RouteSet<T> routeSet,
  _CompiledSlot<T> compiled,
  String pattern,
  DuplicatePolicy duplicatePolicy,
) {
  final head = switch (compiled.bucket) {
    _compiledBucketHigh => routeSet.compiledRoutes,
    _compiledBucketRepeated => routeSet.repeatedCompiledRoutes,
    _compiledBucketLate => routeSet.lateCompiledRoutes,
    _compiledBucketDeferred => routeSet.deferredCompiledRoutes,
    _ => throw StateError('Invalid compiled bucket: ${compiled.bucket}'),
  };
  if (head == null) {
    _setCompiledHead(routeSet, compiled);
    return;
  }
  if (head.shape == compiled.shape) {
    _verifyCompiledNames(
      head.route.paramNames,
      compiled.route.paramNames,
      pattern,
    );
    head.route = router._resolveDup(
      head.route,
      compiled.route,
      pattern,
      duplicatePolicy,
      _dupShape,
    );
    return;
  }
  if (_compiledSortsBefore(compiled.route, head.route)) {
    compiled.next = head;
    _setCompiledHead(routeSet, compiled);
    return;
  }
  for (var current = head; ; current = current.next!) {
    final next = current.next;
    if (next == null) {
      current.next = compiled;
      return;
    }
    if (next.shape == compiled.shape) {
      _verifyCompiledNames(
        next.route.paramNames,
        compiled.route.paramNames,
        pattern,
      );
      next.route = router._resolveDup(
        next.route,
        compiled.route,
        pattern,
        duplicatePolicy,
        _dupShape,
      );
      return;
    }
    if (_compiledSortsBefore(compiled.route, next.route)) {
      compiled.next = next;
      current.next = compiled;
      return;
    }
  }
}

void _setCompiledHead<T>(_RouteSet<T> routeSet, _CompiledSlot<T> compiled) {
  switch (compiled.bucket) {
    case _compiledBucketHigh:
      routeSet.compiledRoutes = compiled;
    case _compiledBucketRepeated:
      routeSet.repeatedCompiledRoutes = compiled;
    case _compiledBucketLate:
      routeSet.lateCompiledRoutes = compiled;
    case _compiledBucketDeferred:
      routeSet.deferredCompiledRoutes = compiled;
  }
}

void _verifyCompiledNames(List<String> a, List<String> b, String pattern) {
  if (a.length != b.length) throw FormatException('$_dupShape$pattern');
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) throw FormatException('$_dupShape$pattern');
  }
}

RouteMatch<T> _materializeCompiled<T>(
  _Route<T> route,
  List<int> groupIndexes,
  RegExpMatch match,
) {
  if (route.paramNames.isEmpty) return route.noParamsMatch;
  final params = <String, String>{};
  for (var i = 0; i < route.paramNames.length; i++) {
    final value = match.group(groupIndexes[i]);
    if (value != null) params[route.paramNames[i]] = value;
  }
  return RouteMatch<T>(route.data, params);
}

class _CompiledSlot<T> {
  final RegExp regex;
  final String shape;
  final int bucket;
  final int depth;
  final List<int> groupIndexes;
  _Route<T> route;
  _CompiledSlot<T>? next;

  _CompiledSlot(
    this.regex,
    this.shape,
    this.bucket,
    this.depth,
    this.groupIndexes,
    this.route,
  );
}
