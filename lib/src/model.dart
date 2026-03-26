// ignore_for_file: public_member_api_docs

const String unnamedGroupPrefix = '__roux_unnamed_';

class RouteMatch<T> {
  final T data;
  final Map<String, String>? params;
  RouteMatch(this.data, [this.params]);
}

class RouterNode<T> {
  Map<String, RouterNode<T>>? statics;
  RouterNode<T>? param;
  RouterNode<T>? wildcard;
  bool hasRegexParam = false;
  Map<String, List<RouteData<T>>>? methods;

  bool get isEmpty =>
      (statics?.isEmpty ?? true) &&
      param == null &&
      wildcard == null &&
      (methods?.isEmpty ?? true);
}

class SegmentPattern {
  const SegmentPattern(this.regex, this.captureNames);

  final RegExp regex;
  final List<String> captureNames;
}

class ParamSpec {
  const ParamSpec(this.index, this.key, this.optional);

  final int index;
  final Object key; // String name or SegmentPattern
  final bool optional;
}

class RouteData<T> {
  RouteData({required this.data, required this.paramsRegexp, this.paramsMap});

  final T data;
  final List<SegmentPattern?> paramsRegexp;
  final List<ParamSpec>? paramsMap;

  RouteMatch<T> materialize(List<String> segments) {
    final map = paramsMap;
    if (map == null || map.isEmpty) return RouteMatch(data);
    final params = <String, String>{};
    for (final spec in map) {
      final segment = spec.index < 0
          ? segments.sublist(-(spec.index + 1)).join('/')
          : spec.index < segments.length
          ? segments[spec.index]
          : '';
      if (spec.key is String) {
        final name = spec.key as String;
        if (spec.optional && spec.index >= 0 && segment.isEmpty) continue;
        params[normalizeUnnamedGroupKey(name)] = segment;
      } else {
        final pattern = spec.key as SegmentPattern;
        final m = pattern.regex.firstMatch(segment);
        if (m == null) continue;
        for (final name in pattern.captureNames) {
          final value = m.namedGroup(name);
          if (value != null) params[normalizeUnnamedGroupKey(name)] = value;
        }
      }
    }
    return RouteMatch(data, params.isEmpty ? null : params);
  }
}

String normalizeUnnamedGroupKey(String key) =>
    key.startsWith(unnamedGroupPrefix)
    ? key.substring(unnamedGroupPrefix.length)
    : key;

bool isParamCode(int code, bool first) =>
    ((code | 32) >= 97 && (code | 32) <= 122) ||
    code == 95 ||
    (!first && code >= 48 && code <= 57) ||
    (!first && code == 45);

bool validParamSlice(String s, int start, int end) {
  if (start >= end) return false;
  for (var i = start; i < end; i++) {
    if (!isParamCode(s.codeUnitAt(i), i == start)) return false;
  }
  return true;
}
