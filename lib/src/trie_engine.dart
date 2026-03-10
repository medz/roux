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
  final exactRoutes = <String, RouteEntry<T>>{}, root = SimpleNode<T>();

  /// Flags describing trie shape and validation requirements.
  bool hasBranchingChoices = false,
      hasWildcardRoutes = false,
      needsStrictPathValidation = false,
      hasNonExactRoutes = false;

  /// Shared fallback route for `/**`-style matches.
  RouteEntry<T>? globalFallback;

  /// The deepest number of params seen in simple routes.
  int maxParamDepth = 0;

  /// Straight-plan state used by the hot matching path.
  bool straightDirty = false;

  /// Straight-plan segments and leaf route tables.
  List<String?> straightSegments = [];

  /// Straight-plan leaf routes aligned with [straightSegments].
  List<Map<String, RouteEntry<T>>?> straightLeaves = [];

  /// Straight-plan exact and wildcard slots.
  List<RouteEntry<T>?> straightExacts = [], straightWildcards = [];

  /// Tail-leaf routes for the specialized straight matcher.
  Map<String, RouteEntry<T>>? straightTailLeaves;

  /// Captured metadata for the straight tail-leaf matcher.
  int straightParamCount = 0;

  /// Cached parameter names for the straight tail-leaf matcher.
  String? straightParam0, straightParam1;
  var _normalizedSpans = Uint32List(0);

  /// Adds a route to the trie engine, returning `false` for compiled syntax.
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
    RouteEntry<T> mergeSlot(
      RouteEntry<T>? existing,
      RouteEntry<T> route,
      String rejectPrefix,
    ) =>
        mergeRouteEntries(existing, route, path, duplicatePolicy, rejectPrefix);

    void finishSimple() {
      hasNonExactRoutes = true;
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
          globalFallback = mergeSlot(globalFallback, route, dupFallback);
        } else {
          hasWildcardRoutes = true;
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
          routes[key] = mergeSlot(
            routes[key],
            buildRoute(
              null,
              depth + 1,
              paramCount == 0 ? exactSpecificity : singleDynamicSpecificity,
              staticChars + segmentEnd - cursor,
              0,
            ),
            dupShape,
          );
          finishSimple();
          return true;
        }
        if (node.paramChild != null) {
          hasBranchingChoices = true;
        }
        node = node.getOrCreateStaticChildSlice(key);
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
        paramCount == 0 ? exactSpecificity : singleDynamicSpecificity,
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

  /// Returns an exact-route match if present.
  RouteMatch<T>? matchExact(String path) => exactRoutes.isEmpty
      ? null
      : exactRoutes[canonicalizeRoutePath(path, caseSensitive)]?.noParamsMatch;

  /// Rebuilds the cached straight matching plan.
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
    if (tailLeaves == null || tailLeaves.isEmpty) {
      straightTailLeaves = null;
      straightParamCount = 0;
      straightParam0 = null;
      straightParam1 = null;
      return;
    }
    final sample = tailLeaves.values.first;
    for (final leaf in tailLeaves.values.skip(1)) {
      if (!_sameParamNames(sample.paramNames, leaf.paramNames)) {
        straightTailLeaves = null;
        straightParamCount = 0;
        straightParam0 = null;
        straightParam1 = null;
        return;
      }
    }
    straightTailLeaves = tailLeaves;
    straightParamCount = sample.paramNames.length;
    straightParam0 = straightParamCount > 0 ? sample.paramNames[0] : null;
    straightParam1 = straightParamCount > 1 ? sample.paramNames[1] : null;
  }

  /// Ensures the straight matching plan is ready.
  void ensureStraightPlan() {
    if (straightDirty || straightExacts.isEmpty) {
      rebuildStraightPlan();
      straightDirty = false;
    }
  }

  /// Matches a path using the most efficient simple-route strategy.
  RouteMatch<T>? matchStraight(String path) {
    ensureStraightPlan();
    if (caseSensitive && !hasWildcardRoutes && maxParamDepth <= 2) {
      final tailLeaves = straightTailLeaves;
      if (tailLeaves != null) {
        return matchStraightTailLeaf(path, tailLeaves);
      }
      return matchStraightFast(path);
    }
    return walkNode(root, path, true, 1, 0, null);
  }

  /// Whether normalized matching can stay on the straight fast path.
  bool get canMatchStraightNormalized {
    ensureStraightPlan();
    return caseSensitive &&
        !hasWildcardRoutes &&
        maxParamDepth <= 2 &&
        straightTailLeaves != null;
  }

  /// Matches a normalized path on the straight fast path when possible.
  RouteMatch<T>? matchStraightNormalized(String path) {
    if (!canMatchStraightNormalized) return null;
    final tailLeaves = straightTailLeaves!;
    final segments = straightSegments;
    var cursor = 1;
    var depth = 0;
    var p0Start = 0, p0End = 0, p1Start = 0, p1End = 0;

    while (depth < segments.length) {
      if (cursor >= path.length) return null;
      final segmentEnd = findSegmentEnd(path, cursor);
      if (segmentEnd == cursor) {
        return matchStraightTailLeafDirtyNormalized(path);
      }
      final segmentLength = segmentEnd - cursor;
      if ((segmentLength == 1 && path.codeUnitAt(cursor) == 46) ||
          (segmentLength == 2 &&
              path.codeUnitAt(cursor) == 46 &&
              path.codeUnitAt(cursor + 1) == 46)) {
        return matchStraightTailLeafDirtyNormalized(path);
      }
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
    if (segmentEnd == cursor) return matchStraightTailLeafDirtyNormalized(path);
    final segmentLength = segmentEnd - cursor;
    if ((segmentLength == 1 && path.codeUnitAt(cursor) == 46) ||
        (segmentLength == 2 &&
            path.codeUnitAt(cursor) == 46 &&
            path.codeUnitAt(cursor + 1) == 46) ||
        segmentEnd != path.length) {
      return matchStraightTailLeafDirtyNormalized(path);
    }
    final leaf = tailLeaves[path.substring(cursor, segmentEnd)];
    return leaf == null
        ? null
        : buildStraightTailLeafMatch(
            leaf,
            path,
            p0Start,
            p0End,
            p1Start,
            p1End,
          );
  }

  /// Normalizes a dirty path into spans and retries straight matching.
  RouteMatch<T>? matchStraightTailLeafDirtyNormalized(String path) {
    _normalizedSpans = ensureSpanBuffer(_normalizedSpans, path.length);
    final spanLength = normalizePathSpans(path, _normalizedSpans);
    if (spanLength < 0) return null;
    return matchStraightTailLeafNormalized(path, _normalizedSpans, spanLength);
  }

  /// Matches a tail-leaf straight path without normalization.
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

  /// Matches a tail-leaf straight path using prepared normalized spans.
  RouteMatch<T>? matchStraightTailLeafNormalized(
    String path,
    List<int> spans,
    int spanLength,
  ) {
    final segments = straightSegments;
    if (spanLength != (segments.length + 1) * 2) return null;
    var p0Start = 0, p0End = 0, p1Start = 0, p1End = 0;
    for (var depth = 0; depth < segments.length; depth++) {
      final pair = spanLength - 2 - depth * 2;
      final start = spans[pair];
      final end = spans[pair + 1];
      final staticKey = segments[depth];
      if (staticKey != null) {
        if (!equalsPathSlice(staticKey, path, start, end)) return null;
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
    final leaf = straightTailLeaves?[path.substring(leafStart, leafEnd)];
    return leaf == null
        ? null
        : buildStraightTailLeafMatch(
            leaf,
            path,
            p0Start,
            p0End,
            p1Start,
            p1End,
          );
  }

  /// Matches a straight path without wildcard handling.
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

  /// Returns whether two param-name lists have identical capture order.
  bool _sameParamNames(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Builds a small parameter match without the generic materializer.
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

  /// Builds the specialized tail-leaf straight-path match.
  RouteMatch<T> buildStraightTailLeafMatch(
    RouteEntry<T> leaf,
    String path,
    int p0Start,
    int p0End,
    int p1Start,
    int p1End,
  ) {
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

  /// Matches a path against the general trie walker.
  RouteMatch<T>? match(String path, bool allowWildcards) =>
      walkNode(root, path, allowWildcards, 1, 0, null);

  /// Collects every trie match for [path].
  void collect(String path, int methodRank, MatchAccumulator<T> output) =>
      walkNode(root, path, true, 1, 0, null, methodRank, output);

  /// Materializes a route match from captured trie state.
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

  /// Collects every route chained from a trie slot.
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

  /// Walks the trie recursively for general matching and collection.
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

/// Trie node for simple segment-based routing.
class SimpleNode<T> {
  /// The canonical static segment held by this node, if any.
  final String? staticKey;

  /// Linked-list and map-based child references.
  SimpleNode<T>? staticChild, staticNext, paramChild;

  /// Static and leaf route tables stored on this node.
  Map<String, SimpleNode<T>>? staticMap;

  /// Leaf routes keyed by the final segment.
  Map<String, RouteEntry<T>>? leafRoutes;

  /// Static child count and terminal routes for this node.
  int staticCount = 0;

  /// Exact and wildcard terminal routes for this node.
  RouteEntry<T>? exactRoute, wildcardRoute;

  /// Creates a trie node for an optional static segment.
  SimpleNode([this.staticKey]);

  /// Returns an existing static child or creates one for [key].
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

  /// Finds a static child matching a path slice.
  SimpleNode<T>? findStaticChildSlice(
    String path,
    int start,
    int end,
    bool caseSensitive,
  ) {
    if (!caseSensitive) {
      return findStaticChild(sliceKey(path, start, end));
    }
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

  /// Finds a static child matching an already canonicalized key.
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

  /// Finds a leaf route matching a path slice.
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

  /// Promotes a recently matched static child to the front of the list.
  void promoteStaticChild(SimpleNode<T>? prev, SimpleNode<T> child) {
    if (prev == null) return;
    prev.staticNext = child.staticNext;
    child.staticNext = staticChild;
    staticChild = child;
  }
}

/// Compares a canonical key against a raw path slice.
bool equalsPathSlice(String key, String path, int start, int end) {
  if (key.length != end - start) return false;
  for (var i = 0; i < key.length; i++) {
    if (key.codeUnitAt(i) != path.codeUnitAt(start + i)) return false;
  }
  return true;
}

/// Compares a lowercased key against a path slice without allocating.
bool equalsFoldedPathSlice(String key, String path, int start, int end) {
  if (key.length != end - start) return false;
  for (var i = 0; i < key.length; i++) {
    final code = path.codeUnitAt(start + i);
    final lowered = code >= 65 && code <= 90 ? code + 32 : code;
    if (key.codeUnitAt(i) != lowered) return false;
  }
  return true;
}

/// Builds a folded key for case-insensitive static lookups.
String sliceKey(String path, int start, int end) =>
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

/// Small-map implementation optimized for one or two parameters.
class CompactParamsMap extends MapBase<String, String> {
  /// Creates a compact map containing one entry.
  CompactParamsMap.one(this._k0, this._v0) : _k1 = null, _v1 = null, _count = 1;

  /// Creates a compact map containing two entries.
  CompactParamsMap.two(this._k0, this._v0, this._k1, this._v1) : _count = 2;

  final String _k0, _v0;
  final String? _k1, _v1;
  final int _count;
  Map<String, String>? _backing;

  /// Promotes the compact map to a regular mutable backing map.
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
