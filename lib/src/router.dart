import 'dart:collection';

const _slashCode = 47;
const _asteriskCode = 42;
const _colonCode = 58;
const _staticMapUpgradeThreshold = 4;
const _wildcardSpecificityRank = 0;
const _paramSpecificityRank = 1;
const _staticSpecificityRank = 2;

enum DuplicatePolicy { reject, replace, keepFirst, append }

class RouteMatch<T> {
  final T data;
  Map<String, String>? _params;
  final _Route<T>? _route;
  final String? _path;
  final _ParamStack? _paramValues;
  final int _wildcardStart;

  RouteMatch(this.data, [Map<String, String>? params])
    : _params = params,
      _route = null,
      _path = null,
      _paramValues = null,
      _wildcardStart = 0;

  RouteMatch._lazy(
    this.data,
    this._route,
    this._path,
    this._paramValues,
    this._wildcardStart,
  );

  Map<String, String>? get params {
    final route = _route;
    return route == null
        ? _params
        : _params ??= _LazyParamsMap(
            route.paramNames,
            route.hasWildcard,
            _path!,
            _paramValues,
            _wildcardStart,
          );
  }
}

class Router<T> {
  final _MethodState<T> _anyState = _MethodState<T>();
  Map<String, _MethodState<T>>? _methodStates;
  final DuplicatePolicy _duplicatePolicy;

  Router({
    Map<String, T>? routes,
    DuplicatePolicy duplicatePolicy = DuplicatePolicy.reject,
  }) : _duplicatePolicy = duplicatePolicy {
    if (routes != null && routes.isNotEmpty) {
      addAll(routes);
    }
  }

  void add(
    String path,
    T data, {
    String? method,
    DuplicatePolicy? duplicatePolicy,
  }) {
    _addPattern(
      _stateForWrite(method),
      path,
      data,
      duplicatePolicy: duplicatePolicy ?? _duplicatePolicy,
    );
  }

  void addAll(
    Map<String, T> routes, {
    String? method,
    DuplicatePolicy? duplicatePolicy,
  }) {
    final state = _stateForWrite(method);
    final effectivePolicy = duplicatePolicy ?? _duplicatePolicy;
    for (final entry in routes.entries) {
      _addPattern(
        state,
        entry.key,
        entry.value,
        duplicatePolicy: effectivePolicy,
      );
    }
  }

  RouteMatch<T>? match(String path, {String? method}) {
    final normalized = _normalizeInputPath(path);
    if (normalized == null) return null;
    if (method != null) {
      final methodToken = _normalizeMethodToken(method);
      final methodState = _methodStates?[methodToken];
      if (methodState != null) {
        final matched = _matchInState(methodState, normalized);
        if (matched != null) return matched;
      }
    }
    return _matchInState(_anyState, normalized);
  }

  List<RouteMatch<T>> matchAll(String path, {String? method}) {
    final normalized = _normalizeInputPath(path);
    if (normalized == null) return <RouteMatch<T>>[];
    final pathDepth = _countPathSegments(normalized);
    final collected = _MatchCollector<T>(pathDepth);
    _collectAllInState(
      _anyState,
      normalized,
      pathDepth: pathDepth,
      methodRank: 0,
      output: collected,
    );

    if (method != null) {
      final methodToken = _normalizeMethodToken(method);
      final methodState = _methodStates?[methodToken];
      if (methodState != null) {
        _collectAllInState(
          methodState,
          normalized,
          pathDepth: pathDepth,
          methodRank: 1,
          output: collected,
        );
      }
    }

    return collected.finish();
  }

  _MethodState<T> _stateForWrite(String? method) {
    if (method == null) {
      return _anyState;
    }
    final token = _normalizeMethodToken(method);
    final states = _methodStates ??= <String, _MethodState<T>>{};
    return states.putIfAbsent(token, _MethodState<T>.new);
  }

  String _normalizeMethodToken(String method) => switch (method.trim()) {
    '' => throw ArgumentError.value(
      method,
      'method',
      'Method must not be empty.',
    ),
    final trimmed => trimmed.toUpperCase(),
  };

  RouteMatch<T>? _matchInState(_MethodState<T> state, String normalized) {
    final exactStatic = state.staticExactRoutes[normalized];
    if (exactStatic != null) {
      return exactStatic.noParamsMatch;
    }

    final matched = _matchNodePath(state, normalized);
    final fallback = state.globalFallback;
    return matched ??
        (fallback == null
            ? null
            : _materializeMatch(fallback, normalized, null, 1));
  }

  void _collectAllInState(
    _MethodState<T> state,
    String normalized, {
    required int pathDepth,
    required int methodRank,
    required _MatchCollector<T> output,
  }) {
    final fallback = state.globalFallback;
    if (fallback != null) {
      _collectSlotMatches(
        fallback,
        normalized,
        null,
        1,
        depth: 0,
        routeKind: _wildcardSpecificityRank,
        methodRank: methodRank,
        output: output,
      );
    }

    _collectNodeMatches(state, normalized, methodRank, output);

    final exactStatic = state.staticExactRoutes[normalized];
    if (exactStatic != null) {
      _collectSlotMatches(
        exactStatic,
        normalized,
        null,
        0,
        depth: pathDepth,
        routeKind: _staticSpecificityRank,
        methodRank: methodRank,
        output: output,
      );
    }
  }

  void _addPattern(
    _MethodState<T> state,
    String pattern,
    T data, {
    required DuplicatePolicy duplicatePolicy,
  }) {
    if (pattern.isEmpty || pattern.codeUnitAt(0) != _slashCode) {
      throw FormatException('Route pattern must start with "/": $pattern');
    }

    var end = pattern.length;
    if (end > 1 && pattern.codeUnitAt(end - 1) == _slashCode) {
      if (pattern.codeUnitAt(end - 2) == _slashCode) {
        throw FormatException('Route pattern contains empty segment: $pattern');
      }
      end -= 1;
    }

    var hasReservedToken = false;
    var prevSlash = true;
    for (var i = 1; i < end; i++) {
      final code = pattern.codeUnitAt(i);
      if (code == _slashCode) {
        if (prevSlash) {
          throw FormatException(
            'Route pattern contains empty segment: $pattern',
          );
        }
        prevSlash = true;
        continue;
      }
      if (code == _colonCode || code == _asteriskCode) {
        hasReservedToken = true;
      }
      prevSlash = false;
    }

    final normalized = end == pattern.length
        ? pattern
        : pattern.substring(0, end);

    if (normalized == '/*') {
      final route = _Route<T>(data, const <String>[], true);
      final existing = state.globalFallback;
      state.globalFallback = existing == null
          ? route
          : _resolveDuplicateRoute(
              existing: existing,
              replacement: route,
              pattern: normalized,
              duplicatePolicy: duplicatePolicy,
              rejectMessage: 'Duplicate global fallback route: $normalized',
            );
      return;
    }

    if (!hasReservedToken) {
      final route = _Route<T>(data, const <String>[], false);
      final existing = state.staticExactRoutes[normalized];
      state.staticExactRoutes[normalized] = existing == null
          ? route
          : _resolveDuplicateRoute(
              existing: existing,
              replacement: route,
              pattern: normalized,
              duplicatePolicy: duplicatePolicy,
              rejectMessage:
                  'Duplicate route shape conflicts with existing route: $normalized',
            );
      return;
    }

    List<String>? paramNames;
    var paramCount = 0;
    var node = state.root;
    for (var cursor = end == 1 ? end : 1; cursor < end;) {
      var segmentEnd = cursor;
      var hasReservedInSegment = false;
      while (segmentEnd < end) {
        final code = pattern.codeUnitAt(segmentEnd);
        if (code == _slashCode) {
          break;
        }
        if (code == _colonCode || code == _asteriskCode) {
          hasReservedInSegment = true;
        }
        segmentEnd += 1;
      }

      final segmentLength = segmentEnd - cursor;
      final firstCode = pattern.codeUnitAt(cursor);
      if (segmentLength == 1 && firstCode == _asteriskCode) {
        if (segmentEnd != end) {
          throw FormatException(
            'Wildcard must be the last segment: $normalized',
          );
        }
        final route = _Route<T>(data, paramNames ?? const <String>[], true);
        final existing = node.wildcardRoute;
        node.wildcardRoute = existing == null
            ? route
            : _resolveDuplicateRoute(
                existing: existing,
                replacement: route,
                pattern: normalized,
                duplicatePolicy: duplicatePolicy,
                rejectMessage:
                    'Duplicate wildcard route shape at prefix for pattern: $normalized',
              );
        if (paramCount > state.maxParamDepth) {
          state.maxParamDepth = paramCount;
        }
        return;
      }

      if (firstCode == _colonCode) {
        final paramName = pattern.substring(cursor + 1, segmentEnd);
        if (!_isValidParamName(paramName)) {
          throw FormatException('Invalid parameter name in route: $normalized');
        }
        node = node.paramChild ??= _Node<T>();
        (paramNames ??= <String>[]).add(paramName);
        paramCount += 1;
      } else {
        if (hasReservedInSegment) {
          throw FormatException(
            'Unsupported segment syntax in route: $normalized',
          );
        }
        node = node.getOrCreateStaticChildSlice(pattern, cursor, segmentEnd);
      }
      cursor = segmentEnd + 1;
    }

    final route = _Route<T>(data, paramNames ?? const <String>[], false);
    final existing = node.exactRoute;
    node.exactRoute = existing == null
        ? route
        : _resolveDuplicateRoute(
            existing: existing,
            replacement: route,
            pattern: normalized,
            duplicatePolicy: duplicatePolicy,
            rejectMessage:
                'Duplicate route shape conflicts with existing route: $normalized',
          );
    if (paramCount == 0) {
      state.staticExactRoutes[normalized] = node.exactRoute!;
    }
    if (paramCount > state.maxParamDepth) {
      state.maxParamDepth = paramCount;
    }
  }

  RouteMatch<T>? _matchNodePath(_MethodState<T> state, String path) {
    _ParamStack? paramStack;
    _Branch<T>? stack;
    var node = state.root;
    var cursor = 1;
    var paramLength = 0;

    top:
    do {
      final params = paramStack;
      if (params != null) {
        params.truncate(paramLength);
      }
      final stackParams = paramStack;
      if (cursor >= path.length) {
        final exact = node.exactRoute;
        if (exact != null) {
          return _materializeMatch(exact, path, stackParams, 0);
        }
        final wildcard = node.wildcardRoute;
        if (wildcard != null) {
          return _materializeMatch(wildcard, path, stackParams, path.length);
        }
      } else {
        final segmentEnd = _findSegmentEnd(path, cursor);
        if (segmentEnd != cursor) {
          final nextCursor = segmentEnd < path.length
              ? segmentEnd + 1
              : path.length;
          final currentParamLength = stackParams?.length ?? 0;
          final staticChild = node._findStaticChildSlice(
            path,
            cursor,
            segmentEnd,
          );
          final paramChild = node.paramChild;
          final wildcard = node.wildcardRoute;

          if (staticChild != null) {
            if (paramChild != null || wildcard != null) {
              stack = _Branch<T>(
                node,
                cursor,
                currentParamLength,
                segmentEnd,
                nextCursor,
                0,
                paramChild != null,
                stack,
              );
            }
            node = staticChild;
            cursor = nextCursor;
            paramLength = currentParamLength;
            continue top;
          }
          if (paramChild != null) {
            paramStack ??= _ParamStack(state.maxParamDepth);
            paramStack.truncate(currentParamLength);
            paramStack.push(cursor, segmentEnd);
            if (wildcard != null) {
              stack = _Branch<T>(
                node,
                cursor,
                currentParamLength,
                segmentEnd,
                nextCursor,
                0,
                false,
                stack,
              );
            }
            node = paramChild;
            cursor = nextCursor;
            paramLength = paramStack.length;
            continue top;
          }
          if (wildcard != null) {
            return _materializeMatch(wildcard, path, stackParams, cursor);
          }
        }
      }

      while (stack != null) {
        final branch = stack;
        node = branch.node;
        cursor = branch.cursor;
        paramLength = branch.paramLength;
        if (paramStack != null) {
          paramStack.truncate(paramLength);
        }
        if (branch.flag) {
          branch.flag = false;
          paramStack ??= _ParamStack(state.maxParamDepth);
          paramStack.truncate(paramLength);
          paramStack.push(cursor, branch.a);
          node = node.paramChild!;
          cursor = branch.b;
          paramLength = paramStack.length;
          continue top;
        }

        stack = branch.prev;
        final wildcard = node.wildcardRoute;
        if (wildcard != null) {
          return _materializeMatch(wildcard, path, paramStack, cursor);
        }
      }
      return null;
    } while (true);
  }

  void _collectNodeMatches(
    _MethodState<T> state,
    String path,
    int methodRank,
    _MatchCollector<T> output,
  ) {
    _ParamStack? paramStack;
    _Branch<T>? stack;
    var node = state.root;
    var cursor = 1;
    var depth = 0;
    var paramLength = 0;

    top:
    do {
      final params = paramStack;
      if (params != null) {
        params.truncate(paramLength);
      }
      final stackParams = paramStack;

      if (cursor >= path.length) {
        final wildcard = node.wildcardRoute;
        if (wildcard != null) {
          _collectSlotMatches(
            wildcard,
            path,
            stackParams,
            path.length,
            depth: depth,
            routeKind: _wildcardSpecificityRank,
            methodRank: methodRank,
            output: output,
          );
        }

        final exact = node.exactRoute;
        if (exact != null) {
          _collectSlotMatches(
            exact,
            path,
            stackParams,
            0,
            depth: depth,
            routeKind: _paramSpecificityRank,
            methodRank: methodRank,
            output: output,
          );
        }
      } else {
        final segmentEnd = _findSegmentEnd(path, cursor);
        if (segmentEnd != cursor) {
          final nextCursor = segmentEnd < path.length
              ? segmentEnd + 1
              : path.length;
          final wildcard = node.wildcardRoute;
          if (wildcard != null) {
            _collectSlotMatches(
              wildcard,
              path,
              stackParams,
              cursor,
              depth: depth,
              routeKind: _wildcardSpecificityRank,
              methodRank: methodRank,
              output: output,
            );
          }

          final currentParamLength = stackParams?.length ?? 0;
          final staticChild = node._findStaticChildSlice(
            path,
            cursor,
            segmentEnd,
          );
          final paramChild = node.paramChild;
          if (staticChild != null) {
            if (paramChild != null) {
              stack = _Branch<T>(
                paramChild,
                nextCursor,
                currentParamLength,
                depth + 1,
                cursor,
                segmentEnd,
                false,
                stack,
              );
            }
            node = staticChild;
            cursor = nextCursor;
            depth += 1;
            paramLength = currentParamLength;
            continue top;
          }

          if (paramChild != null) {
            paramStack ??= _ParamStack(state.maxParamDepth);
            paramStack.truncate(currentParamLength);
            paramStack.push(cursor, segmentEnd);
            node = paramChild;
            cursor = nextCursor;
            depth += 1;
            paramLength = paramStack.length;
            continue top;
          }
        }
      }

      while (stack != null) {
        final branch = stack;
        stack = branch.prev;
        paramStack ??= _ParamStack(state.maxParamDepth);
        paramStack.truncate(branch.paramLength);
        paramStack.push(branch.b, branch.c);
        node = branch.node;
        cursor = branch.cursor;
        depth = branch.a;
        paramLength = paramStack.length;
        continue top;
      }
      return;
    } while (true);
  }

  RouteMatch<T> _materializeMatch(
    _Route<T> route,
    String path,
    _ParamStack? paramValues,
    int wildcardStart,
  ) => route.hasWildcard || route.paramNames.isNotEmpty
      ? RouteMatch<T>._lazy(route.data, route, path, paramValues, wildcardStart)
      : route.noParamsMatch;

  void _collectSlotMatches(
    _Route<T> slot,
    String path,
    _ParamStack? paramValues,
    int wildcardStart, {
    required int depth,
    required int routeKind,
    required int methodRank,
    required _MatchCollector<T> output,
  }) {
    if (slot.next == null) {
      output.add(
        _materializeMatch(slot, path, paramValues, wildcardStart),
        depth: depth,
        routeKind: routeKind,
        methodRank: methodRank,
      );
      return;
    }

    _Route<T>? current = slot;
    while (current != null) {
      final entry = current;
      output.add(
        _materializeMatch(entry, path, paramValues, wildcardStart),
        depth: depth,
        routeKind: routeKind,
        methodRank: methodRank,
      );

      current = entry.next;
    }
  }

  _Route<T> _resolveDuplicateRoute({
    required _Route<T> existing,
    required _Route<T> replacement,
    required String pattern,
    required DuplicatePolicy duplicatePolicy,
    required String rejectMessage,
  }) {
    final a = existing.paramNames;
    final b = replacement.paramNames;
    if (a.length != b.length) {
      throw FormatException(
        'Duplicate route shape conflicts with existing route: $pattern',
      );
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        throw FormatException(
          'Duplicate route shape conflicts with existing route: $pattern',
        );
      }
    }

    switch (duplicatePolicy) {
      case DuplicatePolicy.reject:
        throw FormatException(rejectMessage);
      case DuplicatePolicy.replace:
        return replacement;
      case DuplicatePolicy.keepFirst:
        return existing;
      case DuplicatePolicy.append:
        return existing.appended(replacement);
    }
  }
}

class _MethodState<T> {
  final _Node<T> root = _Node<T>();
  _Route<T>? globalFallback;
  final Map<String, _Route<T>> staticExactRoutes = <String, _Route<T>>{};
  int maxParamDepth = 0;
}

class _Branch<T> {
  final _Node<T> node;
  final int cursor;
  final int paramLength;
  final int a;
  final int b;
  final int c;
  bool flag;
  final _Branch<T>? prev;

  _Branch(
    this.node,
    this.cursor,
    this.paramLength,
    this.a,
    this.b,
    this.c,
    this.flag,
    this.prev,
  );
}

class _Route<T> {
  final T data;
  final List<String> paramNames;
  final bool hasWildcard;
  _Route<T>? next;
  RouteMatch<T>? _cachedNoParamsMatch;

  _Route(this.data, this.paramNames, this.hasWildcard);

  RouteMatch<T> get noParamsMatch =>
      _cachedNoParamsMatch ??= RouteMatch<T>(data);

  _Route<T> appended(_Route<T> route) {
    _Route<T> current = this;
    while (current.next != null) {
      current = current.next!;
    }
    current.next = route;
    return this;
  }
}

class _LazyParamsMap extends MapBase<String, String> {
  final List<String> _paramNames;
  final bool _hasWildcard;
  final String _path;
  final _ParamStack? _paramValues;
  final int _wildcardStart;
  Map<String, String>? _materialized;

  _LazyParamsMap(
    this._paramNames,
    this._hasWildcard,
    this._path,
    this._paramValues,
    this._wildcardStart,
  );

  @override
  String? operator [](Object? key) {
    if (key is! String) {
      return null;
    }
    final materialized = _materialized;
    if (materialized != null) {
      return materialized[key];
    }
    if (_hasWildcard && key == 'wildcard') {
      return _sliceWildcard();
    }
    for (var i = 0; i < _paramNames.length; i++) {
      if (_paramNames[i] == key) {
        final captured = _captures;
        return _path.substring(captured.startAt(i), captured.endAt(i));
      }
    }
    return null;
  }

  @override
  void operator []=(String key, String value) =>
      (_materialized ??= _materialize())[key] = value;

  @override
  void clear() => (_materialized ??= _materialize()).clear();

  @override
  Iterable<String> get keys => (_materialized ??= _materialize()).keys;

  @override
  String? remove(Object? key) =>
      key is! String ? null : (_materialized ??= _materialize()).remove(key);

  @override
  int get length =>
      _materialized?.length ?? _paramNames.length + (_hasWildcard ? 1 : 0);

  Map<String, String> _materialize() {
    final params = <String, String>{};
    if (_paramNames.isNotEmpty) {
      final captured = _captures;
      for (var i = 0; i < _paramNames.length; i++) {
        params[_paramNames[i]] = _path.substring(
          captured.startAt(i),
          captured.endAt(i),
        );
      }
    }
    if (_hasWildcard) {
      params['wildcard'] = _sliceWildcard();
    }
    return params;
  }

  _ParamStack get _captures =>
      _paramValues ??
      (throw StateError('Missing parameter capture stack for matched route.'));

  String _sliceWildcard() =>
      _wildcardStart < _path.length ? _path.substring(_wildcardStart) : '';
}

class _Node<T> {
  final String? _staticKey;
  _Node<T>? _staticChild;
  _Node<T>? _staticNext;
  Map<String, _Node<T>>? _staticMap;
  int _staticCount = 0;
  _Node<T>? paramChild;
  _Route<T>? exactRoute;
  _Route<T>? wildcardRoute;

  _Node([this._staticKey]);

  _Node<T> getOrCreateStaticChildSlice(String path, int start, int end) {
    final map = _staticMap;
    if (map != null) {
      final key = path.substring(start, end);
      return map[key] ??= _Node<T>(key);
    }
    final child = _findStaticChildSlice(path, start, end);
    if (child != null) {
      return child;
    }
    final created = _Node<T>(path.substring(start, end));
    created._staticNext = _staticChild;
    _staticChild = created;
    if (++_staticCount >= _staticMapUpgradeThreshold) {
      final upgraded = <String, _Node<T>>{};
      for (var node = _staticChild; node != null; node = node._staticNext) {
        upgraded[node._staticKey!] = node;
      }
      _staticMap = upgraded;
    }
    return created;
  }

  _Node<T>? _findStaticChildSlice(String path, int start, int end) {
    final map = _staticMap;
    if (map != null) {
      return map[path.substring(start, end)];
    }
    _Node<T>? prev;
    var child = _staticChild;
    while (child != null) {
      if (_equalsPathSlice(child._staticKey!, path, start, end)) {
        if (prev != null) {
          prev._staticNext = child._staticNext;
          child._staticNext = _staticChild;
          _staticChild = child;
        }
        return child;
      }
      prev = child;
      child = child._staticNext;
    }
    return null;
  }
}

String? _normalizeInputPath(String path) {
  if (path.isEmpty || path.codeUnitAt(0) != _slashCode) {
    return null;
  }
  if (path.length > 1 && path.codeUnitAt(path.length - 1) == _slashCode) {
    if (path.codeUnitAt(path.length - 2) == _slashCode) {
      return null;
    }
    path = path.substring(0, path.length - 1);
  }
  if (path.length > 1 && path.codeUnitAt(1) == _slashCode) {
    return null;
  }
  return path;
}

int _findSegmentEnd(String path, int start) {
  var i = start;
  while (i < path.length && path.codeUnitAt(i) != _slashCode) {
    i += 1;
  }
  return i;
}

bool _equalsPathSlice(String key, String path, int start, int end) {
  if (key.length != (end - start)) {
    return false;
  }
  for (var i = 0; i < key.length; i++) {
    if (key.codeUnitAt(i) != path.codeUnitAt(start + i)) {
      return false;
    }
  }
  return true;
}

int _countPathSegments(String path) {
  var count = path.length == 1 ? 0 : 1;
  for (var i = 1; i < path.length; i++) {
    if (path.codeUnitAt(i) == _slashCode) count += 1;
  }
  return count;
}

class _MatchCollector<T> {
  final List<List<RouteMatch<T>>?> _buckets;
  int _count = 0;

  _MatchCollector(int maxDepth)
    : _buckets = List<List<RouteMatch<T>>?>.filled(
        (maxDepth + 1) * 6,
        null,
        growable: false,
      );

  void add(
    RouteMatch<T> match, {
    required int depth,
    required int routeKind,
    required int methodRank,
  }) {
    final index = depth * 6 + routeKind * 2 + methodRank;
    (_buckets[index] ??= <RouteMatch<T>>[]).add(match);
    _count += 1;
  }

  List<RouteMatch<T>> finish() {
    if (_count == 0) {
      return <RouteMatch<T>>[];
    }
    final result = List<RouteMatch<T>?>.filled(_count, null, growable: false);
    var offset = 0;
    for (final bucket in _buckets) {
      if (bucket != null) {
        for (final match in bucket) {
          result[offset++] = match;
        }
      }
    }
    return result.cast<RouteMatch<T>>();
  }
}

class _ParamStack {
  final List<int> _values;
  int _length = 0;

  _ParamStack(int capacity)
    : _values = List<int>.filled(
        (capacity == 0 ? 1 : capacity) * 2,
        0,
        growable: false,
      );

  void push(int start, int end) {
    _values[_length] = start;
    _values[_length + 1] = end;
    _length += 2;
  }

  int get length => _length;

  void truncate(int length) => _length = length;

  int startAt(int index) => _values[index * 2];

  int endAt(int index) => _values[index * 2 + 1];
}

bool _isValidParamName(String name) {
  if (name.isEmpty) return false;

  final first = name.codeUnitAt(0);
  final validFirst =
      (first >= 65 && first <= 90) ||
      (first >= 97 && first <= 122) ||
      first == 95;
  if (!validFirst) return false;

  for (var i = 1; i < name.length; i++) {
    final c = name.codeUnitAt(i);
    final valid =
        (c >= 65 && c <= 90) ||
        (c >= 97 && c <= 122) ||
        (c >= 48 && c <= 57) ||
        c == 95;
    if (!valid) return false;
  }
  return true;
}
