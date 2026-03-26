// Public types and internal router data structures.
// ignore_for_file: public_member_api_docs

const int colonCode = 58,
    asteriskCode = 42,
    openBraceCode = 123,
    closeBraceCode = 125,
    questionCode = 63,
    plusCode = 43;

const int specRem = 0, specDyn = 1, specStruct = 2, specExact = 3;

const String dupShape = 'Duplicate route shape conflicts with existing route: ';
const String dupWildcard =
    'Duplicate wildcard route shape at prefix for pattern: ';
const String dupFallback = 'Duplicate global fallback route: ';
const String unnamedGroupPrefix = '__roux_unnamed_';

enum DuplicatePolicy { reject, replace, keepFirst, append }

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
}

class SegmentPattern {
  const SegmentPattern(this.regex, this.captureNames);

  final RegExp regex;
  final List<String> captureNames;
}

class ParamSpec {
  const ParamSpec(this.index, this.key, this.optional);

  final int index;
  final Object key;
  final bool optional;
}

class RouteData<T> {
  RouteData({
    required this.data,
    required this.shapeKey,
    required this.captureNames,
    required this.paramsRegexp,
    required this.order,
    required this.rank,
    required this.matchRank,
    this.paramsMap,
    this.emptyParams = false,
  });

  final T data;
  final String shapeKey;
  final List<String> captureNames;
  final List<SegmentPattern?> paramsRegexp;
  final List<ParamSpec>? paramsMap;
  final int order;
  final int rank;
  final int matchRank;
  final bool emptyParams;

  RouteMatch<T> materialize(List<String> segments) {
    final paramsMap = this.paramsMap;
    if (paramsMap == null || paramsMap.isEmpty) {
      return emptyParams ? RouteMatch(data, {}) : RouteMatch(data);
    }

    final params = <String, String>{};
    for (final spec in paramsMap) {
      final segment =
          spec.index < 0 ? segments.sublist(-(spec.index + 1)).join('/') : segments[spec.index];
      if (spec.key is String) {
        final name = spec.key as String;
        if (spec.optional &&
            spec.index >= 0 &&
            segment.isEmpty &&
            !name.startsWith(unnamedGroupPrefix)) {
          continue;
        }
        params[normalizeUnnamedGroupKey(name)] = segment;
        continue;
      }

      final pattern = spec.key as SegmentPattern;
      final match = pattern.regex.firstMatch(segment);
      if (match == null) continue;
      for (final name in pattern.captureNames) {
        final value = match.namedGroup(name);
        if (value != null) {
          params[normalizeUnnamedGroupKey(name)] = value;
        }
      }
    }
    if (params.isEmpty && !emptyParams) return RouteMatch(data);
    return RouteMatch(data, params);
  }
}

class MatchAccumulator<T> {
  final _items = <(RouteMatch<T>, int, int, int)>[];

  void add(RouteMatch<T> match, int rank, int methodRank, int order) =>
      _items.add((match, rank, methodRank, order));

  List<RouteMatch<T>> get results {
    _items.sort((a, b) {
      final r = a.$2 - b.$2;
      if (r != 0) return r;
      final m = a.$3 - b.$3;
      if (m != 0) return m;
      return a.$4 - b.$4;
    });
    final seenOrders = <int>{};
    final matches = <RouteMatch<T>>[];
    for (final item in _items) {
      if (!seenOrders.add(item.$4)) continue;
      matches.add(item.$1);
    }
    return matches;
  }
}

String normalizeUnnamedGroupKey(String key) =>
    key.startsWith(unnamedGroupPrefix) ? key.substring(unnamedGroupPrefix.length) : key;

int computeRank(int specificity, int depth, int staticChars, int constraintScore) =>
    (((specificity * 256) + depth) * 4096 + staticChars) * 4 + constraintScore;

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
