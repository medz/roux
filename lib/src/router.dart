import 'dart:collection';

const _slashCode = 47,
    _asteriskCode = 42,
    _colonCode = 58,
    _openBraceCode = 123,
    _closeBraceCode = 125,
    _mapAt = 4;
const _wildRank = 0, _paramRank = 1, _staticRank = 2;
const _compiledBucketHigh = 0,
    _compiledBucketRepeated = 1,
    _compiledBucketLate = 2,
    _compiledBucketDeferred = 3;
const _dupShape = 'Duplicate route shape conflicts with existing route: ';
const _dupWildcard = 'Duplicate wildcard route shape at prefix for pattern: ';
const _dupFallback = 'Duplicate global fallback route: ';
const _emptySegment = 'Route pattern contains empty segment: ';
const _missingCaptures = 'Missing parameter capture stack for matched route.';

/// Controls how duplicate route registrations are handled.
enum DuplicatePolicy {
  /// Throws when the same normalized route shape is registered again.
  reject,

  /// Replaces the existing route entry with the latest registration.
  replace,

  /// Keeps the first registered route entry and ignores later duplicates.
  keepFirst,

  /// Retains every duplicate route entry in registration order.
  append,
}

/// The matched route payload and any captured path parameters.
class RouteMatch<T> {
  /// The value associated with the matched route.
  final T data;
  Map<String, String>? _params;
  final _Route<T>? _route;
  final String? _path;
  final _ParamStack? _captures;
  final int _wildcardStart;

  /// Creates an eager route match with an optional prebuilt params map.
  RouteMatch(this.data, [Map<String, String>? params])
    : _params = params,
      _route = null,
      _path = null,
      _captures = null,
      _wildcardStart = 0;
  RouteMatch._lazy(
    this.data,
    this._route,
    this._path,
    this._captures,
    this._wildcardStart,
  );

  /// Captured parameter values for the matched route, if any.
  Map<String, String>? get params => switch (_route) {
    null => _params,
    final route => _params ??= _LazyParamsMap(
      route.paramNames,
      route.wildcardName,
      _path!,
      _captures,
      _wildcardStart,
    ),
  };
}

/// A compact path router with support for exact, parameter, and wildcard routes.
class Router<T> {
  final _MethodState<T> _anyState = _MethodState<T>();
  Map<String, _MethodState<T>>? _methodStates;
  final DuplicatePolicy _duplicatePolicy;
  final bool _caseSensitive;
  final bool _decodePath;

  /// Creates a router and optionally preloads [routes].
  Router({
    Map<String, T>? routes,
    DuplicatePolicy duplicatePolicy = DuplicatePolicy.reject,
    bool caseSensitive = true,
    bool decodePath = false,
  }) : _duplicatePolicy = duplicatePolicy,
       _caseSensitive = caseSensitive,
       _decodePath = decodePath {
    if (routes != null && routes.isNotEmpty) addAll(routes);
  }

  /// Registers a route payload for [path].
  void add(
    String path,
    T data, {
    String? method,
    DuplicatePolicy? duplicatePolicy,
  }) => _addPattern(
    _stateForWrite(method),
    path,
    data,
    duplicatePolicy: duplicatePolicy ?? _duplicatePolicy,
  );

  /// Registers every entry in [routes].
  void addAll(
    Map<String, T> routes, {
    String? method,
    DuplicatePolicy? duplicatePolicy,
  }) {
    final state = _stateForWrite(method),
        policy = duplicatePolicy ?? _duplicatePolicy;
    for (final entry in routes.entries) {
      _addPattern(state, entry.key, entry.value, duplicatePolicy: policy);
    }
  }

  /// Returns the highest-priority match for [path], or `null` if none exists.
  RouteMatch<T>? match(String path, {String? method}) {
    final normalized = _prepareInputPath(path);
    if (normalized == null) return null;
    final methodToken = method == null ? null : _methodToken(method);
    final methodState = methodToken == null
        ? null
        : _methodStates?[methodToken];
    return (methodState == null
            ? null
            : _matchInState(methodState, normalized)) ??
        _matchInState(_anyState, normalized);
  }

  /// Returns every matching route for [path] in router priority order.
  List<RouteMatch<T>> matchAll(String path, {String? method}) {
    final normalized = _prepareInputPath(path);
    if (normalized == null) return <RouteMatch<T>>[];
    final pathDepth = _pathDepth(normalized);
    final collected = _MatchCollector<T>(pathDepth);
    _collectState(_anyState, normalized, pathDepth, 0, collected);
    final methodToken = method == null ? null : _methodToken(method);
    final methodState = methodToken == null
        ? null
        : _methodStates?[methodToken];
    if (methodState != null) {
      _collectState(methodState, normalized, pathDepth, 1, collected);
    }
    return collected.finish();
  }

  _MethodState<T> _stateForWrite(String? method) => method == null
      ? _anyState
      : (_methodStates ??= <String, _MethodState<T>>{}).putIfAbsent(
          _methodToken(method),
          _MethodState<T>.new,
        );
  String _methodToken(String method) {
    final token = method.trim();
    if (token.isEmpty) {
      throw ArgumentError.value(method, 'method', 'Method must not be empty.');
    }
    return token.toUpperCase();
  }

  String _canonicalPath(String path) =>
      _caseSensitive ? path : path.toLowerCase();

  String _canonicalLiteral(String literal) =>
      _caseSensitive ? literal : literal.toLowerCase();

  String? _prepareInputPath(String path) {
    if (_decodePath && path.contains('%')) {
      try {
        path = Uri.decodeFull(path);
      } on ArgumentError {
        return null;
      }
    }
    return _normalizeInputPath(path);
  }

  RouteMatch<T>? _matchInState(_MethodState<T> state, String normalized) {
    final exact = state.staticExactRoutes[_canonicalPath(normalized)]?.noParamsMatch;
    if (exact != null) return exact;
    if (!state.hasSlowMatchPath) {
      return _matchNodePathFast(state, normalized);
    }
    final fallback = state.globalFallback,
        compiled = state.compiledRoutes,
        repeated = state.repeatedCompiledRoutes,
        late = state.lateCompiledRoutes,
        deferred = state.deferredCompiledRoutes;
    return (compiled == null ? null : _matchCompiled(compiled, normalized)) ??
        _matchNodePath(state, normalized, false) ??
        (late == null ? null : _matchCompiled(late, normalized)) ??
        (repeated == null ? null : _matchCompiled(repeated, normalized)) ??
        _matchNodePath(state, normalized, true) ??
        (deferred == null ? null : _matchCompiled(deferred, normalized)) ??
        (fallback == null ? null : _materialize(fallback, normalized, null, 1));
  }

  void _collectState(
    _MethodState<T> state,
    String normalized,
    int pathDepth,
    int methodRank,
    _MatchCollector<T> output,
  ) {
    final fallback = state.globalFallback;
    if (fallback != null) {
      _collectSlot(
        fallback,
        normalized,
        null,
        1,
        0,
        _wildRank,
        methodRank,
        output,
      );
    }
    final repeated = state.repeatedCompiledRoutes;
    if (repeated != null) {
      _collectCompiled(repeated, normalized, pathDepth, methodRank, output);
    }
    _collectNode(state, normalized, methodRank, output);
    final compiled = state.compiledRoutes;
    if (compiled != null) {
      _collectCompiled(compiled, normalized, pathDepth, methodRank, output);
    }
    final late = state.lateCompiledRoutes;
    if (late != null) {
      _collectCompiled(late, normalized, pathDepth, methodRank, output);
    }
    final exactStatic = state.staticExactRoutes[_canonicalPath(normalized)];
    if (exactStatic != null) {
      _collectSlot(
        exactStatic,
        normalized,
        null,
        0,
        pathDepth,
        _staticRank,
        methodRank,
        output,
      );
    }
    final deferred = state.deferredCompiledRoutes;
    if (deferred != null) {
      _collectCompiled(deferred, normalized, pathDepth, methodRank, output);
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
        throw FormatException('$_emptySegment$pattern');
      }
      end -= 1;
    }

    var hasReservedToken = false;
    var prevSlash = true;
    for (var i = 1; i < end; i++) {
      final code = pattern.codeUnitAt(i);
      if (code == _slashCode) {
        if (prevSlash) {
          throw FormatException('$_emptySegment$pattern');
        }
        prevSlash = true;
        continue;
      }
      if (code == _colonCode ||
          code == _asteriskCode ||
          code == _openBraceCode ||
          code == _closeBraceCode ||
          code == _questionCode) {
        hasReservedToken = true;
      }
      prevSlash = false;
    }

    final normalized = end == pattern.length
        ? pattern
        : pattern.substring(0, end);
    final canonical = _canonicalPath(normalized);

    if (!hasReservedToken) {
      state.staticExactRoutes[canonical] = _mergedRoute(
        state.staticExactRoutes[canonical],
        _Route<T>(data, const <String>[], null),
        normalized,
        duplicatePolicy,
        _dupShape,
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
        if (code == _colonCode ||
            code == _asteriskCode ||
            code == _openBraceCode ||
            code == _closeBraceCode ||
            code == _questionCode) {
          hasReservedInSegment = true;
        }
        segmentEnd += 1;
      }

      final firstCode = pattern.codeUnitAt(cursor);
      final doubleWildcardName = _readDoubleWildcardName(
        pattern,
        cursor,
        segmentEnd,
      );
      if (doubleWildcardName != null) {
        if (segmentEnd != end) {
          throw FormatException(
            'Double wildcard must be the last segment: $normalized',
          );
        }
        final route = _Route<T>(
          data,
          paramNames ?? const <String>[],
          doubleWildcardName,
        );
        if (cursor == 1 && paramCount == 0) {
          state.hasSlowMatchPath = true;
          state.globalFallback = _mergedRoute(
            state.globalFallback,
            route,
            normalized,
            duplicatePolicy,
            _dupFallback,
          );
        } else {
          state.hasSlowMatchPath = true;
          node.wildcardRoute = _mergedRoute(
            node.wildcardRoute,
            route,
            normalized,
            duplicatePolicy,
            _dupWildcard,
          );
        }
        if (paramCount > state.maxParamDepth) state.maxParamDepth = paramCount;
        return;
      }

      if (firstCode == _colonCode) {
        if (!_isSimpleParamSegment(pattern, cursor + 1, segmentEnd)) {
          final compiled = _compilePatternRoute(normalized, data, _caseSensitive);
          if (compiled == null) {
            throw FormatException(
              'Unsupported segment syntax in route: $normalized',
            );
          }
          state.hasSlowMatchPath = true;
          _addCompiled(state, compiled, normalized, duplicatePolicy);
          if (compiled.route.paramNames.length > state.maxParamDepth) {
            state.maxParamDepth = compiled.route.paramNames.length;
          }
          return;
        }
        final paramName = pattern.substring(cursor + 1, segmentEnd);
        if (!_isValidParamName(paramName)) {
          throw FormatException('Invalid parameter name in route: $normalized');
        }
        node = node.paramChild ??= _Node<T>();
        (paramNames ??= <String>[]).add(paramName);
        paramCount += 1;
      } else {
        if (hasReservedInSegment) {
          final compiled = _compilePatternRoute(normalized, data, _caseSensitive);
          if (compiled == null) {
            throw FormatException(
              'Unsupported segment syntax in route: $normalized',
            );
          }
          state.hasSlowMatchPath = true;
          _addCompiled(state, compiled, normalized, duplicatePolicy);
          if (compiled.route.paramNames.length > state.maxParamDepth) {
            state.maxParamDepth = compiled.route.paramNames.length;
          }
          return;
        }
        node = node.getOrCreateStaticChildSlice(
          _canonicalLiteral(pattern.substring(cursor, segmentEnd)),
        );
      }
      cursor = segmentEnd + 1;
    }

    node.exactRoute = _mergedRoute(
      node.exactRoute,
      _Route<T>(data, paramNames ?? const <String>[], null),
      normalized,
      duplicatePolicy,
      _dupShape,
    );
    if (paramCount > state.maxParamDepth) state.maxParamDepth = paramCount;
  }

  RouteMatch<T>? _matchCompiled(_CompiledSlot<T> current, String path) {
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

  void _collectCompiled(
    _CompiledSlot<T> current,
    String path,
    int pathDepth,
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
            pathDepth,
            current.collectRank,
            methodRank,
          );
        }
      }
      final next = current.next;
      if (next == null) return;
      current = next;
    }
  }

  RouteMatch<T>? _matchNodePathFast(_MethodState<T> state, String path) {
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
        if (exact != null) return _materialize(exact, path, stackParams, 0);
        final wildcard = node.wildcardRoute;
        if (wildcard != null) {
          return _materialize(wildcard, path, stackParams, path.length);
        }
      } else {
        final segmentEnd = _findSegmentEnd(path, cursor);
        if (segmentEnd != cursor) {
          final nextCursor = segmentEnd < path.length
              ? segmentEnd + 1
              : path.length;
          final staticChild = node._findStaticChildSlice(
            path,
            cursor,
            segmentEnd,
            _caseSensitive,
          );
          final paramChild = node.paramChild;
          final wildcard = node.wildcardRoute;

          if (staticChild != null) {
            if (paramChild != null || wildcard != null) {
              stack = _Branch<T>(
                node,
                cursor,
                paramLength,
                segmentEnd,
                nextCursor,
                0,
                paramChild != null,
                stack,
              );
            }
            node = staticChild;
            cursor = nextCursor;
            continue top;
          }
          if (paramChild != null) {
            paramStack ??= _ParamStack(state.maxParamDepth);
            paramStack.truncate(paramLength);
            paramStack.push(cursor, segmentEnd);
            if (wildcard != null) {
              stack = _Branch<T>(
                node,
                cursor,
                paramLength,
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
            return _materialize(wildcard, path, stackParams, cursor);
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
        if (branch.pendingParam) {
          branch.pendingParam = false;
          paramStack ??= _ParamStack(state.maxParamDepth);
          paramStack.truncate(paramLength);
          paramStack.push(cursor, branch.depthOrSegmentEnd);
          node = node.paramChild!;
          cursor = branch.segmentStartOrNextCursor;
          paramLength = paramStack.length;
          continue top;
        }

        stack = branch.prev;
        final wildcard = node.wildcardRoute;
        if (wildcard != null) {
          return _materialize(wildcard, path, paramStack, cursor);
        }
      }
      return null;
    } while (true);
  }

  RouteMatch<T>? _matchNodePath(
    _MethodState<T> state,
    String path,
    bool allowWildcards,
  ) {
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
        if (exact != null) return _materialize(exact, path, stackParams, 0);
        final wildcard = node.wildcardRoute;
        if (allowWildcards && wildcard != null) {
          return _materialize(wildcard, path, stackParams, path.length);
        }
      } else {
        final segmentEnd = _findSegmentEnd(path, cursor);
        if (segmentEnd != cursor) {
          final nextCursor = segmentEnd < path.length
              ? segmentEnd + 1
              : path.length;
          final staticChild = node._findStaticChildSlice(
            path,
            cursor,
            segmentEnd,
            _caseSensitive,
          );
          final paramChild = node.paramChild;
          final wildcard = allowWildcards ? node.wildcardRoute : null;

          if (staticChild != null) {
            if (paramChild != null || wildcard != null) {
              stack = _Branch<T>(
                node,
                cursor,
                paramLength,
                segmentEnd,
                nextCursor,
                0,
                paramChild != null,
                stack,
              );
            }
            node = staticChild;
            cursor = nextCursor;
            continue top;
          }
          if (paramChild != null) {
            paramStack ??= _ParamStack(state.maxParamDepth);
            paramStack.truncate(paramLength);
            paramStack.push(cursor, segmentEnd);
            if (wildcard != null) {
              stack = _Branch<T>(
                node,
                cursor,
                paramLength,
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
          if (allowWildcards && wildcard != null) {
            return _materialize(wildcard, path, stackParams, cursor);
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
        if (branch.pendingParam) {
          branch.pendingParam = false;
          paramStack ??= _ParamStack(state.maxParamDepth);
          paramStack.truncate(paramLength);
          paramStack.push(cursor, branch.depthOrSegmentEnd);
          node = node.paramChild!;
          cursor = branch.segmentStartOrNextCursor;
          paramLength = paramStack.length;
          continue top;
        }

        stack = branch.prev;
        final wildcard = node.wildcardRoute;
        if (allowWildcards && wildcard != null) {
          return _materialize(wildcard, path, paramStack, cursor);
        }
      }
      return null;
    } while (true);
  }

  void _collectNode(
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
          _collectSlot(
            wildcard,
            path,
            stackParams,
            path.length,
            depth,
            _wildRank,
            methodRank,
            output,
          );
        }
        final exact = node.exactRoute;
        if (exact != null) {
          _collectSlot(
            exact,
            path,
            stackParams,
            0,
            depth,
            _paramRank,
            methodRank,
            output,
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
            _collectSlot(
              wildcard,
              path,
              stackParams,
              cursor,
              depth,
              _wildRank,
              methodRank,
              output,
            );
          }
          final staticChild = node._findStaticChildSlice(
            path,
            cursor,
            segmentEnd,
            _caseSensitive,
          );
          final paramChild = node.paramChild;
          if (staticChild != null) {
            if (paramChild != null) {
              stack = _Branch<T>(
                paramChild,
                nextCursor,
                paramLength,
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
            continue top;
          }
          if (paramChild != null) {
            paramStack ??= _ParamStack(state.maxParamDepth);
            paramStack.truncate(paramLength);
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
        paramStack.push(branch.segmentStartOrNextCursor, branch.segmentEnd);
        node = branch.node;
        cursor = branch.cursor;
        depth = branch.depthOrSegmentEnd;
        paramLength = paramStack.length;
        continue top;
      }
      return;
    } while (true);
  }

  RouteMatch<T> _materialize(
    _Route<T> route,
    String path,
    _ParamStack? paramValues,
    int wildcardStart,
  ) => route.wildcardName != null || route.paramNames.isNotEmpty
      ? RouteMatch<T>._lazy(route.data, route, path, paramValues, wildcardStart)
      : route.noParamsMatch;
  void _collectSlot(
    _Route<T> slot,
    String path,
    _ParamStack? paramValues,
    int wildcardStart,
    int depth,
    int routeKind,
    int methodRank,
    _MatchCollector<T> output,
  ) {
    if (slot.wildcardName != null || slot.paramNames.isNotEmpty) {
      final captures = paramValues?.snapshot();
      for (_Route<T>? current = slot; current != null; current = current.next) {
        output.add(
          RouteMatch<T>._lazy(
            current.data,
            current,
            path,
            captures,
            wildcardStart,
          ),
          depth,
          routeKind,
          methodRank,
        );
      }
      return;
    }
    for (_Route<T>? current = slot; current != null; current = current.next) {
      output.add(current.noParamsMatch, depth, routeKind, methodRank);
    }
  }

  _Route<T> _mergedRoute(
    _Route<T>? existing,
    _Route<T> route,
    String pattern,
    DuplicatePolicy duplicatePolicy,
    String rejectPrefix,
  ) => existing == null
      ? route
      : _resolveDup(existing, route, pattern, duplicatePolicy, rejectPrefix);

  _Route<T> _resolveDup(
    _Route<T> existing,
    _Route<T> replacement,
    String pattern,
    DuplicatePolicy duplicatePolicy,
    String rejectPrefix,
  ) {
    final a = existing.paramNames, b = replacement.paramNames;
    if (a.length != b.length) throw FormatException('$_dupShape$pattern');
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) throw FormatException('$_dupShape$pattern');
    }
    if (existing.wildcardName != replacement.wildcardName) {
      throw FormatException('$_dupShape$pattern');
    }
    return switch (duplicatePolicy) {
      DuplicatePolicy.reject => throw FormatException('$rejectPrefix$pattern'),
      DuplicatePolicy.replace => replacement,
      DuplicatePolicy.keepFirst => existing,
      DuplicatePolicy.append => existing.appended(replacement),
    };
  }

  void _addCompiled(
    _MethodState<T> state,
    _CompiledSlot<T> compiled,
    String pattern,
    DuplicatePolicy duplicatePolicy,
  ) {
    final head = switch (compiled.bucket) {
      _compiledBucketHigh => state.compiledRoutes,
      _compiledBucketRepeated => state.repeatedCompiledRoutes,
      _compiledBucketLate => state.lateCompiledRoutes,
      _compiledBucketDeferred => state.deferredCompiledRoutes,
      _ => throw StateError('Invalid compiled bucket: ${compiled.bucket}'),
    };
    _CompiledSlot<T>? prev;
    for (var current = head; current != null; current = current.next) {
      if (current.shape != compiled.shape) {
        prev = current;
        continue;
      }
      _verifyCompiledNames(
        current.route.paramNames,
        compiled.route.paramNames,
        pattern,
      );
      current.route = _resolveDup(
        current.route,
        compiled.route,
        pattern,
        duplicatePolicy,
        _dupShape,
      );
      return;
    }

    if (prev == null) {
      switch (compiled.bucket) {
        case _compiledBucketHigh:
          compiled.next = state.compiledRoutes;
          state.compiledRoutes = compiled;
        case _compiledBucketRepeated:
          compiled.next = state.repeatedCompiledRoutes;
          state.repeatedCompiledRoutes = compiled;
        case _compiledBucketLate:
          compiled.next = state.lateCompiledRoutes;
          state.lateCompiledRoutes = compiled;
        case _compiledBucketDeferred:
          compiled.next = state.deferredCompiledRoutes;
          state.deferredCompiledRoutes = compiled;
      }
      return;
    }
    prev.next = compiled;
  }

  void _verifyCompiledNames(List<String> a, List<String> b, String pattern) {
    if (a.length != b.length) throw FormatException('$_dupShape$pattern');
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) throw FormatException('$_dupShape$pattern');
    }
  }

  RouteMatch<T> _materializeCompiled(
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
}

class _MethodState<T> {
  final _Node<T> root = _Node<T>();
  bool hasSlowMatchPath = false;
  _Route<T>? globalFallback;
  _CompiledSlot<T>? compiledRoutes;
  _CompiledSlot<T>? repeatedCompiledRoutes;
  _CompiledSlot<T>? lateCompiledRoutes;
  _CompiledSlot<T>? deferredCompiledRoutes;
  final Map<String, _Route<T>> staticExactRoutes = <String, _Route<T>>{};
  int maxParamDepth = 0;
}

class _Branch<T> {
  final _Node<T> node;
  final int cursor,
      paramLength,
      depthOrSegmentEnd,
      segmentStartOrNextCursor,
      segmentEnd;
  bool pendingParam;
  final _Branch<T>? prev;
  _Branch(
    this.node,
    this.cursor,
    this.paramLength,
    this.depthOrSegmentEnd,
    this.segmentStartOrNextCursor,
    this.segmentEnd,
    this.pendingParam,
    this.prev,
  );
}

class _Route<T> {
  final T data;
  final List<String> paramNames;
  final String? wildcardName;
  _Route<T>? next;
  late final RouteMatch<T> noParamsMatch = RouteMatch<T>(data);
  _Route(this.data, this.paramNames, this.wildcardName);
  _Route<T> appended(_Route<T> route) {
    var current = this;
    while (current.next != null) {
      current = current.next!;
    }
    current.next = route;
    return this;
  }
}

class _CompiledSlot<T> {
  final RegExp regex;
  final String shape;
  final int bucket;
  final int collectRank;
  final List<int> groupIndexes;
  _Route<T> route;
  _CompiledSlot<T>? next;
  _CompiledSlot(
    this.regex,
    this.shape,
    this.bucket,
    this.collectRank,
    this.groupIndexes,
    this.route,
  );
}

class _LazyParamsMap extends MapBase<String, String> {
  final List<String> _names;
  final String? _wildcardName;
  final String _path;
  final _ParamStack? _captures;
  final int _wildcardStart;
  Map<String, String>? _map;
  _LazyParamsMap(
    this._names,
    this._wildcardName,
    this._path,
    this._captures,
    this._wildcardStart,
  );
  Map<String, String> get _materialized => _map ??= _materialize();
  _ParamStack get _requiredCaptures =>
      _captures ?? (throw StateError(_missingCaptures));
  String get _wildcardValue =>
      _wildcardStart < _path.length ? _path.substring(_wildcardStart) : '';
  @override
  String? operator [](Object? key) {
    if (key is! String) return null;
    final map = _map;
    if (map != null) return map[key];
    if (_wildcardName != null && key == _wildcardName) return _wildcardValue;
    for (var i = 0; i < _names.length; i++) {
      if (_names[i] == key) {
        final captures = _requiredCaptures;
        return _path.substring(captures.startAt(i), captures.endAt(i));
      }
    }
    return null;
  }

  @override
  void operator []=(String key, String value) => _materialized[key] = value;
  @override
  void clear() => _materialized.clear();
  @override
  Iterable<String> get keys =>
      _map?.keys ??
      (_wildcardName == null ? _names : _names.followedBy([_wildcardName]));
  @override
  String? remove(Object? key) =>
      key is String ? _materialized.remove(key) : null;
  @override
  int get length =>
      _map?.length ?? _names.length + (_wildcardName == null ? 0 : 1);
  Map<String, String> _materialize() {
    final map = <String, String>{};
    if (_names.isNotEmpty) {
      final captures = _requiredCaptures;
      for (var i = 0; i < _names.length; i++) {
        map[_names[i]] = _path.substring(
          captures.startAt(i),
          captures.endAt(i),
        );
      }
    }
    if (_wildcardName != null) map[_wildcardName] = _wildcardValue;
    return map;
  }
}

class _Node<T> {
  final String? _staticKey;
  _Node<T>? _staticChild, _staticNext, paramChild;
  Map<String, _Node<T>>? _staticMap;
  int _staticCount = 0;
  _Route<T>? exactRoute, wildcardRoute;
  _Node([this._staticKey]);
  _Node<T> getOrCreateStaticChildSlice(String key) {
    final map = _staticMap;
    if (map != null) {
      return map[key] ??= _Node<T>(key);
    }
    final child = _findStaticChild(key);
    if (child != null) return child;
    final created = _Node<T>(key);
    created._staticNext = _staticChild;
    _staticChild = created;
    if (++_staticCount >= _mapAt) {
      final upgraded = <String, _Node<T>>{};
      for (var node = _staticChild; node != null; node = node._staticNext) {
        upgraded[node._staticKey!] = node;
      }
      _staticMap = upgraded;
    }
    return created;
  }

  _Node<T>? _findStaticChildSlice(
    String path,
    int start,
    int end,
    bool caseSensitive,
  ) {
    if (!caseSensitive) {
      return _findStaticChild(path.substring(start, end).toLowerCase());
    }
    final map = _staticMap;
    if (map != null) return map[path.substring(start, end)];
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

  _Node<T>? _findStaticChild(String key) {
    final map = _staticMap;
    if (map != null) return map[key];
    _Node<T>? prev;
    var child = _staticChild;
    while (child != null) {
      if (child._staticKey == key) {
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

bool _equalsPathSlice(String key, String path, int start, int end) {
  if (key.length != end - start) return false;
  for (var i = 0; i < key.length; i++) {
    if (key.codeUnitAt(i) != path.codeUnitAt(start + i)) return false;
  }
  return true;
}

String? _normalizeInputPath(String path) {
  if (path.isEmpty || path.codeUnitAt(0) != _slashCode) return null;
  final last = path.length - 1;
  if (path.length > 1 && path.codeUnitAt(last) == _slashCode) {
    if (path.codeUnitAt(last - 1) == _slashCode) return null;
    path = path.substring(0, last);
  }
  for (var i = 1; i < path.length; i++) {
    if (path.codeUnitAt(i - 1) == _slashCode &&
        path.codeUnitAt(i) == _slashCode) {
      return null;
    }
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

int _pathDepth(String path) {
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
  void add(RouteMatch<T> match, int depth, int routeKind, int methodRank) {
    final index = depth * 6 + routeKind * 2 + methodRank;
    (_buckets[index] ??= <RouteMatch<T>>[]).add(match);
    _count += 1;
  }

  List<RouteMatch<T>> finish() {
    if (_count == 0) return <RouteMatch<T>>[];
    final result = List<RouteMatch<T>?>.filled(_count, null, growable: false);
    var offset = 0;
    for (final bucket in _buckets) {
      if (bucket == null) continue;
      for (final match in bucket) {
        result[offset++] = match;
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
  _ParamStack snapshot() {
    final copy = _ParamStack(_values.length ~/ 2);
    for (var i = 0; i < _length; i++) {
      copy._values[i] = _values[i];
    }
    copy._length = _length;
    return copy;
  }
}

bool _isValidParamName(String name) {
  if (name.isEmpty) return false;
  var code = name.codeUnitAt(0);
  if (!(((code | 32) >= 97 && (code | 32) <= 122) || code == 95)) return false;
  for (var i = 1; i < name.length; i++) {
    code = name.codeUnitAt(i);
    if (!(((code | 32) >= 97 && (code | 32) <= 122) ||
        code == 95 ||
        (code >= 48 && code <= 57))) {
      return false;
    }
  }
  return true;
}

bool _isSimpleParamSegment(String pattern, int start, int end) =>
    start < end && _isValidParamName(pattern.substring(start, end));

_CompiledSlot<T>? _compilePatternRoute<T>(
  String pattern,
  T data,
  bool caseSensitive,
) {
  if (pattern.contains('{')) {
    return _compileGroupedRoute(pattern, data, caseSensitive);
  }
  var needsCompiled = false;
  var bucket = _compiledBucketHigh;
  var collectRank = _paramRank;
  final regex = StringBuffer('^');
  final shape = StringBuffer('^');
  final paramNames = <String>[];
  final groupIndexes = <int>[];
  var groupCount = 0;
  var unnamedCount = 0;
  var cursor = pattern.length == 1 ? pattern.length : 1;
  while (cursor < pattern.length) {
    final segmentEnd = _findSegmentEnd(pattern, cursor);
    final firstCode = pattern.codeUnitAt(cursor);
    if (segmentEnd == cursor) {
      throw FormatException('$_emptySegment$pattern');
    }
    if (firstCode == _colonCode &&
        _isSimpleParamSegment(pattern, cursor + 1, segmentEnd)) {
      cursor = segmentEnd + 1;
      continue;
    }
    if (segmentEnd - cursor == 1 && firstCode == _asteriskCode) {
      regex.write('/([^/]+)');
      shape.write('/([^/]+)');
      paramNames.add('${unnamedCount++}');
      groupCount += 1;
      groupIndexes.add(groupCount);
      needsCompiled = true;
      bucket = _compiledBucketLate;
      collectRank = _staticRank;
      cursor = segmentEnd + 1;
      continue;
    }
    final repeated = _readRepeatedParam(pattern, cursor, segmentEnd);
    if (repeated != null) {
      final quantifier = repeated.$2;
      if (quantifier == _plusCode) {
        regex.write('/(.+(?:/.+)*)');
        shape.write('/(.+(?:/.+)*)');
      } else {
        regex.write('(?:/(.*))?');
        shape.write('(?:/(.*))?');
      }
      paramNames.add(repeated.$1);
      groupCount += 1;
      groupIndexes.add(groupCount);
      needsCompiled = true;
      bucket = _compiledBucketRepeated;
      collectRank = _paramRank;
      cursor = segmentEnd + 1;
      continue;
    }
    final optionalName = _readOptionalParamName(pattern, cursor, segmentEnd);
    if (optionalName != null) {
      regex.write('(?:/([^/]+))?');
      shape.write('(?:/([^/]+))?');
      paramNames.add(optionalName);
      groupCount += 1;
      groupIndexes.add(groupCount);
      needsCompiled = true;
      bucket = _compiledBucketDeferred;
      collectRank = _staticRank;
      cursor = segmentEnd + 1;
      continue;
    }

    regex.write('/');
    shape.write('/');

    var segmentCursor = cursor;
    var lastWasParam = false;
    while (segmentCursor < segmentEnd) {
      final code = pattern.codeUnitAt(segmentCursor);
      if (code == _asteriskCode) {
        regex.write('([^/]*)');
        shape.write('([^/]*)');
        paramNames.add('${unnamedCount++}');
        groupCount += 1;
        groupIndexes.add(groupCount);
        needsCompiled = true;
        collectRank = _wildRank;
        segmentCursor += 1;
        lastWasParam = false;
        continue;
      }
      if (code == _colonCode) {
        if (lastWasParam) {
          throw FormatException(
            'Unsupported segment syntax in route: $pattern',
          );
        }
        var nameEnd = segmentCursor + 1;
        while (nameEnd < segmentEnd &&
            _isParamNameCode(
              pattern.codeUnitAt(nameEnd),
              nameEnd == segmentCursor + 1,
            )) {
          nameEnd += 1;
        }
        final paramName = pattern.substring(segmentCursor + 1, nameEnd);
        if (!_isValidParamName(paramName)) {
          throw FormatException('Invalid parameter name in route: $pattern');
        }
        if (nameEnd < segmentEnd && pattern.codeUnitAt(nameEnd) == 40) {
          final regexEnd = _findRegexEnd(pattern, nameEnd, segmentEnd);
          final body = pattern.substring(nameEnd + 1, regexEnd);
          regex
            ..write('(')
            ..write(body)
            ..write(')');
          shape
            ..write('(')
            ..write(body)
            ..write(')');
          groupCount += 1;
          groupIndexes.add(groupCount);
          groupCount += _countCapturingGroups(body);
          segmentCursor = regexEnd + 1;
        } else {
          regex.write('([^/]+)');
          shape.write('([^/]+)');
          groupCount += 1;
          groupIndexes.add(groupCount);
          segmentCursor = nameEnd;
        }
        paramNames.add(paramName);
        lastWasParam = true;
        needsCompiled = true;
        continue;
      }

      final literalStart = segmentCursor;
      segmentCursor += 1;
      while (segmentCursor < segmentEnd) {
        final literalCode = pattern.codeUnitAt(segmentCursor);
        if (literalCode == _colonCode || literalCode == _asteriskCode) break;
        segmentCursor += 1;
      }
      final literal = pattern.substring(literalStart, segmentCursor);
      regex.write(RegExp.escape(literal));
      shape.write(
        RegExp.escape(caseSensitive ? literal : literal.toLowerCase()),
      );
      lastWasParam = false;
    }
    cursor = segmentEnd + 1;
  }
  regex.write(r'$');
  shape.write(r'$');
  if (!needsCompiled) return null;
  return _CompiledSlot<T>(
    RegExp(regex.toString(), caseSensitive: caseSensitive),
    shape.toString(),
    bucket,
    collectRank,
    groupIndexes,
    _Route<T>(data, paramNames, null),
  );
}

_CompiledSlot<T> _compileGroupedRoute<T>(
  String pattern,
  T data,
  bool caseSensitive,
) {
  final regex = StringBuffer('^');
  final shape = StringBuffer('^');
  final paramNames = <String>[];
  final groupIndexes = <int>[];
  var groupCount = 0;
  var unnamedCount = 0;
  var hasWildcard = false;

  void writeChunk(StringBuffer targetRegex, StringBuffer targetShape, int start, int end) {
    var cursor = start;
    while (cursor < end) {
      final code = pattern.codeUnitAt(cursor);
      if (code == _openBraceCode) {
        final close = _findGroupEnd(pattern, cursor + 1, end);
        final optional = close + 1 < end && pattern.codeUnitAt(close + 1) == _questionCode;
        final innerRegex = StringBuffer();
        final innerShape = StringBuffer();
        writeChunk(innerRegex, innerShape, cursor + 1, close);
        targetRegex
          ..write('(?:')
          ..write(innerRegex)
          ..write(optional ? ')?' : ')');
        targetShape
          ..write('(?:')
          ..write(innerShape)
          ..write(optional ? ')?' : ')');
        cursor = optional ? close + 2 : close + 1;
        continue;
      }
      if (code == _asteriskCode) {
        if (cursor + 1 < end && pattern.codeUnitAt(cursor + 1) == _asteriskCode) {
          throw FormatException('Unsupported group syntax in route: $pattern');
        }
        targetRegex.write('([^/]*)');
        targetShape.write('([^/]*)');
        paramNames.add('${unnamedCount++}');
        groupCount += 1;
        groupIndexes.add(groupCount);
        hasWildcard = true;
        cursor += 1;
        continue;
      }
      if (code == _colonCode) {
        var nameEnd = cursor + 1;
        while (nameEnd < end &&
            _isParamNameCode(
              pattern.codeUnitAt(nameEnd),
              nameEnd == cursor + 1,
            )) {
          nameEnd += 1;
        }
        final paramName = pattern.substring(cursor + 1, nameEnd);
        if (!_isValidParamName(paramName)) {
          throw FormatException('Invalid parameter name in route: $pattern');
        }
        if (nameEnd < end && pattern.codeUnitAt(nameEnd) == 40) {
          final regexEnd = _findRegexEnd(pattern, nameEnd, end);
          final body = pattern.substring(nameEnd + 1, regexEnd);
          targetRegex
            ..write('(')
            ..write(body)
            ..write(')');
          targetShape
            ..write('(')
            ..write(body)
            ..write(')');
          groupCount += 1;
          groupIndexes.add(groupCount);
          groupCount += _countCapturingGroups(body);
          cursor = regexEnd + 1;
        } else {
          targetRegex.write('([^/]+)');
          targetShape.write('([^/]+)');
          groupCount += 1;
          groupIndexes.add(groupCount);
          cursor = nameEnd;
        }
        paramNames.add(paramName);
        continue;
      }
      if (code == _questionCode || code == _closeBraceCode) {
        throw FormatException('Unsupported group syntax in route: $pattern');
      }

      final literalStart = cursor;
      cursor += 1;
      while (cursor < end) {
        final literalCode = pattern.codeUnitAt(cursor);
        if (literalCode == _openBraceCode ||
            literalCode == _closeBraceCode ||
            literalCode == _questionCode ||
            literalCode == _colonCode ||
            literalCode == _asteriskCode) {
          break;
        }
        cursor += 1;
      }
      final literal = pattern.substring(literalStart, cursor);
      targetRegex.write(RegExp.escape(literal));
      targetShape.write(
        RegExp.escape(caseSensitive ? literal : literal.toLowerCase()),
      );
    }
  }

  writeChunk(regex, shape, 0, pattern.length);
  regex.write(r'$');
  shape.write(r'$');
  return _CompiledSlot<T>(
    RegExp(regex.toString(), caseSensitive: caseSensitive),
    shape.toString(),
    _compiledBucketDeferred,
    hasWildcard ? _wildRank : _staticRank,
    groupIndexes,
    _Route<T>(data, paramNames, null),
  );
}

bool _isParamNameCode(int code, bool first) {
  if (first) {
    return ((code | 32) >= 97 && (code | 32) <= 122) || code == 95;
  }
  return ((code | 32) >= 97 && (code | 32) <= 122) ||
      code == 95 ||
      (code >= 48 && code <= 57);
}

String? _readOptionalParamName(String pattern, int start, int end) {
  if (start >= end || pattern.codeUnitAt(start) != _colonCode) return null;
  if (pattern.codeUnitAt(end - 1) != _questionCode) return null;
  final name = pattern.substring(start + 1, end - 1);
  return _isValidParamName(name) ? name : null;
}

const _questionCode = 63, _plusCode = 43;

String? _readDoubleWildcardName(String pattern, int start, int end) {
  if (end - start == 2 &&
      pattern.codeUnitAt(start) == _asteriskCode &&
      pattern.codeUnitAt(start + 1) == _asteriskCode) {
    return '_';
  }
  if (end - start <= 3 ||
      pattern.codeUnitAt(start) != _asteriskCode ||
      pattern.codeUnitAt(start + 1) != _asteriskCode ||
      pattern.codeUnitAt(start + 2) != _colonCode) {
    return null;
  }
  final name = pattern.substring(start + 3, end);
  return _isValidParamName(name) ? name : null;
}

(String, int)? _readRepeatedParam(String pattern, int start, int end) {
  if (start >= end || pattern.codeUnitAt(start) != _colonCode) return null;
  final last = pattern.codeUnitAt(end - 1);
  if (last != _asteriskCode && last != _plusCode) return null;
  final name = pattern.substring(start + 1, end - 1);
  if (!_isValidParamName(name)) return null;
  return (name, last);
}

int _findGroupEnd(String pattern, int start, int end) {
  var depth = 0;
  var cursor = start;
  while (cursor < end) {
    final code = pattern.codeUnitAt(cursor);
    if (code == _openBraceCode) {
      depth += 1;
      cursor += 1;
      continue;
    }
    if (code == _closeBraceCode) {
      if (depth == 0) return cursor;
      depth -= 1;
      cursor += 1;
      continue;
    }
    if (code == _colonCode) {
      var nameEnd = cursor + 1;
      while (nameEnd < end &&
          _isParamNameCode(
            pattern.codeUnitAt(nameEnd),
            nameEnd == cursor + 1,
          )) {
        nameEnd += 1;
      }
      if (nameEnd < end && pattern.codeUnitAt(nameEnd) == 40) {
        cursor = _findRegexEnd(pattern, nameEnd, end) + 1;
        continue;
      }
    }
    cursor += 1;
  }
  throw FormatException('Unclosed group in route: $pattern');
}

int _findRegexEnd(String pattern, int start, int segmentEnd) {
  var depth = 0;
  var escaped = false;
  var inCharClass = false;
  for (var i = start; i < segmentEnd; i++) {
    final code = pattern.codeUnitAt(i);
    if (escaped) {
      escaped = false;
      continue;
    }
    if (code == 92) {
      escaped = true;
      continue;
    }
    if (inCharClass) {
      if (code == 93) inCharClass = false;
      continue;
    }
    if (code == 91) {
      inCharClass = true;
      continue;
    }
    if (code == 40) {
      depth += 1;
      continue;
    }
    if (code == 41) {
      depth -= 1;
      if (depth == 0) return i;
    }
  }
  throw FormatException('Unterminated regex in route: $pattern');
}

int _countCapturingGroups(String pattern) {
  var count = 0;
  var escaped = false;
  var inCharClass = false;
  for (var i = 0; i < pattern.length; i++) {
    final code = pattern.codeUnitAt(i);
    if (escaped) {
      escaped = false;
      continue;
    }
    if (code == 92) {
      escaped = true;
      continue;
    }
    if (inCharClass) {
      if (code == 93) inCharClass = false;
      continue;
    }
    if (code == 91) {
      inCharClass = true;
      continue;
    }
    if (code != 40) continue;
    if (i + 1 >= pattern.length || pattern.codeUnitAt(i + 1) != 63) {
      count += 1;
      continue;
    }
    if (i + 2 < pattern.length && pattern.codeUnitAt(i + 2) == 60) {
      if (i + 3 < pattern.length) {
        final next = pattern.codeUnitAt(i + 3);
        if (next != 61 && next != 33) count += 1;
      }
    }
  }
  return count;
}
