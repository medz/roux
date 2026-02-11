import '_router_utils.dart';
import '_utils.dart';
import 'add_route.dart' show materializePendingRoutes;
import 'node.dart';
import 'router.dart';

/// Finds all matching routes for [method] and [path].
///
/// Matches are ordered from least specific to most specific: wildcard matches
/// first, then param matches, then static/end-of-path matches. When [params] is
/// false, params extraction is skipped and the returned [MatchedRoute] values
/// contain only [data].
List<MatchedRoute<T>> findAllRoutes<T>(
  RouterContext<T> ctx,
  String? method,
  String path, {
  bool params = true,
}) {
  if (ctx.pendingRoutes.isNotEmpty) {
    materializePendingRoutes(ctx);
  }
  final methodToken = normalizeMethod(ctx, method);

  if (path.isNotEmpty && path.codeUnitAt(path.length - 1) == 47) {
    path = path.substring(0, path.length - 1);
  }

  final matchPath = normalizePath(ctx, path);
  final segments = splitPath(path);
  final matchSegments = normalizeSegments(ctx, segments);

  final matches = _findAll(ctx, ctx.root, methodToken, matchSegments, 0);
  final staticNode = ctx.static[matchPath];
  if (staticNode != null) {
    final staticMatch = matchNodeMethods(ctx, staticNode, methodToken);
    if (staticMatch != null) {
      matches.addAll(staticMatch);
    }
  }

  if (matches.isEmpty) {
    return const [];
  }

  final uniqueMatches = <MethodData<T>>[];
  final seen = Set<MethodData<T>>.identity();
  for (final match in matches) {
    if (seen.add(match)) {
      uniqueMatches.add(match);
    }
  }

  if (!params) {
    return uniqueMatches.map((match) => MatchedRoute<T>(match.data)).toList();
  }

  return uniqueMatches.map((match) => toMatched(match, segments)).toList();
}

List<MethodData<T>> _findAll<T>(
  RouterContext<T> ctx,
  Node<T> node,
  String methodToken,
  List<String> segments,
  int index, [
  List<MethodData<T>>? matches,
]) {
  final acc = matches ?? <MethodData<T>>[];
  final segment = index < segments.length ? segments[index] : null;

  // 1. Wildcard
  final wildcardNode = node.wildcard;
  if (wildcardNode != null) {
    final match = matchNodeMethods(ctx, wildcardNode, methodToken);
    if (match != null) {
      acc.addAll(match);
    }
  }

  // 2. Param
  final paramNode = node.param;
  if (paramNode != null) {
    if (segment != null) {
      _findAll(ctx, paramNode, methodToken, segments, index + 1, acc);
    }
    if (index == segments.length) {
      final match = matchNodeMethods(ctx, paramNode, methodToken);
      if (match != null && match.isNotEmpty) {
        final pMap = match[0].paramsMap;
        if (pMap != null && pMap.isNotEmpty && pMap.last.optional) {
          acc.addAll(match);
        }
      }
    }
  }

  // 3. Static
  if (segment != null) {
    final staticChild = node.static?[segment];
    if (staticChild != null) {
      _findAll(ctx, staticChild, methodToken, segments, index + 1, acc);
    }
  }

  // 4. End of path
  if (index == segments.length) {
    final match = matchNodeMethods(ctx, node, methodToken);
    if (match != null) {
      acc.addAll(match);
    }
  }

  return acc;
}
