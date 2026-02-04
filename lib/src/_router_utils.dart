import 'node.dart';
import 'router.dart';

String normalizeMethod<T>(RouterContext<T> ctx, String? method) {
  if (method == null || method.isEmpty) {
    return ctx.anyMethodTokenNormalized;
  }
  final normalized = method.toUpperCase();
  return normalized == ctx.anyMethodTokenNormalized
      ? ctx.anyMethodTokenNormalized
      : normalized;
}

String normalizePath<T>(RouterContext<T> ctx, String path) {
  return ctx.caseSensitive ? path : path.toLowerCase();
}

List<String> normalizeSegments<T>(RouterContext<T> ctx, List<String> segments) {
  if (ctx.caseSensitive) {
    return List<String>.from(segments);
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
