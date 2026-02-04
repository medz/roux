import '_router_utils.dart';
import '_utils.dart';
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
  final methodToken = normalizeMethod(ctx, method);

  if (path.isNotEmpty && path.codeUnitAt(path.length - 1) == 47) {
    path = path.substring(0, path.length - 1);
  }

  final matchPath = normalizePath(ctx, path);

  // Static
  final staticNode = ctx.static[matchPath];
  if (staticNode?.methods != null) {
    final staticMatch = matchMethods(ctx, staticNode!.methods!, methodToken);
    if (staticMatch != null) {
      return params
          ? toMatched(staticMatch[0], splitPath(path))
          : MatchedRoute<T>(staticMatch[0].data);
    }
  }

  final segments = splitPath(path);
  final matchSegments = normalizeSegments(ctx, segments);

  final matches = _lookupTree(
    ctx,
    ctx.root,
    methodToken,
    matchSegments,
    0,
  );

  if (matches == null || matches.isEmpty) {
    return null;
  }

  final match = matches.first;

  if (!params) {
    return MatchedRoute<T>(match.data);
  }

  return toMatched(match, segments);
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
    if (node.methods != null) {
      final match = matchMethods(ctx, node.methods!, methodToken);
      if (match != null) {
        return match;
      }
    }

    // Fallback to dynamic for last child
    if (node.param?.methods != null) {
      final match = matchMethods(ctx, node.param!.methods!, methodToken);
      if (match != null) {
        final pMap = match[0].paramsMap;
        if (pMap != null && pMap.isNotEmpty && pMap.last.optional) {
          return match;
        }
      }
    }
    if (node.wildcard?.methods != null) {
      final match = matchMethods(ctx, node.wildcard!.methods!, methodToken);
      if (match != null) {
        final pMap = match[0].paramsMap;
        if (pMap != null && pMap.isNotEmpty && pMap.last.optional) {
          return match;
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
  if (node.wildcard?.methods != null) {
    return matchMethods(ctx, node.wildcard!.methods!, methodToken);
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
