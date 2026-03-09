part of 'router.dart';

extension _SimpleEngine<T> on Router<T> {
  void _addPattern(
    _RouteSet<T> routeSet,
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
    var exactDepth = 0;
    var exactStaticChars = 0;
    for (var i = 1; i < end; i++) {
      final code = pattern.codeUnitAt(i);
      if (code == _slashCode) {
        if (prevSlash) {
          throw FormatException('$_emptySegment$pattern');
        }
        exactDepth += 1;
        prevSlash = true;
        continue;
      }
      if (code == _colonCode ||
          code == _asteriskCode ||
          code == _openBraceCode ||
          code == _closeBraceCode ||
          code == _questionCode) {
        hasReservedToken = true;
        break;
      }
      exactStaticChars += 1;
      prevSlash = false;
    }
    if (!hasReservedToken && end > 1 && !prevSlash) {
      exactDepth += 1;
    }

    final normalized = end == pattern.length
        ? pattern
        : pattern.substring(0, end);
    final canonical = _canonicalPath(normalized);

    if (!hasReservedToken) {
      _addExactStaticRoute(
        routeSet,
        canonical,
        normalized,
        data,
        duplicatePolicy,
        exactDepth,
        exactStaticChars,
      );
      return;
    }

    List<String>? paramNames;
    var paramCount = 0;
    var staticChars = 0;
    var depth = 0;
    var node = routeSet.root;
    for (var cursor = end == 1 ? end : 1; cursor < end;) {
      var segmentEnd = cursor;
      var hasReservedInSegment = false;
      while (segmentEnd < end) {
        final code = pattern.codeUnitAt(segmentEnd);
        if (code == _slashCode) break;
        if (code == _colonCode ||
            code == _asteriskCode ||
            code == _openBraceCode ||
            code == _closeBraceCode ||
            code == _questionCode) {
          hasReservedInSegment = true;
        }
        segmentEnd += 1;
      }
      if (segmentEnd == cursor) {
        throw FormatException('$_emptySegment$pattern');
      }

      final firstCode = pattern.codeUnitAt(cursor);
      final doubleWildcardName = firstCode == _asteriskCode
          ? _readDoubleWildcardName(pattern, cursor, segmentEnd)
          : null;
      if (doubleWildcardName != null) {
        if (segmentEnd != end) {
          throw FormatException(
            'Double wildcard must be the last segment: $normalized',
          );
        }
        final route = _newRoute(
          data,
          paramNames ?? const <String>[],
          doubleWildcardName,
          normalized,
          depth,
          _remainderSpecificity,
          staticChars,
          0,
        );
        if (cursor == 1 && paramCount == 0) {
          routeSet.hasSlowMatchPath = true;
          routeSet.globalFallback = _mergeRoutes(
            routeSet.globalFallback,
            route,
            normalized,
            duplicatePolicy,
            _dupFallback,
          );
        } else {
          routeSet.hasSlowMatchPath = true;
          node.wildcardRoute = _mergeRoutes(
            node.wildcardRoute,
            route,
            normalized,
            duplicatePolicy,
            _dupWildcard,
          );
        }
        if (paramCount > routeSet.maxParamDepth) {
          routeSet.maxParamDepth = paramCount;
        }
        return;
      }

      if (firstCode == _colonCode) {
        if (!_hasValidParamNameSlice(pattern, cursor + 1, segmentEnd)) {
          _addCompiledPattern(routeSet, normalized, data, duplicatePolicy);
          return;
        }
        if (node._staticChild != null || node._staticMap != null) {
          routeSet.hasBranchingChoices = true;
        }
        final paramName = pattern.substring(cursor + 1, segmentEnd);
        node = node.paramChild ??= _Node<T>();
        (paramNames ??= <String>[]).add(paramName);
        paramCount += 1;
      } else {
        if (hasReservedInSegment) {
          _addCompiledPattern(routeSet, normalized, data, duplicatePolicy);
          return;
        }
        if (node.paramChild != null) {
          routeSet.hasBranchingChoices = true;
        }
        node = node.getOrCreateStaticChildSlice(
          _canonicalPath(pattern.substring(cursor, segmentEnd)),
        );
        staticChars += segmentEnd - cursor;
      }
      depth += 1;
      cursor = segmentEnd + 1;
    }

    node.exactRoute = _mergeRoutes(
      node.exactRoute,
      _newRoute(
        data,
        paramNames ?? const <String>[],
        null,
        normalized,
        depth,
        paramCount == 0 ? _exactSpecificity : _singleDynamicSpecificity,
        staticChars,
        0,
      ),
      normalized,
      duplicatePolicy,
      _dupShape,
    );
    if (paramCount > routeSet.maxParamDepth) {
      routeSet.maxParamDepth = paramCount;
    }
  }

  void _addExactStaticRoute(
    _RouteSet<T> routeSet,
    String canonical,
    String normalized,
    T data,
    DuplicatePolicy duplicatePolicy,
    int depth,
    int staticChars,
  ) {
    routeSet.staticExactRoutes[canonical] = _mergeRoutes(
      routeSet.staticExactRoutes[canonical],
      _newRoute(
        data,
        const <String>[],
        null,
        normalized,
        depth,
        _exactSpecificity,
        staticChars,
        0,
      ),
      normalized,
      duplicatePolicy,
      _dupShape,
    );
  }

  RouteMatch<T>? _matchNodePathFast(_RouteSet<T> routeSet, String path) {
    _ParamStack? paramStack;
    _Branch<T>? stack;
    var node = routeSet.root;
    var cursor = 1;
    var paramLength = 0;
    top:
    do {
      final params = paramStack;
      if (params != null) params.truncate(paramLength);
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
            paramStack ??= _ParamStack(routeSet.maxParamDepth);
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
        if (paramStack != null) paramStack.truncate(paramLength);
        if (branch.pendingParam) {
          branch.pendingParam = false;
          paramStack ??= _ParamStack(routeSet.maxParamDepth);
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

  RouteMatch<T>? _matchNodePathStraight(_RouteSet<T> routeSet, String path) {
    final smallParams = routeSet.maxParamDepth <= 2;
    _ParamStack? paramStack;
    var node = routeSet.root;
    var cursor = 1;
    var paramCount = 0;
    var p0Start = 0, p0End = 0, p1Start = 0, p1End = 0;
    while (true) {
      if (cursor >= path.length) {
        final exact = node.exactRoute;
        if (exact == null) return null;
        if (!smallParams) return _materialize(exact, path, paramStack, 0);
        final names = exact.paramNames;
        if (names.isEmpty) return exact.noParamsMatch;
        if (names.length == 1) {
          return RouteMatch<T>(
            exact.data,
            _SmallParamsMap1(names[0], path.substring(p0Start, p0End)),
          );
        }
        return RouteMatch<T>(
          exact.data,
          _SmallParamsMap2(
            names[0],
            path.substring(p0Start, p0End),
            names[1],
            path.substring(p1Start, p1End),
          ),
        );
      }
      final segmentEnd = _findSegmentEnd(path, cursor);
      if (segmentEnd == cursor) return null;
      final nextCursor = segmentEnd < path.length
          ? segmentEnd + 1
          : path.length;
      final staticChild = node._findStaticChildSlice(
        path,
        cursor,
        segmentEnd,
        _caseSensitive,
      );
      if (staticChild != null) {
        node = staticChild;
        cursor = nextCursor;
        continue;
      }
      final paramChild = node.paramChild;
      if (paramChild == null) return null;
      if (smallParams) {
        if (paramCount == 0) {
          p0Start = cursor;
          p0End = segmentEnd;
        } else {
          p1Start = cursor;
          p1End = segmentEnd;
        }
        paramCount += 1;
      } else {
        (paramStack ??= _ParamStack(
          routeSet.maxParamDepth,
        )).push(cursor, segmentEnd);
      }
      node = paramChild;
      cursor = nextCursor;
    }
  }

  RouteMatch<T>? _matchNodePath(
    _RouteSet<T> routeSet,
    String path,
    bool allowWildcards,
  ) {
    _ParamStack? paramStack;
    _Branch<T>? stack;
    var node = routeSet.root;
    var cursor = 1;
    var paramLength = 0;
    top:
    do {
      final params = paramStack;
      if (params != null) params.truncate(paramLength);
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
            paramStack ??= _ParamStack(routeSet.maxParamDepth);
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
        if (paramStack != null) paramStack.truncate(paramLength);
        if (branch.pendingParam) {
          branch.pendingParam = false;
          paramStack ??= _ParamStack(routeSet.maxParamDepth);
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
    _RouteSet<T> routeSet,
    String path,
    int methodRank,
    _MatchCollector<T> output,
  ) {
    _ParamStack? paramStack;
    _Branch<T>? stack;
    var node = routeSet.root;
    var cursor = 1;
    var depth = 0;
    var paramLength = 0;
    top:
    do {
      final params = paramStack;
      if (params != null) params.truncate(paramLength);
      final stackParams = paramStack;
      if (cursor >= path.length) {
        final wildcard = node.wildcardRoute;
        if (wildcard != null) {
          _collectSlot(
            wildcard,
            path,
            stackParams,
            path.length,
            methodRank,
            output,
          );
        }
        final exact = node.exactRoute;
        if (exact != null) {
          _collectSlot(exact, path, stackParams, 0, methodRank, output);
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
            paramStack ??= _ParamStack(routeSet.maxParamDepth);
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
        paramStack ??= _ParamStack(routeSet.maxParamDepth);
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
      ? RouteMatch<T>(
          route.data,
          _materializeParams(route, path, paramValues, wildcardStart),
        )
      : route.noParamsMatch;

  void _collectSlot(
    _Route<T> slot,
    String path,
    _ParamStack? paramValues,
    int wildcardStart,
    int methodRank,
    _MatchCollector<T> output,
  ) {
    if (slot.wildcardName != null || slot.paramNames.isNotEmpty) {
      final captures = paramValues?.snapshot();
      for (_Route<T>? current = slot; current != null; current = current.next) {
        output.add(
          RouteMatch<T>(
            current.data,
            _materializeParams(current, path, captures, wildcardStart),
          ),
          current,
          methodRank,
        );
      }
      return;
    }
    for (_Route<T>? current = slot; current != null; current = current.next) {
      output.add(current.noParamsMatch, current, methodRank);
    }
  }

  Map<String, String> _materializeParams(
    _Route<T> route,
    String path,
    _ParamStack? captures,
    int wildcardStart,
  ) {
    final names = route.paramNames;
    final wildcardName = route.wildcardName;
    if (wildcardName == null) {
      if (names.length == 1) {
        final requiredCaptures = captures!;
        return _SmallParamsMap1(
          names[0],
          path.substring(
            requiredCaptures.startAt(0),
            requiredCaptures.endAt(0),
          ),
        );
      }
      if (names.length == 2) {
        final requiredCaptures = captures!;
        return _SmallParamsMap2(
          names[0],
          path.substring(
            requiredCaptures.startAt(0),
            requiredCaptures.endAt(0),
          ),
          names[1],
          path.substring(
            requiredCaptures.startAt(1),
            requiredCaptures.endAt(1),
          ),
        );
      }
    }
    final params = <String, String>{};
    if (names.isNotEmpty) {
      final requiredCaptures = captures!;
      for (var i = 0; i < names.length; i++) {
        params[names[i]] = path.substring(
          requiredCaptures.startAt(i),
          requiredCaptures.endAt(i),
        );
      }
    }
    if (wildcardName != null) {
      params[wildcardName] = wildcardStart < path.length
          ? path.substring(wildcardStart)
          : '';
    }
    return params;
  }
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

abstract class _SmallParamsMap extends MapBase<String, String> {
  Map<String, String>? _promoted;

  Map<String, String> _ensurePromoted();

  @override
  bool containsKey(Object? key) => this[key] != null;

  @override
  void operator []=(String key, String value) => _ensurePromoted()[key] = value;

  @override
  void clear() => _ensurePromoted().clear();

  @override
  Iterable<String> get keys => _promoted?.keys ?? _inlineKeys();

  Iterable<String> _inlineKeys();

  @override
  String? remove(Object? key) => _ensurePromoted().remove(key);
}

class _SmallParamsMap1 extends _SmallParamsMap {
  final String _k0;
  final String _v0;
  late final Iterable<MapEntry<String, String>> _entries = _MapEntryIterable1(
    MapEntry<String, String>(_k0, _v0),
  );

  _SmallParamsMap1(this._k0, this._v0);

  @override
  int get length => _promoted?.length ?? 1;

  @override
  String? operator [](Object? key) =>
      _promoted?[key] ?? (key == _k0 ? _v0 : null);

  @override
  Iterable<MapEntry<String, String>> get entries =>
      _promoted?.entries ?? _entries;

  @override
  Iterable<String> _inlineKeys() => <String>[_k0];

  @override
  Map<String, String> _ensurePromoted() =>
      _promoted ??= <String, String>{_k0: _v0};
}

class _SmallParamsMap2 extends _SmallParamsMap {
  final String _k0, _k1;
  final String _v0, _v1;
  late final Iterable<MapEntry<String, String>> _entries = _MapEntryIterable2(
    MapEntry<String, String>(_k0, _v0),
    MapEntry<String, String>(_k1, _v1),
  );

  _SmallParamsMap2(this._k0, this._v0, this._k1, this._v1);

  @override
  int get length => _promoted?.length ?? 2;

  @override
  String? operator [](Object? key) =>
      _promoted?[key] ?? (key == _k0 ? _v0 : (key == _k1 ? _v1 : null));

  @override
  Iterable<MapEntry<String, String>> get entries =>
      _promoted?.entries ?? _entries;

  @override
  Iterable<String> _inlineKeys() => <String>[_k0, _k1];

  @override
  Map<String, String> _ensurePromoted() =>
      _promoted ??= <String, String>{_k0: _v0, _k1: _v1};
}

class _MapEntryIterable1 extends Iterable<MapEntry<String, String>> {
  final MapEntry<String, String> _entry;

  _MapEntryIterable1(this._entry);

  @override
  Iterator<MapEntry<String, String>> get iterator => _MapEntryIterator1(_entry);
}

class _MapEntryIterator1 implements Iterator<MapEntry<String, String>> {
  final MapEntry<String, String> _entry;
  bool _seen = false;

  _MapEntryIterator1(this._entry);

  @override
  MapEntry<String, String> get current => _entry;

  @override
  bool moveNext() {
    if (_seen) return false;
    _seen = true;
    return true;
  }
}

class _MapEntryIterable2 extends Iterable<MapEntry<String, String>> {
  final MapEntry<String, String> _first;
  final MapEntry<String, String> _second;

  _MapEntryIterable2(this._first, this._second);

  @override
  Iterator<MapEntry<String, String>> get iterator =>
      _MapEntryIterator2(_first, _second);
}

class _MapEntryIterator2 implements Iterator<MapEntry<String, String>> {
  final MapEntry<String, String> _first;
  final MapEntry<String, String> _second;
  int _index = -1;

  _MapEntryIterator2(this._first, this._second);

  @override
  MapEntry<String, String> get current => _index == 0 ? _first : _second;

  @override
  bool moveNext() {
    if (_index >= 1) return false;
    _index += 1;
    return true;
  }
}

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
