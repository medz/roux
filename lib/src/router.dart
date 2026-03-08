import 'dart:collection';

const _slashCode = 47;
const _asteriskCode = 42;
const _colonCode = 58;
const _staticMapUpgradeThreshold = 8;
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
  final String? _wildcardValue;
  final int _wildcardStart;

  RouteMatch(this.data, [Map<String, String>? params])
    : _params = params,
      _route = null,
      _path = null,
      _paramValues = null,
      _wildcardValue = null,
      _wildcardStart = 0;

  RouteMatch._lazy({
    required this.data,
    required _Route<T> route,
    required String path,
    required _ParamStack? paramValues,
    required String? wildcardValue,
    required int wildcardStart,
  }) : _route = route,
       _path = path,
       _paramValues = paramValues,
       _wildcardValue = wildcardValue,
       _wildcardStart = wildcardStart;

  Map<String, String>? get params {
    final route = _route;
    return route == null
        ? _params
        : _params ??= route.paramsView(
            _path!,
            _paramValues,
            _wildcardValue,
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
    final state = _stateForWrite(method);
    final normalized = _normalizePatternForCompile(path);
    _addCompiledPattern(
      state,
      normalized.$1,
      data,
      duplicatePolicy: duplicatePolicy ?? _duplicatePolicy,
      hasReservedToken: normalized.$2,
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
      final normalized = _normalizePatternForCompile(entry.key);
      _addCompiledPattern(
        state,
        normalized.$1,
        entry.value,
        duplicatePolicy: effectivePolicy,
        hasReservedToken: normalized.$2,
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
    final collected = _MatchCollector<T>(_countPathSegments(normalized));
    _collectAllInState(_anyState, normalized, methodRank: 0, output: collected);

    if (method != null) {
      final methodToken = _normalizeMethodToken(method);
      final methodState = _methodStates?[methodToken];
      if (methodState != null) {
        _collectAllInState(
          methodState,
          normalized,
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

    final start = normalized.length == 1 ? normalized.length : 1;
    final matched = _matchNodePath(state, normalized, start);
    if (matched != null) {
      return matched;
    }

    final fallback = state.globalFallback;
    if (fallback == null) {
      return null;
    }
    final wildcardValue = normalized.length == 1 ? '' : normalized.substring(1);
    return _materializeMatch(fallback, normalized, null, wildcardValue, 0);
  }

  void _collectAllInState(
    _MethodState<T> state,
    String normalized, {
    required int methodRank,
    required _MatchCollector<T> output,
  }) {
    final fallback = state.globalFallback;
    if (fallback != null) {
      final wildcardValue = normalized.length == 1
          ? ''
          : normalized.substring(1);
      _collectSlotMatches(
        fallback,
        normalized,
        null,
        wildcardValue,
        0,
        depth: 0,
        routeKind: _wildcardSpecificityRank,
        methodRank: methodRank,
        output: output,
      );
    }

    final start = normalized.length == 1 ? normalized.length : 1;
    _collectNodeMatches(
      state,
      normalized,
      start,
      methodRank,
      output,
    );

    final exactStatic = state.staticExactRoutes[normalized];
    if (exactStatic != null) {
      _collectSlotMatches(
        exactStatic,
        normalized,
        null,
        null,
        0,
        depth: _countPathSegments(normalized),
        routeKind: _staticSpecificityRank,
        methodRank: methodRank,
        output: output,
      );
    }
  }

  void _addCompiledPattern(
    _MethodState<T> state,
    String pattern,
    T data, {
    required DuplicatePolicy duplicatePolicy,
    required bool hasReservedToken,
  }) {
    if (pattern == '/*') {
      final route = _Route<T>(
        data: data,
        paramNames: const <String>[],
        hasWildcard: true,
      );
      final existing = state.globalFallback;
      state.globalFallback = existing == null
          ? route
          : _resolveDuplicateRoute(
              existing: existing,
              replacement: route,
              pattern: pattern,
              duplicatePolicy: duplicatePolicy,
              rejectMessage: 'Duplicate global fallback route: $pattern',
            );
      return;
    }

    if (!hasReservedToken) {
      final route = _Route<T>(
        data: data,
        paramNames: const <String>[],
        hasWildcard: false,
      );
      final existing = state.staticExactRoutes[pattern];
      state.staticExactRoutes[pattern] = existing == null
          ? route
          : _resolveDuplicateRoute(
              existing: existing,
              replacement: route,
              pattern: pattern,
              duplicatePolicy: duplicatePolicy,
              rejectMessage:
                  'Duplicate route shape conflicts with existing route: $pattern',
            );
      return;
    }

    List<String>? paramNames;
    var paramCount = 0;
    var node = state.root;
    for (
      var cursor = pattern.length == 1 ? pattern.length : 1;
      cursor < pattern.length;
    ) {
      var segmentEnd = cursor;
      var hasReservedInSegment = false;
      while (segmentEnd < pattern.length) {
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
        if (segmentEnd != pattern.length) {
          throw FormatException('Wildcard must be the last segment: $pattern');
        }
        final route = _Route<T>(
          data: data,
          paramNames: paramNames ?? const <String>[],
          hasWildcard: true,
        );
        final existing = node.wildcardRoute;
        node.wildcardRoute = existing == null
            ? route
            : _resolveDuplicateRoute(
                existing: existing,
                replacement: route,
                pattern: pattern,
                duplicatePolicy: duplicatePolicy,
                rejectMessage:
                    'Duplicate wildcard route shape at prefix for pattern: $pattern',
              );
        if (paramCount > state.maxParamDepth) {
          state.maxParamDepth = paramCount;
        }
        return;
      }

      if (firstCode == _colonCode) {
        final paramName = pattern.substring(cursor + 1, segmentEnd);
        if (!_isValidParamName(paramName)) {
          throw FormatException('Invalid parameter name in route: $pattern');
        }
        node = node.paramChild ??= _Node<T>();
        (paramNames ??= <String>[]).add(paramName);
        paramCount += 1;
      } else {
        if (hasReservedInSegment) {
          throw FormatException(
            'Unsupported segment syntax in route: $pattern',
          );
        }
        node = node.getOrCreateStaticChild(
          pattern.substring(cursor, segmentEnd),
        );
      }
      cursor = segmentEnd + 1;
    }

    final route = _Route<T>(
      data: data,
      paramNames: paramNames ?? const <String>[],
      hasWildcard: false,
    );
    final existing = node.exactRoute;
    node.exactRoute = existing == null
        ? route
        : _resolveDuplicateRoute(
            existing: existing,
            replacement: route,
            pattern: pattern,
            duplicatePolicy: duplicatePolicy,
            rejectMessage:
                'Duplicate route shape conflicts with existing route: $pattern',
          );
    if (paramCount == 0) {
      state.staticExactRoutes[pattern] = node.exactRoute!;
    }
    if (paramCount > state.maxParamDepth) {
      state.maxParamDepth = paramCount;
    }
  }

  RouteMatch<T>? _matchNodePath(_MethodState<T> state, String path, int start) {
    _ParamStack? paramStack;
    _MatchBranch<T>? stack;
    var node = state.root;
    var cursor = start;
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
          return _materializeMatch(exact, path, stackParams, null, 0);
        }

        final terminalWildcard = node.wildcardRoute;
        if (terminalWildcard != null) {
          return _materializeMatch(terminalWildcard, path, stackParams, '', 0);
        }
      } else {
        final segmentEnd = _findSegmentEnd(path, cursor);
        if (segmentEnd != cursor) {
          final nextCursor = segmentEnd < path.length
              ? segmentEnd + 1
              : path.length;
          final currentParamLength = stackParams?.length ?? 0;
          final staticChild = node.lookupStaticChildSlice(
            path,
            cursor,
            segmentEnd,
          );
          final paramChild = node.paramChild;
          final wildcard = node.wildcardRoute;

          if (staticChild != null) {
            if (paramChild != null || wildcard != null) {
              stack = _MatchBranch<T>(
                node: node,
                cursor: cursor,
                segmentEnd: segmentEnd,
                nextCursor: nextCursor,
                paramLength: currentParamLength,
                tryParam: paramChild != null,
                prev: stack,
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
              stack = _MatchBranch<T>(
                node: node,
                cursor: cursor,
                segmentEnd: segmentEnd,
                nextCursor: nextCursor,
                paramLength: currentParamLength,
                tryParam: false,
                prev: stack,
              );
            }
            node = paramChild;
            cursor = nextCursor;
            paramLength = paramStack.length;
            continue top;
          }
          if (wildcard != null) {
            return _materializeMatch(wildcard, path, stackParams, null, cursor);
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
        if (branch.tryParam) {
          branch.tryParam = false;
          paramStack ??= _ParamStack(state.maxParamDepth);
          paramStack.truncate(paramLength);
          paramStack.push(cursor, branch.segmentEnd);
          node = node.paramChild!;
          cursor = branch.nextCursor;
          paramLength = paramStack.length;
          continue top;
        }

        stack = branch.prev;
        final backtrackWildcard = node.wildcardRoute;
        if (backtrackWildcard != null) {
          return _materializeMatch(
            backtrackWildcard,
            path,
            paramStack,
            null,
            cursor,
          );
        }
      }
      return null;
    } while (true);
  }

  void _collectNodeMatches(
    _MethodState<T> state,
    String path,
    int start,
    int methodRank,
    _MatchCollector<T> output,
  ) {
    _ParamStack? paramStack;
    _CollectBranch<T>? stack;
    var node = state.root;
    var cursor = start;
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
            '',
            0,
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
            null,
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
              null,
              cursor,
              depth: depth,
              routeKind: _wildcardSpecificityRank,
              methodRank: methodRank,
              output: output,
            );
          }

          final currentParamLength = stackParams?.length ?? 0;
          final staticChild = node.lookupStaticChildSlice(
            path,
            cursor,
            segmentEnd,
          );
          final paramChild = node.paramChild;
          if (staticChild != null) {
            if (paramChild != null) {
              stack = _CollectBranch<T>(
                node: paramChild,
                cursor: nextCursor,
                depth: depth + 1,
                paramLength: currentParamLength,
                paramStart: cursor,
                paramEnd: segmentEnd,
                prev: stack,
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
        paramStack.push(branch.paramStart, branch.paramEnd);
        node = branch.node;
        cursor = branch.cursor;
        depth = branch.depth;
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
    String? wildcardValue,
    int wildcardStart,
  ) => route.hasWildcard || route.paramNames.isNotEmpty
      ? RouteMatch<T>._lazy(
          data: route.data,
          route: route,
          path: path,
          paramValues: paramValues,
          wildcardValue: wildcardValue,
          wildcardStart: wildcardStart,
        )
      : route.noParamsMatch;

  void _collectSlotMatches(
    _Route<T> slot,
    String path,
    _ParamStack? paramValues,
    String? wildcardValue,
    int wildcardStart, {
    required int depth,
    required int routeKind,
    required int methodRank,
    required _MatchCollector<T> output,
  }) {
    if (slot.next == null) {
      output.add(
        _materializeMatch(slot, path, paramValues, wildcardValue, wildcardStart),
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
        _materializeMatch(
          entry,
          path,
          paramValues,
          wildcardValue,
          wildcardStart,
        ),
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
    if (!_sameParamNames(existing.paramNames, replacement.paramNames)) {
      throw FormatException(
        'Duplicate route shape conflicts with existing route: $pattern',
      );
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

class _MatchBranch<T> {
  final _Node<T> node;
  final int cursor;
  final int segmentEnd;
  final int nextCursor;
  final int paramLength;
  bool tryParam;
  final _MatchBranch<T>? prev;

  _MatchBranch({
    required this.node,
    required this.cursor,
    required this.segmentEnd,
    required this.nextCursor,
    required this.paramLength,
    required this.tryParam,
    required this.prev,
  });
}

class _CollectBranch<T> {
  final _Node<T> node;
  final int cursor;
  final int depth;
  final int paramLength;
  final int paramStart;
  final int paramEnd;
  final _CollectBranch<T>? prev;

  _CollectBranch({
    required this.node,
    required this.cursor,
    required this.depth,
    required this.paramLength,
    required this.paramStart,
    required this.paramEnd,
    required this.prev,
  });
}

class _Route<T> {
  final T data;
  final List<String> paramNames;
  final bool hasWildcard;
  _Route<T>? next;
  RouteMatch<T>? _cachedNoParamsMatch;

  _Route({
    required this.data,
    required this.paramNames,
    required this.hasWildcard,
  });

  RouteMatch<T> get noParamsMatch =>
      _cachedNoParamsMatch ??= RouteMatch<T>(data);

  Map<String, String>? paramsView(
    String path,
    _ParamStack? paramValues,
    String? wildcardValue,
    int wildcardStart,
  ) {
    if (paramNames.isEmpty && !hasWildcard) {
      return null;
    }
    return _LazyParamsMap(
      paramNames: paramNames,
      hasWildcard: hasWildcard,
      path: path,
      paramValues: paramValues,
      wildcardValue: wildcardValue,
      wildcardStart: wildcardStart,
    );
  }

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
  final String? _wildcardValue;
  final int _wildcardStart;
  Map<String, String>? _materialized;

  _LazyParamsMap({
    required List<String> paramNames,
    required bool hasWildcard,
    required String path,
    required _ParamStack? paramValues,
    required String? wildcardValue,
    required int wildcardStart,
  }) : _paramNames = paramNames,
       _hasWildcard = hasWildcard,
       _path = path,
       _paramValues = paramValues,
       _wildcardValue = wildcardValue,
       _wildcardStart = wildcardStart;

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
      return _wildcardValue ?? _sliceWildcard();
    }
    for (var i = 0; i < _paramNames.length; i++) {
      if (_paramNames[i] == key) {
        final captured = _paramValues;
        if (captured == null) {
          throw StateError('Missing parameter capture stack for matched route.');
        }
        return _path.substring(captured.startAt(i), captured.endAt(i));
      }
    }
    return null;
  }

  @override
  void operator []=(String key, String value) {
    (_materialized ??= _materialize())[key] = value;
  }

  @override
  void clear() {
    (_materialized ??= _materialize()).clear();
  }

  @override
  Iterable<String> get keys sync* {
    final materialized = _materialized;
    if (materialized != null) {
      yield* materialized.keys;
      return;
    }
    yield* _paramNames;
    if (_hasWildcard) {
      yield 'wildcard';
    }
  }

  @override
  String? remove(Object? key) {
    if (key is! String) {
      return null;
    }
    return (_materialized ??= _materialize()).remove(key);
  }

  @override
  int get length =>
      _materialized?.length ?? _paramNames.length + (_hasWildcard ? 1 : 0);

  Map<String, String> _materialize() {
    final params = <String, String>{};
    final captured = _paramValues;
    if (_paramNames.isNotEmpty) {
      if (captured == null) {
        throw StateError('Missing parameter capture stack for matched route.');
      }
      for (var i = 0; i < _paramNames.length; i++) {
        params[_paramNames[i]] = _path.substring(
          captured.startAt(i),
          captured.endAt(i),
        );
      }
    }
    if (_hasWildcard) {
      params['wildcard'] = _wildcardValue ?? _sliceWildcard();
    }
    return params;
  }

  String _sliceWildcard() =>
      _wildcardStart < _path.length ? _path.substring(_wildcardStart) : '';
}

class _Node<T> {
  List<String>? _staticKeys;
  List<_Node<T>>? _staticChildren;
  Map<String, _Node<T>>? _staticMap;

  _Node<T>? paramChild;
  _Route<T>? exactRoute;
  _Route<T>? wildcardRoute;

  _Node<T> getOrCreateStaticChild(String segment) {
    final map = _staticMap;
    if (map != null) {
      final existing = map[segment];
      if (existing != null) {
        return existing;
      }
      final child = _Node<T>();
      map[segment] = child;
      return child;
    }

    final keys = _staticKeys;
    final children = _staticChildren;
    if (keys != null && children != null) {
      for (var i = 0; i < keys.length; i++) {
        if (keys[i] == segment) {
          return children[i];
        }
      }
    }

    final child = _Node<T>();
    (_staticKeys ??= <String>[]).add(segment);
    (_staticChildren ??= <_Node<T>>[]).add(child);

    final currentKeys = _staticKeys!;
    if (currentKeys.length >= _staticMapUpgradeThreshold) {
      final upgraded = <String, _Node<T>>{};
      final currentChildren = _staticChildren!;
      for (var i = 0; i < currentKeys.length; i++) {
        upgraded[currentKeys[i]] = currentChildren[i];
      }
      _staticMap = upgraded;
      _staticKeys = null;
      _staticChildren = null;
    }

    return child;
  }

  _Node<T>? lookupStaticChildSlice(String path, int start, int end) {
    final map = _staticMap;
    if (map != null) {
      if (map.length >= 16) {
        return map[path.substring(start, end)];
      }
      for (final entry in map.entries) {
        if (_equalsPathSlice(entry.key, path, start, end)) {
          return entry.value;
        }
      }
      return null;
    }

    final keys = _staticKeys;
    final children = _staticChildren;
    if (keys == null || children == null) {
      return null;
    }
    for (var i = 0; i < keys.length; i++) {
      if (_equalsPathSlice(keys[i], path, start, end)) {
        return children[i];
      }
    }
    return null;
  }
}

(String, bool) _normalizePatternForCompile(String path) {
  if (path.isEmpty || path.codeUnitAt(0) != _slashCode) {
    throw FormatException('Route pattern must start with "/": $path');
  }

  var end = path.length;
  if (end > 1 && path.codeUnitAt(end - 1) == _slashCode) {
    if (path.codeUnitAt(end - 2) == _slashCode) {
      throw FormatException('Route pattern contains empty segment: $path');
    }
    end -= 1;
  }

  var hasReservedToken = false;
  var prevSlash = true;
  for (var i = 1; i < end; i++) {
    final code = path.codeUnitAt(i);
    if (code == _slashCode) {
      if (prevSlash) {
        throw FormatException('Route pattern contains empty segment: $path');
      }
      prevSlash = true;
      continue;
    }
    if (code == _colonCode || code == _asteriskCode) hasReservedToken = true;
    prevSlash = false;
  }
  return (end == path.length ? path : path.substring(0, end), hasReservedToken);
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
  var count = 0;
  for (var i = 1; i < path.length; i++) {
    if (path.codeUnitAt(i) == _slashCode) count += 1;
  }
  return path.length == 1 ? 0 : count + 1;
}

bool _sameParamNames(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
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
    final result = <RouteMatch<T>>[];
    for (final bucket in _buckets) {
      if (bucket != null) {
        result.addAll(bucket);
      }
    }
    return result;
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

  void pop() => _length -= 2;

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
