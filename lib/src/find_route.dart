import '_router_utils.dart';
import '_utils.dart';
import 'add_route.dart' show materializePendingRoutes;
import 'node.dart';
import 'router.dart';

const _maxFindRouteCacheEntriesPerMethod = 8192;

/// Finds the first matching route for [method] and [path].
///
/// Returns null when no route matches. When [params] is false, params
/// extraction is skipped and the returned [MatchedRoute] contains only [data].
MatchedRoute<T>? findRoute<T>(
  RouterContext<T> ctx,
  String? method,
  String path, {
  bool params = true,
}) {
  _prepareFindRouteState(ctx);
  final methodToken = normalizeMethod(ctx, method);

  if (path.isNotEmpty && path.codeUnitAt(path.length - 1) == 47) {
    path = path.substring(0, path.length - 1);
  }

  final hitCache = params
      ? ctx.findRouteCacheWithParams
      : ctx.findRouteCacheWithoutParams;
  final noMatchCache = params
      ? ctx.findRouteNoMatchCacheWithParams
      : ctx.findRouteNoMatchCacheWithoutParams;
  final cachePath = params ? path : normalizePath(ctx, path);
  final hitByMethod = hitCache[methodToken];
  final cachedHit = hitByMethod?[cachePath];
  if (cachedHit != null) {
    return cachedHit;
  }
  if (noMatchCache[methodToken]?.contains(cachePath) ?? false) {
    return null;
  }

  final matchPath = normalizePath(ctx, path);

  // Static
  final staticNode = ctx.static[matchPath];
  if (staticNode != null) {
    final staticMatch = matchNodeMethods(ctx, staticNode, methodToken);
    if (staticMatch != null && staticMatch.isNotEmpty) {
      final result = MatchedRoute<T>(staticMatch[0].data);
      _cacheResult(hitCache, noMatchCache, methodToken, cachePath, result);
      return result;
    }
  }

  final segments = splitPath(path);
  final matchSegments = normalizeSegments(ctx, segments);

  final matches = _lookupTree(ctx, ctx.root, methodToken, matchSegments, 0);

  if (matches == null || matches.isEmpty) {
    _cacheResult(hitCache, noMatchCache, methodToken, cachePath, null);
    return null;
  }

  final match = matches.first;
  final result = !params
      ? MatchedRoute<T>(match.data)
      : toMatched(match, segments);
  _cacheResult(hitCache, noMatchCache, methodToken, cachePath, result);
  return result;
}

void _prepareFindRouteState<T>(RouterContext<T> ctx) {
  if (ctx.cacheVersion == ctx.mutationVersion) {
    return;
  }
  clearFindRouteCaches(ctx);
  materializePendingRoutes(ctx);
  ctx.cacheVersion = ctx.mutationVersion;
}

void _cacheResult<T>(
  Map<String, Map<String, MatchedRoute<T>>> hitCache,
  Map<String, Set<String>> noMatchCache,
  String methodToken,
  String cachePath,
  MatchedRoute<T>? result,
) {
  if (result == null) {
    final misses = noMatchCache.putIfAbsent(methodToken, () => <String>{});
    if (!misses.contains(cachePath) &&
        misses.length >= _maxFindRouteCacheEntriesPerMethod) {
      misses.remove(misses.first);
    }
    misses.add(cachePath);

    final hits = hitCache[methodToken];
    if (hits != null) {
      hits.remove(cachePath);
      if (hits.isEmpty) {
        hitCache.remove(methodToken);
      }
    }
    return;
  }

  final hits = hitCache.putIfAbsent(
    methodToken,
    () => <String, MatchedRoute<T>>{},
  );
  if (!hits.containsKey(cachePath) &&
      hits.length >= _maxFindRouteCacheEntriesPerMethod) {
    hits.remove(hits.keys.first);
  }
  hits[cachePath] = result;

  final misses = noMatchCache[methodToken];
  if (misses != null) {
    misses.remove(cachePath);
    if (misses.isEmpty) {
      noMatchCache.remove(methodToken);
    }
  }
}

List<MethodData<T>>? _lookupTree<T>(
  RouterContext<T> ctx,
  Node<T> node,
  String methodToken,
  List<String> segments,
  int index,
) {
  // 0. End of path
  if (index == segments.length) {
    final match = matchNodeMethods(ctx, node, methodToken);
    if (match != null) {
      return match;
    }

    // Fallback to dynamic for last child
    final paramNode = node.param;
    if (paramNode != null) {
      final paramMatch = matchNodeMethods(ctx, paramNode, methodToken);
      if (paramMatch != null && paramMatch.isNotEmpty) {
        final pMap = paramMatch[0].paramsMap;
        if (pMap != null && pMap.isNotEmpty && pMap.last.optional) {
          return paramMatch;
        }
      }
    }
    final wildcardNode = node.wildcard;
    if (wildcardNode != null) {
      final wildcardMatch = matchNodeMethods(ctx, wildcardNode, methodToken);
      if (wildcardMatch != null && wildcardMatch.isNotEmpty) {
        final pMap = wildcardMatch[0].paramsMap;
        if (pMap != null && pMap.isNotEmpty && pMap.last.optional) {
          return wildcardMatch;
        }
      }
    }
    return null;
  }

  final segment = segments[index];

  // 1. Static
  if (node.static != null) {
    final staticChild = node.static![segment];
    if (staticChild != null) {
      final match = _lookupTree(
        ctx,
        staticChild,
        methodToken,
        segments,
        index + 1,
      );
      if (match != null) {
        return match;
      }
    }
  }

  // 2. Param
  if (node.param != null) {
    final match = _lookupTree(
      ctx,
      node.param!,
      methodToken,
      segments,
      index + 1,
    );
    if (match != null) {
      if (node.param!.hasRegexParam) {
        final exact = _selectRegexMatch(match, index, segment);
        return exact == null ? null : <MethodData<T>>[exact];
      }
      return match;
    }
  }

  // 3. Wildcard
  final wildcardNode = node.wildcard;
  if (wildcardNode != null) {
    return matchNodeMethods(ctx, wildcardNode, methodToken);
  }

  return null;
}

MethodData<T>? _selectRegexMatch<T>(
  List<MethodData<T>> matches,
  int index,
  String segment,
) {
  for (final match in matches) {
    final regexp = _getRegexpAt(match.paramsRegexp, index);
    if (regexp != null && regexp.hasMatch(segment)) {
      return match;
    }
  }
  for (final match in matches) {
    final regexp = _getRegexpAt(match.paramsRegexp, index);
    if (regexp == null) {
      return match;
    }
  }
  return null;
}

RegExp? _getRegexpAt(List<RegExp?> paramsRegexp, int index) {
  if (index < 0 || index >= paramsRegexp.length) {
    return null;
  }
  return paramsRegexp[index];
}
