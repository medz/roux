const int slashCode = 47,
    asteriskCode = 42,
    colonCode = 58,
    openBraceCode = 123,
    closeBraceCode = 125,
    questionCode = 63,
    plusCode = 43,
    mapAt = 4;

const int remainderSpecificity = 0,
    singleDynamicSpecificity = 1,
    structuredDynamicSpecificity = 2,
    exactSpecificity = 3;

const int compiledBucketHigh = 0,
    compiledBucketRepeated = 1,
    compiledBucketLate = 2,
    compiledBucketDeferred = 3;

const String dupShape = 'Duplicate route shape conflicts with existing route: ';
const String dupWildcard =
    'Duplicate wildcard route shape at prefix for pattern: ';
const String dupFallback = 'Duplicate global fallback route: ';
const String emptySegment = 'Route pattern contains empty segment: ';

enum DuplicatePolicy { reject, replace, keepFirst, append }

class RouteMatch<T> {
  final T data;
  final Map<String, String>? params;

  RouteMatch(this.data, [this.params]);
}

class RouteEntry<T> {
  final T data;
  final List<String> paramNames;
  final String? wildcardName;
  final int registrationOrder;
  final int sortKey;
  RouteEntry<T>? next;
  late final noParamsMatch = RouteMatch<T>(data);

  RouteEntry(
    this.data,
    this.paramNames,
    this.wildcardName,
    int depth,
    int specificity,
    int staticChars,
    int constraintScore,
    this.registrationOrder,
  ) : sortKey =
          (((specificity * 256) + depth) * 4096 + staticChars) * 4 +
          constraintScore;

  RouteEntry<T> appended(RouteEntry<T> route) {
    var current = this;
    while (current.next != null) {
      current = current.next!;
    }
    current.next = route;
    return this;
  }
}

class MatchAccumulator<T> {
  final bool sortBySpecificity;
  final items = <(RouteMatch<T>, RouteEntry<T>, int)>[];

  MatchAccumulator(this.sortBySpecificity);

  void add(RouteMatch<T> match, RouteEntry<T> route, int methodRank) =>
      items.add((match, route, methodRank));

  List<RouteMatch<T>> get matches {
    if (sortBySpecificity) {
      items.sort((a, b) {
        final rankDiff = a.$2.sortKey - b.$2.sortKey;
        if (rankDiff != 0) return rankDiff;
        final methodDiff = a.$3 - b.$3;
        if (methodDiff != 0) return methodDiff;
        return a.$2.registrationOrder - b.$2.registrationOrder;
      });
    }
    return <RouteMatch<T>>[for (final item in items) item.$1];
  }
}

RouteEntry<T> newRoute<T>(
  T data,
  List<String> paramNames,
  String? wildcardName,
  String pattern,
  int depth,
  int specificity,
  int staticChars,
  int constraintScore,
  int registrationOrder,
) {
  validateCaptureNames(paramNames, wildcardName, pattern);
  return RouteEntry<T>(
    data,
    paramNames,
    wildcardName,
    depth,
    specificity,
    staticChars,
    constraintScore,
    registrationOrder,
  );
}

RouteEntry<T> mergeRouteEntries<T>(
  RouteEntry<T>? existing,
  RouteEntry<T> replacement,
  String pattern,
  DuplicatePolicy duplicatePolicy,
  String rejectPrefix,
) {
  if (existing == null) return replacement;
  final a = existing.paramNames;
  final b = replacement.paramNames;
  if (a.length != b.length) throw FormatException('$dupShape$pattern');
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) throw FormatException('$dupShape$pattern');
  }
  if (existing.wildcardName != replacement.wildcardName) {
    throw FormatException('$dupShape$pattern');
  }
  return switch (duplicatePolicy) {
    DuplicatePolicy.reject => throw FormatException('$rejectPrefix$pattern'),
    DuplicatePolicy.replace => replacement,
    DuplicatePolicy.keepFirst => existing,
    DuplicatePolicy.append => existing.appended(replacement),
  };
}

void validateCaptureNames(
  List<String> paramNames,
  String? wildcardName,
  String pattern,
) {
  if (paramNames.isEmpty) return;
  final seen = <String>{};
  for (final name in paramNames) {
    if (!seen.add(name)) {
      throw FormatException('Duplicate capture name in route: $pattern');
    }
  }
  if (wildcardName != null && wildcardName != '_' && !seen.add(wildcardName)) {
    throw FormatException('Duplicate capture name in route: $pattern');
  }
}

bool isValidParamName(String name) =>
    hasValidParamNameSlice(name, 0, name.length);

bool hasValidParamNameSlice(String pattern, int start, int end) {
  if (start >= end) return false;
  for (var i = start; i < end; i++) {
    if (!isParamNameCode(pattern.codeUnitAt(i), i == start)) return false;
  }
  return true;
}

bool isParamNameCode(int code, bool first) =>
    ((code | 32) >= 97 && (code | 32) <= 122) ||
    code == 95 ||
    (!first && code >= 48 && code <= 57);

String? readDoubleWildcardName(String pattern, int start, int end) {
  if (end - start == 2 &&
      pattern.codeUnitAt(start) == asteriskCode &&
      pattern.codeUnitAt(start + 1) == asteriskCode) {
    return '_';
  }
  if (end - start <= 3 ||
      pattern.codeUnitAt(start) != asteriskCode ||
      pattern.codeUnitAt(start + 1) != asteriskCode ||
      pattern.codeUnitAt(start + 2) != colonCode) {
    return null;
  }
  final name = pattern.substring(start + 3, end);
  return isValidParamName(name) ? name : null;
}
