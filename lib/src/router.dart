const _slashCode = 47;
const _asteriskCode = 42;
const _colonCode = 58;
const _staticMapUpgradeThreshold = 8;
const _wildcardSpecificityRank = 0;
const _paramSpecificityRank = 1;
const _staticSpecificityRank = 2;

enum DuplicatePolicy { reject, replace, keepFirst, append }

/// Match result produced by [Router.match].
class RouteMatch<T> {
  final T data;
  final Map<String, String>? params;

  const RouteMatch(this.data, [this.params]);
}

final class _LazyRouteMatch<T> extends RouteMatch<T> {
  final List<String> _paramNames;
  final bool _hasWildcard;
  final String _path;
  final _ParamStack? _paramValues;
  final String? _wildcardValue;
  final int _wildcardStart;
  Map<String, String>? _cachedParams;

  _LazyRouteMatch({
    required T data,
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
       _wildcardStart = wildcardStart,
       super(data);

  @override
  Map<String, String>? get params {
    final cached = _cachedParams;
    if (cached != null) {
      return cached;
    }
    if (_paramNames.isEmpty && !_hasWildcard) {
      return null;
    }

    // Params are materialized lazily so data-only consumers avoid allocations.
    final params = <String, String>{};
    if (_paramNames.isNotEmpty) {
      final captured = _paramValues;
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
      params['wildcard'] = _wildcardValue ?? _path.substring(_wildcardStart);
    }

    _cachedParams = params;
    return params;
  }
}

/// Path router with static, parameter and wildcard matching.
///
/// Route precedence is fixed:
/// 1. static segment
/// 2. parameter segment (`:id`)
/// 3. wildcard (`*`)
/// 4. global fallback (`/*`)
class Router<T> {
  // Default bucket for routes without an explicit HTTP method.
  final _MethodState<T> _anyState = _MethodState<T>();
  // Method-specific buckets keyed by normalized method token (for example GET).
  Map<String, _MethodState<T>>? _methodStates;
  final Map<String, String> _methodTokenCache = <String, String>{};
  final DuplicatePolicy _duplicatePolicy;

  /// Creates a router and optionally registers initial `ANY` routes.
  Router({
    Map<String, T>? routes,
    DuplicatePolicy duplicatePolicy = DuplicatePolicy.reject,
  }) : _duplicatePolicy = duplicatePolicy {
    if (routes != null && routes.isNotEmpty) {
      addAll(routes);
    }
  }

  /// Registers one route.
  ///
  /// When [method] is omitted the route is stored in the `ANY` bucket.
  /// Path syntax supports:
  /// - static segments (`/users/all`)
  /// - parameters (`/users/:id`)
  /// - wildcard tail (`/assets/*`)
  /// - global fallback (`/*`)
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
      normalized.path,
      data,
      duplicatePolicy: _effectiveDuplicatePolicy(duplicatePolicy),
      hasReservedToken: normalized.hasReservedToken,
    );
  }

  /// Registers multiple routes in the same method bucket.
  ///
  /// Passing `method: null` registers all routes as `ANY`.
  void addAll(
    Map<String, T> routes, {
    String? method,
    DuplicatePolicy? duplicatePolicy,
  }) {
    final state = _stateForWrite(method);
    final effectivePolicy = _effectiveDuplicatePolicy(duplicatePolicy);
    for (final entry in routes.entries) {
      final normalized = _normalizePatternForCompile(entry.key);
      _addCompiledPattern(
        state,
        normalized.path,
        entry.value,
        duplicatePolicy: effectivePolicy,
        hasReservedToken: normalized.hasReservedToken,
      );
    }
  }

  /// Matches [path] and returns route data with lazily materialized params.
  ///
  /// If [method] is provided, the router first checks that specific bucket and
  /// then falls back to `ANY` when there is no hit. If duplicate entries are
  /// retained in the winning slot, the earliest retained entry is returned.
  RouteMatch<T>? match(String path, {String? method}) {
    final normalized = _normalizeInputPath(path);
    if (normalized == null) {
      return null;
    }

    if (method != null) {
      // Method-specific routes have precedence over the ANY bucket.
      final methodToken = _normalizeMethodToken(method);
      final methodState = _methodStates?[methodToken];
      if (methodState != null) {
        final matched = _matchInState(methodState, normalized);
        if (matched != null) {
          return matched;
        }
      }
    }

    return _matchInState(_anyState, normalized);
  }

  /// Matches [path] and returns every matching route from less specific to
  /// more specific.
  ///
  /// When [method] is provided, both the `ANY` bucket and the exact method
  /// bucket participate in the result. Duplicate entries retained in the same
  /// slot are expanded in registration order. Invalid paths return an empty
  /// list.
  List<RouteMatch<T>> matchAll(String path, {String? method}) {
    final normalized = _normalizeInputPath(path);
    if (normalized == null) {
      return <RouteMatch<T>>[];
    }

    final collected = <_CollectedMatch<T>>[];
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

    if (collected.isEmpty) {
      return <RouteMatch<T>>[];
    }

    collected.sort(_compareCollectedMatches);
    return <RouteMatch<T>>[
      for (final collectedMatch in collected) collectedMatch.match,
    ];
  }

  DuplicatePolicy _effectiveDuplicatePolicy(DuplicatePolicy? override) {
    return override ?? _duplicatePolicy;
  }

  _MethodState<T> _stateForWrite(String? method) {
    // Method buckets are created lazily to keep the default ANY-only path light.
    if (method == null) {
      return _anyState;
    }
    final token = _normalizeMethodToken(method);
    final states = _methodStates ??= <String, _MethodState<T>>{};
    return states.putIfAbsent(token, _MethodState<T>.new);
  }

  String _normalizeMethodToken(String method) {
    final cached = _methodTokenCache[method];
    if (cached != null) {
      return cached;
    }

    final trimmed = method.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(method, 'method', 'Method must not be empty.');
    }

    // Cache multiple spellings so repeated method normalization is cheap.
    final token = trimmed.toUpperCase();
    _methodTokenCache[method] = token;
    _methodTokenCache[trimmed] = token;
    _methodTokenCache[token] = token;
    return token;
  }

  RouteMatch<T>? _matchInState(_MethodState<T> state, String normalized) {
    // Fast path for exact static hits: length pre-filter then map lookup.
    if (state.staticExactPathLengths.contains(normalized.length)) {
      final exactStatic = state.staticExactRoutes[normalized];
      if (exactStatic != null) {
        return exactStatic.first.noParamsMatch;
      }
    }

    final start = normalized.length == 1 ? normalized.length : 1;
    final matched = _matchNodePath(state, state.root, normalized, start, null);
    if (matched != null) {
      return matched;
    }

    final fallback = state.globalFallback;
    if (fallback == null) {
      return null;
    }
    final wildcardValue = normalized.length == 1 ? '' : normalized.substring(1);
    return _materializeMatch(
      fallback.first,
      normalized,
      null,
      wildcardValue,
      0,
    );
  }

  void _collectAllInState(
    _MethodState<T> state,
    String normalized, {
    required int methodRank,
    required List<_CollectedMatch<T>> output,
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
      state.root,
      normalized,
      start,
      null,
      0,
      methodRank,
      output,
    );

    if (state.staticExactPathLengths.contains(normalized.length)) {
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
  }

  void _addCompiledPattern(
    _MethodState<T> state,
    String pattern,
    T data, {
    required DuplicatePolicy duplicatePolicy,
    required bool hasReservedToken,
  }) {
    // Global fallback applies only when no more specific route matches.
    if (pattern == '/*') {
      final route = _Route<T>(
        data: data,
        paramNames: const <String>[],
        hasWildcard: true,
      );
      final existing = state.globalFallback;
      if (existing != null) {
        final resolved = _resolveDuplicateSlot(
          existing: existing,
          replacement: route,
          pattern: pattern,
          duplicatePolicy: duplicatePolicy,
          rejectMessage: 'Duplicate global fallback route: $pattern',
        );
        if (identical(resolved, existing)) {
          return;
        }
        state.globalFallback = resolved;
        return;
      }
      state.globalFallback = _RouteSlot<T>.single(route);
      return;
    }

    if (!hasReservedToken) {
      // Pure static patterns bypass trie construction and go directly to exact map.
      final existing = state.staticExactRoutes[pattern];
      if (existing != null) {
        final route = _Route<T>(
          data: data,
          paramNames: const <String>[],
          hasWildcard: false,
        );
        final resolved = _resolveDuplicateSlot(
          existing: existing,
          replacement: route,
          pattern: pattern,
          duplicatePolicy: duplicatePolicy,
          rejectMessage:
              'Duplicate route shape conflicts with existing route: $pattern',
        );
        if (identical(resolved, existing)) {
          return;
        }
        state.staticExactRoutes[pattern] = resolved;
        return;
      }
      final route = _Route<T>(
        data: data,
        paramNames: const <String>[],
        hasWildcard: false,
      );
      state.staticExactRoutes[pattern] = _RouteSlot<T>.single(route);
      state.staticExactPathLengths.add(pattern.length);
      return;
    }

    List<String>? paramNames;
    var paramCount = 0;
    var node = state.root;
    var cursor = pattern.length == 1 ? pattern.length : 1;

    // Single-pass segment scanner used for compile-time insertion.
    while (cursor < pattern.length) {
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
      final isLastSegment = segmentEnd == pattern.length;

      if (segmentLength == 1 && firstCode == _asteriskCode) {
        if (!isLastSegment) {
          throw FormatException('Wildcard must be the last segment: $pattern');
        }
        final route = _Route<T>(
          data: data,
          paramNames: paramNames ?? const <String>[],
          hasWildcard: true,
        );
        final existing = node.wildcardRoute;
        if (existing != null) {
          final resolved = _resolveDuplicateSlot(
            existing: existing,
            replacement: route,
            pattern: pattern,
            duplicatePolicy: duplicatePolicy,
            rejectMessage:
                'Duplicate wildcard route shape at prefix for pattern: $pattern',
          );
          if (identical(resolved, existing)) {
            return;
          }
          node.wildcardRoute = resolved;
          return;
        }
        node.wildcardRoute = _RouteSlot<T>.single(route);
        if (paramCount > state.maxParamDepth) {
          state.maxParamDepth = paramCount;
          state.paramStackCapacity = state.maxParamDepth == 0
              ? 1
              : state.maxParamDepth;
        }
        return;
      }

      if (firstCode == _colonCode) {
        final paramName = pattern.substring(cursor + 1, segmentEnd);
        if (!_isValidParamName(paramName)) {
          throw FormatException('Invalid parameter name in route: $pattern');
        }
        node.paramChild ??= _Node<T>();
        node = node.paramChild!;
        (paramNames ??= <String>[]).add(paramName);
        paramCount += 1;
      } else if (hasReservedInSegment) {
        throw FormatException('Unsupported segment syntax in route: $pattern');
      } else {
        final segment = pattern.substring(cursor, segmentEnd);
        node = node.getOrCreateStaticChild(segment);
      }

      cursor = segmentEnd + 1;
    }

    final route = _Route<T>(
      data: data,
      paramNames: paramNames ?? const <String>[],
      hasWildcard: false,
    );
    final existing = node.exactRoute;
    if (existing != null) {
      final resolved = _resolveDuplicateSlot(
        existing: existing,
        replacement: route,
        pattern: pattern,
        duplicatePolicy: duplicatePolicy,
        rejectMessage:
            'Duplicate route shape conflicts with existing route: $pattern',
      );
      if (identical(resolved, existing)) {
        return;
      }
      node.exactRoute = resolved;
      return;
    }
    node.exactRoute = _RouteSlot<T>.single(route);
    if (paramCount == 0) {
      state.staticExactRoutes[pattern] = node.exactRoute!;
      state.staticExactPathLengths.add(pattern.length);
    }
    if (paramCount > state.maxParamDepth) {
      state.maxParamDepth = paramCount;
      state.paramStackCapacity = state.maxParamDepth == 0
          ? 1
          : state.maxParamDepth;
    }
  }

  RouteMatch<T>? _matchNodePath(
    _MethodState<T> state,
    _Node<T> node,
    String path,
    int cursor,
    _ParamStack? paramStack,
  ) {
    if (cursor >= path.length) {
      final exact = node.exactRoute;
      if (exact != null) {
        return _materializeMatch(exact.first, path, paramStack, null, 0);
      }

      final wildcard = node.wildcardRoute;
      if (wildcard != null) {
        return _materializeMatch(wildcard.first, path, paramStack, '', 0);
      }
      return null;
    }

    final segmentEnd = _findSegmentEnd(path, cursor);
    if (segmentEnd == cursor) {
      return null;
    }
    final nextCursor = segmentEnd < path.length ? segmentEnd + 1 : path.length;

    // Precedence must remain static > param > wildcard.
    final staticChild = node.lookupStaticChildSlice(path, cursor, segmentEnd);
    if (staticChild != null) {
      final matched = _matchNodePath(
        state,
        staticChild,
        path,
        nextCursor,
        paramStack,
      );
      if (matched != null) {
        return matched;
      }
    }

    final paramChild = node.paramChild;
    if (paramChild != null) {
      // Allocate/capture param stack only when a parameter branch is visited.
      final stack = paramStack ?? _ParamStack(state.paramStackCapacity);
      stack.push(cursor, segmentEnd);
      final matched = _matchNodePath(
        state,
        paramChild,
        path,
        nextCursor,
        stack,
      );
      stack.pop();
      if (matched != null) {
        return matched;
      }
    }

    final wildcard = node.wildcardRoute;
    if (wildcard != null) {
      return _materializeMatch(wildcard.first, path, paramStack, null, cursor);
    }

    return null;
  }

  void _collectNodeMatches(
    _MethodState<T> state,
    _Node<T> node,
    String path,
    int cursor,
    _ParamStack? paramStack,
    int depth,
    int methodRank,
    List<_CollectedMatch<T>> output,
  ) {
    if (cursor >= path.length) {
      final wildcard = node.wildcardRoute;
      if (wildcard != null) {
        _collectSlotMatches(
          wildcard,
          path,
          paramStack,
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
          paramStack,
          null,
          0,
          depth: depth,
          routeKind: _routeSpecificityRank(exact.first, isStaticExact: false),
          methodRank: methodRank,
          output: output,
        );
      }
      return;
    }

    final segmentEnd = _findSegmentEnd(path, cursor);
    if (segmentEnd == cursor) {
      return;
    }
    final nextCursor = segmentEnd < path.length ? segmentEnd + 1 : path.length;

    final wildcard = node.wildcardRoute;
    if (wildcard != null) {
      _collectSlotMatches(
        wildcard,
        path,
        paramStack,
        null,
        cursor,
        depth: depth,
        routeKind: _wildcardSpecificityRank,
        methodRank: methodRank,
        output: output,
      );
    }

    final paramChild = node.paramChild;
    if (paramChild != null) {
      final stack = paramStack ?? _ParamStack(state.paramStackCapacity);
      stack.push(cursor, segmentEnd);
      _collectNodeMatches(
        state,
        paramChild,
        path,
        nextCursor,
        stack,
        depth + 1,
        methodRank,
        output,
      );
      stack.pop();
    }

    final staticChild = node.lookupStaticChildSlice(path, cursor, segmentEnd);
    if (staticChild != null) {
      _collectNodeMatches(
        state,
        staticChild,
        path,
        nextCursor,
        paramStack,
        depth + 1,
        methodRank,
        output,
      );
    }
  }

  RouteMatch<T> _materializeMatch(
    _Route<T> route,
    String path,
    _ParamStack? paramValues,
    String? wildcardValue,
    int wildcardStart,
  ) {
    // Static routes reuse a cached immutable match object.
    if (!route.hasWildcard && route.paramNames.isEmpty) {
      return route.noParamsMatch;
    }

    return _LazyRouteMatch<T>(
      data: route.data,
      paramNames: route.paramNames,
      hasWildcard: route.hasWildcard,
      path: path,
      paramValues: paramValues,
      wildcardValue: wildcardValue,
      wildcardStart: wildcardStart,
    );
  }

  RouteMatch<T> _materializeCollectedMatch(
    _Route<T> route,
    String path,
    _ParamStack? paramValues,
    String? wildcardValue,
    int wildcardStart,
  ) {
    if (!route.hasWildcard && route.paramNames.isEmpty) {
      return route.noParamsMatch;
    }

    final params = _materializeParams(
      route,
      path,
      paramValues,
      wildcardValue,
      wildcardStart,
    );
    return RouteMatch<T>(route.data, params);
  }

  void _collectSlotMatches(
    _RouteSlot<T> slot,
    String path,
    _ParamStack? paramValues,
    String? wildcardValue,
    int wildcardStart, {
    required int depth,
    required int routeKind,
    required int methodRank,
    required List<_CollectedMatch<T>> output,
  }) {
    final single = slot.singleOrNull;
    if (single != null) {
      output.add(
        _CollectedMatch<T>(
          match: _materializeCollectedMatch(
            single,
            path,
            paramValues,
            wildcardValue,
            wildcardStart,
          ),
          depth: depth,
          routeKind: routeKind,
          methodRank: methodRank,
          slotEntryRank: 0,
        ),
      );
      return;
    }

    for (var i = 0; i < slot.length; i++) {
      output.add(
        _CollectedMatch<T>(
          match: _materializeCollectedMatch(
            slot.routeAt(i),
            path,
            paramValues,
            wildcardValue,
            wildcardStart,
          ),
          depth: depth,
          routeKind: routeKind,
          methodRank: methodRank,
          slotEntryRank: i,
        ),
      );
    }
  }

  _RouteSlot<T> _resolveDuplicateSlot({
    required _RouteSlot<T> existing,
    required _Route<T> replacement,
    required String pattern,
    required DuplicatePolicy duplicatePolicy,
    required String rejectMessage,
  }) {
    if (!_sameParamNames(existing.first.paramNames, replacement.paramNames)) {
      throw FormatException(
        'Duplicate route shape conflicts with existing route: $pattern',
      );
    }

    switch (duplicatePolicy) {
      case DuplicatePolicy.reject:
        throw FormatException(rejectMessage);
      case DuplicatePolicy.replace:
        return _RouteSlot<T>.single(replacement);
      case DuplicatePolicy.keepFirst:
        return existing;
      case DuplicatePolicy.append:
        return existing.appended(replacement);
    }
  }
}

class _MethodState<T> {
  // Each method bucket keeps an independent path index and matching metadata.
  final _Node<T> root = _Node<T>();
  _RouteSlot<T>? globalFallback;
  final Map<String, _RouteSlot<T>> staticExactRoutes =
      <String, _RouteSlot<T>>{};
  final Set<int> staticExactPathLengths = <int>{};
  int maxParamDepth = 0;
  int paramStackCapacity = 1;
}

class _CollectedMatch<T> {
  final RouteMatch<T> match;
  final int depth;
  final int routeKind;
  final int methodRank;
  final int slotEntryRank;

  const _CollectedMatch({
    required this.match,
    required this.depth,
    required this.routeKind,
    required this.methodRank,
    required this.slotEntryRank,
  });
}

class _Route<T> {
  final T data;
  final List<String> paramNames;
  final bool hasWildcard;
  RouteMatch<T>? _cachedNoParamsMatch;

  _Route({
    required this.data,
    required this.paramNames,
    required this.hasWildcard,
  });

  RouteMatch<T> get noParamsMatch {
    // Avoids per-request allocations for pure static exact matches.
    assert(!hasWildcard && paramNames.isEmpty);
    final cached = _cachedNoParamsMatch;
    if (cached != null) {
      return cached;
    }
    final created = RouteMatch<T>(data);
    _cachedNoParamsMatch = created;
    return created;
  }
}

extension type _RouteSlot<T>(Object _value) {
  _RouteSlot.single(_Route<T> route) : this(route);

  _Route<T> get first {
    final single = singleOrNull;
    if (single != null) {
      return single;
    }
    return (_value as List<_Route<T>>)[0];
  }

  _Route<T>? get singleOrNull {
    final value = _value;
    if (value is _Route<T>) {
      return value;
    }
    return null;
  }

  int get length {
    final single = singleOrNull;
    if (single != null) {
      return 1;
    }
    return (_value as List<_Route<T>>).length;
  }

  _Route<T> routeAt(int index) {
    final single = singleOrNull;
    if (single != null) {
      if (index != 0) {
        throw RangeError.index(index, this, 'index', null, 1);
      }
      return single;
    }
    return (_value as List<_Route<T>>)[index];
  }

  _RouteSlot<T> appended(_Route<T> route) {
    final single = singleOrNull;
    if (single != null) {
      return _RouteSlot<T>(<_Route<T>>[single, route]);
    }

    final routes = _value as List<_Route<T>>;
    routes.add(route);
    return this;
  }
}

class _Node<T> {
  // Hybrid representation:
  // - tiny fan-out: compact parallel lists
  // - larger fan-out: hash map
  List<String>? _staticKeys;
  List<_Node<T>>? _staticChildren;
  Map<String, _Node<T>>? _staticMap;

  _Node<T>? paramChild;
  _RouteSlot<T>? exactRoute;
  _RouteSlot<T>? wildcardRoute;

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

    // Small nodes stay on compact lists; upgrade to map after threshold.
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
        // For larger maps hashing a temporary substring is faster than linear scan.
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

class _NormalizedPattern {
  final String path;
  final bool hasReservedToken;

  const _NormalizedPattern({
    required this.path,
    required this.hasReservedToken,
  });
}

_NormalizedPattern _normalizePatternForCompile(String path) {
  // Normalize and validate in one scan to reduce build-time overhead.
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

    if (code == _colonCode || code == _asteriskCode) {
      hasReservedToken = true;
    }
    prevSlash = false;
  }

  if (end == path.length) {
    return _NormalizedPattern(path: path, hasReservedToken: hasReservedToken);
  }
  return _NormalizedPattern(
    path: path.substring(0, end),
    hasReservedToken: hasReservedToken,
  );
}

String? _normalizeInputPath(String path) {
  // Query-time normalization is intentionally minimal: reject invalid shapes
  // but avoid extra allocations when the input is already canonical.
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

int _compareCollectedMatches<T>(_CollectedMatch<T> a, _CollectedMatch<T> b) {
  final depthCompare = a.depth.compareTo(b.depth);
  if (depthCompare != 0) {
    return depthCompare;
  }

  final kindCompare = a.routeKind.compareTo(b.routeKind);
  if (kindCompare != 0) {
    return kindCompare;
  }

  final methodCompare = a.methodRank.compareTo(b.methodRank);
  if (methodCompare != 0) {
    return methodCompare;
  }

  return a.slotEntryRank.compareTo(b.slotEntryRank);
}

Map<String, String>? _materializeParams<T>(
  _Route<T> route,
  String path,
  _ParamStack? paramValues,
  String? wildcardValue,
  int wildcardStart,
) {
  if (route.paramNames.isEmpty && !route.hasWildcard) {
    return null;
  }

  final params = <String, String>{};
  if (route.paramNames.isNotEmpty) {
    final captured = paramValues;
    if (captured == null) {
      throw StateError('Missing parameter capture stack for matched route.');
    }
    for (var i = 0; i < route.paramNames.length; i++) {
      params[route.paramNames[i]] = path.substring(
        captured.startAt(i),
        captured.endAt(i),
      );
    }
  }

  if (route.hasWildcard) {
    params['wildcard'] = wildcardValue ?? path.substring(wildcardStart);
  }

  return params;
}

int _routeSpecificityRank<T>(_Route<T> route, {required bool isStaticExact}) {
  if (route.hasWildcard) {
    return _wildcardSpecificityRank;
  }
  if (isStaticExact || route.paramNames.isEmpty) {
    return _staticSpecificityRank;
  }
  return _paramSpecificityRank;
}

int _countPathSegments(String path) {
  if (path.length == 1) {
    return 0;
  }

  var count = 1;
  for (var i = 1; i < path.length; i++) {
    if (path.codeUnitAt(i) == _slashCode) {
      count += 1;
    }
  }
  return count;
}

bool _sameParamNames(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

class _ParamStack {
  final List<int> _starts;
  final List<int> _ends;
  int _length = 0;

  // Fixed-capacity stack sized from max route param depth in this method bucket.
  _ParamStack(int capacity)
    : _starts = List<int>.filled(capacity, 0, growable: false),
      _ends = List<int>.filled(capacity, 0, growable: false);

  void push(int start, int end) {
    _starts[_length] = start;
    _ends[_length] = end;
    _length += 1;
  }

  void pop() {
    _length -= 1;
  }

  int startAt(int index) => _starts[index];

  int endAt(int index) => _ends[index];
}

bool _isValidParamName(String name) {
  if (name.isEmpty) {
    return false;
  }

  final first = name.codeUnitAt(0);
  final validFirst =
      (first >= 65 && first <= 90) ||
      (first >= 97 && first <= 122) ||
      first == 95;
  if (!validFirst) {
    return false;
  }

  for (var i = 1; i < name.length; i++) {
    final c = name.codeUnitAt(i);
    final valid =
        (c >= 65 && c <= 90) ||
        (c >= 97 && c <= 122) ||
        (c >= 48 && c <= 57) ||
        c == 95;
    if (!valid) {
      return false;
    }
  }
  return true;
}
