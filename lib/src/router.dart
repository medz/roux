import 'dart:collection';

const _slashCode = 47, _asteriskCode = 42, _colonCode = 58, _mapAt = 4;
const _wildRank = 0, _paramRank = 1, _staticRank = 2;
const _dupShape = 'Duplicate route shape conflicts with existing route: ';
const _dupWildcard = 'Duplicate wildcard route shape at prefix for pattern: ';
const _dupFallback = 'Duplicate global fallback route: ';
const _emptySegment = 'Route pattern contains empty segment: ';
const _missingCaptures = 'Missing parameter capture stack for matched route.';

enum DuplicatePolicy { reject, replace, keepFirst, append }

class RouteMatch<T> {
  final T data;
  Map<String, String>? _params;
  final _Route<T>? _r;
  final String? _p;
  final _Caps? _v;
  final int _w;
  RouteMatch(this.data, [Map<String, String>? params])
    : _params = params,
      _r = null,
      _p = null,
      _v = null,
      _w = 0;
  RouteMatch._lazy(this.data, this._r, this._p, this._v, this._w);
  Map<String, String>? get params => switch (_r) {
    null => _params,
    final route => _params ??= _Params(
      route.paramNames,
      route.hasWildcard,
      _p!,
      _v,
      _w,
    ),
  };
}

class Router<T> {
  final _State<T> _anyState = _State<T>();
  Map<String, _State<T>>? _methodStates;
  final DuplicatePolicy _duplicatePolicy;
  Router({
    Map<String, T>? routes,
    DuplicatePolicy duplicatePolicy = DuplicatePolicy.reject,
  }) : _duplicatePolicy = duplicatePolicy {
    if (routes != null && routes.isNotEmpty) addAll(routes);
  }
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

  RouteMatch<T>? match(String path, {String? method}) {
    final normalized = _normalize(path);
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

  List<RouteMatch<T>> matchAll(String path, {String? method}) {
    final normalized = _normalize(path);
    if (normalized == null) return <RouteMatch<T>>[];
    final pathDepth = _pathDepth(normalized);
    final collected = _Buckets<T>(pathDepth);
    _collectState(_anyState, normalized, d: pathDepth, m: 0, o: collected);
    final methodToken = method == null ? null : _methodToken(method);
    final methodState = methodToken == null
        ? null
        : _methodStates?[methodToken];
    if (methodState != null) {
      _collectState(methodState, normalized, d: pathDepth, m: 1, o: collected);
    }
    return collected.finish();
  }

  _State<T> _stateForWrite(String? method) => method == null
      ? _anyState
      : (_methodStates ??= <String, _State<T>>{}).putIfAbsent(
          _methodToken(method),
          _State<T>.new,
        );
  String _methodToken(String method) {
    final token = method.trim();
    if (token.isEmpty)
      throw ArgumentError.value(method, 'method', 'Method must not be empty.');
    return token.toUpperCase();
  }

  RouteMatch<T>? _matchInState(_State<T> state, String normalized) {
    final fallback = state.globalFallback;
    return state.staticExactRoutes[normalized]?.noParamsMatch ??
        _matchNodePath(state, normalized) ??
        (fallback == null ? null : _materialize(fallback, normalized, null, 1));
  }

  void _collectState(
    _State<T> state,
    String normalized, {
    required int d,
    required int m,
    required _Buckets<T> o,
  }) {
    final fallback = state.globalFallback;
    if (fallback != null) {
      _collect(fallback, normalized, null, 1, d: 0, k: _wildRank, m: m, o: o);
    }
    _collectNode(state, normalized, m, o);
    final exactStatic = state.staticExactRoutes[normalized];
    if (exactStatic != null) {
      _collect(
        exactStatic,
        normalized,
        null,
        0,
        d: d,
        k: _staticRank,
        m: m,
        o: o,
      );
    }
  }

  void _addPattern(
    _State<T> state,
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
      if (code == _colonCode || code == _asteriskCode) {
        hasReservedToken = true;
      }
      prevSlash = false;
    }

    final normalized = end == pattern.length
        ? pattern
        : pattern.substring(0, end);

    if (normalized == '/*') {
      state.globalFallback = _mergedRoute(
        state.globalFallback,
        _Route<T>(data, const <String>[], true),
        normalized,
        duplicatePolicy,
        _dupFallback,
      );
      return;
    }

    if (!hasReservedToken) {
      state.staticExactRoutes[normalized] = _mergedRoute(
        state.staticExactRoutes[normalized],
        _Route<T>(data, const <String>[], false),
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
        node.wildcardRoute = _mergedRoute(
          node.wildcardRoute,
          _Route<T>(data, paramNames ?? const <String>[], true),
          normalized,
          duplicatePolicy,
          _dupWildcard,
        );
        if (paramCount > state.maxParamDepth) state.maxParamDepth = paramCount;
        return;
      }

      if (firstCode == _colonCode) {
        final paramName = pattern.substring(cursor + 1, segmentEnd);
        if (!_validParam(paramName)) {
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

    node.exactRoute = _mergedRoute(
      node.exactRoute,
      _Route<T>(data, paramNames ?? const <String>[], false),
      normalized,
      duplicatePolicy,
      _dupShape,
    );
    if (paramCount > state.maxParamDepth) state.maxParamDepth = paramCount;
  }

  RouteMatch<T>? _matchNodePath(_State<T> state, String path) {
    _Caps? paramStack;
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
        if (wildcard != null)
          return _materialize(wildcard, path, stackParams, path.length);
      } else {
        final segmentEnd = _segmentEnd(path, cursor);
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
            paramStack ??= _Caps(state.maxParamDepth);
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
          if (wildcard != null)
            return _materialize(wildcard, path, stackParams, cursor);
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
          paramStack ??= _Caps(state.maxParamDepth);
          paramStack.truncate(paramLength);
          paramStack.push(cursor, branch.a);
          node = node.paramChild!;
          cursor = branch.b;
          paramLength = paramStack.length;
          continue top;
        }

        stack = branch.prev;
        final wildcard = node.wildcardRoute;
        if (wildcard != null)
          return _materialize(wildcard, path, paramStack, cursor);
      }
      return null;
    } while (true);
  }

  void _collectNode(_State<T> state, String path, int m, _Buckets<T> o) {
    _Caps? paramStack;
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
          _collect(
            wildcard,
            path,
            stackParams,
            path.length,
            d: depth,
            k: _wildRank,
            m: m,
            o: o,
          );
        }
        final exact = node.exactRoute;
        if (exact != null) {
          _collect(
            exact,
            path,
            stackParams,
            0,
            d: depth,
            k: _paramRank,
            m: m,
            o: o,
          );
        }
      } else {
        final segmentEnd = _segmentEnd(path, cursor);
        if (segmentEnd != cursor) {
          final nextCursor = segmentEnd < path.length
              ? segmentEnd + 1
              : path.length;
          final wildcard = node.wildcardRoute;
          if (wildcard != null) {
            _collect(
              wildcard,
              path,
              stackParams,
              cursor,
              d: depth,
              k: _wildRank,
              m: m,
              o: o,
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
            paramStack ??= _Caps(state.maxParamDepth);
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
        paramStack ??= _Caps(state.maxParamDepth);
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

  RouteMatch<T> _materialize(
    _Route<T> route,
    String path,
    _Caps? paramValues,
    int wildcardStart,
  ) => route.hasWildcard || route.paramNames.isNotEmpty
      ? RouteMatch<T>._lazy(route.data, route, path, paramValues, wildcardStart)
      : route.noParamsMatch;
  void _collect(
    _Route<T> slot,
    String path,
    _Caps? paramValues,
    int wildcardStart, {
    required int d,
    required int k,
    required int m,
    required _Buckets<T> o,
  }) {
    if (slot.next == null) {
      o.add(
        _materialize(slot, path, paramValues, wildcardStart),
        d: d,
        k: k,
        m: m,
      );
      return;
    }
    for (_Route<T>? current = slot; current != null; current = current.next) {
      final entry = current;
      o.add(
        _materialize(entry, path, paramValues, wildcardStart),
        d: d,
        k: k,
        m: m,
      );
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
    return switch (duplicatePolicy) {
      DuplicatePolicy.reject => throw FormatException('$rejectPrefix$pattern'),
      DuplicatePolicy.replace => replacement,
      DuplicatePolicy.keepFirst => existing,
      DuplicatePolicy.append => existing.appended(replacement),
    };
  }
}

class _State<T> {
  final _Node<T> root = _Node<T>();
  _Route<T>? globalFallback;
  final Map<String, _Route<T>> staticExactRoutes = <String, _Route<T>>{};
  int maxParamDepth = 0;
}

class _Branch<T> {
  final _Node<T> node;
  final int cursor, paramLength, a, b, c;
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
  late final RouteMatch<T> noParamsMatch = RouteMatch<T>(data);
  _Route(this.data, this.paramNames, this.hasWildcard);
  _Route<T> appended(_Route<T> route) {
    var current = this;
    while (current.next != null) {
      current = current.next!;
    }
    current.next = route;
    return this;
  }
}

class _Params extends MapBase<String, String> {
  final List<String> _n;
  final bool _w;
  final String _p;
  final _Caps? _c;
  final int _s;
  Map<String, String>? _m;
  _Params(this._n, this._w, this._p, this._c, this._s);
  Map<String, String> get _mat => _m ??= _materialize();
  _Caps get _req => _c ?? (throw StateError(_missingCaptures));
  String get _wild => _s < _p.length ? _p.substring(_s) : '';
  @override
  String? operator [](Object? key) {
    if (key is! String) return null;
    final map = _m;
    if (map != null) return map[key];
    if (_w && key == 'wildcard') return _wild;
    for (var i = 0; i < _n.length; i++) {
      if (_n[i] == key) {
        final caps = _req;
        return _p.substring(caps.startAt(i), caps.endAt(i));
      }
    }
    return null;
  }

  @override
  void operator []=(String key, String value) => _mat[key] = value;
  @override
  void clear() => _mat.clear();
  @override
  Iterable<String> get keys =>
      _m?.keys ?? (_w ? _n.followedBy(const ['wildcard']) : _n);
  @override
  String? remove(Object? key) => key is String ? _mat.remove(key) : null;
  @override
  int get length => _m?.length ?? _n.length + (_w ? 1 : 0);
  Map<String, String> _materialize() {
    final map = <String, String>{};
    if (_n.isNotEmpty) {
      final caps = _req;
      for (var i = 0; i < _n.length; i++) {
        map[_n[i]] = _p.substring(caps.startAt(i), caps.endAt(i));
      }
    }
    if (_w) map['wildcard'] = _wild;
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
  _Node<T> getOrCreateStaticChildSlice(String path, int start, int end) {
    final map = _staticMap;
    if (map != null) {
      final key = path.substring(start, end);
      return map[key] ??= _Node<T>(key);
    }
    final child = _findStaticChildSlice(path, start, end);
    if (child != null) return child;
    final created = _Node<T>(path.substring(start, end));
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

  _Node<T>? _findStaticChildSlice(String path, int start, int end) {
    final map = _staticMap;
    if (map != null) return map[path.substring(start, end)];
    _Node<T>? prev;
    var child = _staticChild;
    while (child != null) {
      if (_eqSlice(child._staticKey!, path, start, end)) {
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

String? _normalize(String path) {
  if (path.isEmpty || path.codeUnitAt(0) != _slashCode) return null;
  final last = path.length - 1;
  if (path.length > 1 && path.codeUnitAt(last) == _slashCode) {
    if (path.codeUnitAt(last - 1) == _slashCode) return null;
    path = path.substring(0, last);
  }
  return path.length > 1 && path.codeUnitAt(1) == _slashCode ? null : path;
}

int _segmentEnd(String path, int start) {
  var i = start;
  while (i < path.length && path.codeUnitAt(i) != _slashCode) {
    i += 1;
  }
  return i;
}

bool _eqSlice(String key, String path, int start, int end) {
  if (key.length != end - start) return false;
  for (var i = 0; i < key.length; i++) {
    if (key.codeUnitAt(i) != path.codeUnitAt(start + i)) return false;
  }
  return true;
}

int _pathDepth(String path) {
  var count = path.length == 1 ? 0 : 1;
  for (var i = 1; i < path.length; i++) {
    if (path.codeUnitAt(i) == _slashCode) count += 1;
  }
  return count;
}

class _Buckets<T> {
  final List<List<RouteMatch<T>>?> _buckets;
  int _count = 0;
  _Buckets(int maxDepth)
    : _buckets = List<List<RouteMatch<T>>?>.filled(
        (maxDepth + 1) * 6,
        null,
        growable: false,
      );
  void add(
    RouteMatch<T> match, {
    required int d,
    required int k,
    required int m,
  }) {
    final index = d * 6 + k * 2 + m;
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

class _Caps {
  final List<int> _values;
  int _length = 0;
  _Caps(int capacity)
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

bool _validParam(String name) {
  if (name.isEmpty || !_isNameStart(name.codeUnitAt(0))) return false;
  for (var i = 1; i < name.length; i++) {
    if (!_isNameChar(name.codeUnitAt(i))) return false;
  }
  return true;
}

bool _isNameStart(int c) => ((c | 32) >= 97 && (c | 32) <= 122) || c == 95;
bool _isNameChar(int c) => _isNameStart(c) || (c >= 48 && c <= 57);
