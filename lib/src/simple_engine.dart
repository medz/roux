import 'dart:collection';

import 'input_path.dart';
import 'route_entry.dart';

class SimpleEngine<T> {
  final SimpleNode<T> root = SimpleNode<T>();
  bool hasBranchingChoices = false;
  bool hasWildcardRoutes = false;
  RouteEntry<T>? globalFallback;
  int maxParamDepth = 0;
  bool straightDirty = false;
  List<String?> straightSegments = <String?>[];
  List<Map<String, RouteEntry<T>>?> straightLeaves =
      <Map<String, RouteEntry<T>>?>[];
  List<RouteEntry<T>?> straightExacts = <RouteEntry<T>?>[];
  List<RouteEntry<T>?> straightWildcards = <RouteEntry<T>?>[];

  void rebuildStraightPlan() {
    straightSegments = <String?>[];
    straightLeaves = <Map<String, RouteEntry<T>>?>[root.leafRoutes];
    straightExacts = <RouteEntry<T>?>[root.exactRoute];
    straightWildcards = <RouteEntry<T>?>[root.wildcardRoute];
    var node = root;
    while (true) {
      final paramChild = node.paramChild;
      if (paramChild != null) {
        straightSegments.add(null);
        node = paramChild;
      } else {
        final staticChild = node.staticChild;
        if (staticChild == null) break;
        straightSegments.add(staticChild.staticKey!);
        node = staticChild;
      }
      straightLeaves.add(node.leafRoutes);
      straightExacts.add(node.exactRoute);
      straightWildcards.add(node.wildcardRoute);
    }
  }

  RouteMatch<T>? matchStraight(String path, bool caseSensitive) {
    if (straightDirty || straightExacts.isEmpty) {
      rebuildStraightPlan();
      straightDirty = false;
    }
    final allowWildcards = hasWildcardRoutes;
    final smallParams = maxParamDepth <= 2;
    ParamStack? paramStack;
    var cursor = 1;
    var depth = 0;
    var paramCount = 0;
    var p0Start = 0, p0End = 0, p1Start = 0, p1End = 0;

    ParamStack? captureStack() {
      if (!smallParams || paramCount == 0) return paramStack;
      final captures = ParamStack(paramCount);
      captures.push(p0Start, p0End);
      if (paramCount > 1) captures.push(p1Start, p1End);
      return captures;
    }

    RouteMatch<T> buildMatch(RouteEntry<T> route, int wildcardStart) {
      if (!smallParams) {
        return materialize(route, path, paramStack, wildcardStart);
      }
      final names = route.paramNames;
      if (route.wildcardName == null) {
        if (names.isEmpty) return route.noParamsMatch;
        if (names.length == 1) {
          return RouteMatch<T>(
            route.data,
            CompactParamsMap.one(names[0], path.substring(p0Start, p0End)),
          );
        }
        if (names.length == 2) {
          return RouteMatch<T>(
            route.data,
            CompactParamsMap.two(
              names[0],
              path.substring(p0Start, p0End),
              names[1],
              path.substring(p1Start, p1End),
            ),
          );
        }
      }
      return materialize(route, path, captureStack(), wildcardStart);
    }

    while (true) {
      if (cursor >= path.length) {
        final exact = straightExacts[depth];
        if (exact != null) {
          return buildMatch(exact, 0);
        }
        final wildcard = allowWildcards ? straightWildcards[depth] : null;
        if (wildcard != null) {
          return buildMatch(wildcard, path.length);
        }
        return null;
      }
      final segmentEnd = findSegmentEnd(path, cursor);
      if (segmentEnd == cursor) return null;
      final nextCursor = segmentEnd < path.length
          ? segmentEnd + 1
          : path.length;
      if (nextCursor == path.length) {
        final leafRoutes = straightLeaves[depth];
        final leaf = leafRoutes == null
            ? null
            : leafRoutes[caseSensitive
                  ? path.substring(cursor, segmentEnd)
                  : path.substring(cursor, segmentEnd).toLowerCase()];
        if (leaf != null) return buildMatch(leaf, 0);
      }
      if (depth >= straightSegments.length) {
        final wildcard = allowWildcards ? straightWildcards[depth] : null;
        if (wildcard != null) return buildMatch(wildcard, cursor);
        return null;
      }
      final staticKey = straightSegments[depth];
      if (staticKey != null &&
          (caseSensitive
              ? equalsPathSlice(staticKey, path, cursor, segmentEnd)
              : equalsFoldedPathSlice(staticKey, path, cursor, segmentEnd))) {
        depth += 1;
        cursor = nextCursor;
        continue;
      }
      final wildcard = allowWildcards ? straightWildcards[depth] : null;
      if (staticKey != null) {
        if (wildcard != null) return buildMatch(wildcard, cursor);
        return null;
      }
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
        (paramStack ??= ParamStack(maxParamDepth)).push(cursor, segmentEnd);
      }
      depth += 1;
      cursor = nextCursor;
    }
  }

  RouteMatch<T>? match(String path, bool caseSensitive, bool allowWildcards) {
    return matchNode(root, path, caseSensitive, allowWildcards, 1, 0, null);
  }

  void collect(
    String path,
    bool caseSensitive,
    int methodRank,
    MatchCollector<T> output,
  ) {
    collectNode(root, path, caseSensitive, 1, 0, null, methodRank, output);
  }

  RouteMatch<T> materialize(
    RouteEntry<T> route,
    String path,
    ParamStack? paramValues,
    int wildcardStart,
  ) => route.wildcardName != null || route.paramNames.isNotEmpty
      ? RouteMatch<T>(
          route.data,
          materializeParams(route, path, paramValues, wildcardStart),
        )
      : route.noParamsMatch;

  void collectSlot(
    RouteEntry<T> slot,
    String path,
    ParamStack? paramValues,
    int wildcardStart,
    int methodRank,
    MatchCollector<T> output,
  ) {
    if (slot.wildcardName != null || slot.paramNames.isNotEmpty) {
      for (
        RouteEntry<T>? current = slot;
        current != null;
        current = current.next
      ) {
        output.add(
          RouteMatch<T>(
            current.data,
            materializeParams(current, path, paramValues, wildcardStart),
          ),
          current,
          methodRank,
        );
      }
      return;
    }
    for (
      RouteEntry<T>? current = slot;
      current != null;
      current = current.next
    ) {
      output.add(current.noParamsMatch, current, methodRank);
    }
  }

  Map<String, String> materializeParams(
    RouteEntry<T> route,
    String path,
    ParamStack? captures,
    int wildcardStart,
  ) {
    final names = route.paramNames;
    final wildcardName = route.wildcardName;
    if (wildcardName == null) {
      if (names.length == 1) {
        final requiredCaptures = captures!;
        return CompactParamsMap.one(
          names[0],
          path.substring(
            requiredCaptures.startAt(0),
            requiredCaptures.endAt(0),
          ),
        );
      }
      if (names.length == 2) {
        final requiredCaptures = captures!;
        return CompactParamsMap.two(
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

  RouteMatch<T>? matchNode(
    SimpleNode<T> node,
    String path,
    bool caseSensitive,
    bool allowWildcards,
    int cursor,
    int paramLength,
    ParamStack? paramStack,
  ) {
    final captures = paramStack;
    captures?.truncate(paramLength);
    if (cursor >= path.length) {
      final exact = node.exactRoute;
      if (exact != null) return materialize(exact, path, captures, 0);
      final wildcard = node.wildcardRoute;
      if (allowWildcards && wildcard != null) {
        return materialize(wildcard, path, captures, path.length);
      }
      return null;
    }

    final segmentEnd = findSegmentEnd(path, cursor);
    if (segmentEnd == cursor) return null;
    final nextCursor = segmentEnd < path.length ? segmentEnd + 1 : path.length;
    if (nextCursor == path.length) {
      final leaf = node.findLeafRouteSlice(
        path,
        cursor,
        segmentEnd,
        caseSensitive,
      );
      if (leaf != null) return materialize(leaf, path, captures, 0);
    }

    final staticChild = node.findStaticChildSlice(
      path,
      cursor,
      segmentEnd,
      caseSensitive,
    );
    if (staticChild != null) {
      final match = matchNode(
        staticChild,
        path,
        caseSensitive,
        allowWildcards,
        nextCursor,
        paramLength,
        captures,
      );
      if (match != null) return match;
      captures?.truncate(paramLength);
    }

    final paramChild = node.paramChild;
    if (paramChild != null) {
      final params = captures ?? ParamStack(maxParamDepth);
      params.truncate(paramLength);
      params.push(cursor, segmentEnd);
      final match = matchNode(
        paramChild,
        path,
        caseSensitive,
        allowWildcards,
        nextCursor,
        params.length,
        params,
      );
      if (match != null) return match;
      params.truncate(paramLength);
    }

    final wildcard = node.wildcardRoute;
    return allowWildcards && wildcard != null
        ? materialize(wildcard, path, captures, cursor)
        : null;
  }

  void collectNode(
    SimpleNode<T> node,
    String path,
    bool caseSensitive,
    int cursor,
    int paramLength,
    ParamStack? paramStack,
    int methodRank,
    MatchCollector<T> output,
  ) {
    final captures = paramStack;
    captures?.truncate(paramLength);
    if (cursor >= path.length) {
      final wildcard = node.wildcardRoute;
      if (wildcard != null) {
        collectSlot(wildcard, path, captures, path.length, methodRank, output);
      }
      final exact = node.exactRoute;
      if (exact != null)
        collectSlot(exact, path, captures, 0, methodRank, output);
      return;
    }

    final segmentEnd = findSegmentEnd(path, cursor);
    if (segmentEnd == cursor) return;
    final nextCursor = segmentEnd < path.length ? segmentEnd + 1 : path.length;
    final wildcard = node.wildcardRoute;
    if (wildcard != null) {
      collectSlot(wildcard, path, captures, cursor, methodRank, output);
    }
    if (nextCursor == path.length) {
      final leaf = node.findLeafRouteSlice(
        path,
        cursor,
        segmentEnd,
        caseSensitive,
      );
      if (leaf != null)
        collectSlot(leaf, path, captures, 0, methodRank, output);
    }

    final staticChild = node.findStaticChildSlice(
      path,
      cursor,
      segmentEnd,
      caseSensitive,
    );
    if (staticChild != null) {
      collectNode(
        staticChild,
        path,
        caseSensitive,
        nextCursor,
        paramLength,
        captures,
        methodRank,
        output,
      );
      captures?.truncate(paramLength);
    }

    final paramChild = node.paramChild;
    if (paramChild != null) {
      final params = captures ?? ParamStack(maxParamDepth);
      params.truncate(paramLength);
      params.push(cursor, segmentEnd);
      collectNode(
        paramChild,
        path,
        caseSensitive,
        nextCursor,
        params.length,
        params,
        methodRank,
        output,
      );
      params.truncate(paramLength);
    }
  }
}

class SimpleNode<T> {
  final String? staticKey;
  SimpleNode<T>? staticChild;
  SimpleNode<T>? staticNext;
  SimpleNode<T>? paramChild;
  Map<String, SimpleNode<T>>? staticMap;
  Map<String, RouteEntry<T>>? leafRoutes;
  int staticCount = 0;
  RouteEntry<T>? exactRoute;
  RouteEntry<T>? wildcardRoute;

  SimpleNode([this.staticKey]);

  SimpleNode<T> getOrCreateStaticChildSlice(String key) {
    final map = staticMap;
    if (map != null) return map[key] ??= SimpleNode<T>(key);
    final child = findStaticChild(key);
    if (child != null) return child;
    final created = SimpleNode<T>(key);
    created.staticNext = staticChild;
    staticChild = created;
    if (++staticCount >= mapAt) {
      final upgraded = <String, SimpleNode<T>>{};
      for (var node = staticChild; node != null; node = node.staticNext) {
        upgraded[node.staticKey!] = node;
      }
      staticMap = upgraded;
    }
    return created;
  }

  SimpleNode<T>? findStaticChildSlice(
    String path,
    int start,
    int end,
    bool caseSensitive,
  ) {
    if (!caseSensitive)
      return findStaticChild(path.substring(start, end).toLowerCase());
    final map = staticMap;
    if (map != null) return map[path.substring(start, end)];
    SimpleNode<T>? prev;
    var child = staticChild;
    while (child != null) {
      if (equalsPathSlice(child.staticKey!, path, start, end)) {
        if (prev != null) {
          prev.staticNext = child.staticNext;
          child.staticNext = staticChild;
          staticChild = child;
        }
        return child;
      }
      prev = child;
      child = child.staticNext;
    }
    return null;
  }

  SimpleNode<T>? findStaticChild(String key) {
    final map = staticMap;
    if (map != null) return map[key];
    SimpleNode<T>? prev;
    var child = staticChild;
    while (child != null) {
      if (child.staticKey == key) {
        if (prev != null) {
          prev.staticNext = child.staticNext;
          child.staticNext = staticChild;
          staticChild = child;
        }
        return child;
      }
      prev = child;
      child = child.staticNext;
    }
    return null;
  }

  RouteEntry<T>? findLeafRouteSlice(
    String path,
    int start,
    int end,
    bool caseSensitive,
  ) {
    final routes = leafRoutes;
    if (routes == null) return null;
    final key = caseSensitive
        ? path.substring(start, end)
        : path.substring(start, end).toLowerCase();
    return routes[key];
  }
}

bool equalsPathSlice(String key, String path, int start, int end) {
  if (key.length != end - start) return false;
  for (var i = 0; i < key.length; i++) {
    if (key.codeUnitAt(i) != path.codeUnitAt(start + i)) return false;
  }
  return true;
}

bool equalsFoldedPathSlice(String key, String path, int start, int end) {
  if (key.length != end - start) return false;
  for (var i = 0; i < key.length; i++) {
    final code = path.codeUnitAt(start + i);
    final lowered = code >= 65 && code <= 90 ? code + 32 : code;
    if (key.codeUnitAt(i) != lowered) return false;
  }
  return true;
}

class ParamStack {
  final List<int> values;
  int length = 0;

  ParamStack(int capacity)
    : values = List<int>.filled(
        (capacity == 0 ? 1 : capacity) * 2,
        0,
        growable: false,
      );

  void push(int start, int end) {
    values[length] = start;
    values[length + 1] = end;
    length += 2;
  }

  void truncate(int value) => length = value;

  int startAt(int index) => values[index * 2];

  int endAt(int index) => values[index * 2 + 1];
}

class CompactParamsMap extends MapBase<String, String> {
  CompactParamsMap.one(this._k0, this._v0) : _k1 = null, _v1 = null, _count = 1;

  CompactParamsMap.two(this._k0, this._v0, this._k1, this._v1) : _count = 2;

  final String _k0;
  final String _v0;
  final String? _k1;
  final String? _v1;
  final int _count;
  Map<String, String>? _backing;
  late final Iterable<MapEntry<String, String>> _inlineEntries =
      _CompactEntries(_k0, _v0, _k1, _v1);

  Map<String, String> _promote() => switch (_count) {
    1 => _backing ??= <String, String>{_k0: _v0},
    _ => _backing ??= <String, String>{_k0: _v0, _k1!: _v1!},
  };

  @override
  int get length => _backing?.length ?? _count;

  @override
  Iterable<String> get keys =>
      _backing?.keys ?? (_count == 1 ? <String>[_k0] : <String>[_k0, _k1!]);

  @override
  String? operator [](Object? key) {
    final backing = _backing;
    if (backing != null) return backing[key];
    if (key == _k0) return _v0;
    if (key == _k1) return _v1;
    return null;
  }

  @override
  void operator []=(String key, String value) => _promote()[key] = value;

  @override
  void clear() => _backing = <String, String>{};

  @override
  String? remove(Object? key) => _promote().remove(key);

  @override
  Iterable<MapEntry<String, String>> get entries =>
      _backing?.entries ?? _inlineEntries;
}

class _CompactEntries extends Iterable<MapEntry<String, String>> {
  _CompactEntries(this._k0, this._v0, this._k1, this._v1);

  final String _k0;
  final String _v0;
  final String? _k1;
  final String? _v1;

  @override
  Iterator<MapEntry<String, String>> get iterator =>
      _CompactEntriesIterator(_k0, _v0, _k1, _v1);
}

class _CompactEntriesIterator implements Iterator<MapEntry<String, String>> {
  _CompactEntriesIterator(this._k0, this._v0, this._k1, this._v1);

  final String _k0;
  final String _v0;
  final String? _k1;
  final String? _v1;
  int _index = -1;

  @override
  MapEntry<String, String> get current => _index == 0
      ? MapEntry<String, String>(_k0, _v0)
      : MapEntry<String, String>(_k1!, _v1!);

  @override
  bool moveNext() {
    if (_index >= 0 && _k1 == null) return false;
    if (_index >= 1) return false;
    _index += 1;
    return true;
  }
}
