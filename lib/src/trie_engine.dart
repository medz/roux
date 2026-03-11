import 'dart:collection';
import 'dart:typed_data';

import 'route_model.dart';
import 'route_path.dart';

/// Matches exact and segment-level routes with a trie-backed engine.
class TrieEngine<T> {
  /// Creates a trie engine with optional case folding.
  TrieEngine(this.caseSensitive);

  /// Whether static literals are matched case-sensitively.
  final bool caseSensitive;

  /// Exact routes and root trie node for this engine.
  final exactRoutes = <String, RouteEntry<T>>{}, root = _SimpleNode<T>();

  /// Flags describing trie shape and validation requirements.
  bool hasBranches = false,
      hasWildcards = false,
      needsStrict = false,
      hasNonExact = false;

  /// Shared fallback route for `/**`-style matches.
  RouteEntry<T>? globalFallback;

  /// The deepest number of params seen in simple routes.
  int paramDepth = 0;

  /// Straight-plan state used by the hot matching path.
  bool planDirty = false;

  /// Straight-plan segments and leaf route tables.
  List<String?> planSegments = [];

  /// Straight-plan leaf routes aligned with [planSegments].
  List<Map<String, RouteEntry<T>>?> planLeaves = [];

  /// Straight-plan exact and wildcard slots.
  List<RouteEntry<T>?> planExacts = [], planWildcards = [];

  /// Tail-leaf routes for the specialized straight matcher.
  Map<String, RouteEntry<T>>? tailLeaves;

  /// Captured metadata for the straight tail-leaf matcher.
  int tailParamCount = 0;

  /// Cached parameter names for the straight tail-leaf matcher.
  String? tailParam0, tailParam1;
  var _spans = Uint32List(0);

  /// Whether the root contains a parameter branch.
  bool get hasRootParamChild => root.paramChild != null;

  /// Adds a route to the trie engine, returning `false` for compiled syntax.
  bool add(String path, T data, DuplicatePolicy duplicatePolicy, int order) {
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
        order,
        exactDepth,
        exactStaticChars,
      );
      return true;
    }

    List<String>? names;
    var paramCount = 0;
    var staticChars = 0;
    var depth = 0;
    var node = root;
    RouteEntry<T> buildRoute(
      String? wildcard,
      int routeDepth,
      int routeSpecificity,
      int routeStaticChars,
      int constraintScore,
    ) => RouteEntry(
      data,
      names ?? const [],
      wildcard,
      path,
      routeDepth,
      routeSpecificity,
      routeStaticChars,
      constraintScore,
      order,
    );
    RouteEntry<T> mergeSlot(
      RouteEntry<T>? existing,
      RouteEntry<T> route,
      String rejectPrefix,
    ) =>
        mergeRouteEntries(existing, route, path, duplicatePolicy, rejectPrefix);

    void finishSimple() {
      hasNonExact = true;
      if (paramCount > paramDepth) paramDepth = paramCount;
      planDirty = true;
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
          ? readRestName(path, cursor, segmentEnd)
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
          specRem,
          staticChars,
          0,
        );
        if (cursor == 1 && paramCount == 0) {
          hasWildcards = true;
          needsStrict = true;
          globalFallback = mergeSlot(globalFallback, route, dupFallback);
        } else {
          hasWildcards = true;
          node.wildcardRoute = mergeSlot(
            node.wildcardRoute,
            route,
            dupWildcard,
          );
        }
        finishSimple();
        return true;
      }

      if (firstCode == colonCode) {
        if (!validParamSlice(path, cursor + 1, segmentEnd)) return false;
        if (node.staticChild != null ||
            node.staticMap != null ||
            node.leafRoutes != null) {
          hasBranches = true;
        }
        final paramName = path.substring(cursor + 1, segmentEnd);
        node = node.paramChild ??= _SimpleNode<T>();
        (names ??= <String>[]).add(paramName);
        paramCount += 1;
      } else {
        if (hasReservedInSegment) return false;
        final key = path.substring(cursor, segmentEnd);
        final canonicalKey = caseSensitive ? key : key.toLowerCase();
        if (segmentEnd == path.length) {
          if (node.paramChild != null || node.wildcardRoute != null) {
            hasBranches = true;
          }
          final routes = node.leafRoutes ??= {};
          routes[canonicalKey] = mergeSlot(
            routes[canonicalKey],
            buildRoute(
              null,
              depth + 1,
              paramCount == 0 ? specExact : specDyn,
              staticChars + segmentEnd - cursor,
              0,
            ),
            dupShape,
          );
          finishSimple();
          return true;
        }
        if (node.paramChild != null) {
          hasBranches = true;
        }
        node = node.getOrCreateStatic(canonicalKey);
        staticChars += segmentEnd - cursor;
      }

      depth += 1;
      cursor = segmentEnd + 1;
    }

    node.exactRoute = mergeSlot(
      node.exactRoute,
      buildRoute(
        null,
        depth,
        paramCount == 0 ? specExact : specDyn,
        staticChars,
        0,
      ),
      dupShape,
    );
    finishSimple();
    return true;
  }

  /// Adds an exact route directly to the exact-route table.
  void addExact(
    String path,
    T data,
    DuplicatePolicy duplicatePolicy,
    int order,
    int depth,
    int staticChars,
  ) {
    final canonical = caseSensitive ? path : path.toLowerCase();
    exactRoutes[canonical] = mergeRouteEntries(
      exactRoutes[canonical],
      RouteEntry(
        data,
        const [],
        null,
        path,
        depth,
        specExact,
        staticChars,
        0,
        order,
      ),
      path,
      duplicatePolicy,
      dupShape,
    );
  }

  /// Returns an exact-route match if present.
  @pragma('vm:prefer-inline')
  RouteMatch<T>? matchExact(String path) => exactRoutes.isEmpty
      ? null
      : exactRoutes[caseSensitive ? path : path.toLowerCase()]?.plainMatch;

  /// Rebuilds the cached straight matching plan.
  void rebuildStraightPlan() {
    planSegments = [];
    planLeaves = [root.leafRoutes];
    planExacts = [root.exactRoute];
    planWildcards = [root.wildcardRoute];
    var node = root;
    while (true) {
      final paramChild = node.paramChild;
      if (paramChild != null) {
        planSegments.add(null);
        node = paramChild;
      } else {
        final staticChild = node.staticChild;
        if (staticChild == null) break;
        planSegments.add(staticChild.staticKey!);
        node = staticChild;
      }
      planLeaves.add(node.leafRoutes);
      planExacts.add(node.exactRoute);
      planWildcards.add(node.wildcardRoute);
    }
    final last = planLeaves.length - 1;
    var tailOnly =
        last >= 0 &&
        planLeaves[last] != null &&
        planExacts[last] == null &&
        planWildcards[last] == null;
    for (var i = 0; tailOnly && i < last; i++) {
      if (planLeaves[i] != null ||
          planExacts[i] != null ||
          planWildcards[i] != null) {
        tailOnly = false;
      }
    }
    final tailLeafRoutes = tailOnly ? planLeaves[last] : null;
    if (tailLeafRoutes == null || tailLeafRoutes.isEmpty) {
      tailLeaves = null;
      tailParamCount = 0;
      tailParam0 = null;
      tailParam1 = null;
      return;
    }
    final sample = tailLeafRoutes.values.first;
    for (final leaf in tailLeafRoutes.values.skip(1)) {
      if (!_sameParamNames(sample.names, leaf.names)) {
        tailLeaves = null;
        tailParamCount = 0;
        tailParam0 = null;
        tailParam1 = null;
        return;
      }
    }
    tailLeaves = tailLeafRoutes;
    tailParamCount = sample.names.length;
    tailParam0 = tailParamCount > 0 ? sample.names[0] : null;
    tailParam1 = tailParamCount > 1 ? sample.names[1] : null;
  }

  /// Ensures the straight matching plan is ready.
  void ensureStraightPlan() {
    if (planDirty || planExacts.isEmpty) {
      rebuildStraightPlan();
      planDirty = false;
    }
  }

  /// Matches a path using the most efficient simple-route strategy.
  RouteMatch<T>? matchStraight(String path) {
    ensureStraightPlan();
    if (caseSensitive && !hasWildcards && paramDepth <= 2) {
      final tailLeafRoutes = tailLeaves;
      if (tailLeafRoutes != null) {
        return matchStraightTailLeaf(path, tailLeafRoutes);
      }
      return matchStraightFast(path);
    }
    return _walkNode(root, path, true, 1, 0, null);
  }

  /// Whether normalized matching can stay on the straight fast path.
  bool get canMatchStraightNormalized {
    ensureStraightPlan();
    return caseSensitive &&
        !hasWildcards &&
        paramDepth <= 2 &&
        tailLeaves != null;
  }

  /// Matches a normalized path on the straight fast path when possible.
  RouteMatch<T>? matchStraightNormalized(String path) {
    if (!canMatchStraightNormalized) return null;
    if (exactRoutes.isNotEmpty &&
        root.paramChild == null &&
        _dirtyFirstSegment(path)) {
      return null;
    }
    final tailLeafRoutes = tailLeaves!;
    final segments = planSegments;
    var cursor = 1;
    var depth = 0;
    var p0Start = 0, p0End = 0, p1Start = 0, p1End = 0;

    while (depth < segments.length) {
      if (cursor >= path.length) return null;
      final segmentEnd = findSegmentEnd(path, cursor);
      if (segmentEnd == cursor) {
        return matchDirtyTail(path);
      }
      final segmentLength = segmentEnd - cursor;
      if ((segmentLength == 1 && path.codeUnitAt(cursor) == 46) ||
          (segmentLength == 2 &&
              path.codeUnitAt(cursor) == 46 &&
              path.codeUnitAt(cursor + 1) == 46)) {
        return matchDirtyTail(path);
      }
      final staticKey = segments[depth];
      if (staticKey != null) {
        if (!_equalsPathSlice(staticKey, path, cursor, segmentEnd)) return null;
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
    if (segmentEnd == cursor) return matchDirtyTail(path);
    final segmentLength = segmentEnd - cursor;
    if ((segmentLength == 1 && path.codeUnitAt(cursor) == 46) ||
        (segmentLength == 2 &&
            path.codeUnitAt(cursor) == 46 &&
            path.codeUnitAt(cursor + 1) == 46) ||
        segmentEnd != path.length) {
      return matchDirtyTail(path);
    }
    final leaf = tailLeafRoutes[path.substring(cursor, segmentEnd)];
    return leaf == null
        ? null
        : buildTailMatch(leaf, path, p0Start, p0End, p1Start, p1End);
  }

  /// Normalizes a dirty path into spans and retries straight matching.
  RouteMatch<T>? matchDirtyTail(String path) {
    _spans = ensureSpanBuffer(_spans, path.length);
    final spanLength = normalizeSpans(path, _spans);
    if (spanLength < 0) return null;
    final match = matchTailSpans(path, _spans, spanLength);
    if (match != null || exactRoutes.isEmpty) return match;
    final normalized = pathFromSpans(path, _spans, spanLength);
    return exactRoutes[caseSensitive ? normalized : normalized.toLowerCase()]
        ?.plainMatch;
  }

  /// Matches a tail-leaf straight path without normalization.
  @pragma('vm:prefer-inline')
  RouteMatch<T>? matchStraightTailLeaf(
    String path,
    Map<String, RouteEntry<T>> tailLeaves,
  ) {
    final segments = planSegments;
    var cursor = 1;
    var depth = 0;
    var p0Start = 0, p0End = 0, p1Start = 0, p1End = 0;

    while (depth < segments.length) {
      if (cursor >= path.length) return null;
      final segmentEnd = findSegmentEnd(path, cursor);
      if (segmentEnd == cursor) return null;
      final staticKey = segments[depth];
      if (staticKey != null) {
        if (!_equalsPathSlice(staticKey, path, cursor, segmentEnd)) return null;
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
    switch (tailParamCount) {
      case 0:
        return leaf.plainMatch;
      case 1:
        return RouteMatch(
          leaf.data,
          _CompactParamsMap.one(tailParam0!, path.substring(p0Start, p0End)),
        );
      case 2:
        return RouteMatch(
          leaf.data,
          _CompactParamsMap.two(
            tailParam0!,
            path.substring(p0Start, p0End),
            tailParam1!,
            path.substring(p1Start, p1End),
          ),
        );
    }
    return buildMatch(leaf, path, p0Start, p0End, p1Start, p1End);
  }

  /// Matches a tail-leaf straight path using prepared normalized spans.
  @pragma('vm:prefer-inline')
  RouteMatch<T>? matchTailSpans(String path, List<int> spans, int spanLength) {
    final segments = planSegments;
    if (spanLength != (segments.length + 1) * 2) return null;
    var p0Start = 0, p0End = 0, p1Start = 0, p1End = 0;
    for (var depth = 0; depth < segments.length; depth++) {
      final pair = spanLength - 2 - depth * 2;
      final start = spans[pair];
      final end = spans[pair + 1];
      final staticKey = segments[depth];
      if (staticKey != null) {
        if (!_equalsPathSlice(staticKey, path, start, end)) return null;
      } else if (p0End == 0) {
        p0Start = start;
        p0End = end;
      } else {
        p1Start = start;
        p1End = end;
      }
    }
    final leafStart = spans[0];
    final leafEnd = spans[1];
    final leaf = tailLeaves?[path.substring(leafStart, leafEnd)];
    return leaf == null
        ? null
        : buildTailMatch(leaf, path, p0Start, p0End, p1Start, p1End);
  }

  /// Matches a straight path without wildcard handling.
  RouteMatch<T>? matchStraightFast(String path) {
    final segments = planSegments;
    final leaves = planLeaves;
    final exacts = planExacts;
    var cursor = 1;
    var depth = 0;
    var p0Start = 0, p0End = 0, p1Start = 0, p1End = 0;

    while (true) {
      if (cursor >= path.length) {
        final exact = exacts[depth];
        return exact == null
            ? null
            : buildMatch(exact, path, p0Start, p0End, p1Start, p1End);
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
          return buildMatch(leaf, path, p0Start, p0End, p1Start, p1End);
        }
      }
      if (depth >= segments.length) return null;
      final staticKey = segments[depth];
      if (staticKey != null) {
        if (!_equalsPathSlice(staticKey, path, cursor, segmentEnd)) return null;
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

  /// Returns whether two param-name lists have identical capture order.
  bool _sameParamNames(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Builds a small parameter match without the generic materializer.
  @pragma('vm:prefer-inline')
  RouteMatch<T> buildMatch(
    RouteEntry<T> route,
    String path,
    int p0Start,
    int p0End,
    int p1Start,
    int p1End, {
    ParamStack? captures,
    int wildcardStart = 0,
  }) {
    if (route.wildcard != null) {
      return materialize(route, path, captures, wildcardStart);
    }
    final names = route.names;
    if (names.isEmpty) return route.plainMatch;
    if (names.length == 1) {
      return RouteMatch(
        route.data,
        _CompactParamsMap.one(names[0], path.substring(p0Start, p0End)),
      );
    }
    if (names.length == 2) {
      return RouteMatch(
        route.data,
        _CompactParamsMap.two(
          names[0],
          path.substring(p0Start, p0End),
          names[1],
          path.substring(p1Start, p1End),
        ),
      );
    }
    return materialize(route, path, captures, wildcardStart);
  }

  /// Builds the specialized tail-leaf straight-path match.
  @pragma('vm:prefer-inline')
  RouteMatch<T> buildTailMatch(
    RouteEntry<T> leaf,
    String path,
    int p0Start,
    int p0End,
    int p1Start,
    int p1End,
  ) {
    switch (tailParamCount) {
      case 0:
        return leaf.plainMatch;
      case 1:
        return RouteMatch(
          leaf.data,
          _CompactParamsMap.one(tailParam0!, path.substring(p0Start, p0End)),
        );
      case 2:
        return RouteMatch(
          leaf.data,
          _CompactParamsMap.two(
            tailParam0!,
            path.substring(p0Start, p0End),
            tailParam1!,
            path.substring(p1Start, p1End),
          ),
        );
    }
    return buildMatch(leaf, path, p0Start, p0End, p1Start, p1End);
  }

  /// Matches a path against the general trie walker.
  RouteMatch<T>? match(String path, bool allowWildcards) =>
      _walkNode(root, path, allowWildcards, 1, 0, null);

  /// Collects every trie match for [path].
  @pragma('vm:prefer-inline')
  void collect(String path, int methodRank, MatchAccumulator<T> output) =>
      _walkNode(root, path, true, 1, 0, null, methodRank, output);

  /// Materializes a route match from captured trie state.
  @pragma('vm:prefer-inline')
  RouteMatch<T> materialize(
    RouteEntry<T> route,
    String path,
    ParamStack? paramValues,
    int wildcardStart,
  ) => route.wildcard != null || route.names.isNotEmpty
      ? RouteMatch(
          route.data,
          buildParams(route, path, paramValues, wildcardStart),
        )
      : route.plainMatch;

  /// Collects every route chained from a trie slot.
  @pragma('vm:prefer-inline')
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

  /// Materializes route parameters from captured trie state.
  @pragma('vm:prefer-inline')
  Map<String, String> buildParams(
    RouteEntry<T> route,
    String path,
    ParamStack? captures,
    int wildcardStart,
  ) {
    final names = route.names;
    final wildcard = route.wildcard;
    final tail = wildcardStart < path.length
        ? path.substring(wildcardStart)
        : '';
    switch (names.length) {
      case 0:
        if (wildcard != null) return _CompactParamsMap.one(wildcard, tail);
      case 1:
        final requiredCaptures = captures!;
        final p0 = path.substring(
          requiredCaptures.startAt(0),
          requiredCaptures.endAt(0),
        );
        return wildcard == null
            ? _CompactParamsMap.one(names[0], p0)
            : _CompactParamsMap.two(names[0], p0, wildcard, tail);
      case 2:
        if (wildcard == null) {
          final requiredCaptures = captures!;
          return _CompactParamsMap.two(
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
    if (wildcard != null) params[wildcard] = tail;
    return params;
  }

  RouteMatch<T>? _walkNode(
    _SimpleNode<T> node,
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
      final leaf = node.findLeafAt(path, cursor, segmentEnd, caseSensitive);
      if (leaf != null) {
        if (collecting) {
          collectSlot(leaf, path, captures, 0, methodRank!, output);
        } else {
          return materialize(leaf, path, captures, 0);
        }
      }
    }

    final staticChild = node.findStaticAt(
      path,
      cursor,
      segmentEnd,
      caseSensitive,
    );
    if (staticChild != null) {
      final match = _walkNode(
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
      final params = captures ?? ParamStack(paramDepth);
      params.truncate(paramLength);
      params.push(cursor, segmentEnd);
      final match = _walkNode(
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

class _SimpleNode<T> {
  final String? staticKey;
  _SimpleNode<T>? staticChild, staticNext, paramChild;
  Map<String, _SimpleNode<T>>? staticMap;
  Map<String, RouteEntry<T>>? leafRoutes;
  int staticCount = 0;
  RouteEntry<T>? exactRoute, wildcardRoute;

  _SimpleNode([this.staticKey]);

  _SimpleNode<T> getOrCreateStatic(String key) {
    final map = staticMap;
    if (map != null) return map[key] ??= _SimpleNode<T>(key);
    final child = findStaticChild(key);
    if (child != null) return child;
    final created = _SimpleNode<T>(key);
    created.staticNext = staticChild;
    staticChild = created;
    if (++staticCount >= mapAt) {
      final upgraded = <String, _SimpleNode<T>>{};
      for (var node = staticChild; node != null; node = node.staticNext) {
        upgraded[node.staticKey!] = node;
      }
      staticMap = upgraded;
    }
    return created;
  }

  _SimpleNode<T>? findStaticAt(
    String path,
    int start,
    int end,
    bool caseSensitive,
  ) {
    if (!caseSensitive) {
      return findStaticChild(_sliceKey(path, start, end));
    }
    final map = staticMap;
    if (map != null) return map[path.substring(start, end)];
    _SimpleNode<T>? prev;
    var child = staticChild;
    while (child != null) {
      if (_equalsPathSlice(child.staticKey!, path, start, end)) {
        promoteStaticChild(prev, child);
        return child;
      }
      prev = child;
      child = child.staticNext;
    }
    return null;
  }

  _SimpleNode<T>? findStaticChild(String key) {
    final map = staticMap;
    if (map != null) return map[key];
    _SimpleNode<T>? prev;
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

  @pragma('vm:prefer-inline')
  RouteEntry<T>? findLeafAt(
    String path,
    int start,
    int end,
    bool caseSensitive,
  ) {
    final routes = leafRoutes;
    if (routes == null) return null;
    return routes[caseSensitive
        ? path.substring(start, end)
        : _sliceKey(path, start, end)];
  }

  void promoteStaticChild(_SimpleNode<T>? prev, _SimpleNode<T> child) {
    if (prev == null) return;
    prev.staticNext = child.staticNext;
    child.staticNext = staticChild;
    staticChild = child;
  }
}

bool _dirtyFirstSegment(String path) {
  if (path.length < 2 || path.codeUnitAt(0) != slashCode) return false;
  final firstEnd = findSegmentEnd(path, 1);
  final length = firstEnd - 1;
  if (length == 0) return true;
  if (length == 1 && path.codeUnitAt(1) == 46) return true;
  return length == 2 && path.codeUnitAt(1) == 46 && path.codeUnitAt(2) == 46;
}

@pragma('vm:prefer-inline')
bool _equalsPathSlice(String key, String path, int start, int end) {
  if (key.length != end - start) return false;
  for (var i = 0; i < key.length; i++) {
    if (key.codeUnitAt(i) != path.codeUnitAt(start + i)) return false;
  }
  return true;
}

String _sliceKey(String path, int start, int end) =>
    path.substring(start, end).toLowerCase();

/// Stores parameter capture spans for generic trie matching.
class ParamStack {
  /// Packed start/end offsets for captured parameters.
  final List<int> values;

  /// The active length within [values].
  int length = 0;

  /// Creates a stack sized for the current trie depth.
  ParamStack(int capacity)
    : values = List.filled(
        (capacity == 0 ? 1 : capacity) * 2,
        0,
        growable: false,
      );

  /// Pushes a captured segment span.
  void push(int start, int end) {
    values[length] = start;
    values[length + 1] = end;
    length += 2;
  }

  /// Truncates the stack to a packed offset length.
  void truncate(int value) => length = value;

  /// Returns the captured segment start at [index].
  int startAt(int index) => values[index * 2];

  /// Returns the captured segment end at [index].
  int endAt(int index) => values[index * 2 + 1];
}

class _CompactParamsMap extends MapBase<String, String> {
  _CompactParamsMap.one(this._k0, this._v0)
    : _k1 = null,
      _v1 = null,
      _count = 1;

  _CompactParamsMap.two(this._k0, this._v0, this._k1, this._v1) : _count = 2;

  final String _k0, _v0;
  final String? _k1, _v1;
  final int _count;
  Map<String, String>? _backing;

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
  Iterable<MapEntry<String, String>> get entries {
    final backing = _backing;
    return backing?.entries ?? _CompactEntries(_k0, _v0, _k1, _v1, _count);
  }
}

class _CompactEntries extends IterableBase<MapEntry<String, String>> {
  _CompactEntries(this._k0, this._v0, this._k1, this._v1, this._count);

  final String _k0, _v0;
  final String? _k1, _v1;
  final int _count;

  @override
  Iterator<MapEntry<String, String>> get iterator =>
      _CompactEntriesIterator(_k0, _v0, _k1, _v1, _count);
}

class _CompactEntriesIterator implements Iterator<MapEntry<String, String>> {
  _CompactEntriesIterator(this._k0, this._v0, this._k1, this._v1, this._count);

  final String _k0, _v0;
  final String? _k1, _v1;
  final int _count;
  int _index = -1;
  MapEntry<String, String>? _current;

  @override
  MapEntry<String, String> get current => _current!;

  @override
  bool moveNext() {
    switch (++_index) {
      case 0:
        _current = MapEntry(_k0, _v0);
        return true;
      case 1 when _count == 2:
        _current = MapEntry(_k1!, _v1!);
        return true;
      default:
        _current = null;
        return false;
    }
  }
}
