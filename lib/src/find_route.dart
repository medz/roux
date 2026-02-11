import '_router_utils.dart';
import '_utils.dart';
import 'add_route.dart' show materializePendingRoutes;
import 'node.dart';
import 'router.dart';

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
  prepareFindRouteCache(ctx);
  materializePendingRoutes(ctx);
  final methodToken = normalizeMethod(ctx, method);

  if (path.isNotEmpty && path.codeUnitAt(path.length - 1) == 47) {
    path = path.substring(0, path.length - 1);
  }

  final cache = params
      ? ctx.findRouteCacheWithParams
      : ctx.findRouteCacheWithoutParams;
  final cachePath = params ? path : normalizePath(ctx, path);
  final cacheByMethod = cache[methodToken];
  if (cacheByMethod != null && cacheByMethod.containsKey(cachePath)) {
    return cacheByMethod[cachePath];
  }

  final matchPath = normalizePath(ctx, path);

  // Static
  final staticNode = ctx.static[matchPath];
  if (staticNode != null) {
    final staticMatch = matchNodeMethods(ctx, staticNode, methodToken);
    if (staticMatch != null && staticMatch.isNotEmpty) {
      final result = MatchedRoute<T>(staticMatch[0].data);
      _cacheResult(cache, methodToken, cachePath, result);
      return result;
    }
  }

  final segments = splitPath(path);
  final matchSegments = normalizeSegments(ctx, segments);

  final matches = _lookupTree(ctx, ctx.root, methodToken, matchSegments, 0);

  if (matches == null || matches.isEmpty) {
    _cacheResult(cache, methodToken, cachePath, null);
    return null;
  }

  final match = matches.first;
  final result = !params
      ? MatchedRoute<T>(match.data)
      : toMatched(match, segments);
  _cacheResult(cache, methodToken, cachePath, result);
  return result;
}

void _cacheResult<T>(
  Map<String, Map<String, MatchedRoute<T>?>> cache,
  String methodToken,
  String cachePath,
  MatchedRoute<T>? result,
) {
  final cacheByMethod = cache.putIfAbsent(
    methodToken,
    () => <String, MatchedRoute<T>?>{},
  );
  cacheByMethod[cachePath] = result;
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
