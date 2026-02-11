const _slashCode = 47;
const _asteriskCode = 42;
const _colonCode = 58;
const _staticMapUpgradeThreshold = 8;

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

  /// Creates a router and optionally registers initial `ANY` routes.
  Router({Map<String, T>? routes}) {
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
  void add(String path, T data, {String? method}) {
    final state = _stateForWrite(method);
    final normalized = _normalizePatternForCompile(path);
    _addCompiledPattern(
      state,
      normalized.path,
      data,
      hasReservedToken: normalized.hasReservedToken,
    );
  }

  /// Registers multiple routes in the same method bucket.
  ///
  /// Passing `method: null` registers all routes as `ANY`.
  void addAll(Map<String, T> routes, {String? method}) {
    final state = _stateForWrite(method);
    for (final entry in routes.entries) {
      final normalized = _normalizePatternForCompile(entry.key);
      _addCompiledPattern(
        state,
        normalized.path,
        entry.value,
        hasReservedToken: normalized.hasReservedToken,
      );
    }
  }

  /// Matches [path] and returns route data with lazily materialized params.
  ///
  /// If [method] is provided, the router first checks that specific bucket and
  /// then falls back to `ANY` when there is no hit.
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
        return exactStatic.noParamsMatch;
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
    return _materializeMatch(fallback, normalized, null, wildcardValue, 0);
  }

  void _addCompiledPattern(
    _MethodState<T> state,
    String pattern,
    T data, {
    required bool hasReservedToken,
  }) {
    // Global fallback applies only when no more specific route matches.
    if (pattern == '/*') {
      if (state.globalFallback != null) {
        throw FormatException('Duplicate global fallback route: $pattern');
      }
      state.globalFallback = _Route<T>(
        data: data,
        paramNames: const <String>[],
        hasWildcard: true,
      );
      return;
    }

    if (!hasReservedToken) {
      // Pure static patterns bypass trie construction and go directly to exact map.
      if (state.staticExactRoutes[pattern] != null) {
        throw FormatException(
          'Duplicate route shape conflicts with existing route: $pattern',
        );
      }
      final route = _Route<T>(
        data: data,
        paramNames: const <String>[],
        hasWildcard: false,
      );
      state.staticExactRoutes[pattern] = route;
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
        if (node.wildcardRoute != null) {
          throw FormatException(
            'Duplicate wildcard route shape at prefix for pattern: $pattern',
          );
        }
        node.wildcardRoute = _Route<T>(
          data: data,
          paramNames: paramNames ?? const <String>[],
          hasWildcard: true,
        );
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

    if (node.exactRoute != null) {
      throw FormatException(
        'Duplicate route shape conflicts with existing route: $pattern',
      );
    }

    final route = _Route<T>(
      data: data,
      paramNames: paramNames ?? const <String>[],
      hasWildcard: false,
    );
    node.exactRoute = route;
    if (paramCount == 0) {
      state.staticExactRoutes[pattern] = route;
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
        return _materializeMatch(exact, path, paramStack, null, 0);
      }

      final wildcard = node.wildcardRoute;
      if (wildcard != null) {
        return _materializeMatch(wildcard, path, paramStack, '', 0);
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
      return _materializeMatch(wildcard, path, paramStack, null, cursor);
    }

    return null;
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
}

class _MethodState<T> {
  // Each method bucket keeps an independent path index and matching metadata.
  final _Node<T> root = _Node<T>();
  _Route<T>? globalFallback;
  final Map<String, _Route<T>> staticExactRoutes = <String, _Route<T>>{};
  final Set<int> staticExactPathLengths = <int>{};
  int maxParamDepth = 0;
  int paramStackCapacity = 1;
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

class _Node<T> {
  // Hybrid representation:
  // - tiny fan-out: compact parallel lists
  // - larger fan-out: hash map
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
