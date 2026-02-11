const _slashCode = 47;
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

/// Immutable path router with static, parameter and wildcard matching.
///
/// Route precedence is fixed:
/// 1. static segment
/// 2. parameter segment (`:id`)
/// 3. wildcard (`*`)
/// 4. global fallback (`/*`)
class Router<T> {
  final _Node<T> _root;
  late final _Route<T>? _globalFallback;
  late final Map<String, RouteMatch<T>> _staticExactMatches;
  late final Set<int> _staticExactPathLengths;
  late final int _maxParamDepth;
  late final int _paramStackCapacity;

  Router({required Map<String, T> routes}) : _root = _Node<T>() {
    final compiled = _compile(routes, _root);
    _globalFallback = compiled.globalFallback;
    _staticExactMatches = compiled.staticExactMatches;
    _staticExactPathLengths = compiled.staticExactPathLengths;
    _maxParamDepth = compiled.maxParamDepth;
    _paramStackCapacity = _maxParamDepth == 0 ? 1 : _maxParamDepth;
  }

  RouteMatch<T>? match(String path) {
    final normalized = _normalizeInputPath(path);
    if (normalized == null) {
      return null;
    }

    if (_staticExactPathLengths.contains(normalized.length)) {
      final exactStatic = _staticExactMatches[normalized];
      if (exactStatic != null) {
        return exactStatic;
      }
    }

    final start = normalized.length == 1 ? normalized.length : 1;
    final matched = _matchNodePath(_root, normalized, start, null);
    if (matched != null) {
      return matched;
    }

    final fallback = _globalFallback;
    if (fallback == null) {
      return null;
    }
    final wildcardValue = normalized.length == 1 ? '' : normalized.substring(1);
    return _materializeMatch(fallback, normalized, null, wildcardValue, 0);
  }

  static _CompileResult<T> _compile<T>(Map<String, T> routes, _Node<T> root) {
    _Route<T>? globalFallback;
    final staticExactMatches = <String, RouteMatch<T>>{};
    final staticExactPathLengths = <int>{};
    var maxParamDepth = 0;

    for (final entry in routes.entries) {
      final pattern = _normalizePattern(entry.key);
      final data = entry.value;

      if (pattern == '/*') {
        if (globalFallback != null) {
          throw FormatException('Duplicate global fallback route: $pattern');
        }
        globalFallback = _Route<T>(
          data: data,
          paramNames: const <String>[],
          hasWildcard: true,
        );
        continue;
      }

      final segments = _splitPathSegments(pattern);
      final paramNames = <String>[];
      var node = root;
      var wildcardAdded = false;

      for (var i = 0; i < segments.length; i++) {
        final segment = segments[i];

        if (segment == '*') {
          if (i != segments.length - 1) {
            throw FormatException(
              'Wildcard must be the last segment: $pattern',
            );
          }
          if (node.wildcardRoute != null) {
            throw FormatException(
              'Duplicate wildcard route shape at prefix for pattern: $pattern',
            );
          }
          node.wildcardRoute = _Route<T>(
            data: data,
            paramNames: List<String>.unmodifiable(paramNames),
            hasWildcard: true,
          );
          if (paramNames.length > maxParamDepth) {
            maxParamDepth = paramNames.length;
          }
          wildcardAdded = true;
          break;
        }

        if (segment.codeUnitAt(0) == 58) {
          final paramName = segment.substring(1);
          if (!_isValidParamName(paramName)) {
            throw FormatException('Invalid parameter name in route: $pattern');
          }
          node.paramChild ??= _Node<T>();
          node = node.paramChild!;
          paramNames.add(paramName);
          continue;
        }

        if (segment.contains(':') || segment.contains('*')) {
          throw FormatException(
            'Unsupported segment syntax in route: $pattern',
          );
        }

        node = node.getOrCreateStaticChild(segment);
      }

      if (wildcardAdded) {
        continue;
      }

      if (node.exactRoute != null) {
        throw FormatException(
          'Duplicate route shape conflicts with existing route: $pattern',
        );
      }
      final route = _Route<T>(
        data: data,
        paramNames: List<String>.unmodifiable(paramNames),
        hasWildcard: false,
      );
      node.exactRoute = route;
      if (paramNames.isEmpty) {
        staticExactMatches[pattern] = route.noParamsMatch;
        staticExactPathLengths.add(pattern.length);
      }
      if (paramNames.length > maxParamDepth) {
        maxParamDepth = paramNames.length;
      }
    }

    return _CompileResult<T>(
      globalFallback: globalFallback,
      staticExactMatches: Map<String, RouteMatch<T>>.unmodifiable(
        staticExactMatches,
      ),
      staticExactPathLengths: Set<int>.unmodifiable(staticExactPathLengths),
      maxParamDepth: maxParamDepth,
    );
  }

  RouteMatch<T>? _matchNodePath(
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

    final staticChild = node.lookupStaticChildSlice(path, cursor, segmentEnd);
    if (staticChild != null) {
      final matched = _matchNodePath(staticChild, path, nextCursor, paramStack);
      if (matched != null) {
        return matched;
      }
    }

    final paramChild = node.paramChild;
    if (paramChild != null) {
      final stack = paramStack ?? _ParamStack(_paramStackCapacity);
      stack.push(cursor, segmentEnd);
      final matched = _matchNodePath(paramChild, path, nextCursor, stack);
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

class _CompileResult<T> {
  final _Route<T>? globalFallback;
  final Map<String, RouteMatch<T>> staticExactMatches;
  final Set<int> staticExactPathLengths;
  final int maxParamDepth;

  const _CompileResult({
    required this.globalFallback,
    required this.staticExactMatches,
    required this.staticExactPathLengths,
    required this.maxParamDepth,
  });
}

class _Route<T> {
  final T data;
  final List<String> paramNames;
  final bool hasWildcard;
  final RouteMatch<T> noParamsMatch;

  _Route({
    required this.data,
    required this.paramNames,
    required this.hasWildcard,
  }) : noParamsMatch = RouteMatch<T>(data);
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
      return map.putIfAbsent(segment, _Node<T>.new);
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

String _normalizePattern(String path) {
  if (path.isEmpty || path.codeUnitAt(0) != _slashCode) {
    throw FormatException('Route pattern must start with "/": $path');
  }
  if (_hasEmptyPathSegments(path)) {
    throw FormatException('Route pattern contains empty segment: $path');
  }
  if (path.length > 1 && path.codeUnitAt(path.length - 1) == _slashCode) {
    path = path.substring(0, path.length - 1);
  }
  return path;
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

bool _hasEmptyPathSegments(String path) {
  for (var i = 1; i < path.length; i++) {
    if (path.codeUnitAt(i) == _slashCode &&
        path.codeUnitAt(i - 1) == _slashCode) {
      return true;
    }
  }
  return false;
}

List<String> _splitPathSegments(String path) {
  if (path.length == 1) {
    return const <String>[];
  }

  final segments = <String>[];
  var start = 1;
  for (var i = 1; i <= path.length; i++) {
    if (i != path.length && path.codeUnitAt(i) != _slashCode) {
      continue;
    }
    if (start != i) {
      segments.add(path.substring(start, i));
    }
    start = i + 1;
  }
  return segments;
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
