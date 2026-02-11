import 'node.dart';
import 'router.dart';

String normalizeMethod<T>(RouterContext<T> ctx, String? method) {
  if (method == null || method.isEmpty) {
    return ctx.anyMethodTokenNormalized;
  }

  final cached = ctx.methodCache[method];
  if (cached != null) {
    return cached;
  }

  var normalized = _isAsciiUpper(method) ? method : method.toUpperCase();
  if (normalized == ctx.anyMethodTokenNormalized) {
    normalized = ctx.anyMethodTokenNormalized;
  }

  ctx.methodCache[method] = normalized;
  return normalized;
}

String normalizePath<T>(RouterContext<T> ctx, String path) {
  return ctx.caseSensitive ? path : path.toLowerCase();
}

List<String> normalizeSegments<T>(RouterContext<T> ctx, List<String> segments) {
  if (ctx.caseSensitive) {
    return segments;
  }
  return segments.map((segment) => segment.toLowerCase()).toList();
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
