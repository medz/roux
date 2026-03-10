import 'dart:collection';

import 'route_model.dart';
import 'route_path.dart';

class TrieEngine<T> {
  TrieEngine(this.caseSensitive);

  final bool caseSensitive;
  final exactRoutes = <String, RouteEntry<T>>{};
  final root = SimpleNode<T>();
  bool hasBranchingChoices = false;
  bool hasWildcardRoutes = false;
  bool needsStrictPathValidation = false;
  RouteEntry<T>? globalFallback;
  int maxParamDepth = 0;
  bool straightDirty = false;
  List<String?> straightSegments = [];
  List<Map<String, RouteEntry<T>>?> straightLeaves = [];
  List<RouteEntry<T>?> straightExacts = [];
  List<RouteEntry<T>?> straightWildcards = [];
  Map<String, RouteEntry<T>>? straightTailLeaves;
  int straightParamCount = 0;
  String? straightParam0;
  String? straightParam1;

  bool add(
    String path,
    T data,
    DuplicatePolicy duplicatePolicy,
    int registrationOrder,
  ) {
    var hasReservedToken = false;
    var prevSlash = true;
    var exactDepth = 0;
    var exactStaticChars = 0;
    for (var i = 1; i < path.length; i++) {
      final code = path.codeUnitAt(i);
      if (code == slashCode) {
        if (prevSlash) throw FormatException('$emptySegment$path');
        exactDepth += 1;
        prevSlash = true;
        continue;
      }
      if (code == colonCode ||
          code == asteriskCode ||
          code == openBraceCode ||
          code == closeBraceCode ||
          code == questionCode) {
        hasReservedToken = true;
        break;
      }
      exactStaticChars += 1;
      prevSlash = false;
    }
    if (!hasReservedToken && path.length > 1 && !prevSlash) exactDepth += 1;
    if (!hasReservedToken) {
      addExact(
        path,
        data,
        duplicatePolicy,
        registrationOrder,
        exactDepth,
        exactStaticChars,
      );
      return true;
    }

    List<String>? paramNames;
    var paramCount = 0;
    var staticChars = 0;
    var depth = 0;
    var node = root;
    RouteEntry<T> buildRoute(
      String? wildcardName,
      int routeDepth,
      int routeSpecificity,
      int routeStaticChars,
      int constraintScore,
    ) => newRoute(
      data,
      paramNames ?? const [],
      wildcardName,
      path,
      routeDepth,
      routeSpecificity,
      routeStaticChars,
      constraintScore,
      registrationOrder,
    );

    void finishSimple() {
      if (paramCount > maxParamDepth) maxParamDepth = paramCount;
      straightDirty = true;
    }

    for (
      var cursor = path.length == 1 ? path.length : 1;
      cursor < path.length;
    ) {
      var segmentEnd = cursor;
      var hasReservedInSegment = false;
      while (segmentEnd < path.length) {
        final code = path.codeUnitAt(segmentEnd);
        if (code == slashCode) break;
        if (code == colonCode ||
            code == asteriskCode ||
            code == openBraceCode ||
            code == closeBraceCode ||
            code == questionCode) {
          hasReservedInSegment = true;
        }
        segmentEnd += 1;
      }
      if (segmentEnd == cursor) throw FormatException('$emptySegment$path');

      final firstCode = path.codeUnitAt(cursor);
      final doubleWildcardName = firstCode == asteriskCode
          ? readDoubleWildcardName(path, cursor, segmentEnd)
          : null;
      if (doubleWildcardName != null) {
        if (segmentEnd != path.length) {
          throw FormatException(
            'Double wildcard must be the last segment: $path',
          );
        }
        final route = buildRoute(
          doubleWildcardName,
          depth,
          remainderSpecificity,
          staticChars,
          0,
        );
        if (cursor == 1 && paramCount == 0) {
          hasWildcardRoutes = true;
          needsStrictPathValidation = true;
          globalFallback = mergeRouteEntries(
            globalFallback,
            route,
            path,
            duplicatePolicy,
            dupFallback,
          );
        } else {
          hasWildcardRoutes = true;
          node.wildcardRoute = mergeRouteEntries(
            node.wildcardRoute,
            route,
            path,
            duplicatePolicy,
            dupWildcard,
          );
        }
        finishSimple();
        return true;
      }

      if (firstCode == colonCode) {
        if (!hasValidParamNameSlice(path, cursor + 1, segmentEnd)) return false;
        if (node.staticChild != null ||
            node.staticMap != null ||
            node.leafRoutes != null) {
          hasBranchingChoices = true;
        }
        final paramName = path.substring(cursor + 1, segmentEnd);
        node = node.paramChild ??= SimpleNode<T>();
        (paramNames ??= <String>[]).add(paramName);
        paramCount += 1;
      } else {
        if (hasReservedInSegment) return false;
        final key = canonicalizeRoutePath(
          path.substring(cursor, segmentEnd),
          caseSensitive,
        );
        if (segmentEnd == path.length) {
          if (node.paramChild != null || node.wildcardRoute != null) {
            hasBranchingChoices = true;
          }
          final routes = node.leafRoutes ??= {};
          routes[key] = mergeRouteEntries(
            routes[key],
            buildRoute(
              null,
              depth + 1,
              paramCount == 0 ? exactSpecificity : singleDynamicSpecificity,
              staticChars + segmentEnd - cursor,
              0,
            ),
            path,
            duplicatePolicy,
            dupShape,
          );
          finishSimple();
          return true;
        }
        if (node.paramChild != null) hasBranchingChoices = true;
        node = node.getOrCreateStaticChildSlice(key);
        staticChars += segmentEnd - cursor;
      }

      depth += 1;
      cursor = segmentEnd + 1;
    }

    node.exactRoute = mergeRouteEntries(
      node.exactRoute,
      buildRoute(
        null,
        depth,
        paramCount == 0 ? exactSpecificity : singleDynamicSpecificity,
        staticChars,
        0,
      ),
      path,
      duplicatePolicy,
      dupShape,
    );
    finishSimple();
    return true;
  }

  void addExact(
    String path,
    T data,
    DuplicatePolicy duplicatePolicy,
    int registrationOrder,
    int depth,
    int staticChars,
  ) {
    final canonical = canonicalizeRoutePath(path, caseSensitive);
    exactRoutes[canonical] = mergeRouteEntries(
      exactRoutes[canonical],
      newRoute(
        data,
        const [],
        null,
        path,
        depth,
        exactSpecificity,
        staticChars,
        0,
        registrationOrder,
      ),
      path,
      duplicatePolicy,
      dupShape,
    );
  }

  RouteMatch<T>? matchExact(String path) => exactRoutes.isEmpty
      ? null
      : exactRoutes[canonicalizeRoutePath(path, caseSensitive)]?.noParamsMatch;

  void collectExact(String path, int methodRank, MatchAccumulator<T> output) {
    if (exactRoutes.isEmpty) return;
    final exact = exactRoutes[canonicalizeRoutePath(path, caseSensitive)];
    if (exact != null) collectSlot(exact, path, null, 0, methodRank, output);
  }

  void rebuildStraightPlan() {
    straightSegments = [];
    straightLeaves = [root.leafRoutes];
    straightExacts = [root.exactRoute];
    straightWildcards = [root.wildcardRoute];
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
    final last = straightLeaves.length - 1;
    var tailOnly =
        last >= 0 &&
        straightLeaves[last] != null &&
        straightExacts[last] == null &&
        straightWildcards[last] == null;
    for (var i = 0; tailOnly && i < last; i++) {
      if (straightLeaves[i] != null ||
          straightExacts[i] != null ||
          straightWildcards[i] != null) {
        tailOnly = false;
      }
    }
    final tailLeaves = tailOnly ? straightLeaves[last] : null;
    straightTailLeaves = tailLeaves;
    if (tailLeaves == null || tailLeaves.isEmpty) {
      straightParamCount = 0;
      straightParam0 = null;
      straightParam1 = null;
      return;
    }
    final sample = tailLeaves.values.first;
    straightParamCount = sample.paramNames.length;
    straightParam0 = straightParamCount > 0 ? sample.paramNames[0] : null;
    straightParam1 = straightParamCount > 1 ? sample.paramNames[1] : null;
  }

  RouteMatch<T>? matchStraight(String path) {
    if (straightDirty || straightExacts.isEmpty) {
      rebuildStraightPlan();
      straightDirty = false;
    }
    if (caseSensitive && !hasWildcardRoutes && maxParamDepth <= 2) {
      final tailLeaves = straightTailLeaves;
      if (tailLeaves != null) {
        return matchStraightTailLeaf(path, tailLeaves);
      }
      return matchStraightFast(path);
    }
    return matchStraightGeneric(path);
  }

  RouteMatch<T>? matchStraightTailLeaf(
    String path,
    Map<String, RouteEntry<T>> tailLeaves,
  ) {
    final segments = straightSegments;
    var cursor = 1;
    var depth = 0;
    var p0Start = 0, p0End = 0, p1Start = 0, p1End = 0;

    while (depth < segments.length) {
      if (cursor >= path.length) return null;
      final segmentEnd = findSegmentEnd(path, cursor);
      if (segmentEnd == cursor) return null;
      final staticKey = segments[depth];
      if (staticKey != null) {
        if (!equalsPathSlice(staticKey, path, cursor, segmentEnd)) return null;
      } else if (p0End == 0) {
        p0Start = cursor;
        p0End = segmentEnd;
      } else {
        p1Start = cursor;
        p1End = segmentEnd;
      }
      depth += 1;
      cursor = segmentEnd < path.length ? segmentEnd + 1 : path.length;
    }

    if (cursor >= path.length) return null;
    final segmentEnd = findSegmentEnd(path, cursor);
    if (segmentEnd == cursor || segmentEnd != path.length) return null;
    final leaf = tailLeaves[path.substring(cursor, segmentEnd)];
    if (leaf == null) return null;
    switch (straightParamCount) {
      case 0:
        return leaf.noParamsMatch;
      case 1:
        return RouteMatch(
          leaf.data,
          CompactParamsMap.one(straightParam0!, path.substring(p0Start, p0End)),
        );
      case 2:
        return RouteMatch(
          leaf.data,
          CompactParamsMap.two(
            straightParam0!,
            path.substring(p0Start, p0End),
            straightParam1!,
            path.substring(p1Start, p1End),
          ),
        );
    }
    return buildSmallMatch(leaf, path, p0Start, p0End, p1Start, p1End);
  }

  RouteMatch<T>? matchStraightFast(String path) {
    final segments = straightSegments;
    final leaves = straightLeaves;
    final exacts = straightExacts;
    var cursor = 1;
    var depth = 0;
    var p0Start = 0, p0End = 0, p1Start = 0, p1End = 0;

    while (true) {
      if (cursor >= path.length) {
        final exact = exacts[depth];
        return exact == null
            ? null
            : buildSmallMatch(exact, path, p0Start, p0End, p1Start, p1End);
      }
      final segmentEnd = findSegmentEnd(path, cursor);
      if (segmentEnd == cursor) return null;
      final nextCursor = segmentEnd < path.length
          ? segmentEnd + 1
          : path.length;
      if (nextCursor == path.length) {
        final leafRoutes = leaves[depth];
        final leaf = leafRoutes == null
            ? null
            : leafRoutes[path.substring(cursor, segmentEnd)];
        if (leaf != null) {
          return buildSmallMatch(leaf, path, p0Start, p0End, p1Start, p1End);
        }
      }
      if (depth >= segments.length) return null;
      final staticKey = segments[depth];
      if (staticKey != null) {
        if (!equalsPathSlice(staticKey, path, cursor, segmentEnd)) return null;
      } else if (p0End == 0) {
        p0Start = cursor;
        p0End = segmentEnd;
      } else {
        p1Start = cursor;
        p1End = segmentEnd;
      }
      depth += 1;
      cursor = nextCursor;
    }
  }

  RouteMatch<T>? matchStraightGeneric(String path) {
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
      return !smallParams
          ? materialize(route, path, paramStack, wildcardStart)
          : buildSmallMatch(
              route,
              path,
              p0Start,
              p0End,
              p1Start,
              p1End,
              captures: captureStack(),
              wildcardStart: wildcardStart,
            );
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
      var segmentEnd = cursor;
      while (segmentEnd < path.length &&
          path.codeUnitAt(segmentEnd) != slashCode) {
        segmentEnd += 1;
      }
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

  RouteMatch<T> buildSmallMatch(
    RouteEntry<T> route,
    String path,
    int p0Start,
    int p0End,
    int p1Start,
    int p1End, {
    ParamStack? captures,
    int wildcardStart = 0,
  }) {
    if (route.wildcardName != null) {
      return materialize(route, path, captures, wildcardStart);
    }
    final names = route.paramNames;
    if (names.isEmpty) return route.noParamsMatch;
    if (names.length == 1) {
      return RouteMatch(
        route.data,
        CompactParamsMap.one(names[0], path.substring(p0Start, p0End)),
      );
    }
    if (names.length == 2) {
      return RouteMatch(
        route.data,
        CompactParamsMap.two(
          names[0],
          path.substring(p0Start, p0End),
          names[1],
          path.substring(p1Start, p1End),
        ),
      );
    }
    return materialize(route, path, captures, wildcardStart);
  }

  RouteMatch<T>? match(String path, bool allowWildcards) {
    return walkNode(root, path, allowWildcards, 1, 0, null);
  }

  void collect(String path, int methodRank, MatchAccumulator<T> output) {
    walkNode(root, path, true, 1, 0, null, methodRank, output);
  }

  RouteMatch<T> materialize(
    RouteEntry<T> route,
    String path,
    ParamStack? paramValues,
    int wildcardStart,
  ) => route.wildcardName != null || route.paramNames.isNotEmpty
      ? RouteMatch(
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
    MatchAccumulator<T> output,
  ) {
    for (
      RouteEntry<T>? current = slot;
      current != null;
      current = current.next
    ) {
      output.add(
        materialize(current, path, paramValues, wildcardStart),
        current,
        methodRank,
      );
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

  RouteMatch<T>? walkNode(
    SimpleNode<T> node,
    String path,
    bool allowWildcards,
    int cursor,
    int paramLength,
    ParamStack? paramStack, [
    int? methodRank,
    MatchAccumulator<T>? output,
  ]) {
    final collecting = output != null;
    final captures = paramStack;
    captures?.truncate(paramLength);
    if (cursor >= path.length) {
      final wildcard = node.wildcardRoute;
      final exact = node.exactRoute;
      if (collecting) {
        if (wildcard != null) {
          collectSlot(
            wildcard,
            path,
            captures,
            path.length,
            methodRank!,
            output,
          );
        }
        if (exact != null) {
          collectSlot(exact, path, captures, 0, methodRank!, output);
        }
        return null;
      }
      if (exact != null) return materialize(exact, path, captures, 0);
      return allowWildcards && wildcard != null
          ? materialize(wildcard, path, captures, path.length)
          : null;
    }

    final segmentEnd = findSegmentEnd(path, cursor);
    if (segmentEnd == cursor) return null;
    final nextCursor = segmentEnd < path.length ? segmentEnd + 1 : path.length;
    final wildcard = node.wildcardRoute;
    if (collecting && wildcard != null) {
      collectSlot(wildcard, path, captures, cursor, methodRank!, output);
    }
    if (nextCursor == path.length) {
      final leaf = node.findLeafRouteSlice(
        path,
        cursor,
        segmentEnd,
        caseSensitive,
      );
      if (leaf != null) {
        if (collecting) {
          collectSlot(leaf, path, captures, 0, methodRank!, output);
        } else {
          return materialize(leaf, path, captures, 0);
        }
      }
    }

    final staticChild = node.findStaticChildSlice(
      path,
      cursor,
      segmentEnd,
      caseSensitive,
    );
    if (staticChild != null) {
      final match = walkNode(
        staticChild,
        path,
        allowWildcards,
        nextCursor,
        paramLength,
        captures,
        methodRank,
        output,
      );
      if (match != null) return match;
      captures?.truncate(paramLength);
    }

    final paramChild = node.paramChild;
    if (paramChild != null) {
      final params = captures ?? ParamStack(maxParamDepth);
      params.truncate(paramLength);
      params.push(cursor, segmentEnd);
      final match = walkNode(
        paramChild,
        path,
        allowWildcards,
        nextCursor,
        params.length,
        params,
        methodRank,
        output,
      );
      if (match != null) return match;
      params.truncate(paramLength);
    }

    return allowWildcards && wildcard != null
        ? materialize(wildcard, path, captures, cursor)
        : null;
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
    if (!caseSensitive) return findStaticChild(sliceKey(path, start, end));
    final map = staticMap;
    if (map != null) return map[path.substring(start, end)];
    SimpleNode<T>? prev;
    var child = staticChild;
    while (child != null) {
      if (equalsPathSlice(child.staticKey!, path, start, end)) {
        promoteStaticChild(prev, child);
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
        promoteStaticChild(prev, child);
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
    return routes[caseSensitive
        ? path.substring(start, end)
        : sliceKey(path, start, end)];
  }

  void promoteStaticChild(SimpleNode<T>? prev, SimpleNode<T> child) {
    if (prev == null) return;
    prev.staticNext = child.staticNext;
    child.staticNext = staticChild;
    staticChild = child;
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

String sliceKey(String path, int start, int end) =>
    path.substring(start, end).toLowerCase();

class ParamStack {
  final List<int> values;
  int length = 0;

  ParamStack(int capacity)
    : values = List.filled(
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
  late final _inlineEntries = _CompactEntries(_k0, _v0, _k1, _v1);

  Map<String, String> _promote() => switch (_count) {
    1 => _backing ??= {_k0: _v0},
    _ => _backing ??= {_k0: _v0, _k1!: _v1!},
  };

  @override
  int get length => _backing?.length ?? _count;

  @override
  Iterable<String> get keys =>
      _backing?.keys ?? (_count == 1 ? [_k0] : [_k0, _k1!]);

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
  void clear() => _backing = {};

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
  MapEntry<String, String> get current =>
      _index == 0 ? MapEntry(_k0, _v0) : MapEntry(_k1!, _v1!);

  @override
  bool moveNext() {
    if (_index >= 0 && _k1 == null) return false;
    if (_index >= 1) return false;
    _index += 1;
    return true;
  }
}
