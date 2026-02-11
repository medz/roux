import 'node.dart';
import 'router.dart';

String normalizeMethod<T>(RouterContext<T> ctx, String? method) {
  if (method == null || method.isEmpty) {
    return ctx.anyMethodTokenNormalized;
  }

  if (_isAsciiUpper(method)) {
    return method == ctx.anyMethodTokenNormalized
        ? ctx.anyMethodTokenNormalized
        : method;
  }

  final cached = ctx.methodCache[method];
  if (cached != null) {
    return cached;
  }

  var normalized = method.toUpperCase();
  if (normalized == ctx.anyMethodTokenNormalized) {
    normalized = ctx.anyMethodTokenNormalized;
  }

  ctx.methodCache[method] = normalized;
  return normalized;
}

String normalizePath<T>(RouterContext<T> ctx, String path) {
  return ctx.caseSensitive ? path : path.toLowerCase();
}

String normalizeStaticCachePath(String path) {
  if (path.isNotEmpty && path.codeUnitAt(path.length - 1) == 47) {
    return path.substring(0, path.length - 1);
  }
  return path;
}

List<String> normalizeSegments<T>(RouterContext<T> ctx, List<String> segments) {
  if (ctx.caseSensitive) {
    return segments;
  }
  return segments.map((segment) => segment.toLowerCase()).toList();
}

List<MethodData<T>> getOrCreateMethodBucket<T>(
  Node<T> node,
  String methodToken,
) {
  final methods = node.methods;
  if (methods != null) {
    return methods.putIfAbsent(methodToken, () => <MethodData<T>>[]);
  }

  final singleBucket = node.singleMethodBucket;
  if (singleBucket == null) {
    final bucket = <MethodData<T>>[];
    node.singleMethodToken = methodToken;
    node.singleMethodBucket = bucket;
    return bucket;
  }

  if (node.singleMethodToken == methodToken) {
    return singleBucket;
  }

  final upgraded = <String, List<MethodData<T>>>{
    node.singleMethodToken!: singleBucket,
  };
  node.methods = upgraded;
  node.singleMethodToken = null;
  node.singleMethodBucket = null;
  return upgraded.putIfAbsent(methodToken, () => <MethodData<T>>[]);
}

List<MethodData<T>>? matchNodeMethods<T>(
  RouterContext<T> ctx,
  Node<T> node,
  String methodToken,
) {
  final methods = node.methods;
  if (methods != null) {
    return methods[methodToken] ?? methods[ctx.anyMethodTokenNormalized];
  }

  final singleBucket = node.singleMethodBucket;
  if (singleBucket == null) {
    return null;
  }

  final singleToken = node.singleMethodToken;
  if (singleToken == methodToken ||
      singleToken == ctx.anyMethodTokenNormalized) {
    return singleBucket;
  }

  return null;
}

List<MethodData<T>>? matchMethods<T>(
  RouterContext<T> ctx,
  Map<String, List<MethodData<T>>> methods,
  String methodToken,
) {
  return methods[methodToken] ?? methods[ctx.anyMethodTokenNormalized];
}

RegExp getParamRegexp<T>(RouterContext<T> ctx, String segment) {
  final pattern = segment
      .replaceAllMapped(
        RegExp(r':(\w+)'),
        (match) => '(?<${match.group(1)}>[^/]+)',
      )
      .replaceAll('.', r'\.');
  return RegExp('^$pattern\$', caseSensitive: ctx.caseSensitive);
}

bool _isAsciiUpper(String input) {
  for (var i = 0; i < input.length; i++) {
    final code = input.codeUnitAt(i);
    if (code >= 97 && code <= 122) {
      return false;
    }
  }
  return true;
}

void clearFindRouteCaches<T>(RouterContext<T> ctx) {
  if (ctx.findRouteCacheWithParams.isNotEmpty) {
    ctx.findRouteCacheWithParams.clear();
  }
  if (ctx.findRouteCacheWithoutParams.isNotEmpty) {
    ctx.findRouteCacheWithoutParams.clear();
  }
}

void markFindRouteCacheDirty<T>(RouterContext<T> ctx) {
  if (ctx.findRouteCacheWithParams.isEmpty &&
      ctx.findRouteCacheWithoutParams.isEmpty) {
    return;
  }
  ctx.mutationVersion += 1;
}

void prepareFindRouteCache<T>(RouterContext<T> ctx) {
  if (ctx.cacheVersion == ctx.mutationVersion) {
    return;
  }
  clearFindRouteCaches(ctx);
  ctx.cacheVersion = ctx.mutationVersion;
}
